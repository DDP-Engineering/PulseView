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
@file run_builder_validation.py
@brief Run every mandatory builder validation role with strict exit handling.
@details Exit 77 is a hard failure in this candidate-qualification context.
"""

# IMPORTS

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
from typing import Any

import builder_identity
import dependency_contract


# CONSTANTS

STAGE_ROLES = {"windows-python", "networking-stack", "pe-import-closure"}
APPIMAGE_ROLES = {
    "appimage-identity",
    "appimage-runtime",
    "appimage-gui-startup",
}


# DATA MODELS / TYPEDEFINITIONS

JsonObject = dict[str, Any]


# HELPER FUNCTIONS


def atomic_write(path: Path, content: bytes) -> None:
    """@brief Atomically replace a complete passing report."""
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


def utc_now() -> str:
    """@brief Return one timezone-aware UTC timestamp."""
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def shell_path(path: Path) -> str:
    """@brief Render a filesystem path for the available Bash runtime."""
    if os.name == "nt" and shutil.which("cygpath"):
        return subprocess.check_output(
            ["cygpath", "-u", str(path)], text=True, timeout=10
        ).strip()
    return str(path)


def role_command(
    role: str, script: Path, arguments: argparse.Namespace
) -> tuple[list[str], dict[str, str]]:
    """@brief Build one mandatory test command and constrained environment."""
    bash = shutil.which("bash")
    if bash is None:
        raise ValueError("bash is required for mandatory validation tests")
    command = [bash, shell_path(script)]
    environment = dict(os.environ)
    environment["BUILDER_ARCHITECTURE"] = dependency_contract.normalize_architecture(
        arguments.platform
    )
    if role in STAGE_ROLES:
        if arguments.stage is None:
            raise ValueError(f"mandatory role {role} requires --stage")
        command.append(shell_path(arguments.stage))
    if role in APPIMAGE_ROLES:
        if arguments.appimage is None:
            raise ValueError(f"mandatory role {role} requires --appimage")
        environment["APPIMAGE_PATH"] = shell_path(arguments.appimage)
    if role == "deb-metadata":
        if arguments.deb is None:
            raise ValueError("mandatory role deb-metadata requires --deb")
        environment["DEB_PATH"] = shell_path(arguments.deb)
    return command, environment


# PUBLIC API


def run_suite(arguments: argparse.Namespace) -> int:
    """@brief Run all selected policy roles and write a report only on pass."""
    architecture = dependency_contract.normalize_architecture(arguments.platform)
    _, actual_policy_spec = builder_identity.validation_inputs(arguments)
    if actual_policy_spec != arguments.policy_spec:
        raise ValueError(
            "validation policy identity mismatch: "
            f"{actual_policy_spec} != {arguments.policy_spec}"
        )
    policy = builder_identity.selected_policy(
        arguments.policy, arguments.image, architecture
    )
    arguments.report.unlink(missing_ok=True)
    suite_started_at = utc_now()
    log_directory = arguments.report.parent / f"{arguments.report.stem}.logs"
    log_directory.mkdir(parents=True, exist_ok=True)
    results: list[JsonObject] = []
    for index, role in enumerate(policy["mandatory_tests"], start=1):
        script = builder_identity.test_role_path(str(role), arguments.tests_dir)
        if not script.is_file():
            raise ValueError(f"mandatory test for {role} missing: {script}")
        command, environment = role_command(str(role), script, arguments)
        started_at = utc_now()
        try:
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                env=environment,
                timeout=arguments.timeout,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeError(
                f"mandatory test {role} could not run: {error}"
            ) from error
        finished_at = utc_now()
        log_path = log_directory / f"{index:02d}-{role}.log"
        log_content = (f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}").encode()
        atomic_write(log_path, log_content)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            if result.returncode == 77:
                raise RuntimeError(
                    f"mandatory test {role} returned exit 77; "
                    f"candidate prerequisites are incomplete: {detail}"
                )
            raise RuntimeError(
                f"mandatory test {role} failed with exit {result.returncode}: {detail}"
            )
        results.append(
            {
                "role": role,
                "command": command,
                "runner": {
                    "system": platform.system(),
                    "machine": platform.machine(),
                    "bash": command[0],
                    "builder_engine": environment.get("BUILDER_ENGINE", ""),
                    "builder_tag": environment.get("BUILDER_TAG", ""),
                },
                "started_at": started_at,
                "finished_at": finished_at,
                "exit_code": 0,
                "output_log": log_path.relative_to(arguments.report.parent).as_posix(),
            }
        )
    report = {
        "schema": 1,
        "result": "pass",
        "image": arguments.image,
        "architecture": architecture,
        "validation_policy_spec": actual_policy_spec,
        "started_at": suite_started_at,
        "completed_at": utc_now(),
        "tests": results,
    }
    content = (
        json.dumps(report, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("utf-8")
    atomic_write(arguments.report, content)
    return 0


def command_parser() -> argparse.ArgumentParser:
    """@brief Create the command parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--policy-spec", required=True)
    parser.add_argument(
        "--verifier",
        type=Path,
        default=Path(__file__).resolve().parent / "verify_builder_environment.sh",
    )
    parser.add_argument("--image", choices=("mingw", "appimage"), required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--tests-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--appimage", type=Path)
    parser.add_argument("--deb", type=Path)
    parser.add_argument("--timeout", type=int, default=900)
    return parser


def main() -> int:
    """@brief Run the suite with bounded errors."""
    try:
        return run_suite(command_parser().parse_args())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

# END OF FILE
