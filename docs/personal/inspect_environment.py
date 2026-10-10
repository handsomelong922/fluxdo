#!/usr/bin/env python3
"""Read-only offline recovery report. No package setup, network, or secrets."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess


def run(*args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return (result.stdout + result.stderr).strip() or f"exit={result.returncode}"
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"unavailable: {type(exc).__name__}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-sdk", type=Path,
                        default=Path("/workspace/shared/flutter-sdk"))
    parser.add_argument("--dart", type=Path,
                        help="Optional standalone Dart executable; no installation performed")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    print("Repository:", root)
    for label, command in (
        ("Git", ["git", "--version"]),
        ("Commit", ["git", "-C", str(root), "rev-parse", "HEAD"]),
        ("Branch", ["git", "-C", str(root), "branch", "--show-current"]),
        ("Worktree", ["git", "-C", str(root), "status", "--short"]),
        ("Submodules", ["git", "-C", str(root), "submodule", "status", "--recursive"]),
    ):
        print(f"\n{label}:\n{run(*command)}")
    metadata = args.flutter_sdk / "bin/cache/flutter.version.json"
    if metadata.is_file():
        try:
            values = json.loads(metadata.read_text())
            print("\nSDK metadata:")
            for key in ("frameworkVersion", "frameworkRevision", "engineRevision",
                        "dartSdkVersion", "devToolsVersion"):
                print(f"  {key}: {values.get(key, 'unknown')}")
        except (OSError, ValueError):
            print("SDK metadata unreadable")
    else:
        print("\nSDK metadata missing; no download attempted")
    dart = args.dart or args.flutter_sdk / "bin/cache/dart-sdk/bin/dart"
    print("\nDirect Dart:", run(str(dart), "--version"))
    for executable, flag in (("python3", "--version"), ("node", "--version"),
                             ("java", "-version"), ("gh", "--version"),
                             ("cargo", "--version"), ("rustc", "--version")):
        print(f"\n{executable}: " + (run(executable, flag) if shutil.which(executable)
                                      else "not found on PATH"))
    print("\nInformational report only; no dependencies installed or tests run.")


if __name__ == "__main__":
    main()
