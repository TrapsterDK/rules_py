load("//py/private/toolchain:types.bzl", "PY_TOOLCHAIN")

def _to_runfile_path(path, workspace_name):
    normalized = path.replace("\\", "/")
    for _ in range(10):
        if not normalized.startswith("../"):
            break
        normalized = normalized[3:]

    first_segment = normalized.split("/")[0]

    if first_segment not in [workspace_name, "external"] and not first_segment.startswith("rules_") and not first_segment.startswith("+") and not first_segment.startswith("@") and not normalized.startswith("_"):
        normalized = workspace_name + "/" + normalized

    if normalized.startswith("external/"):
        normalized = normalized[len("external/"):]

    return normalized

def _windows_py_tool_impl(ctx):
    runtime = ctx.toolchains[PY_TOOLCHAIN].py3_runtime
    interpreter = runtime.interpreter
    script = ctx.file.main

    if interpreter != None:
        interpreter_cmd = interpreter.path.replace("/", "\\")
    else:
        interpreter_cmd = runtime.interpreter_path.replace("/", "\\")
    runtime_runfiles = ctx.runfiles(transitive_files = runtime.files) if interpreter != None else ctx.runfiles()

    output = ctx.actions.declare_file(ctx.label.name + ".bat")
    script_cmd = script.path.replace("/", "\\")
    ctx.actions.write(
        output = output,
        content = "\r\n".join([
            "@echo off",
            "setlocal EnableExtensions",
            "\"{}\" \"{}\" %*".format(interpreter_cmd, script_cmd),
            "exit /b %ERRORLEVEL%",
            "",
        ]),
        is_executable = True,
    )

    return [DefaultInfo(
        executable = output,
        files = depset([output, script]),
        runfiles = ctx.runfiles(files = [script]).merge(runtime_runfiles),
    )]

windows_py_tool = rule(
    implementation = _windows_py_tool_impl,
    attrs = {
        "main": attr.label(
            allow_single_file = [".py"],
            mandatory = True,
        ),
    },
    executable = True,
    toolchains = [PY_TOOLCHAIN],
)
