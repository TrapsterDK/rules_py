"""Implementation for the py_binary and py_test rules."""

load("@bazel_lib//lib:expand_make_vars.bzl", "expand_locations", "expand_variables")
load("@bazel_lib//lib:paths.bzl", "BASH_RLOCATION_FUNCTION", "to_rlocation_path")
load("@rules_python//python:defs.bzl", "PyInfo")
load("//py/private:py_library.bzl", _py_library = "py_library_utils")
load("//py/private:py_semantics.bzl", _py_semantics = "semantics")
load("//py/private/toolchain:types.bzl", "PY_TOOLCHAIN", "VENV_TOOLCHAIN")
load(":transitions.bzl", "python_version_transition")

def _dict_to_exports(env):
    return [
        "export %s=\"%s\"" % (k, v)
        for (k, v) in env.items()
    ]

def _dict_to_windows_exports(env):
    return [
        "set \"%s=%s\"" % (k, v)
        for (k, v) in env.items()
    ]

def _py_binary_rule_impl(ctx):
    venv_toolchain = ctx.toolchains[VENV_TOOLCHAIN]
    py_toolchain = _py_semantics.resolve_toolchain(ctx)
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])

    # Resolve our `main=` to a label, which it isn't
    main = _py_semantics.determine_main(ctx)

    # Check for duplicate virtual dependency names. Those that map to the same resolution target would have been merged by the depset for us.
    virtual_resolution = _py_library.resolve_virtuals(ctx)
    imports_depset = _py_library.make_imports_depset(ctx, extra_imports_depsets = virtual_resolution.imports)

    pth_lines = ctx.actions.args()
    pth_lines.use_param_file("%s", use_always = True)
    pth_lines.set_param_file_format("multiline")

    if is_windows:
        pth_lines.add_all(imports_depset)
    else:
        # The venv is created at the root in the runfiles tree, in 'VENV_NAME', the full path is "${RUNFILES_DIR}/${VENV_NAME}",
        # but depending on if we are running as the top level binary or a tool, then $RUNFILES_DIR may be absolute or relative.
        # Paths in the .pth are relative to the site-packages folder where they reside.
        # All "import" paths from `py_library` start with the workspace name, so we need to go back up the tree for
        # each segment from site-packages in the venv to the root of the runfiles tree.
        # Five .. will get us back to the root of the venv:
        # {name}.runfiles/.{name}.venv/lib/python{version}/site-packages/first_party.pth
        # If the target is defined with a slash, it adds to the level of nesting
        target_depth = len(ctx.label.name.split("/")) - 1
        escape = "/".join(([".."] * (4 + target_depth)))

        # A few imports rely on being able to reference the root of the runfiles tree as a Python module,
        # the common case here being the @rules_python//python/runfiles target that adds the runfiles helper,
        # which ends up in bazel_tools/tools/python/runfiles/runfiles.py, but there are no imports attrs that hint we
        # should be adding the root to the PYTHONPATH
        # Maybe in the future we can opt out of this?
        pth_lines.add(escape)

        pth_lines.add_all(imports_depset, format_each = "{}/%s".format(escape))

    site_packages_pth_file = ctx.actions.declare_file("{}.venv.pth".format(ctx.attr.name))
    ctx.actions.write(
        output = site_packages_pth_file,
        content = pth_lines,
    )

    venv_dir = None
    if is_windows:
        venv_dir = ctx.actions.declare_directory(".{}.venv".format(ctx.attr.name))

        srcs_depset = _py_library.make_srcs_depset(ctx)
        action_runfiles = _py_library.make_merged_runfiles(
            ctx,
            extra_depsets = [
                py_toolchain.files,
                srcs_depset,
            ] + virtual_resolution.srcs + virtual_resolution.runfiles,
            extra_runfiles = [
                site_packages_pth_file,
            ],
            extra_runfiles_depsets = [
                venv_toolchain.default_info.default_runfiles,
            ],
        )

        ctx.actions.run(
            executable = venv_toolchain.bin.bin,
            arguments = [
                "--location=" + venv_dir.path,
                "--pth-file=" + site_packages_pth_file.path,
                "--bin-dir=" + ctx.bin_dir.path,
                "--collision-strategy=" + ctx.attr.package_collisions,
                "--venv-name=.{}.venv".format(ctx.attr.name),
            ],
            inputs = action_runfiles.files,
            outputs = [venv_dir],
            toolchain = VENV_TOOLCHAIN,
        )

    default_env = {
        "BAZEL_TARGET": str(ctx.label).lstrip("@"),
        "BAZEL_WORKSPACE": ctx.workspace_name,
        "BAZEL_TARGET_NAME": ctx.attr.name,
    }

    passed_env = dict(ctx.attr.env)
    for k, v in passed_env.items():
        passed_env[k] = expand_variables(
            ctx,
            expand_locations(ctx, v, ctx.attr.data),
            attribute_name = "env",
        )

    srcs_depset = _py_library.make_srcs_depset(ctx)

    entrypoint_name = to_rlocation_path(ctx, main)

    executable_launcher = ctx.actions.declare_file(ctx.attr.name + ".bat" if is_windows else ctx.attr.name)
    ctx.actions.expand_template(
        template = ctx.file._run_tmpl_windows if is_windows else ctx.file._run_tmpl,
        output = executable_launcher,
        substitutions = {
            "{{BASH_RLOCATION_FN}}": BASH_RLOCATION_FUNCTION,
            "{{INTERPRETER_FLAGS}}": " ".join(py_toolchain.flags + ctx.attr.interpreter_options),
            "{{ARG_COLLISION_STRATEGY}}": ctx.attr.package_collisions,
            "{{ARG_VENV_NAME}}": ".{}.venv".format(ctx.attr.name),
            "{{ENTRYPOINT}}": entrypoint_name,
            "{{VENV}}": venv_dir.basename if is_windows else "",
            "{{PYTHON_ENV}}": ("\r\n" if is_windows else "\n").join((
                _dict_to_windows_exports(default_env) if is_windows else _dict_to_exports(default_env)
            )).strip(),
            "{{EXEC_PYTHON_BIN}}": "python{}".format(
                py_toolchain.interpreter_version_info.major,
            ),
            "{{RUNFILES_INTERPRETER}}": str(py_toolchain.runfiles_interpreter).lower(),
        },
        is_executable = True,
    )

    runfiles = _py_library.make_merged_runfiles(
        ctx,
        extra_depsets = [
            py_toolchain.files,
            srcs_depset,
        ] + virtual_resolution.srcs + virtual_resolution.runfiles,
        extra_runfiles = [
            site_packages_pth_file,
        ] + ([venv_dir] if is_windows else [
        ]),
        extra_runfiles_depsets = [
            ctx.attr._runfiles_lib[DefaultInfo].default_runfiles,
            venv_toolchain.default_info.default_runfiles,
        ],
    )

    instrumented_files_info = _py_library.make_instrumented_files_info(
        ctx,
        extra_source_attributes = ["main"],
    )

    return [
        DefaultInfo(
            files = depset([
                executable_launcher,
                main,
                site_packages_pth_file,
            ] + ([venv_dir] if is_windows else [])),
            executable = executable_launcher,
            runfiles = runfiles,
        ),
        PyInfo(
            imports = imports_depset,
            transitive_sources = srcs_depset,
            has_py2_only_sources = False,
            has_py3_only_sources = True,
            uses_shared_libraries = False,
        ),
        instrumented_files_info,
        RunEnvironmentInfo(
            environment = passed_env,
            inherited_environment = getattr(ctx.attr, "env_inherit", []),
        ),
    ]

_attrs = dict({
    "env": attr.string_dict(
        doc = "Environment variables to set when running the binary.",
        default = {},
    ),
    "main": attr.label(
        allow_single_file = True,
        doc = """
Script to execute with the Python interpreter.

Must be a label pointing to a `.py` source file.
If such a label is provided, it will be honored.

If no label is provided AND there is only one `srcs` file, that `srcs` file will be used.

If there are more than one `srcs`, a file matching `{name}.py` is searched for.
This is for historical compatibility with the Bazel native `py_binary` and `rules_python`.
Relying on this behavior is STRONGLY discouraged, may produce warnings and may
be deprecated in the future.

""",
    ),
    "venv": attr.string(
        doc = """The name of the Python virtual environment within which deps should be resolved.

Part of the aspect_rules_py//uv system, has no effect in rules_python's pip.
""",
    ),
    "python_version": attr.string(
        doc = """Whether to build this target and its transitive deps for a specific python version.""",
    ),
    "package_collisions": attr.string(
        doc = """The action that should be taken when a symlink collision is encountered when creating the venv.
A collision can occur when multiple packages providing the same file are installed into the venv. The possible values are:

* "error": When conflicting symlinks are found, an error is reported and venv creation halts.
* "warning": When conflicting symlinks are found, an warning is reported, however venv creation continues.
* "ignore": When conflicting symlinks are found, no message is reported and venv creation continues.
""",
        default = "error",
        values = ["error", "warning", "ignore"],
    ),
    "interpreter_options": attr.string_list(
        doc = "Additional options to pass to the Python interpreter in addition to -B and -I passed by rules_py",
        default = [],
    ),
    "_run_tmpl": attr.label(
        allow_single_file = True,
        default = "//py/private:run.tmpl.sh",
    ),
    "_run_tmpl_windows": attr.label(
        allow_single_file = True,
        default = "//py/private:run.tmpl.bat",
    ),
    "_runfiles_lib": attr.label(
        default = "@bazel_tools//tools/bash/runfiles",
    ),
    "_windows_constraint": attr.label(
        default = "@platforms//os:windows",
    ),
    # Required for py_version attribute
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
})

_attrs.update(**_py_library.attrs)

_test_attrs = dict({
    "env_inherit": attr.string_list(
        doc = "Specifies additional environment variables to inherit from the external environment when the test is executed by bazel test.",
        default = [],
    ),
    # Magic attribute to make coverage --combined_report flag work.
    # There's no docs about this.
    # See https://github.com/bazelbuild/bazel/blob/fde4b67009d377a3543a3dc8481147307bd37d36/tools/test/collect_coverage.sh#L186-L194
    # NB: rules_python ALSO includes this attribute on the py_binary rule, but we think that's a mistake.
    # see https://github.com/aspect-build/rules_py/pull/520#pullrequestreview-2579076197
    "_lcov_merger": attr.label(
        default = configuration_field(fragment = "coverage", name = "output_generator"),
        executable = True,
        cfg = "exec",
    ),
})

py_base = struct(
    implementation = _py_binary_rule_impl,
    attrs = _attrs,
    test_attrs = _test_attrs,
    toolchains = [
        PY_TOOLCHAIN,
        VENV_TOOLCHAIN,
    ],
    cfg = python_version_transition,
)

py_binary = rule(
    doc = "Run a Python program under Bazel. Most users should use the [py_binary macro](#py_binary) instead of loading this directly.",
    implementation = py_base.implementation,
    attrs = py_base.attrs,
    toolchains = py_base.toolchains,
    executable = True,
    cfg = py_base.cfg,
)

py_test = rule(
    doc = "Run a Python program under Bazel. Most users should use the [py_test macro](#py_test) instead of loading this directly.",
    implementation = py_base.implementation,
    attrs = py_base.attrs | py_base.test_attrs,
    toolchains = py_base.toolchains,
    test = True,
    cfg = py_base.cfg,
)
