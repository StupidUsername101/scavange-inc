#!/usr/bin/env python3
"""Build the portable SDF GDExtension through godot-cpp's supported SCons entrypoint."""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
BACKEND = ROOT / "native" / "sdf_backend"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot-cpp", required=True, type=pathlib.Path)
    parser.add_argument("--target", choices=("template_debug", "template_release"), default="template_debug")
    parser.add_argument("--platform", choices=("linux", "windows", "macos", "android", "ios", "web"))
    parser.add_argument("--arch", default="x86_64")
    parser.add_argument("--jobs", type=int, default=max(1, os.cpu_count() or 1))
    parser.add_argument("--scons", default="scons")
    args = parser.parse_args()

    godot_cpp = args.godot_cpp.resolve()
    if not (godot_cpp / "SConstruct").is_file():
        parser.error(f"{godot_cpp} is not a godot-cpp checkout")

    command = [
        args.scons,
        f"-j{args.jobs}",
        f"target={args.target}",
        f"arch={args.arch}",
        f"build_profile={BACKEND / 'build_profile.json'}",
    ]
    if args.platform:
        command.append(f"platform={args.platform}")
    environment = os.environ.copy()
    environment["GODOT_CPP_PATH"] = str(godot_cpp)
    return subprocess.call(command, cwd=BACKEND, env=environment)


if __name__ == "__main__":
    sys.exit(main())
