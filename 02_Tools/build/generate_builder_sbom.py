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
@file generate_builder_sbom.py
@brief Generate and verify identity-bound SPDX 2.3 builder SBOMs.
"""

# IMPORTS

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any


# CONSTANTS

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
CREATED_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
INVENTORY_FIELDS = {"schema", "packages"}
PACKAGE_FIELDS = {"name", "version", "architecture"}


# DATA MODELS / TYPEDEFINITIONS

JsonObject = dict[str, Any]


# HELPER FUNCTIONS


def sha256(value: str, label: str) -> str:
    """@brief Validate and return one lowercase SHA-256 value."""
    if not SHA256_PATTERN.fullmatch(value):
        raise ValueError(f"{label} must be lowercase SHA-256")
    return value


def canonical_bytes(value: Any) -> bytes:
    """@brief Serialize canonical JSON with one trailing newline."""
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")


def atomic_write(path: Path, content: bytes) -> None:
    """@brief Atomically replace one complete generated file."""
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


def plain_string(value: Any, label: str) -> str:
    """@brief Validate one non-empty single-line string."""
    if not isinstance(value, str) or not value or "\n" in value or "\x00" in value:
        raise ValueError(f"{label} must be a non-empty single-line string")
    return value


def read_inventory(path: Path) -> tuple[list[JsonObject], str]:
    """@brief Strictly parse resolved package inventory and hash exact bytes."""
    content = path.read_bytes()
    data = json.loads(content)
    if (
        not isinstance(data, dict)
        or set(data) != INVENTORY_FIELDS
        or data["schema"] != 1
    ):
        raise ValueError("inventory must be an exact schema-1 document")
    if not isinstance(data["packages"], list):
        raise ValueError("inventory packages must be an array")
    result: list[JsonObject] = []
    keys: set[tuple[str, str]] = set()
    for index, package in enumerate(data["packages"], start=1):
        if not isinstance(package, dict) or set(package) != PACKAGE_FIELDS:
            raise ValueError(f"inventory package {index} has an unexpected shape")
        normalized = {
            field: plain_string(package[field], f"package {index}.{field}")
            for field in ("name", "version", "architecture")
        }
        key = (normalized["name"], normalized["architecture"])
        if key in keys:
            raise ValueError(f"duplicate inventory package: {key[0]}/{key[1]}")
        keys.add(key)
        result.append(normalized)
    ordered = sorted(result, key=lambda item: (item["name"], item["architecture"]))
    return ordered, hashlib.sha256(content).hexdigest()


def created_time(value: str) -> str:
    """@brief Validate a stable UTC SPDX timestamp."""
    if not CREATED_PATTERN.fullmatch(value):
        raise ValueError("created must use YYYY-MM-DDTHH:MM:SSZ")
    datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    return value


def package_id(package: JsonObject) -> str:
    """@brief Create a stable SPDX identifier without lossy name escaping."""
    key = f"{package['name']}\0{package['version']}\0{package['architecture']}"
    return "SPDXRef-Package-" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:20]


def sbom_document(arguments: argparse.Namespace) -> JsonObject:
    """@brief Build one complete deterministic SPDX document."""
    packages, inventory_sha = read_inventory(arguments.inventory)
    image_id = sha256(arguments.image_id.removeprefix("sha256:"), "image ID")
    recipe = sha256(arguments.builder_recipe_spec, "builder recipe identity")
    contract = sha256(
        arguments.dependency_contract_spec, "dependency contract identity"
    )
    architecture = arguments.platform.removeprefix("linux/")
    if architecture == "x86_64":
        architecture = "amd64"
    elif architecture == "aarch64":
        architecture = "arm64"
    if architecture not in {"amd64", "arm64"}:
        raise ValueError(f"unsupported architecture: {arguments.platform}")
    if arguments.image == "mingw" and architecture != "amd64":
        raise ValueError("MinGW SBOM cannot select arm64")
    identity = {
        "image": arguments.image,
        "architecture": architecture,
        "image_id": image_id,
        "builder_recipe_spec": recipe,
        "dependency_contract_spec": contract,
        "resolved_inventory_sha256": inventory_sha,
    }
    image_package = {
        "SPDXID": "SPDXRef-BuilderImage",
        "name": "builder-image",
        "versionInfo": image_id,
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "copyrightText": "NOASSERTION",
        "comment": json.dumps(identity, sort_keys=True, separators=(",", ":")),
    }
    package_documents: list[JsonObject] = [image_package]
    relationships: list[JsonObject] = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": "SPDXRef-BuilderImage",
        }
    ]
    for package in packages:
        identifier = package_id(package)
        package_documents.append(
            {
                "SPDXID": identifier,
                "name": package["name"],
                "versionInfo": package["version"],
                "primaryPackagePurpose": "LIBRARY",
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": "NOASSERTION",
                "licenseDeclared": "NOASSERTION",
                "copyrightText": "NOASSERTION",
                "comment": f"dpkg architecture: {package['architecture']}",
            }
        )
        relationships.append(
            {
                "spdxElementId": "SPDXRef-BuilderImage",
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": identifier,
            }
        )
    namespace = f"https://ddp.example.invalid/spdx/builder/{image_id}/{inventory_sha}"
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"pulseview-{arguments.image}-builder-{architecture}",
        "documentNamespace": namespace,
        "creationInfo": {
            "created": created_time(arguments.created),
            "creators": ["Tool: PulseView generate_builder_sbom.py"],
        },
        "documentDescribes": ["SPDXRef-BuilderImage"],
        "packages": package_documents,
        "relationships": relationships,
    }


# PUBLIC API


def generate_command(arguments: argparse.Namespace) -> int:
    """@brief Generate one canonical SPDX 2.3 JSON file."""
    atomic_write(arguments.output, canonical_bytes(sbom_document(arguments)))
    return 0


def verify_command(arguments: argparse.Namespace) -> int:
    """@brief Require an SBOM to exactly match the selected inventory and identities."""
    actual = json.loads(arguments.sbom.read_text(encoding="utf-8"))
    expected = sbom_document(arguments)
    if actual != expected:
        raise ValueError(
            "SBOM content does not match selected inventory and identities"
        )
    if arguments.sbom.read_bytes() != canonical_bytes(actual):
        raise ValueError("SBOM is not canonical JSON")
    return 0


def add_common(parser: argparse.ArgumentParser) -> None:
    """@brief Add arguments shared by generate and verify."""
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--image", choices=("mingw", "appimage"), required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--builder-recipe-spec", required=True)
    parser.add_argument("--dependency-contract-spec", required=True)
    parser.add_argument("--created", required=True)


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the command parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    generate = commands.add_parser("generate")
    add_common(generate)
    generate.add_argument("--output", type=Path, required=True)
    generate.set_defaults(handler=generate_command)
    verify = commands.add_parser("verify")
    add_common(verify)
    verify.add_argument("--sbom", type=Path, required=True)
    verify.set_defaults(handler=verify_command)
    return parser


def main() -> int:
    """@brief Run selected operation with bounded errors."""
    try:
        arguments = command_parser().parse_args()
        return int(arguments.handler(arguments))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
