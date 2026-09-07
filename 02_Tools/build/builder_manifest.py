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
@file builder_manifest.py
@brief Create, strictly parse and verify builder archive manifests.
@details Supports complete schema-2 lifecycle metadata and read-only schema-1
         archive compatibility. All outputs are atomic.
"""

# IMPORTS

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib
from typing import Any, BinaryIO, NoReturn


# CONSTANTS

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
IMAGE_ID_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
SAFE_FILE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
SCHEMA1_FIELDS = {
    "schema",
    "format",
    "image",
    "platform",
    "tag",
    "image_id",
    "builder_spec",
    "archive",
    "archive_size",
    "archive_sha256",
    "part",
}
SCHEMA2_FIELDS = {
    "schema",
    "format",
    "image",
    "platform",
    "install_tag",
    "archive_tag",
    "image_id",
    "builder_recipe_spec",
    "dependency_contract_spec",
    "validation_policy_spec",
    "archive",
    "normalized_contract",
    "resolved_inventory",
    "sbom",
    "part",
}
ARTIFACT_FIELDS = {"file", "size", "sha256"}
LICENSE_HEADER = """# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
"""


# DATA MODELS / TYPEDEFINITIONS

JsonObject = dict[str, Any]


# HELPER FUNCTIONS


def fail(message: str) -> NoReturn:
    """@brief Stop parsing with one actionable error."""
    raise ValueError(message)


def sha256(value: Any, label: str) -> str:
    """@brief Validate one lowercase SHA-256 string."""
    if not isinstance(value, str) or not SHA256_PATTERN.fullmatch(value):
        fail(f"{label} must be lowercase SHA-256")
    return value


def plain_string(value: Any, label: str) -> str:
    """@brief Validate one non-empty single-line string."""
    if not isinstance(value, str) or not value or "\n" in value or "\x00" in value:
        fail(f"{label} must be a non-empty single-line string")
    return value


def safe_file(value: Any, label: str) -> str:
    """@brief Validate a local basename with no traversal or separators."""
    name = plain_string(value, label)
    if not SAFE_FILE_PATTERN.fullmatch(name) or Path(name).name != name:
        fail(f"{label} must be a safe local basename: {name}")
    return name


def integer(value: Any, label: str) -> int:
    """@brief Validate a non-negative integer excluding Boolean values."""
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        fail(f"{label} must be a non-negative integer")
    return value


def architecture(platform: Any) -> str:
    """@brief Validate a canonical manifest platform and return architecture."""
    value = plain_string(platform, "platform")
    if value == "linux/amd64":
        return "amd64"
    if value == "linux/arm64":
        return "arm64"
    fail(f"unsupported manifest platform: {value}")


def input_architecture(platform: Any) -> str:
    """@brief Normalize a command-line architecture or platform spelling."""
    value = plain_string(platform, "platform")
    if value in {"x86_64", "amd64", "linux/amd64"}:
        return "amd64"
    if value in {"aarch64", "arm64", "linux/arm64"}:
        return "arm64"
    fail(f"unsupported platform: {value}")


def validate_artifact(value: Any, label: str) -> JsonObject:
    """@brief Validate one exact file-size-hash table."""
    if not isinstance(value, dict) or set(value) != ARTIFACT_FIELDS:
        fail(f"{label} must contain exactly file, size, and sha256")
    return {
        "file": safe_file(value["file"], f"{label}.file"),
        "size": integer(value["size"], f"{label}.size"),
        "sha256": sha256(value["sha256"], f"{label}.sha256"),
    }


def validate_parts(value: Any) -> list[JsonObject]:
    """@brief Validate ordered unique archive part records."""
    if not isinstance(value, list) or not value:
        fail("manifest part must be a non-empty array of tables")
    result: list[JsonObject] = []
    names: set[str] = set()
    for index, item in enumerate(value, start=1):
        part = validate_artifact(item, f"part[{index}]")
        if part["file"] in names:
            fail(f"duplicate part file: {part['file']}")
        names.add(str(part["file"]))
        result.append(part)
    return result


def validate_common(data: JsonObject) -> tuple[str, str]:
    """@brief Validate fields shared by both manifest schemas."""
    if data.get("format") != "docker-archive":
        fail("manifest format must be docker-archive")
    image = plain_string(data.get("image"), "image")
    if image not in {"mingw", "appimage"}:
        fail(f"unsupported manifest image: {image}")
    arch = architecture(data.get("platform"))
    if image == "mingw" and arch != "amd64":
        fail("MinGW manifest cannot select arm64")
    if data.get("schema") == 1:
        plain_string(data.get("tag"), "tag")
    else:
        plain_string(data.get("install_tag"), "install_tag")
        plain_string(data.get("archive_tag"), "archive_tag")
    image_id = plain_string(data.get("image_id"), "image_id")
    if not IMAGE_ID_PATTERN.fullmatch(image_id):
        fail("image_id must be sha256:<lowercase SHA-256>")
    return image, arch


def parse_schema1(data: JsonObject) -> JsonObject:
    """@brief Normalize one strict legacy manifest."""
    if set(data) != SCHEMA1_FIELDS:
        fail("schema-1 manifest has unknown or missing fields")
    image, arch = validate_common(data)
    builder_spec = data["builder_spec"]
    if builder_spec != "":
        sha256(builder_spec, "builder_spec")
    parts = validate_parts(data["part"])
    archive = {
        "file": safe_file(data["archive"], "archive"),
        "size": integer(data["archive_size"], "archive_size"),
        "sha256": sha256(data["archive_sha256"], "archive_sha256"),
    }
    return {
        "schema": 1,
        "legacy": True,
        "format": "docker-archive",
        "image": image,
        "platform": data["platform"],
        "architecture": arch,
        "tag": data["tag"],
        "install_tag": data["tag"],
        "archive_tag": data["tag"],
        "image_id": data["image_id"],
        "builder_recipe_spec": builder_spec or None,
        "dependency_contract_spec": None,
        "validation_policy_spec": None,
        "normalized_contract_sha256": None,
        "resolved_inventory_sha256": None,
        "sbom_sha256": None,
        "archive": archive,
        "part": parts,
    }


def parse_schema2(data: JsonObject) -> JsonObject:
    """@brief Normalize one strict complete lifecycle manifest."""
    if set(data) != SCHEMA2_FIELDS:
        fail("schema-2 manifest has unknown or missing fields")
    image, arch = validate_common(data)
    archive = validate_artifact(data["archive"], "archive")
    contract = validate_artifact(data["normalized_contract"], "normalized_contract")
    inventory = validate_artifact(data["resolved_inventory"], "resolved_inventory")
    sbom = validate_artifact(data["sbom"], "sbom")
    contract_spec = sha256(data["dependency_contract_spec"], "dependency_contract_spec")
    if contract_spec != contract["sha256"]:
        fail("dependency_contract_spec does not match normalized contract hash")
    return {
        "schema": 2,
        "legacy": False,
        "format": "docker-archive",
        "image": image,
        "platform": data["platform"],
        "architecture": arch,
        "tag": data["install_tag"],
        "install_tag": data["install_tag"],
        "archive_tag": data["archive_tag"],
        "image_id": data["image_id"],
        "builder_recipe_spec": sha256(
            data["builder_recipe_spec"], "builder_recipe_spec"
        ),
        "dependency_contract_spec": contract_spec,
        "validation_policy_spec": sha256(
            data["validation_policy_spec"], "validation_policy_spec"
        ),
        "normalized_contract_sha256": contract["sha256"],
        "resolved_inventory_sha256": inventory["sha256"],
        "sbom_sha256": sbom["sha256"],
        "normalized_contract": contract,
        "resolved_inventory": inventory,
        "sbom": sbom,
        "archive": archive,
        "part": validate_parts(data["part"]),
    }


def read_manifest(path: Path) -> JsonObject:
    """@brief Strictly parse and normalize one supported manifest."""
    with path.open("rb") as stream:
        data = tomllib.load(stream)
    if not isinstance(data, dict):
        fail("manifest root must be a table")
    schema = data.get("schema")
    if schema == 1 and not isinstance(schema, bool):
        return parse_schema1(data)
    if schema == 2 and not isinstance(schema, bool):
        return parse_schema2(data)
    fail(f"unsupported manifest schema: {schema!r}")


def file_artifact(path: Path) -> JsonObject:
    """@brief Calculate a basename, byte size and SHA-256 record."""
    if not path.is_file() or path.is_symlink():
        fail(f"artifact is not a regular non-symlink file: {path}")
    return {
        "file": safe_file(path.name, "artifact file"),
        "size": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def toml_string(value: str) -> str:
    """@brief Render a TOML-compatible basic string."""
    return json.dumps(value, ensure_ascii=True)


def artifact_toml(name: str, artifact: JsonObject) -> list[str]:
    """@brief Render one named artifact table."""
    return [
        f"[{name}]",
        f"file = {toml_string(str(artifact['file']))}",
        f"size = {artifact['size']}",
        f"sha256 = {toml_string(str(artifact['sha256']))}",
        "",
    ]


def atomic_write(path: Path, content: bytes) -> None:
    """@brief Atomically replace a generated output."""
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


def ensure_colocated(output: Path, path: Path) -> None:
    """@brief Require referenced files beside the manifest being written."""
    if path.resolve().parent != output.resolve().parent:
        fail(f"manifest artifact must be beside output: {path}")


def sha256_file(path: Path) -> str:
    """@brief Hash an artifact with bounded memory use."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_one(directory: Path, artifact: JsonObject, label: str) -> Path:
    """@brief Verify one referenced artifact without following a symlink."""
    path = directory / str(artifact["file"])
    if not path.is_file() or path.is_symlink():
        fail(f"{label} is missing or not a regular file: {path.name}")
    if path.stat().st_size != artifact["size"]:
        fail(f"{label} size mismatch: {path.name}")
    if sha256_file(path) != artifact["sha256"]:
        fail(f"{label} checksum mismatch: {path.name}")
    return path


def verify_sbom_binding(path: Path, manifest: JsonObject) -> None:
    """@brief Require SPDX metadata to bind the manifest's exact identities."""
    sbom = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(sbom, dict) or sbom.get("spdxVersion") != "SPDX-2.3":
        fail("SBOM is not an SPDX 2.3 JSON document")
    packages = sbom.get("packages")
    if not isinstance(packages, list):
        fail("SBOM packages must be an array")
    images = [
        package
        for package in packages
        if isinstance(package, dict) and package.get("SPDXID") == "SPDXRef-BuilderImage"
    ]
    if len(images) != 1 or not isinstance(images[0].get("comment"), str):
        fail("SBOM must contain one identity-bearing builder image package")
    identity = json.loads(images[0]["comment"])
    expected = {
        "image": manifest["image"],
        "architecture": manifest["architecture"],
        "image_id": str(manifest["image_id"]).removeprefix("sha256:"),
        "builder_recipe_spec": manifest["builder_recipe_spec"],
        "dependency_contract_spec": manifest["dependency_contract_spec"],
        "resolved_inventory_sha256": manifest["resolved_inventory_sha256"],
    }
    if identity != expected:
        fail("SBOM identities do not match the manifest")


# PUBLIC API


def create_command(arguments: argparse.Namespace) -> int:
    """@brief Write a deterministic schema-2 manifest for colocated files."""
    paths = [
        arguments.archive,
        arguments.contract_file,
        arguments.inventory_file,
        arguments.sbom_file,
        *arguments.part,
    ]
    for path in paths:
        ensure_colocated(arguments.output, path)
    image_id = plain_string(arguments.image_id, "image_id")
    if not IMAGE_ID_PATTERN.fullmatch(image_id):
        fail("image_id must be sha256:<lowercase SHA-256>")
    arch = input_architecture(arguments.platform)
    if arguments.image == "mingw" and arch != "amd64":
        fail("MinGW manifest cannot select arm64")
    contract = file_artifact(arguments.contract_file)
    contract_spec = sha256(
        arguments.dependency_contract_spec, "dependency_contract_spec"
    )
    if contract["sha256"] != contract_spec:
        fail("dependency contract file hash does not match its identity")
    lines = [
        LICENSE_HEADER.rstrip(),
        "",
        "schema = 2",
        'format = "docker-archive"',
        f"image = {toml_string(arguments.image)}",
        f"platform = {toml_string('linux/' + arch)}",
        f"install_tag = {toml_string(plain_string(arguments.install_tag, 'install_tag'))}",
        f"archive_tag = {toml_string(plain_string(arguments.archive_tag, 'archive_tag'))}",
        f"image_id = {toml_string(image_id)}",
        "builder_recipe_spec = "
        + toml_string(sha256(arguments.builder_recipe_spec, "builder_recipe_spec")),
        f"dependency_contract_spec = {toml_string(contract_spec)}",
        "validation_policy_spec = "
        + toml_string(
            sha256(arguments.validation_policy_spec, "validation_policy_spec")
        ),
        "",
    ]
    lines += artifact_toml("archive", file_artifact(arguments.archive))
    lines += artifact_toml("normalized_contract", contract)
    lines += artifact_toml(
        "resolved_inventory", file_artifact(arguments.inventory_file)
    )
    lines += artifact_toml("sbom", file_artifact(arguments.sbom_file))
    part_artifacts = [file_artifact(path) for path in arguments.part]
    if len({item["file"] for item in part_artifacts}) != len(part_artifacts):
        fail("duplicate archive part filename")
    for part in part_artifacts:
        lines += [
            "[[part]]",
            f"file = {toml_string(str(part['file']))}",
            f"size = {part['size']}",
            f"sha256 = {toml_string(str(part['sha256']))}",
            "",
        ]
    atomic_write(arguments.output, ("\n".join(lines).rstrip() + "\n").encode("utf-8"))
    return 0


def read_command(arguments: argparse.Namespace) -> int:
    """@brief Print or atomically write normalized manifest JSON."""
    data = read_manifest(arguments.manifest)
    if arguments.format != "json":
        fail("only JSON normalized output is supported")
    content = (
        json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")
    if arguments.output is None:
        sys.stdout.buffer.write(content)
    else:
        atomic_write(arguments.output, content)
    return 0


def verify_command(arguments: argparse.Namespace) -> int:
    """@brief Verify manifest metadata and optionally reconstruct its archive."""
    manifest = read_manifest(arguments.manifest)
    directory = arguments.manifest.resolve().parent
    if arguments.mode == "metadata":
        if manifest["legacy"]:
            fail("schema-1 manifest has no lifecycle metadata to verify")
        verified = {
            field: verify_one(directory, manifest[field], field)
            for field in ("normalized_contract", "resolved_inventory", "sbom")
        }
        verify_sbom_binding(verified["sbom"], manifest)
        return 0

    if not manifest["legacy"]:
        verified = {
            field: verify_one(directory, manifest[field], field)
            for field in ("normalized_contract", "resolved_inventory", "sbom")
        }
        verify_sbom_binding(verified["sbom"], manifest)
    parts = [verify_one(directory, part, "archive part") for part in manifest["part"]]
    if sum(path.stat().st_size for path in parts) != manifest["archive"]["size"]:
        fail("archive parts do not sum to declared archive size")
    hasher = hashlib.sha256()
    output = arguments.reconstructed_output
    temporary_path: Path | None = None
    destination: BinaryIO | None = None
    try:
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(
                prefix=f".{output.name}.", dir=output.parent
            )
            os.close(descriptor)
            temporary_path = Path(temporary)
            destination = temporary_path.open("wb")
        for part in parts:
            with part.open("rb") as source:
                while chunk := source.read(1024 * 1024):
                    hasher.update(chunk)
                    if destination is not None:
                        destination.write(chunk)
        if destination is not None:
            destination.flush()
            os.fsync(destination.fileno())
            destination.close()
            destination = None
        if hasher.hexdigest() != manifest["archive"]["sha256"]:
            fail("reconstructed archive checksum mismatch")
        if temporary_path is not None and output is not None:
            os.replace(temporary_path, output)
            temporary_path = None
    finally:
        if destination is not None:
            destination.close()
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    return 0


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the manifest command parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create")
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--image", choices=("mingw", "appimage"), required=True)
    create.add_argument("--platform", required=True)
    create.add_argument("--install-tag", required=True)
    create.add_argument("--archive-tag", required=True)
    create.add_argument("--image-id", required=True)
    create.add_argument("--builder-recipe-spec", required=True)
    create.add_argument("--dependency-contract-spec", required=True)
    create.add_argument("--validation-policy-spec", required=True)
    create.add_argument("--contract-file", type=Path, required=True)
    create.add_argument("--inventory-file", type=Path, required=True)
    create.add_argument("--sbom-file", type=Path, required=True)
    create.add_argument("--archive", type=Path, required=True)
    create.add_argument("--part", type=Path, action="append", required=True)
    create.set_defaults(handler=create_command)
    read = commands.add_parser("read")
    read.add_argument("--manifest", type=Path, required=True)
    read.add_argument("--format", choices=("json",), default="json")
    read.add_argument("--output", type=Path)
    read.set_defaults(handler=read_command)
    verify = commands.add_parser("verify")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--mode", choices=("metadata", "archive"), required=True)
    verify.add_argument("--reconstructed-output", type=Path)
    verify.set_defaults(handler=verify_command)
    return parser


def main() -> int:
    """@brief Run the selected command with bounded error output."""
    try:
        arguments = command_parser().parse_args()
        return int(arguments.handler(arguments))
    except (
        OSError,
        ValueError,
        tomllib.TOMLDecodeError,
        json.JSONDecodeError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
