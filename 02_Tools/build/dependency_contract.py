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
@file dependency_contract.py
@brief Validate and normalize builder dependency contracts.
@details Selects one builder architecture, emits canonical JSON and a direct-
         package projection, and rejects unsupported contract data before any
         output is replaced.
"""

# IMPORTS

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
import tomllib
from typing import Any, NoReturn


# CONSTANTS

SCHEMA_VERSION = 1
ARCHITECTURE_ALIASES = {
    "x86_64": "amd64",
    "amd64": "amd64",
    "linux/amd64": "amd64",
    "aarch64": "arm64",
    "arm64": "arm64",
    "linux/arm64": "arm64",
}
TOP_LEVEL_FIELDS = {
    "schema",
    "image",
    "direct_package",
    "command",
    "pkg_config",
    "header",
    "library",
    "file",
    "target_output",
    "feature",
}
ENTRY_FIELDS = {
    "direct_package": {"name", "architectures"},
    "command": {
        "name",
        "path",
        "version_args",
        "version_regex",
        "level",
        "architectures",
    },
    "pkg_config": {"name", "min_version", "level", "architectures"},
    "header": {"path", "level", "architectures"},
    "library": {
        "name",
        "language",
        "header",
        "symbol",
        "pkg_config",
        "level",
        "architectures",
    },
    "file": {
        "path",
        "sha256_artifact",
        "level",
        "architectures",
    },
    "target_output": {"name", "path", "level", "architectures"},
    "feature": {
        "name",
        "probe",
        "expected",
        "level",
        "architectures",
    },
}
REQUIRED_FIELDS = {
    "direct_package": {"name"},
    "command": {"name"},
    "pkg_config": {"name"},
    "header": {"path"},
    "library": {"name", "language", "header", "symbol"},
    "file": {"path", "sha256_artifact"},
    "target_output": {"name", "path"},
    "feature": {"name", "probe", "expected"},
}
LEVELS = {"quick", "standard", "full"}
FEATURE_PROBES = {
    "driver-list",
    "decoder-list",
    "networking-stack",
    "pe-import-closure",
    "appimage-identity",
    "appimage-runtime",
    "appimage-gui-startup",
    "deb-metadata",
}
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.:@/-]*$")
PACKAGE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9+.-]*$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


# DATA MODELS / TYPEDEFINITIONS

Contract = dict[str, Any]


# HELPER FUNCTIONS


def fail(message: str) -> NoReturn:
    """@brief Stop with one actionable contract error."""
    raise ValueError(message)


def require_string(value: Any, field: str) -> str:
    """@brief Return a non-empty single-line string or reject it."""
    if not isinstance(value, str) or not value or "\x00" in value or "\n" in value:
        fail(f"{field} must be a non-empty single-line string")
    return value


def require_string_list(value: Any, field: str) -> list[str]:
    """@brief Return a validated list of strings."""
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"{field} must be an array of strings")
    return [require_string(item, field) for item in value]


def normalize_architecture(value: str) -> str:
    """@brief Map supported architecture spellings to manifest names."""
    try:
        return ARCHITECTURE_ALIASES[value]
    except KeyError as error:
        raise ValueError(f"unsupported architecture: {value}") from error


def validate_absolute_path(value: Any, field: str) -> str:
    """@brief Validate an absolute POSIX path without traversal."""
    text = require_string(value, field)
    parsed = PurePosixPath(text)
    if not parsed.is_absolute() or ".." in parsed.parts:
        fail(f"{field} must be an absolute POSIX path without '..': {text}")
    return text


def semantic_key(kind: str, entry: Contract) -> str:
    """@brief Return the field that uniquely identifies an entry."""
    if kind == "header" or "name" not in entry:
        return str(entry["path"])
    return str(entry["name"])


def selected_architectures(entry: Contract, field: str) -> set[str]:
    """@brief Validate and normalize an optional architecture selector."""
    raw = entry.get("architectures")
    if raw is None:
        return {"amd64", "arm64"}
    values = require_string_list(raw, f"{field}.architectures")
    if not values:
        fail(f"{field}.architectures must not be empty")
    normalized = [normalize_architecture(item) for item in values]
    if len(normalized) != len(set(normalized)):
        fail(f"{field}.architectures contains duplicates")
    return set(normalized)


def load_lock_artifacts(path: Path) -> dict[str, Contract]:
    """@brief Read unique checksum-bearing artifact entries from the lock."""
    with path.open("rb") as stream:
        data = tomllib.load(stream)
    artifacts: dict[str, Contract] = {}
    for index, item in enumerate(data.get("artifact", []), start=1):
        if not isinstance(item, dict):
            fail(f"lock artifact {index} must be a table")
        name = require_string(item.get("name"), f"lock artifact {index}.name")
        if name in artifacts:
            fail(f"duplicate lock artifact: {name}")
        artifacts[name] = item
    return artifacts


def validate_common_entry(kind: str, entry: Any, index: int) -> Contract:
    """@brief Validate table shape, known fields and common selectors."""
    label = f"{kind}[{index}]"
    if not isinstance(entry, dict):
        fail(f"{label} must be a table")
    unknown = set(entry) - ENTRY_FIELDS[kind]
    if unknown:
        fail(f"{label} has unknown field(s): {', '.join(sorted(unknown))}")
    missing = REQUIRED_FIELDS[kind] - set(entry)
    if missing:
        fail(f"{label} misses field(s): {', '.join(sorted(missing))}")
    selected_architectures(entry, label)
    if kind != "direct_package":
        default_level = "full" if kind == "feature" else "standard"
        level = entry.get("level", default_level)
        if level not in LEVELS:
            fail(f"{label}.level must be quick, standard, or full")
        if kind == "feature" and level != "full":
            fail(f"{label}.level must be full")
    return dict(entry)


def validate_entry(
    kind: str,
    raw_entry: Any,
    index: int,
    artifacts: dict[str, Contract],
) -> Contract:
    """@brief Validate fields specific to one contract entry kind."""
    entry = validate_common_entry(kind, raw_entry, index)
    label = f"{kind}[{index}]"

    if "name" in entry:
        name = require_string(entry["name"], f"{label}.name")
        pattern = PACKAGE_PATTERN if kind == "direct_package" else NAME_PATTERN
        if not pattern.fullmatch(name):
            fail(f"{label}.name has unsupported characters: {name}")

    if kind in {"header", "file", "target_output"}:
        entry["path"] = validate_absolute_path(entry["path"], f"{label}.path")

    if kind == "command":
        if "path" in entry:
            entry["path"] = require_string(entry["path"], f"{label}.path")
        if "version_args" in entry:
            entry["version_args"] = require_string_list(
                entry["version_args"], f"{label}.version_args"
            )
        if "version_regex" in entry:
            expression = require_string(
                entry["version_regex"], f"{label}.version_regex"
            )
            if not entry.get("version_args"):
                fail(f"{label}.version_regex requires version_args")
            try:
                re.compile(expression)
            except re.error as error:
                raise ValueError(
                    f"{label}.version_regex is invalid: {error}"
                ) from error

    if kind == "pkg_config" and "min_version" in entry:
        require_string(entry["min_version"], f"{label}.min_version")

    if kind == "library":
        if entry["language"] not in {"c", "c++"}:
            fail(f"{label}.language must be c or c++")
        for field in ("header", "symbol"):
            require_string(entry[field], f"{label}.{field}")
        if "pkg_config" in entry:
            require_string(entry["pkg_config"], f"{label}.pkg_config")

    if kind == "file":
        artifact_name = require_string(
            entry["sha256_artifact"], f"{label}.sha256_artifact"
        )
        artifact = artifacts.get(artifact_name)
        if artifact is None:
            fail(f"{label} references unknown lock artifact: {artifact_name}")
        digest = artifact.get("sha256")
        if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
            fail(f"lock artifact {artifact_name} has no valid sha256")
        entry["sha256"] = digest

    if kind == "feature":
        probe = require_string(entry["probe"], f"{label}.probe")
        if probe not in FEATURE_PROBES:
            fail(f"{label}.probe is unsupported: {probe}")
        require_string(entry["expected"], f"{label}.expected")

    return entry


def normalize_entry(kind: str, entry: Contract) -> Contract:
    """@brief Remove selection fields and materialize defaults."""
    result = {
        key: value
        for key, value in entry.items()
        if key not in {"architectures", "sha256_artifact"}
    }
    if kind != "direct_package":
        result.setdefault("level", "full" if kind == "feature" else "standard")
    if kind == "command":
        result.setdefault("path", result["name"])
        result.setdefault("version_args", [])
    return result


def normalize_contract(
    source: Path,
    image: str,
    architecture: str,
    lock: Path,
) -> Contract:
    """
    @brief Validate and select one normalized dependency contract.
    @param[in] source Contract TOML path.
    @param[in] image Expected builder image type.
    @param[in] architecture Normalized architecture name.
    @param[in] lock Upstream lock TOML path.
    @return Canonical-data dictionary ready for JSON serialization.
    """
    with source.open("rb") as stream:
        data = tomllib.load(stream)
    if not isinstance(data, dict):
        fail("contract root must be a table")
    unknown = set(data) - TOP_LEVEL_FIELDS
    if unknown:
        fail(f"contract has unknown field(s): {', '.join(sorted(unknown))}")
    if data.get("schema") != SCHEMA_VERSION or isinstance(data.get("schema"), bool):
        fail(f"unsupported dependency contract schema: {data.get('schema')!r}")
    contract_image = require_string(data.get("image"), "image")
    if contract_image not in {"mingw", "appimage"}:
        fail(f"unsupported contract image: {contract_image}")
    if image != contract_image:
        fail(f"contract image is {contract_image}, requested {image}")
    if image == "mingw" and architecture != "amd64":
        fail("the MinGW dependency contract supports only amd64")

    artifacts = load_lock_artifacts(lock)
    normalized: Contract = {
        "schema": SCHEMA_VERSION,
        "image": image,
        "architecture": architecture,
    }
    for kind in (
        "direct_package",
        "command",
        "pkg_config",
        "header",
        "library",
        "file",
        "target_output",
        "feature",
    ):
        raw_entries = data.get(kind, [])
        if not isinstance(raw_entries, list):
            fail(f"{kind} must be an array of tables")
        selected: list[Contract] = []
        seen: set[str] = set()
        for index, raw_entry in enumerate(raw_entries, start=1):
            entry = validate_entry(kind, raw_entry, index, artifacts)
            if architecture not in selected_architectures(entry, f"{kind}[{index}]"):
                continue
            key = semantic_key(kind, entry)
            if key in seen:
                fail(f"duplicate selected {kind}: {key}")
            seen.add(key)
            selected.append(normalize_entry(kind, entry))
        normalized[kind] = sorted(selected, key=lambda item: semantic_key(kind, item))
    return normalized


def canonical_json_bytes(data: Contract) -> bytes:
    """@brief Serialize canonical JSON with one trailing newline."""
    text = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return (text + "\n").encode("utf-8")


def atomic_write(path: Path, content: bytes) -> None:
    """@brief Atomically replace one output with exact bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


# PUBLIC API


def normalize_command(arguments: argparse.Namespace) -> int:
    """@brief Implement the normalize subcommand."""
    architecture = normalize_architecture(arguments.platform)
    normalized = normalize_contract(
        arguments.contract, arguments.image, architecture, arguments.lock
    )
    output = canonical_json_bytes(normalized)
    packages = "".join(
        f"{item['name']}\n" for item in normalized["direct_package"]
    ).encode("utf-8")
    atomic_write(arguments.output, output)
    if arguments.packages_output is not None:
        atomic_write(arguments.packages_output, packages)
    print(hashlib.sha256(output).hexdigest())
    return 0


def inventory_command(arguments: argparse.Namespace) -> int:
    """@brief Convert dpkg-query TSV on standard input to canonical JSON."""
    packages: list[Contract] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(sys.stdin, start=1):
        line = raw_line.rstrip("\n")
        fields = line.split("\t")
        if len(fields) != 3:
            fail(f"inventory line {line_number} must have three tab-separated fields")
        name, version, architecture = (
            require_string(value, f"inventory line {line_number}") for value in fields
        )
        if not NAME_PATTERN.fullmatch(name):
            fail(f"inventory line {line_number} has invalid package name: {name}")
        if name in seen:
            fail(f"duplicate resolved package: {name}")
        seen.add(name)
        packages.append(
            {"name": name, "version": version, "architecture": architecture}
        )
    if not packages:
        fail("resolved package inventory must not be empty")
    data: Contract = {
        "schema": 1,
        "packages": sorted(packages, key=lambda item: str(item["name"])),
    }
    output = canonical_json_bytes(data)
    atomic_write(arguments.output, output)
    print(hashlib.sha256(output).hexdigest())
    return 0


def parser() -> argparse.ArgumentParser:
    """@brief Create the command-line parser."""
    result = argparse.ArgumentParser(description=__doc__)
    subcommands = result.add_subparsers(dest="command", required=True)
    normalize = subcommands.add_parser("normalize")
    normalize.add_argument("--contract", type=Path, required=True)
    normalize.add_argument("--image", choices=("mingw", "appimage"), required=True)
    normalize.add_argument("--platform", required=True)
    normalize.add_argument("--lock", type=Path, required=True)
    normalize.add_argument("--output", type=Path, required=True)
    normalize.add_argument("--packages-output", type=Path)
    normalize.set_defaults(handler=normalize_command)
    inventory = subcommands.add_parser("inventory")
    inventory.add_argument("--output", type=Path, required=True)
    inventory.set_defaults(handler=inventory_command)
    return result


def main() -> int:
    """@brief Run the selected command and render bounded errors."""
    try:
        arguments = parser().parse_args()
        return int(arguments.handler(arguments))
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
