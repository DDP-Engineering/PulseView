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
@file builder_validation_record.py
@brief Write canonical external builder validation evidence.
"""

# IMPORTS

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import tempfile


# CONSTANTS

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


# HELPER FUNCTIONS


def sha256(value: str, label: str) -> str:
    """@brief Validate a lowercase SHA-256 value."""
    if not SHA256_PATTERN.fullmatch(value):
        raise ValueError(f"{label} must be lowercase SHA-256")
    return value


def atomic_write(path: Path, content: bytes) -> None:
    """@brief Atomically replace one record after complete serialization."""
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


def expected_fields(arguments: argparse.Namespace) -> dict[str, object]:
    """@brief Return validated identity fields shared by write and check."""
    return {
        "image": arguments.image,
        "architecture": arguments.architecture,
        "image_id": sha256(arguments.image_id, "image ID"),
        "builder_recipe_spec": sha256(arguments.recipe, "recipe identity"),
        "dependency_contract_spec": sha256(arguments.contract, "contract identity"),
        "normalized_contract_sha256": sha256(
            arguments.normalized_contract, "normalized contract hash"
        ),
        "resolved_inventory_sha256": sha256(
            arguments.inventory, "resolved inventory hash"
        ),
        "validation_policy_spec": sha256(arguments.policy, "policy identity"),
    }


def write_record(arguments: argparse.Namespace) -> int:
    """@brief Validate and write one passing evidence record."""
    data = {
        "schema": 1,
        "result": "pass",
        "verified_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "level": arguments.level,
        **expected_fields(arguments),
    }
    content = (
        json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")
    atomic_write(arguments.output, content)
    return 0


def check_record(arguments: argparse.Namespace) -> int:
    """@brief Reject stale, malformed or non-passing validation evidence."""
    data = json.loads(arguments.input.read_text(encoding="utf-8"))
    required = {
        "schema",
        "result",
        "verified_at",
        "level",
        *expected_fields(arguments).keys(),
    }
    if not isinstance(data, dict) or set(data) != required:
        raise ValueError("validation record has an unexpected shape")
    if data["schema"] != 1 or data["result"] != "pass":
        raise ValueError("validation record is not a schema-1 pass")
    if data["level"] not in {"standard", "full"}:
        raise ValueError("validation record has insufficient level")
    for key, value in expected_fields(arguments).items():
        if data.get(key) != value:
            raise ValueError(f"validation record {key} does not match")
    return 0


def add_identity_arguments(parser: argparse.ArgumentParser) -> None:
    """@brief Add identity fields shared by write and check commands."""
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--image", choices=("mingw", "appimage"), required=True)
    parser.add_argument("--architecture", choices=("amd64", "arm64"), required=True)
    parser.add_argument("--recipe", required=True)
    parser.add_argument("--contract", required=True)
    parser.add_argument("--normalized-contract", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--policy", required=True)


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the command-line parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    write = commands.add_parser("write")
    write.add_argument("--output", type=Path, required=True)
    write.add_argument("--level", choices=("standard", "full"), required=True)
    add_identity_arguments(write)
    write.set_defaults(handler=write_record)
    check = commands.add_parser("check")
    check.add_argument("--input", type=Path, required=True)
    add_identity_arguments(check)
    check.set_defaults(handler=check_record)
    return parser


def main() -> int:
    """@brief Write a record with bounded error output."""
    try:
        arguments = command_parser().parse_args()
        return int(arguments.handler(arguments))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
