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
@file builder_identity.py
@brief Calculate separated builder lifecycle identities.
@details Hashes selected normalized contract and image-content inputs separately
         from verifier and mandatory test-policy inputs.
"""

# IMPORTS

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tomllib
from typing import Any

import dependency_contract


# CONSTANTS

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
POLICY_ROLE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
PROFILE_FIELDS = {
    "schema",
    "image",
    "platform",
    "target",
    "qt5_freeze",
    "glib_version",
    "include_patches",
    "exclude_patches",
}
POLICY_FIELDS = {"schema", "policy"}
POLICY_ENTRY_FIELDS = {"image", "architecture", "mandatory_tests"}
TEST_ROLE_FILES = {
    "windows-python": "windows_python_smoke.sh",
    "networking-stack": "networking_stack_decode_smoke.sh",
    "pe-import-closure": "pe_import_closure_test.sh",
    "appimage-identity": "appimage_identity_smoke.sh",
    "appimage-runtime": "appimage_runtime_smoke.sh",
    "appimage-gui-startup": "appimage_gui_smoke.sh",
    "deb-metadata": "deb_artifact_metadata_test.sh",
}
TEST_ROLE_INPUT_FILES = {
    "networking-stack": (
        "networking_stack_decode_smoke.sh",
        "gen_networking_stack_captures.py",
    ),
    "appimage-runtime": (
        "appimage_runtime_smoke.sh",
        "gen_networking_stack_captures.py",
    ),
}
LOCK_SELECTION = {
    ("mingw", "amd64"): {
        "source": {"mxe": ("commit",)},
        "artifact": {
            "builder-base-debian-bookworm-slim": ("version", "url", "sha256"),
            "cpython-windows-embed": ("version", "url", "sha256"),
            "cpython-source": ("version", "url", "sha256"),
        },
    },
    ("appimage", "amd64"): {
        "source": {},
        "artifact": {
            "builder-base-ubuntu-22.04": ("version", "url", "sha256"),
            "appimagetool": ("version", "url", "sha256"),
            "linuxdeployqt": ("version", "url", "sha256"),
            "appimage-runtime-x86_64": ("version", "url", "sha256"),
        },
    },
    ("appimage", "arm64"): {
        "source": {},
        "artifact": {
            "builder-base-ubuntu-22.04": ("version", "url", "sha256"),
            "appimagetool-aarch64": ("version", "url", "sha256"),
            "linuxdeployqt-aarch64": ("version", "url", "sha256"),
            "appimage-runtime-aarch64": ("version", "url", "sha256"),
        },
    },
}


# DATA MODELS / TYPEDEFINITIONS

JsonObject = dict[str, Any]


# HELPER FUNCTIONS


def canonical_bytes(data: Any) -> bytes:
    """@brief Serialize canonical JSON bytes with one trailing newline."""
    return (
        json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")


def digest_bytes(content: bytes) -> str:
    """@brief Return lowercase SHA-256 for exact bytes."""
    return hashlib.sha256(content).hexdigest()


def digest_file(path: Path) -> str:
    """@brief Return lowercase SHA-256 for one required file."""
    return digest_bytes(path.read_bytes())


def read_toml(path: Path) -> JsonObject:
    """@brief Read one TOML root table."""
    with path.open("rb") as stream:
        data = tomllib.load(stream)
    if not isinstance(data, dict):
        raise ValueError(f"{path} root must be a table")
    return data


def require_string(value: Any, label: str) -> str:
    """@brief Validate a non-empty single-line string."""
    if not isinstance(value, str) or not value or "\n" in value or "\x00" in value:
        raise ValueError(f"{label} must be a non-empty single-line string")
    return value


def require_string_list(value: Any, label: str) -> list[str]:
    """@brief Validate an array of unique strings."""
    if not isinstance(value, list):
        raise ValueError(f"{label} must be an array")
    result = [require_string(item, label) for item in value]
    if len(result) != len(set(result)):
        raise ValueError(f"{label} contains duplicates")
    return result


def unique_entries(data: JsonObject, table: str) -> dict[str, JsonObject]:
    """@brief Index one lock table by unique name."""
    result: dict[str, JsonObject] = {}
    entries = data.get(table, [])
    if not isinstance(entries, list):
        raise ValueError(f"lock {table} must be an array of tables")
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"lock {table}[{index}] must be a table")
        name = require_string(entry.get("name"), f"lock {table}[{index}].name")
        if name in result:
            raise ValueError(f"duplicate lock {table}: {name}")
        result[name] = entry
    return result


def selected_lock_data(path: Path, image: str, architecture: str) -> JsonObject:
    """@brief Return only consumed fields for applicable lock entries."""
    try:
        selection = LOCK_SELECTION[(image, architecture)]
    except KeyError as error:
        raise ValueError(
            f"unsupported builder variant: {image}/{architecture}"
        ) from error
    lock = read_toml(path)
    result: JsonObject = {"source": {}, "artifact": {}}
    for table in ("source", "artifact"):
        indexed = unique_entries(lock, table)
        for name, fields in selection[table].items():
            if name not in indexed:
                raise ValueError(f"lock has no {table} named {name}")
            selected: JsonObject = {}
            for field in fields:
                if field not in indexed[name]:
                    raise ValueError(f"lock {table}.{name} has no {field}")
                value = indexed[name][field]
                if isinstance(value, (dict, list)):
                    raise ValueError(f"lock {table}.{name}.{field} must be scalar")
                selected[field] = value
            result[table][name] = selected
    return result


def load_profile(path: Path, image: str, architecture: str) -> JsonObject:
    """@brief Validate and normalize the canonical MinGW profile."""
    data = read_toml(path)
    unknown = set(data) - PROFILE_FIELDS
    if unknown:
        raise ValueError(f"profile has unknown fields: {', '.join(sorted(unknown))}")
    if data.get("schema") != 1 or isinstance(data.get("schema"), bool):
        raise ValueError("unsupported builder profile schema")
    if data.get("image") != image or image != "mingw":
        raise ValueError("profile does not describe the MinGW builder")
    if data.get("platform") != f"linux/{architecture}" or architecture != "amd64":
        raise ValueError("canonical MinGW profile must target linux/amd64")
    target = require_string(data.get("target"), "profile.target")
    if target != "x86_64-w64-mingw32.static.posix":
        raise ValueError(f"unsupported canonical MinGW target: {target}")
    if not isinstance(data.get("qt5_freeze"), bool):
        raise ValueError("profile.qt5_freeze must be Boolean")
    glib_version = require_string(data.get("glib_version"), "profile.glib_version")
    include = require_string_list(data.get("include_patches"), "include_patches")
    exclude = require_string_list(data.get("exclude_patches"), "exclude_patches")
    overlap = set(include) & set(exclude)
    if overlap:
        raise ValueError(f"profile patch appears in both lists: {sorted(overlap)[0]}")
    return {
        "schema": 1,
        "image": image,
        "platform": "linux/amd64",
        "target": target,
        "qt5_freeze": data["qt5_freeze"],
        "glib_version": glib_version,
        "include_patches": sorted(include),
        "exclude_patches": sorted(exclude),
    }


def selected_contract(
    contract_path: Path,
    lock_path: Path,
    image: str,
    architecture: str,
) -> tuple[JsonObject, bytes, str]:
    """@brief Normalize the selected contract and return data, bytes, digest."""
    data = dependency_contract.normalize_contract(
        contract_path, image, architecture, lock_path
    )
    content = dependency_contract.canonical_json_bytes(data)
    return data, content, digest_bytes(content)


def recipe_inputs(arguments: argparse.Namespace) -> tuple[JsonObject, str]:
    """@brief Build canonical image-content input data and its digest."""
    architecture = dependency_contract.normalize_architecture(arguments.platform)
    _, _, contract_spec = selected_contract(
        arguments.contract, arguments.lock, arguments.image, architecture
    )
    profile: JsonObject | None = None
    patches: list[JsonObject] = []
    effective: JsonObject = {}
    if arguments.image == "mingw":
        if arguments.profile is None:
            raise ValueError("the MinGW builder requires --profile")
        profile = load_profile(arguments.profile, arguments.image, architecture)
        selected = set(profile["include_patches"])
        selected -= set(arguments.skip_patch)
        if arguments.no_sigrok_patches:
            selected.clear()
        for name in sorted(selected):
            patch = arguments.patch_dir / name
            if not patch.is_file():
                raise ValueError(f"selected patch missing: {patch}")
            patches.append({"name": name, "sha256": digest_file(patch)})
        effective = {
            "target": profile["target"],
            "qt5_freeze": bool(profile["qt5_freeze"] or arguments.qt5_freeze),
            "glib_version": arguments.glib_version or profile["glib_version"],
            "patches": [item["name"] for item in patches],
        }
    elif arguments.profile is not None:
        raise ValueError("--profile applies only to the MinGW builder")

    helpers: list[JsonObject] = []
    if arguments.image == "mingw":
        for name in ("mxe-build.sh", "mxe-glib-hold.sh"):
            path = arguments.helpers_dir / name
            if not path.is_file():
                raise ValueError(f"builder helper missing: {path}")
            helpers.append({"role": name, "sha256": digest_file(path)})

    if not arguments.dockerfile.is_file():
        raise ValueError(f"Dockerfile missing: {arguments.dockerfile}")
    data: JsonObject = {
        "schema": 1,
        "image": arguments.image,
        "architecture": architecture,
        "dependency_contract_spec": contract_spec,
        "dockerfile_sha256": digest_file(arguments.dockerfile),
        "helpers": helpers,
        "patches": patches,
        "lock": selected_lock_data(arguments.lock, arguments.image, architecture),
        "effective": effective,
        "metadata_finalization_schema": 1,
        "metadata_dockerfile_sha256": digest_file(arguments.metadata_dockerfile),
    }
    if profile is not None:
        data["profile"] = profile
    return data, digest_bytes(canonical_bytes(data))


def selected_policy(path: Path, image: str, architecture: str) -> JsonObject:
    """@brief Validate and select one mandatory-test policy row."""
    data = read_toml(path)
    unknown = set(data) - POLICY_FIELDS
    if unknown:
        raise ValueError(f"policy has unknown fields: {', '.join(sorted(unknown))}")
    if data.get("schema") != 1 or isinstance(data.get("schema"), bool):
        raise ValueError("unsupported validation policy schema")
    rows = data.get("policy")
    if not isinstance(rows, list):
        raise ValueError("policy must be an array of tables")
    selected: list[JsonObject] = []
    seen: set[tuple[str, str]] = set()
    for index, row in enumerate(rows, start=1):
        if not isinstance(row, dict):
            raise ValueError(f"policy[{index}] must be a table")
        unknown_row = set(row) - POLICY_ENTRY_FIELDS
        if unknown_row:
            raise ValueError(
                f"policy[{index}] has unknown fields: {', '.join(sorted(unknown_row))}"
            )
        row_image = require_string(row.get("image"), f"policy[{index}].image")
        row_arch = dependency_contract.normalize_architecture(
            require_string(row.get("architecture"), f"policy[{index}].architecture")
        )
        key = (row_image, row_arch)
        if key in seen:
            raise ValueError(f"duplicate validation policy: {row_image}/{row_arch}")
        seen.add(key)
        tests = require_string_list(
            row.get("mandatory_tests"), f"policy[{index}].mandatory_tests"
        )
        if not tests:
            raise ValueError(f"policy[{index}].mandatory_tests must not be empty")
        for role in tests:
            if not POLICY_ROLE_PATTERN.fullmatch(role):
                raise ValueError(
                    f"policy[{index}].mandatory_tests has invalid role: {role}"
                )
        if key == (image, architecture):
            selected.append(
                {
                    "image": row_image,
                    "architecture": row_arch,
                    "mandatory_tests": tests,
                }
            )
    if len(selected) != 1:
        raise ValueError(f"validation policy has no row for {image}/{architecture}")
    return selected[0]


def test_role_path(role: str, tests_dir: Path) -> Path:
    """@brief Resolve one policy role to its repository test file."""
    filename = TEST_ROLE_FILES.get(role, f"{role.replace('-', '_')}.sh")
    return tests_dir / filename


def test_role_input_paths(role: str, tests_dir: Path) -> list[Path]:
    """@brief Resolve the executable test and any helper inputs it consumes."""
    filenames = TEST_ROLE_INPUT_FILES.get(role)
    if filenames is None:
        return [test_role_path(role, tests_dir)]
    return [tests_dir / filename for filename in filenames]


def validation_inputs(arguments: argparse.Namespace) -> tuple[JsonObject, str]:
    """@brief Build canonical validation-policy inputs and digest."""
    architecture = dependency_contract.normalize_architecture(arguments.platform)
    if (
        arguments.policy is None
        or arguments.verifier is None
        or arguments.tests_dir is None
    ):
        raise ValueError(
            "validation identity requires --policy, --verifier, and --tests-dir"
        )
    selected = selected_policy(arguments.policy, arguments.image, architecture)
    if not arguments.verifier.is_file():
        raise ValueError(f"verifier missing: {arguments.verifier}")
    verifier_files = [arguments.verifier]
    default_verifier = Path(__file__).resolve().parent / "verify_builder_environment.sh"
    if arguments.verifier.resolve() == default_verifier:
        verifier_files += [
            Path(__file__).resolve(),
            Path(__file__).resolve().parent / "dependency_contract.py",
            Path(__file__).resolve().parent / "verify_dependency_contract.py",
            Path(__file__).resolve().parent / "builder_validation_record.py",
            Path(__file__).resolve().parent / "run_builder_validation.py",
        ]
    verifier_inputs = []
    for path in verifier_files:
        if not path.is_file():
            raise ValueError(f"validation policy input missing: {path}")
        verifier_inputs.append({"role": path.name, "sha256": digest_file(path)})
    verifier_inputs.sort(key=lambda item: item["role"])
    tests: list[JsonObject] = []
    for role in selected["mandatory_tests"]:
        for path in test_role_input_paths(role, arguments.tests_dir):
            if not path.is_file():
                raise ValueError(f"mandatory test input for {role} missing: {path}")
            tests.append(
                {
                    "role": role,
                    "file": path.name,
                    "sha256": digest_file(path),
                }
            )
    data = {
        "schema": 1,
        "selection": selected,
        "verifier_files": verifier_inputs,
        "tests": tests,
    }
    return data, digest_bytes(canonical_bytes(data))


# PUBLIC API


def run(arguments: argparse.Namespace) -> int:
    """@brief Calculate and print the selected identity form."""
    architecture = dependency_contract.normalize_architecture(arguments.platform)
    if arguments.kind == "profile":
        if arguments.profile is None:
            raise ValueError("profile output requires --profile")
        profile = load_profile(arguments.profile, arguments.image, architecture)
        print(canonical_bytes(profile).decode("utf-8"), end="")
        return 0
    _, contract_content, contract_spec = selected_contract(
        arguments.contract,
        arguments.lock,
        arguments.image,
        architecture,
    )
    result: JsonObject = {"dependency_contract_spec": contract_spec}
    if arguments.kind in {"recipe", "all"}:
        inputs, recipe_spec = recipe_inputs(arguments)
        result["builder_recipe_spec"] = recipe_spec
        if arguments.include_inputs:
            result["builder_recipe_inputs"] = inputs
    if arguments.kind in {"validation", "all"}:
        inputs, policy_spec = validation_inputs(arguments)
        result["validation_policy_spec"] = policy_spec
        if arguments.include_inputs:
            result["validation_policy_inputs"] = inputs
    if arguments.kind == "contract":
        print(contract_spec)
    elif arguments.kind == "recipe" and not arguments.json:
        print(result["builder_recipe_spec"])
    elif arguments.kind == "validation" and not arguments.json:
        print(result["validation_policy_spec"])
    else:
        print(canonical_bytes(result).decode("utf-8"), end="")
    del contract_content
    return 0


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the identity command parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "kind", choices=("recipe", "contract", "validation", "profile", "all")
    )
    parser.add_argument("--image", choices=("mingw", "appimage"), required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--dockerfile", type=Path)
    parser.add_argument("--metadata-dockerfile", type=Path)
    parser.add_argument("--helpers-dir", type=Path)
    parser.add_argument("--patch-dir", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--verifier", type=Path)
    parser.add_argument("--tests-dir", type=Path)
    parser.add_argument("--skip-patch", action="append", default=[])
    parser.add_argument("--no-sigrok-patches", action="store_true")
    parser.add_argument("--qt5-freeze", action="store_true")
    parser.add_argument("--glib-version", default="")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--include-inputs", action="store_true")
    return parser


def fill_defaults(arguments: argparse.Namespace) -> None:
    """@brief Fill repository defaults relative to this script."""
    script_dir = Path(__file__).resolve().parent
    root = script_dir.parent.parent
    images = script_dir / "images"
    architecture = dependency_contract.normalize_architecture(arguments.platform)
    suffix = "mingw" if arguments.image == "mingw" else "appimage"
    arguments.dockerfile = arguments.dockerfile or images / f"Dockerfile.{suffix}"
    arguments.metadata_dockerfile = (
        arguments.metadata_dockerfile or images / "Dockerfile.builder-metadata"
    )
    arguments.helpers_dir = arguments.helpers_dir or images
    arguments.patch_dir = arguments.patch_dir or (
        root / "05_Software/sigrok-util/cross-compile/mingw"
    )
    if arguments.image == "mingw":
        arguments.profile = arguments.profile or images / "builder_profile.mingw.toml"
    if arguments.kind in {"validation", "all"}:
        arguments.policy = arguments.policy or images / "validation_policy.toml"
        arguments.verifier = (
            arguments.verifier or script_dir / "verify_builder_environment.sh"
        )
        arguments.tests_dir = arguments.tests_dir or root / "02_Tools/test"
    if arguments.image == "mingw" and architecture != "amd64":
        raise ValueError("the MinGW builder supports only amd64")


def main() -> int:
    """@brief Run identity calculation with bounded error output."""
    try:
        arguments = command_parser().parse_args()
        fill_defaults(arguments)
        return run(arguments)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
