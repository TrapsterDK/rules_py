import subprocess
import sys


def main() -> None:
    result = subprocess.run(["python", *sys.argv[1:]])
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
