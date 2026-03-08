import argparse
import os
import pathlib
import shutil
import subprocess
import sys
from typing import Iterable, Optional

_VIRTUALENV_PY = """\
\"\"\"Patches that are applied at runtime to the virtual environment.\"\"\"

import os
import sys

VIRTUALENV_PATCH_FILE = os.path.join(__file__)


def patch_dist(dist):
    old_parse_config_files = dist.Distribution.parse_config_files

    def parse_config_files(self, *args, **kwargs):
        result = old_parse_config_files(self, *args, **kwargs)
        install = self.get_option_dict("install")

        if "prefix" in install:
            install["prefix"] = VIRTUALENV_PATCH_FILE, os.path.abspath(sys.prefix)
        for base in ("purelib", "platlib", "headers", "scripts", "data"):
            key = f"install_{base}"
            if key in install:
                install.pop(key, None)
        return result

    dist.Distribution.parse_config_files = parse_config_files


_DISTUTILS_PATCH = "distutils.dist", "setuptools.dist"


class _Finder:
    fullname = None
    lock = []

    def find_spec(self, fullname, path, target = None):
        if fullname in _DISTUTILS_PATCH and self.fullname is None:
            if len(self.lock) == 0:
                import threading

                self.lock.append(threading.Lock())

            from functools import partial
            from importlib.util import find_spec

            with self.lock[0]:
                self.fullname = fullname
                try:
                    spec = find_spec(fullname, path)
                    if spec is not None:
                        is_new_api = hasattr(spec.loader, "exec_module")
                        func_name = "exec_module" if is_new_api else "load_module"
                        old = getattr(spec.loader, func_name)
                        func = self.exec_module if is_new_api else self.load_module
                        if old is not func:
                            try:
                                setattr(spec.loader, func_name, partial(func, old))
                            except AttributeError:
                                pass
                        return spec
                finally:
                    self.fullname = None
        return None

    @staticmethod
    def exec_module(old, module):
        old(module)
        if module.__name__ in _DISTUTILS_PATCH:
            patch_dist(module)

    @staticmethod
    def load_module(old, name):
        module = old(name)
        if module.__name__ in _DISTUTILS_PATCH:
            patch_dist(module)
        return module


sys.meta_path.insert(0, _Finder())
"""


def parse_bool(value: str) -> bool:
    return value.lower() in ("1", "true", "yes", "on")


def resolve_python(python: str) -> str:
    path = pathlib.Path(python)
    candidates = [path]

    cwd = pathlib.Path.cwd()
    candidates.append(cwd / path)
    candidates.append(cwd / "external" / path)

    for candidate in candidates:
        candidate = pathlib.Path(str(candidate).replace("/", "\\"))
        if candidate.exists():
            return str(candidate)
        if candidate.suffix.lower() != ".exe":
            exe_candidate = pathlib.Path(str(candidate) + ".exe")
            if exe_candidate.exists():
                return str(exe_candidate)

    return str(pathlib.Path(str(path).replace("/", "\\")))


def write_pth(pth_file: pathlib.Path, site_packages: pathlib.Path, bin_dir: Optional[str]) -> None:
    site_packages.mkdir(parents = True, exist_ok = True)
    (site_packages / pth_file.name).write_text(
        rewrite_pth(pth_file, site_packages, bin_dir),
        encoding = "utf-8",
    )


def write_virtualenv_runtime(site_packages: pathlib.Path) -> None:
    (site_packages / "_virtualenv.py").write_text(_VIRTUALENV_PY, encoding = "utf-8")
    (site_packages / "_virtualenv.pth").write_text("import _virtualenv\n", encoding = "utf-8")


def ensure_bin_aliases(location: pathlib.Path) -> None:
    scripts_dir = location / "Scripts"
    bin_dir = location / "bin"
    bin_dir.mkdir(parents = True, exist_ok = True)

    for src_name, dest_name in [
        ("python.exe", "python.exe"),
        ("python.exe", "python3.exe"),
        ("pythonw.exe", "pythonw.exe"),
    ]:
        src = scripts_dir / src_name
        dest = bin_dir / dest_name
        if src.exists():
            shutil.copyfile(src, dest)

    activate = scripts_dir / "activate"
    if activate.exists():
        shutil.copyfile(activate, bin_dir / "activate")


def run_python_venv(python: str, location: pathlib.Path, include_system_site_packages: bool) -> None:
    if location.exists():
        shutil.rmtree(location)

    cmd = [
        python,
        "-m",
        "venv",
        str(location),
    ]
    if include_system_site_packages:
        cmd.append("--system-site-packages")
    subprocess.run(cmd, check = True)


def site_packages_for(location: pathlib.Path) -> pathlib.Path:
    return location / "Lib" / "site-packages"


def alt_site_packages_for(location: pathlib.Path) -> pathlib.Path:
    return location / "lib" / "site-packages"


def candidate_roots(bin_dir: Optional[str]) -> Iterable[pathlib.Path]:
    cwd = pathlib.Path.cwd()
    yield cwd
    yield cwd / "external"

    if bin_dir:
        bin_root = pathlib.Path(bin_dir)
        if not bin_root.is_absolute():
            bin_root = cwd / bin_root
        yield bin_root
        yield bin_root / "external"

    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if runfiles_dir:
        root = pathlib.Path(runfiles_dir)
        yield root
        yield root / "_main"


def resolve_pth_entry(entry: str, unix_site_packages: pathlib.Path, bin_dir: Optional[str]) -> pathlib.Path:
    entry = entry.strip()

    if entry == "_main":
        return pathlib.Path.cwd().resolve()

    if entry.startswith("_main/"):
        entry = entry[len("_main/"):]

    entry_path = pathlib.Path(entry.replace("/", os.sep))

    if entry_path.is_absolute():
        return entry_path

    if entry.startswith(".."):
        return (unix_site_packages / entry_path).resolve()

    for root in candidate_roots(bin_dir):
        candidate = (root / entry_path).resolve()
        if candidate.exists():
            return candidate

    cwd = pathlib.Path.cwd()
    if (cwd / entry_path).exists():
        return (cwd / entry_path).resolve()
    if (cwd / "external" / entry_path).exists():
        return (cwd / "external" / entry_path).resolve()
    return (cwd / entry_path).resolve()


def rewrite_pth(pth_file: pathlib.Path, site_packages: pathlib.Path, bin_dir: Optional[str]) -> str:
    unix_site_packages = pth_file.parent / "lib" / "python3.9" / "site-packages"
    lines = []
    for raw_line in pth_file.read_text(encoding = "utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        resolved = resolve_pth_entry(line, unix_site_packages, bin_dir)
        lines.append(str(resolved).replace("\\", "/"))
    return "\n".join(lines) + "\n"


def create_windows_venv(args: argparse.Namespace) -> None:
    location = pathlib.Path(args.location)
    pth_file = pathlib.Path(args.pth_file)
    python = resolve_python(args.python) if args.python else sys.executable

    run_python_venv(python, location, args.include_system_site_packages)
    ensure_bin_aliases(location)
    for site_packages in [site_packages_for(location), alt_site_packages_for(location)]:
        write_pth(pth_file, site_packages, args.bin_dir)
        write_virtualenv_runtime(site_packages)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo")
    parser.add_argument("--python")
    parser.add_argument("--venv-shim")
    parser.add_argument("--location", required = True)
    parser.add_argument("--pth-file", required = True)
    parser.add_argument("--env-file")
    parser.add_argument("--pth-entry-prefix")
    parser.add_argument("--bin-dir")
    parser.add_argument("--collision-strategy")
    parser.add_argument("--venv-name", required = True)
    parser.add_argument("--mode", default = "dynamic-symlink")
    parser.add_argument("--version")
    parser.add_argument("--debug", action = "store_true")
    parser.add_argument("--include-system-site-packages", type = parse_bool, default = False)
    parser.add_argument("--include-user-site-packages", type = parse_bool, default = False)
    args = parser.parse_args()

    create_windows_venv(args)


if __name__ == "__main__":
    main()
