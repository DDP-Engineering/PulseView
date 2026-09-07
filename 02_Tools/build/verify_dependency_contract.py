#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# -----------------------------------------------------------------------------
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
# -----------------------------------------------------------------------------
"""
@file verify_dependency_contract.py
@brief Verify normalized dependency-contract probes inside a builder image.
@details Executes only declared command, package, file, pkg-config, header,
         target-output and compile/link probes up to a selected level.
"""

# IMPORTS

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from typing import Any


# CONSTANTS

LEVEL_RANK = {"quick": 0, "standard": 1, "full": 2}
CONTRACT_KEYS = {
    "schema",
    "image",
    "architecture",
    "direct_package",
    "command",
    "pkg_config",
    "header",
    "library",
    "file",
    "target_output",
    "feature",
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


# DATA MODELS / TYPEDEFINITIONS

JsonObject = dict[str, Any]


# HELPER FUNCTIONS


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    """@brief Run a probe without a shell and report its semantic label."""
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"{label}: {error}") from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"{label}: exit {result.returncode}: {detail}")
    return result


def applies(entry: JsonObject, level: str) -> bool:
    """@brief Return whether an entry belongs to the requested level."""
    return LEVEL_RANK[str(entry.get("level", "standard"))] <= LEVEL_RANK[level]


def host_path(root: Path, declared: str) -> Path:
    """@brief Map a declared absolute image path under an optional test root."""
    return root / declared.lstrip("/")


def sha256_file(path: Path) -> str:
    """@brief Hash one fixed input without loading it all into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_packages(contract: JsonObject, root: Path) -> None:
    """@brief Verify every selected direct package is installed."""
    if root != Path("/"):
        raise RuntimeError("package verification does not support a synthetic root")
    for entry in contract["direct_package"]:
        name = str(entry["name"])
        result = run_checked(
            ["dpkg-query", "-W", "-f=${db:Status-Abbrev}", name],
            f"package {name}",
        )
        if not result.stdout.startswith("ii "):
            raise RuntimeError(f"package {name}: not installed ({result.stdout!r})")


def verify_commands(contract: JsonObject, level: str) -> None:
    """@brief Verify command discovery and optional version constraints."""
    for entry in contract["command"]:
        if not applies(entry, level):
            continue
        declared = str(entry["path"])
        executable = declared if "/" in declared else shutil.which(declared)
        if executable is None or not Path(executable).is_file():
            raise RuntimeError(f"command {entry['name']}: not found: {declared}")
        version_args = [str(item) for item in entry.get("version_args", [])]
        if version_args:
            result = run_checked(
                [str(executable), *version_args], f"command {entry['name']} version"
            )
            expression = entry.get("version_regex")
            if expression and not re.search(
                str(expression), result.stdout + result.stderr, re.MULTILINE
            ):
                raise RuntimeError(
                    f"command {entry['name']}: version output did not match {expression}"
                )


def verify_pkg_config(contract: JsonObject, level: str) -> None:
    """@brief Verify selected pkg-config modules and minimum versions."""
    for entry in contract["pkg_config"]:
        if not applies(entry, level):
            continue
        command = ["pkg-config", "--exists", str(entry["name"])]
        if "min_version" in entry:
            command = [
                "pkg-config",
                f"--atleast-version={entry['min_version']}",
                str(entry["name"]),
            ]
        run_checked(command, f"pkg-config {entry['name']}")


def verify_paths(contract: JsonObject, level: str, root: Path) -> None:
    """@brief Verify headers, fixed files and target outputs."""
    for entry in contract["header"]:
        if applies(entry, level) and not host_path(root, str(entry["path"])).is_file():
            raise RuntimeError(f"header missing: {entry['path']}")
    for entry in contract["target_output"]:
        if applies(entry, level) and not host_path(root, str(entry["path"])).exists():
            raise RuntimeError(
                f"target output {entry['name']} missing: {entry['path']}"
            )
    for entry in contract["file"]:
        if not applies(entry, level):
            continue
        path = host_path(root, str(entry["path"]))
        if not path.is_file():
            raise RuntimeError(f"file missing: {entry['path']}")
        expected = str(entry.get("sha256", ""))
        if not SHA256_PATTERN.fullmatch(expected):
            raise RuntimeError(f"file {entry['path']}: contract has no fixed checksum")
        actual = sha256_file(path)
        if actual != expected:
            raise RuntimeError(
                f"file {entry['path']}: checksum mismatch ({actual} != {expected})"
            )


def verify_libraries(contract: JsonObject, level: str) -> None:
    """@brief Compile and link declared library symbols."""
    for entry in contract["library"]:
        if not applies(entry, level):
            continue
        compiler = "cc" if entry["language"] == "c" else "c++"
        suffix = ".c" if entry["language"] == "c" else ".cpp"
        source = (
            f"#include <{entry['header']}>\n"
            f"int main(void) {{ (void)&{entry['symbol']}; return 0; }}\n"
        )
        flags: list[str] = []
        module = entry.get("pkg_config")
        if module:
            result = run_checked(
                ["pkg-config", "--cflags", "--libs", str(module)],
                f"library {entry['name']} flags",
            )
            flags = shlex.split(result.stdout)
        with tempfile.TemporaryDirectory(prefix="builder-library-") as temporary:
            source_path = Path(temporary) / f"probe{suffix}"
            output_path = Path(temporary) / "probe"
            source_path.write_text(source, encoding="utf-8")
            run_checked(
                [compiler, str(source_path), "-o", str(output_path), *flags],
                f"library {entry['name']}",
            )


def load_contract(path: Path) -> JsonObject:
    """@brief Parse and minimally validate normalized contract structure."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) != CONTRACT_KEYS:
        raise ValueError("normalized contract has an unexpected top-level shape")
    if data.get("schema") != 1:
        raise ValueError("unsupported normalized contract schema")
    for key in CONTRACT_KEYS - {"schema", "image", "architecture"}:
        if not isinstance(data[key], list):
            raise ValueError(f"normalized contract {key} must be an array")
    return data


# PUBLIC API


def verify(arguments: argparse.Namespace) -> int:
    """@brief Verify declared probes at the selected level."""
    contract = load_contract(arguments.contract)
    root = arguments.root
    verify_commands(contract, arguments.level)
    verify_paths(contract, arguments.level, root)
    if LEVEL_RANK[arguments.level] >= LEVEL_RANK["standard"]:
        verify_packages(contract, root)
        verify_pkg_config(contract, arguments.level)
        verify_libraries(contract, arguments.level)
    print(f"dependency contract: {arguments.level} verification passed")
    return 0


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the command-line parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--level", choices=tuple(LEVEL_RANK), required=True)
    parser.add_argument("--root", type=Path, default=Path("/"))
    return parser


def main() -> int:
    """@brief Run verification with bounded error output."""
    try:
        return verify(command_parser().parse_args())
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
