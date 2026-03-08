import argparse
import pathlib
import shutil
import zipfile


def site_packages_root(location: pathlib.Path, major: int, minor: int) -> pathlib.Path:
    return location / "lib" / f"python{major}.{minor}" / "site-packages"


def install_path(location: pathlib.Path, site_packages: pathlib.Path, member: str) -> pathlib.Path:
    parts = pathlib.PurePosixPath(member).parts
    if not parts:
        return site_packages

    first = parts[0]
    if first.endswith(".data") and len(parts) >= 2:
        data_dir = parts[1]
        tail = parts[2:]
        if data_dir in ("purelib", "platlib"):
            return site_packages.joinpath(*tail)
        if data_dir == "scripts":
            return location / "bin" / pathlib.Path(*tail)
        if data_dir in ("headers", "include"):
            return location / "lib" / "include" / pathlib.Path(*tail)
        if data_dir == "data":
            return site_packages.joinpath(*tail)
        return location.joinpath(*tail)

    return site_packages.joinpath(*parts)


def unpack_wheel(into: pathlib.Path, wheel: pathlib.Path, major: int, minor: int) -> None:
    if wheel.is_dir():
        matches = list(wheel.glob("*.whl"))
        if len(matches) != 1:
            raise SystemExit("expected exactly one wheel in directory")
        wheel = matches[0]

    if into.exists():
        shutil.rmtree(into)

    site_packages = site_packages_root(into, major, minor)
    site_packages.mkdir(parents = True, exist_ok = True)
    (into / "bin").mkdir(parents = True, exist_ok = True)

    with zipfile.ZipFile(wheel) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue

            dest = install_path(into, site_packages, info.filename)
            dest.parent.mkdir(parents = True, exist_ok = True)
            with zf.open(info) as src, open(dest, "wb") as dst:
                shutil.copyfileobj(src, dst)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--into", required = True)
    parser.add_argument("--wheel", required = True)
    parser.add_argument("--python-version-major", type = int, required = True)
    parser.add_argument("--python-version-minor", type = int, required = True)
    args = parser.parse_args()

    unpack_wheel(
        pathlib.Path(args.into),
        pathlib.Path(args.wheel),
        args.python_version_major,
        args.python_version_minor,
    )


if __name__ == "__main__":
    main()
