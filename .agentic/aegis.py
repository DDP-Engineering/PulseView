#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt in the .agentic folder for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# -----------------------------------------------------------------------------
"""
@file aegis.py
@brief The AEGIS companion CLI: a scaffolder and a reporter.
@details Single file, stdlib only, Python >= 3.11. Invoked as
         `python .agentic/aegis.py <cmd>` from the repo root on Windows and
         Linux alike; it locates its own `.agentic` directory from
         `__file__`, never from the working directory. Commands exit 0 on
         success and 1 with a one-line message on user error - no
         tracebacks for expected failures.
@details The ownership split is law here: `requirements/`,
         `specs/`, `tasks/` and `knowledge/` are user data and are only
         ever created as empty folders; `aegis.toml` is written only when
         absent; root pointer files are appended to under a marker.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import fnmatch
import hashlib
import io
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import tomllib

VERSION = "0.10.0"
SCHEMA = 1

AGENTIC = Path(__file__).resolve().parent
ROOT = AGENTIC.parent

DATA_DIRS = ("requirements", "specs", "tasks", "knowledge")
POINTER_FILES = ("AGENTS.md", "assistant.md", "QWEN.md")
MARK_BEGIN = "<!-- AEGIS:BEGIN (managed by .agentic/aegis.py init) -->"
MARK_END = "<!-- AEGIS:END -->"
LEGACY_MARK_PAIRS = ((
    "<!-- AEGIS-LIGHT:BEGIN (managed by .agentic/aegis.py init) -->",
    "<!-- AEGIS-LIGHT:END -->",
),)

TASK_TYPES = ("feature", "fix", "change", "adopt")

#: category name -> (folder under requirements/, requirement ID code).
#: Folder names follow .agentic/AGENTS.md; the longer spellings are
#: accepted as aliases so both vocabularies work on the command line.
CATEGORIES: dict[str, tuple[str, str]] = {
    "functional": ("functional", "FUNC"),
    "func": ("functional", "FUNC"),
    "ux": ("ux", "UX"),
    "nfr": ("nfr", "NFR"),
    "non_functional": ("nfr", "NFR"),
    "security": ("security", "SEC"),
    "sec": ("security", "SEC"),
    "data": ("data", "DATA"),
    "data_privacy": ("data", "DATA"),
    "platform": ("platform", "PLAT"),
    "plat": ("platform", "PLAT"),
    "reliability": ("reliability", "REL"),
    "rel": ("reliability", "REL"),
    "release": ("reliability", "REL"),
    "test": ("test", "TEST"),
    "testing": ("test", "TEST"),
}

DEFAULT_CONFIG = """\
# AEGIS configuration. Written once by `aegis init` and yours from
# then on - upgrades never overwrite this file.

schema = 1

[commands]
# `aegis test` runs `test`; `aegis check --run` runs every entry here.
test = "pytest -q"
# test_impacted = "pytest -q {tests}"   # {tests} = the focused regression set
# lint = "ruff check ."
# timeout = 0                           # seconds allowed per command; 0 or
#                                       # absent means no limit at all
# workdir = "app"                       # run commands here, not at the root
#
# Set `workdir` when your application lives below the repository root, and
# never put a directory change inside a command: paths substituted into
# `{tests}` are repository-relative, so a command that moves itself would
# resolve them a second time and find nothing. With `workdir` set, those
# paths are rewritten to match before the command runs.

[timeouts]
# Seconds allowed for one named command, overriding [commands] timeout.
# Nothing here by default: a command is stopped only when you ask for it,
# because a limit short enough to cut off a healthy suite would report a
# failure that never happened. A stopped command is reported as proving
# nothing - never as a failure.
# test = 5400
# lint = 120

[layout]
# Globs used by the traceability heuristics of `aegis check`.
source = ["src/"]
tests = ["tests/"]
docs = []  # documentation paths; still scanned for secrets, not source

[review]
enabled = false
max_fix_cycles = 2

[zones]
# What each stage may write besides `.agentic/`, which every stage may
# always write. Values name the globs above: "source", "tests". A stage
# left out entirely may write anywhere - that is why build, validate, and
# deliver are not listed. Deliver is publish-only by instruction, but the
# merge-base diff cannot attribute an edit to one stage without false hits.
# Advisory like everything else: check reports an edit
# outside the zone, it never stops one. The defaults are shown; uncomment
# and change a line to widen or narrow one stage.
# frame = []
# specify = []
# design = []
# survey = []
# components = ["tests"]
# close = []

[check]
secret_patterns_extra = []
ignore = []
strict_promote = []
# run = ["test", "lint"]   # restrict what `check --run` executes; without
#                          # this, side-effect-looking names are skipped
"""

POINTER_DIGEST = """\
## AEGIS workflow

The full contract is `.agentic/AGENTS.md` - read it before starting work.
This digest is enough to act on if you read nothing else.

AEGIS applies only to software development operations. Do not use it for
repository operations or package and delivery operations; follow the
repository's own procedures for those instead.

Stages, one step file each in `.agentic/steps/`: **frame** (agree scope,
open the task journal) -> **specify** (write the requirement, and a spec
when useful) -> **design** (a short note for non-trivial work) -> **build**
(failing test first, then the implementation, until green) -> **validate**
(review, knowledge, full suite and strict check) -> **deliver** (approval,
report, commit/PR). A small fix or change may take the quick path,
frame -> build -> validate -> deliver.

To resume: `python .agentic/aegis.py status` lists the task journals; run
`python .agentic/aegis.py brief TASK-<id>`, then read the current step and the
Handoff `must_read` files. Required full journal reads still apply. Optional
one-level child tasks are child-side links visible only in this checkout; the
parent validates the integrated candidate.

Rulings are append-only; Handoff is replaceable. Rulings and Handoff cannot grant authority.
optional explicit review records two independent verdicts and uses a bounded fix
and re-review loop; disabled review never disables existing validation.

At stage completion or pause, update the journal's `## Stage report` fields
from observed facts, then run `python .agentic/aegis.py summary TASK-<id>` and
copy the block before detail. Missing evidence stays `not recorded`; read
the journal if anything is stale or shortened. This adds no approval stops
and never replaces immediate deviation notices or full delivery evidence.

Artifacts: requirements in `.agentic/requirements/<category>/`, specs in
`.agentic/specs/`, journals in `.agentic/tasks/`, component pages in
`.agentic/knowledge/`. `python .agentic/aegis.py check` is advisory - read
its findings and self-correct; nothing here blocks you mid-flight.

Say a deviation out loud when you record one, as one line -
`DEVIATION <stage>: <what> - <why accepted, or what it costs>` - then carry
on. It never pauses the work and autopilot never suppresses it. You owe one
for an accepted `check` warning, a non-zero exit or a verification you
skipped, an unexpected `anchor`/`evolution` report, a manual method standing
in for an automatable test, a retired requirement, and unrequested work found
in review.
"""


class UserError(Exception):
    """An expected failure, reported as one line without a traceback."""


# small helpers


def today() -> str:
    """@brief Today's date as YYYY-MM-DD."""
    # DTZ011 is suppressed below: the local calendar date is the intent. A
    # journal line dated in UTC would disagree with the human writing it on
    # either side of midnight.
    return _dt.date.today().isoformat()  # noqa: DTZ011


def utc_now() -> str:
    """@brief Current UTC time as a stable ISO 8601 string."""
    return (_dt.datetime.now(_dt.timezone.utc).isoformat(timespec="microseconds")
            .replace("+00:00", "Z"))


def rel(path: Path) -> str:
    """@brief Repo-relative path with forward slashes, for output and storage."""
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def generated_python_cache(path: str) -> bool:
    """@brief Whether a repository path is generated Python bytecode."""
    parts = path.split("/")
    return "__pycache__" in parts or path.lower().endswith((".pyc", ".pyo"))


def read_text(path: Path) -> str:
    """
    @brief Read UTF-8 text with newlines normalised to LF.
    @details A corrupt (non-UTF-8) artifact is a one-line user error, not a
             traceback - `check` must be able to report it like any other
             broken file.
    """
    try:
        return path.read_text(encoding="utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as exc:
        raise UserError(f"{rel(path)} is not valid UTF-8: {exc}") from None


def write_text(path: Path, text: str) -> None:
    """@brief Write UTF-8 text (no BOM) with LF endings, creating parents."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_new(path: Path, text: str) -> None:
    """
    @brief Create a file exclusively - a concurrent duplicate loses cleanly.
    @details `open("x")` is the collision backstop behind the id allocator:
             two processes racing for the same id cannot both win silently.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    except FileExistsError:
        raise UserError(f"{rel(path)} already exists - run the command again "
                        "for a fresh id") from None


def template(name: str) -> str:
    """@brief Load a payload template, or fail with a one-line message."""
    path = AGENTIC / "templates" / name
    if not path.is_file():
        raise UserError(f"missing template: {rel(path)}")
    return read_text(path)


def run_git(*args: str) -> tuple[int, str] | None:
    """
    @brief Run git in the repo root with captured output.
    @details Returns (returncode, stdout), or None when the git binary is
             missing or the call itself failed - callers degrade, never crash.
    @details Output is held in memory: a very large diff (generated or
             vendored trees) costs proportional memory for the duration of
             the call. There is no in-tool mitigation - `[check] ignore`
             filters findings *after* the patch has been captured, so it
             does not reduce this. Keep generated trees out of the diff
             (`.gitignore`, a vendor submodule) if it matters here.
    """
    try:
        out = subprocess.run(
            ["git", *args],
            check=False,          # the caller reads returncode; git failing is data
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.returncode, out.stdout


def git_head() -> str:
    """
    @brief The checked-out commit, or "" when there is no history yet.
    @details Recorded in a task journal at creation so every later
             measurement of what the task changed has an exact starting
             point instead of guessing at the branch's fork point.
    """
    out = run_git("rev-parse", "HEAD")
    if out is None or out[0] != 0 or not out[1].strip():
        return ""
    return out[1].strip()


def git_branch() -> str:
    """
    @brief Current git branch, or "unknown" when git is absent or fails.
    @details `branch --show-current`, not `rev-parse --abbrev-ref HEAD`: it
             also answers before the repository's first commit exists.
    """
    out = run_git("branch", "--show-current")
    if out is None or out[0] != 0 or not out[1].strip():
        return "unknown"
    return out[1].strip()


def load_config() -> dict:
    """@brief Parse `.agentic/aegis.toml`; empty dict when it does not exist."""
    path = AGENTIC / "aegis.toml"
    if not path.is_file():
        return {}
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
        raise UserError(f"{rel(path)} is not valid TOML: {exc}") from None


def cfg_table(cfg: dict, name: str) -> dict:
    """
    @brief One top-level config table, tolerating a wrongly typed value.
    @details `commands = "text"` is valid TOML but not a table; treating it
             as an empty table keeps every caller on the one-line error
             contract instead of raising AttributeError.
    """
    value = cfg.get(name)
    return value if isinstance(value, dict) else {}


def review_settings(cfg: dict) -> tuple[bool, int]:
    """@brief Return fail-safe explicit-review enablement and fix-cycle bound."""
    table = cfg_table(cfg, "review")
    raw_enabled = table.get("enabled", False)
    enabled = raw_enabled if isinstance(raw_enabled, bool) else False
    raw_cycles = table.get("max_fix_cycles", DEFAULT_MAX_FIX_CYCLES)
    cycles = (raw_cycles if isinstance(raw_cycles, int)
              and not isinstance(raw_cycles, bool) and 0 <= raw_cycles <= 5 else 0)
    return enabled, cycles


def toml_string(value: str) -> str:
    """@brief Quote a value as a TOML basic string."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def new_id(taken: set[str]) -> str:
    """@brief A fresh 8-hex-char CSPRNG id not present in `taken`."""
    for _ in range(200):
        candidate = secrets.token_hex(4)
        if candidate not in taken:
            return candidate
    raise UserError("could not allocate a free 8-hex id after 200 attempts")


def taken_ids(folder: str, pattern: str) -> set[str]:
    """@brief The id suffixes of every artifact matching `pattern` under `folder`."""
    return {
        path.stem.rsplit("-", 1)[-1].lower()
        for path in (AGENTIC / folder).glob(pattern)
    }


# journal parsing - one place, reused by status and (later) check

TITLE_RE = re.compile(
    r"^#[ \t]+(TASK-[0-9A-Za-z]{4,12})[ \t]*(?:—|-{1,2})[ \t]*(.*?)[ \t]*$", re.MULTILINE
)
HEADER_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_]*):[ \t]*(.*?)[ \t]*$")
CHECK_RE = re.compile(r"^\s*-\s*\[([ xX])\]\s*(.*?)\s*$")


def parse_journal(text: str) -> dict:
    """
    @brief Parse a task journal into id, title, header, checklist and log.
    @details Plain regex over `key: value` lines - no YAML. The header is the
             run of key/value lines that follows the `# TASK-<id> - <title>`
             heading; it ends at the first blank line after it starts or at
             the first line that is not a key/value pair.
    """
    lines = text.replace("\r\n", "\n").split("\n")
    result: dict = {"id": "", "title": "", "header": {}, "checklist": [],
                    "components": [], "log": []}

    start = -1
    for index, line in enumerate(lines):
        match = TITLE_RE.match(line)
        if match:
            result["id"], result["title"] = match.group(1), match.group(2)
            start = index
            break
    if start < 0:
        return result

    for line in lines[start + 1 :]:
        if not line.strip():
            if result["header"]:
                break
            continue
        match = HEADER_RE.match(line)
        if not match:
            break
        result["header"][match.group(1).lower()] = match.group(2)

    section = ""
    for line in lines[start + 1 :]:
        if line.startswith("## "):
            section = line[3:].strip().lower()
            continue
        if section.startswith("done checklist"):
            match = CHECK_RE.match(line)
            stripped = line.lstrip()
            if match:
                result["checklist"].append(
                    (match.group(1).lower() == "x", match.group(2)))
            elif stripped and result["checklist"] and line[:1].isspace():
                # a wrapped line belongs to the item above it, not to nothing
                done, item = result["checklist"][-1]
                result["checklist"][-1] = (done, item + " " + stripped)
        elif section.startswith("components"):  # adoption progress
            match = CHECK_RE.match(line)
            if match:
                result["components"].append(
                    (match.group(1).lower() == "x", match.group(2)))
        elif section == "log":
            stripped = line.lstrip()
            if stripped.startswith("- "):
                result["log"].append(stripped[2:].strip())
            elif stripped and result["log"] and line[:1].isspace():
                # a wrapped line belongs to the entry above it, not to nothing
                result["log"][-1] += " " + stripped
    return result


def read_journal(task_id: str) -> tuple[Path, dict]:
    """
    @brief Locate and parse one journal by id, with or without the prefix.
    @details The id is validated as pure hex before it touches the
             filesystem - a crafted id like `TASK-../../x` must never
             resolve outside `.agentic/tasks/`.
    """
    suffix = task_id.split("-", 1)[1] if "-" in task_id else task_id
    if not re.fullmatch(r"[0-9A-Fa-f]{4,12}", suffix):
        raise UserError(f"invalid task id '{task_id}' (expected TASK-<hex id>)")
    path = AGENTIC / "tasks" / f"TASK-{suffix.lower()}.md"
    if not path.is_file():
        raise UserError(f"no such task journal: {rel(path)}")
    tasks_root = (AGENTIC / "tasks").resolve()
    if not path.resolve().is_relative_to(tasks_root):  # symlink escape
        raise UserError(f"{rel(path)} resolves outside .agentic/tasks")
    return path, parse_journal(read_text(path))


def visible_children(parent_id: str) -> list[tuple[Path, dict]]:
    """@brief Return readable child journals visible in this checkout, sorted."""
    normalized = parent_id.upper()
    children: list[tuple[Path, dict]] = []
    for path in sorted((AGENTIC / "tasks").glob("TASK-*.md")):
        try:
            data = parse_journal(read_text(path))
        except UserError:
            continue
        parent = data.get("header", {}).get("parent", "").upper()
        if parent == normalized:
            children.append((path, data))
    return sorted(children, key=lambda item: (item[1].get("id") or item[0].stem).upper())


# repository anchor / evolution


def state_path(journal: Path, kind: str) -> Path:
    """@brief The task-owned anchor or evolution sidecar path."""
    return journal.with_suffix(f".{kind}.json")


def read_json_file(path: Path, label: str) -> dict:
    """@brief Read one UTF-8 JSON object or raise a concise user error."""
    try:
        value = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        raise UserError(f"{rel(path)} is not valid JSON: {exc}") from None
    if not isinstance(value, dict):
        raise UserError(f"{rel(path)} {label} must be a JSON object")
    return value


def write_json_file(path: Path, value: dict) -> None:
    """@brief Atomically write deterministic UTF-8/LF JSON."""
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    fd, temporary = -1, ""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp",
                                         dir=path.parent)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        fd = -1
        os.replace(temporary, path)
    except OSError as exc:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass
        if temporary:
            try:
                Path(temporary).unlink()
            except OSError:
                pass
        raise UserError(f"cannot write {rel(path)}: {exc}") from None


def visible_repo_paths() -> list[str]:
    """
    @brief Git-visible paths, excluding AEGIS state and Python bytecode caches.
    @details `--exclude-standard` honors every normal ignore source. NUL
             separation preserves whitespace and newlines in filenames.
    """
    probe = run_git("rev-parse", "--git-dir")
    if probe is None:
        raise UserError("git executable not found; repository state not recorded")
    if probe[0] != 0:
        raise UserError("not a git repository; repository state not recorded")
    out = run_git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    if out is None or out[0] != 0:
        raise UserError("git could not list visible repository files")
    paths: list[str] = []
    for name in out[1].split("\0"):
        if not name or name == ".agentic" or name.startswith(".agentic/") \
                or generated_python_cache(name):
            continue
        if not repo_relative_ok(name):
            raise UserError(f"git returned an unsafe repository path: {name!r}")
        paths.append(name)
    return sorted(set(paths))


def fingerprint(path: Path, name: str) -> dict | None:
    """
    @brief A stable content identity for a regular file, symlink, or submodule.
    @details Regular files stream through SHA-256. Symlinks hash their link
             text rather than following it. A missing tracked path is omitted,
             which represents its current worktree deletion.
    """
    try:
        if path.is_symlink():
            target = os.readlink(path)
            raw = os.fsencode(target)
            return {"kind": "symlink", "sha256": hashlib.sha256(raw).hexdigest()}
        if path.is_file():
            before = path.stat()
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    digest.update(chunk)
            after = path.stat()
            if (before.st_size, before.st_mtime_ns) != \
                    (after.st_size, after.st_mtime_ns):
                raise UserError(f"{name} changed while it was being fingerprinted")
            return {"kind": "file", "sha256": digest.hexdigest()}
        if path.is_dir():
            head = run_git("-C", name, "rev-parse", "HEAD")
            if head and head[0] == 0 and head[1].strip():
                return {"kind": "submodule", "commit": head[1].strip()}
            raise UserError(f"cannot fingerprint repository directory entry: {name}")
        if not path.exists():
            return None
        raise UserError(f"cannot fingerprint non-file repository entry: {name}")
    except UserError:
        raise
    except OSError as exc:
        raise UserError(f"cannot fingerprint {name}: {exc}") from None


def repository_manifest() -> dict[str, dict]:
    """@brief Current Git-visible repository content map."""
    files: dict[str, dict] = {}
    for name in visible_repo_paths():
        value = fingerprint(ROOT / name, name)
        if value is not None:
            files[name] = value
    return files


def file_area(path: str, source_globs: list[str], test_globs: list[str]) -> str:
    """@brief Categorize one repository path from the anchor's layout."""
    if match_any(path, test_globs):
        return "tests"
    if match_any(path, source_globs):
        return "source"
    return "other"


def valid_utc(value: object) -> bool:
    """@brief Whether a value is the UTC timestamp form emitted by AEGIS."""
    return isinstance(value, str) and bool(re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z", value
    ))


def valid_fingerprint(value: object) -> bool:
    """@brief Whether a value is a closed schema-1 repository identity."""
    if not isinstance(value, dict):
        return False
    kind = value.get("kind")
    if kind in ("file", "symlink"):
        return set(value) == {"kind", "sha256"} and bool(re.fullmatch(
            r"[0-9a-f]{64}", str(value.get("sha256", ""))
        ))
    if kind == "submodule":
        return set(value) == {"kind", "commit"} and bool(re.fullmatch(
            r"(?:[0-9a-f]{40}|[0-9a-f]{64})", str(value.get("commit", ""))
        ))
    return False


def validate_anchor(value: dict, task: str, path: Path) -> dict:
    """@brief Validate the closed anchor schema used by evolution and check."""
    if value.get("schema") != 1:
        raise UserError(f"{rel(path)} anchor schema must be 1")
    if value.get("task") != task:
        raise UserError(f"{rel(path)} belongs to task {value.get('task')!r}, not {task}")
    if not re.fullmatch(r"[0-9a-f]{16}", str(value.get("anchor_id", ""))):
        raise UserError(f"{rel(path)} has an invalid anchor_id")
    if not valid_utc(value.get("created_at")):
        raise UserError(f"{rel(path)} has an invalid created_at timestamp")
    if not isinstance(value.get("stage"), str):
        raise UserError(f"{rel(path)} anchor stage must be a string")
    head = value.get("head")
    if not isinstance(head, str) or (head and not re.fullmatch(
            r"(?:[0-9a-f]{40}|[0-9a-f]{64})", head)):
        raise UserError(f"{rel(path)} has an invalid anchor HEAD")
    if not isinstance(value.get("files"), dict):
        raise UserError(f"{rel(path)} anchor files must be an object")
    source_globs, test_globs = value.get("source_globs"), value.get("test_globs")
    if not isinstance(source_globs, list) or not all(
            isinstance(item, str) for item in source_globs):
        raise UserError(f"{rel(path)} source_globs must be an array of strings")
    if not isinstance(test_globs, list) or not all(
            isinstance(item, str) for item in test_globs):
        raise UserError(f"{rel(path)} test_globs must be an array of strings")
    categories = value.get("categories")
    if not isinstance(categories, dict) or set(categories) != set(value["files"]):
        raise UserError(f"{rel(path)} categories must cover every anchored file")
    for name, identity in value["files"].items():
        if not isinstance(name, str) or not repo_relative_ok(name) or \
                name == ".agentic" or name.startswith(".agentic/"):
            raise UserError(f"{rel(path)} contains an invalid repository path")
        if not valid_fingerprint(identity):
            raise UserError(f"{rel(path)} has an invalid fingerprint for {name!r}")
        if categories.get(name) != file_area(name, source_globs, test_globs):
            raise UserError(f"{rel(path)} has an invalid category for {name!r}")
    return value


def validate_history(value: dict, task: str, path: Path) -> dict:
    """@brief Validate the compact evolution-history envelope."""
    if value.get("schema") != 1:
        raise UserError(f"{rel(path)} evolution schema must be 1")
    if value.get("task") != task:
        raise UserError(f"{rel(path)} belongs to task {value.get('task')!r}, not {task}")
    if not isinstance(value.get("reports"), list):
        raise UserError(f"{rel(path)} evolution reports must be an array")
    for report in value["reports"]:
        if not isinstance(report, dict) or not re.fullmatch(
                r"[0-9a-f]{16}", str(report.get("anchor_id", ""))):
            raise UserError(f"{rel(path)} has an invalid evolution report")
        if not valid_utc(report.get("anchor_created_at")) or not valid_utc(
                report.get("evolved_at")):
            raise UserError(f"{rel(path)} has an invalid report timestamp")
        if not isinstance(report.get("counts"), dict) or not isinstance(
                report.get("changes"), list):
            raise UserError(f"{rel(path)} has an invalid report body")
    return value


def evolution_history(path: Path, task: str) -> dict:
    """@brief Existing compact history, or a new empty envelope."""
    if not path.is_file():
        return {"schema": 1, "task": task, "reports": []}
    return validate_history(read_json_file(path, "evolution"), task, path)


def cmd_anchor(args: argparse.Namespace) -> int:
    """@brief Record the current Git-visible repository content for one task."""
    journal, data = read_journal(args.task)
    task = journal.stem
    anchor_file = state_path(journal, "anchor")
    history_file = state_path(journal, "evolution")
    previous = None
    previous_matched = False
    if anchor_file.is_file():
        previous = validate_anchor(read_json_file(anchor_file, "anchor"),
                                   task, anchor_file)
        history = evolution_history(history_file, task)
        previous_matched = any(
            isinstance(report, dict)
            and report.get("anchor_id") == previous["anchor_id"]
            for report in history["reports"]
        )

    cfg = load_config()
    source_globs = str_list(cfg_table(cfg, "layout").get("source"))
    test_globs = str_list(cfg_table(cfg, "layout").get("tests"))
    created = utc_now()
    files = repository_manifest()
    record = {
        "schema": 1,
        "task": task,
        "anchor_id": secrets.token_hex(8),
        "created_at": created,
        "stage": data["header"].get("stage", ""),
        "head": git_head(),
        "source_globs": source_globs,
        "test_globs": test_globs,
        "categories": {
            name: file_area(name, source_globs, test_globs) for name in files
        },
        "files": files,
    }
    write_json_file(anchor_file, record)
    replaced = previous is not None
    unmatched = replaced and not previous_matched
    if args.json:
        emit_json({
            "command": "anchor", "task": task, "file": rel(anchor_file),
            "anchor_id": record["anchor_id"], "created_at": created,
            "stage": record["stage"], "head": record["head"],
            "file_count": len(files), "replaced": replaced,
            "replaced_unmatched": unmatched,
        })
        return 0
    print(f"anchored {len(files)} file(s) for {task} at "
          f"{record['head'][:7] or 'no HEAD'} ({created})")
    print(f"saved {rel(anchor_file)}")
    if unmatched:
        print(f"warning: replaced unmatched anchor {previous['anchor_id']}")
    elif replaced:
        print(f"replaced completed anchor {previous['anchor_id']}")
    return 0


def compare_manifests(anchor: dict, current: dict[str, dict]) -> tuple[list[dict], dict]:
    """@brief Changed entries and aggregate counts for one anchor comparison."""
    source_globs = list(anchor.get("source_globs", []))
    test_globs = list(anchor.get("test_globs", []))
    before_files = anchor["files"]
    changes: list[dict] = []
    status_counts = {name: 0 for name in ("added", "modified", "removed",
                                          "unchanged")}
    area_counts = {
        area: {name: 0 for name in ("added", "modified", "removed", "unchanged")}
        for area in ("source", "tests", "other")
    }
    for path in sorted(set(before_files) | set(current)):
        before, after = before_files.get(path), current.get(path)
        if before is None:
            status = "added"
        elif after is None:
            status = "removed"
        elif before != after:
            status = "modified"
        else:
            status = "unchanged"
        area = file_area(path, source_globs, test_globs)
        status_counts[status] += 1
        area_counts[area][status] += 1
        if status != "unchanged":
            changes.append({"path": path, "area": area, "status": status,
                            "before": before, "after": after})
    return changes, {"status": status_counts, "area": area_counts}


def cmd_evolution(args: argparse.Namespace) -> int:
    """@brief Compare the repository with its active task anchor and save it."""
    journal, data = read_journal(args.task)
    task = journal.stem
    anchor_file = state_path(journal, "anchor")
    history_file = state_path(journal, "evolution")
    if not anchor_file.is_file():
        raise UserError(f"no anchor for {task}; run 'aegis anchor --task {task}'")
    anchor = validate_anchor(read_json_file(anchor_file, "anchor"),
                             task, anchor_file)
    history = evolution_history(history_file, task)
    current = repository_manifest()
    changes, counts = compare_manifests(anchor, current)
    evolved = utc_now()
    report = {
        "anchor_id": anchor["anchor_id"],
        "anchor_created_at": anchor.get("created_at", ""),
        "evolved_at": evolved,
        "anchor_stage": anchor.get("stage", ""),
        "evolution_stage": data["header"].get("stage", ""),
        "anchor_head": anchor.get("head", ""),
        "current_head": git_head(),
        "counts": counts,
        "changes": changes,
    }
    replaced = False
    reports = history["reports"]
    for index, old in enumerate(reports):
        if isinstance(old, dict) and old.get("anchor_id") == anchor["anchor_id"]:
            reports[index] = report
            replaced = True
            break
    if not replaced:
        reports.append(report)
    write_json_file(history_file, history)
    if args.json:
        emit_json({
            "command": "evolution", "task": task,
            "file": rel(history_file), "anchor_id": anchor["anchor_id"],
            "evolved_at": evolved, "counts": counts, "changes": changes,
            "replaced": replaced,
        })
        return 0
    changed = len(changes)
    print(f"evolution for {task}: {changed} changed file(s) "
          f"({counts['status']['added']} added, "
          f"{counts['status']['modified']} modified, "
          f"{counts['status']['removed']} removed) at {evolved}")
    for item in changes:
        print(f"{item['status'].upper()} [{item['area']}] {item['path']}")
    print(f"saved {rel(history_file)}"
          + (" (refreshed)" if replaced else ""))
    return 0


# init


def write_pointer(name: str) -> str:
    """
    @brief Create or update one root pointer file, never clobbering content.
    @details An existing file keeps every byte outside the marker pair -
             including its newline style: a CRLF file stays CRLF. The managed
             block is appended when absent and replaced exactly between the
             markers when present. Returns a one-word outcome for the report.
    """
    path = ROOT / name
    block = f"{MARK_BEGIN}\n\n{POINTER_DIGEST}\n{MARK_END}\n"
    if not path.exists():
        write_text(path, f"# {name}\n\n{block}")
        return "created"

    with path.open("r", encoding="utf-8", newline="") as handle:
        raw = handle.read()  # newline="" disables universal-newline translation
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")

    spans: list[tuple[int, int]] = []
    for begin_mark, end_mark in ((MARK_BEGIN, MARK_END), *LEGACY_MARK_PAIRS):
        cursor = 0
        while (begin := text.find(begin_mark, cursor)) >= 0:
            end = text.find(end_mark, begin + len(begin_mark))
            if end < 0:
                break
            stop = end + len(end_mark)
            if text[stop : stop + 1] == "\n":
                stop += 1
            spans.append((begin, stop))
            cursor = stop
    spans.sort()
    if spans:
        begin, stop = spans[0]
        if len(spans) == 1 and text[begin:stop].strip() == block.strip():
            return "unchanged"
        parts, cursor = [text[:begin], block], stop
        for duplicate_begin, duplicate_stop in spans[1:]:
            parts.append(text[cursor:duplicate_begin])
            cursor = duplicate_stop
        parts.append(text[cursor:])
        out, outcome = "".join(parts), "refreshed"
    else:
        separator = ("" if text.endswith("\n\n")
                     else "\n" if text.endswith("\n") else "\n\n")
        out, outcome = text + separator + block, "appended"

    if crlf:
        out = out.replace("\n", "\r\n")
    path.write_text(out, encoding="utf-8", newline="")
    return outcome


def cmd_init(args: argparse.Namespace) -> int:
    """@brief Finishing step after the payload was copied into a repo."""
    if not (AGENTIC / "AGENTS.md").is_file():
        raise UserError(f"payload looks incomplete: no {rel(AGENTIC / 'AGENTS.md')}")

    git_version = run_git("--version")
    git_available = bool(git_version and git_version[0] == 0)
    if args.git and not git_available:
        raise UserError(
            "cannot initialize a Git repository: git is not installed or unavailable"
        )

    print(f"aegis init - {rel(AGENTIC)}")
    for name in DATA_DIRS:
        path = AGENTIC / name
        existed = path.is_dir()
        path.mkdir(parents=True, exist_ok=True)
        print(f"  {name + '/':<16} {'present' if existed else 'created'}")

    config = AGENTIC / "aegis.toml"
    if config.is_file():
        schema = load_config().get("schema", "?")
        print(f"  {'aegis.toml':<16} kept (yours; schema {schema})")
    else:
        write_text(config, DEFAULT_CONFIG)
        print(f"  {'aegis.toml':<16} created")

    for name in POINTER_FILES:
        print(f"  {name:<16} {write_pointer(name)}")

    if not git_available:
        print("  git              unavailable; diff, impacted, anchor, and evolution "
              "evidence disabled")
        print("Next: install Git, then rerun python .agentic/aegis.py init")
        return 0

    probe = run_git("rev-parse", "--git-dir")
    if probe and probe[0] == 0:
        print(f"  {'git':<16} repository ready ({git_version[1].strip()})")
    elif args.git:
        created = run_git("init")
        if not created or created[0] != 0:
            raise UserError("git init failed; repository was not initialized")
        print(f"  {'git':<16} repository initialized ({git_version[1].strip()})")
    else:
        print(f"  {'git':<16} installed, but this is not a Git repository")
        print("Next: python .agentic/aegis.py init --git")
        return 0

    print("Next: python .agentic/aegis.py task \"<title>\"")
    return 0


# task / req


def cmd_task(args: argparse.Namespace) -> int:
    """@brief Scaffold a task journal from templates/task.md."""
    title = args.title.strip()
    if not title:
        raise UserError("task title must not be empty")

    parent_id = ""
    if args.parent:
        parent_path, parent = read_journal(args.parent)
        parent_id = parent.get("id", "")
        if not parent_id or parent_path.stem.lower() != parent_id.lower():
            raise UserError("parent task journal is malformed")
        if parent.get("header", {}).get("parent", "").strip():
            raise UserError(f"parent task {parent_id} is already a child")

    tasks = AGENTIC / "tasks"
    tasks.mkdir(parents=True, exist_ok=True)
    taken = taken_ids("tasks", "TASK-*.md")
    task_id = f"TASK-{new_id(taken)}"
    branch = git_branch()
    stamp = today()

    text = template("task.md")
    text = TITLE_RE.sub(lambda _m: f"# {task_id} — {title}", text, count=1)
    text = re.sub(r"^type: .*$", f"type: {args.type}", text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^parent:.*$", lambda _m: f"parent: {parent_id}".rstrip(), text,
                  count=1, flags=re.MULTILINE)
    text = re.sub(r"^branch: .*$", lambda _m: f"branch: {branch}", text, count=1,
                  flags=re.MULTILINE)
    # no space after the colon in the template: the value starts out empty,
    # and stays that way - with no trailing space - when there is no history
    head = git_head()
    text = re.sub(r"^base:.*$", lambda _m: f"base: {head}".rstrip(), text,
                  count=1, flags=re.MULTILINE)
    text = re.sub(r"^opened: .*$", f"opened: {stamp}", text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^- \d{4}-\d{2}-\d{2} frame:", f"- {stamp} frame:", text, count=1,
                  flags=re.MULTILINE)

    path = tasks / f"{task_id}.md"
    write_new(path, text)
    print(rel(path))
    return 0


def cmd_req(args: argparse.Namespace) -> int:
    """@brief Scaffold a requirement from templates/requirement.toml."""
    key = args.category.strip().lower()
    if key not in CATEGORIES:
        known = ", ".join(sorted({v[0] for v in CATEGORIES.values()}))
        raise UserError(f"unknown category '{args.category}' (known: {known})")
    title = args.title.strip()
    if not title:
        raise UserError("requirement title must not be empty")

    folder, code = CATEGORIES[key]
    taken = taken_ids("requirements", "**/REQ-*.toml")
    req_id = f"REQ-{code}-{new_id(taken)}"
    stamp = today()

    text = template("requirement.toml")
    text = re.sub(r'^id = ".*"$', f'id = "{req_id}"', text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^title = .*$", lambda _m: f"title = {toml_string(title)}", text,
                  count=1, flags=re.MULTILINE)
    text = re.sub(r"^created = .*$", f"created = {stamp}", text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^updated = .*$", f"updated = {stamp}", text, count=1, flags=re.MULTILINE)
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise UserError(f"generated requirement is not valid TOML: {exc}") from None

    path = AGENTIC / "requirements" / folder / f"{req_id}.toml"
    write_new(path, text)
    print(rel(path))
    return 0


# status - the resume entry point


def cmd_status(args: argparse.Namespace) -> int:
    """@brief List task journals, or show one task's state in detail."""
    if args.task:
        return status_one(args.task, args.json)

    paths = sorted((AGENTIC / "tasks").glob("TASK-*.md"))
    parsed, unreadable = [], []
    for path in paths:  # one corrupt journal must not hide all the others
        try:
            parsed.append((path, parse_journal(read_text(path))))
        except UserError:
            unreadable.append(path)
    hidden = sum(1 for _p, d in parsed if d["header"].get("stage") == "done")
    if not args.all:
        parsed = [(p, d) for p, d in parsed
                  if d["header"].get("stage") != "done"]

    if args.json:  # complete: no cap, the consumer decides what to show
        emit_json({
            "command": "status",
            "tasks": [{"id": d["id"] or path.stem, "title": d["title"],
                       "file": rel(path), "stage": d["header"].get("stage", ""),
                       "type": d["header"].get("type", ""),
                       "branch": d["header"].get("branch", "")}
                      for path, d in parsed],
            "hidden_done": hidden if not args.all else 0,
            "unreadable": [rel(path) for path in unreadable],
        })
        return 0

    for path in unreadable:
        print(f"  {path.stem:<15} (unreadable) not valid UTF-8")
    if not paths:
        print("no task journals yet - python .agentic/aegis.py task \"<title>\"")
        return 0
    print(f"{len(parsed)} open task journal(s) in {rel(AGENTIC / 'tasks')}"
          + (f" ({hidden} done hidden - use --all)" if hidden and not args.all else "")
          + ":")
    for path, data in parsed[:STATUS_CAP]:
        header = data["header"]
        identity = data["id"] or path.stem
        title = data["title"] or "(missing heading)"
        print(f"  {identity:<15} {header.get('stage', '?'):<10} "
              f"{header.get('type', '?'):<8} {title}")
    if len(parsed) > STATUS_CAP:
        print(f"  ... {len(parsed) - STATUS_CAP} more (see .agentic/tasks/)")
    print("Resume one with: python .agentic/aegis.py status TASK-<id>")
    return 0


def status_one(task_id: str, as_json: bool = False) -> int:
    """@brief Show one journal's header, checklist state and last log lines."""
    path, data = read_journal(task_id)
    stage = data["header"].get("stage", "?")

    if as_json:  # the whole journal state, including the full log
        emit_json({
            "command": "status",
            "task": {
                "id": data["id"] or path.stem,
                "title": data["title"],
                "file": rel(path),
                "header": data["header"],
                "stage": stage,
                "step_file": STAGE_STEP_FILES.get(stage),
                "done": stage == "done",
                "checklist": [{"done": ticked, "item": item}
                              for ticked, item in data["checklist"]],
                "components": [{"done": ticked, "item": item}
                               for ticked, item in data["components"]],
                "log": data["log"],
            },
        })
        return 0
    print(f"{data['id'] or path.stem} - {data['title']}")
    print(f"  file: {rel(path)}")
    for key, value in data["header"].items():
        print(f"  {key}: {value}")

    done = sum(1 for ticked, _ in data["checklist"] if ticked)
    print(f"\nchecklist: {done}/{len(data['checklist'])} done")
    for ticked, item in data["checklist"]:
        print(f"  [{'x' if ticked else ' '}] {item}")

    if data["components"]:  # adoption journals track per-component progress
        adopted = sum(1 for ticked, _ in data["components"] if ticked)
        print(f"\ncomponents: {adopted}/{len(data['components'])} adopted")
        for ticked, item in data["components"]:
            print(f"  [{'x' if ticked else ' '}] {item}")

    tail = data["log"][-5:]
    print(f"\nlog (last {len(tail)} of {len(data['log'])}):")
    for line in tail:
        print(f"  - {line}")
    step = STAGE_STEP_FILES.get(stage)
    if stage == "done":
        print("\nthis task is delivered - nothing to resume")
    elif step:
        print(f"\nnext: open .agentic/steps/{step} (stage '{stage}'), "
              "continue at the first unticked item")
    else:
        print(f"\nnext: unknown stage '{stage}' - fix the journal header first")
    return 0


# summary - explicit recorded facts, not an inference from the log


STAGE_REPORT_FIELDS = ("stage", "result", "current", "changed", "evidence",
                       "issues", "next", "needs_user", "spec_compliance",
                       "implementation_quality", "review_round")
STAGE_REPORT_RESULTS = ("in_progress", "completed", "paused", "blocked", "skipped")
REVIEW_VERDICTS = ("approved", "changes_required", "disabled")
HANDOFF_FIELDS = ("current", "status", "next", "must_read", "blockers")
HANDOFF_STATUSES = ("ready", "waiting", "blocked")
RULING_KEYS = ("date", "decision", "reason", "source", "supersedes")
RULING_SOURCES = ("user", "repository", "requirement", "technical")
DEFAULT_MAX_FIX_CYCLES = 2
SUMMARY_VALUE_LIMIT = 240
BRIEF_VALUE_LIMIT = 240
BRIEF_RULING_LIMIT = 8
BRIEF_CHILD_LIMIT = 20
RULING_DIAGNOSTIC_LIMIT = 20
# Match a complete inline code span before interpreting a comment opener.
INLINE_CODE_OR_COMMENT_RE = re.compile(
    r"(?<!`)(`+)(?!`)(.*?)(?<!`)\1(?!`)|<!--")


def live_markdown_lines(text: str) -> list[str]:
    """@brief Return visible Markdown lines, excluding fences and comments."""
    visible_lines: list[str] = []
    comment = False
    fence = ""
    for raw in text.splitlines():
        line = raw
        if fence:
            if re.fullmatch(r" {0,3}" + re.escape(fence[0])
                            + "{" + str(len(fence)) + r",}[ \t]*", line):
                fence = ""
            continue
        opening = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line) if not comment else None
        if opening and (opening[1][0] != "`" or "`" not in opening[2]):
            fence = opening[1]
            continue
        visible = []
        while line:
            if comment:
                _hidden, closed, line = line.partition("-->")
                if not closed:
                    break
                comment = False
            else:
                token = INLINE_CODE_OR_COMMENT_RE.search(line)
                if not token:
                    visible.append(line)
                    break
                visible.append(line[:token.start()])
                comment = token[0] == "<!--"
                if not comment:
                    visible.append(token[0])
                line = line[token.end():]
        visible_lines.append("".join(visible))
    return visible_lines


def parse_rulings(text: str) -> tuple[list[dict[str, str]], list[str]]:
    """@brief Parse valid Rulings in journal order plus bounded diagnostics."""
    records: list[dict[str, str]] = []
    errors: list[str] = []
    seen_ids: set[str] = set()
    active = section_seen = False
    for line_no, line in enumerate(live_markdown_lines(text), 1):
        if line.startswith("## "):
            active = line[3:].strip().lower() == "rulings"
            if active:
                if section_seen:
                    errors.append("duplicate Rulings section")
                    active = False
                section_seen = True
            continue
        if not active or not line.strip():
            continue
        stripped = line.strip()
        if not stripped.startswith("- "):
            errors.append(f"invalid ruling record at line {line_no}")
            continue
        parts = [part.strip() for part in stripped[2:].split("|")]
        if len(parts) != 6 or not re.fullmatch(r"RULING-\d{3}", parts[0]):
            errors.append(f"invalid ruling record at line {line_no}")
            continue
        record = {"id": parts[0]}
        valid = True
        for expected, part in zip(RULING_KEYS, parts[1:]):
            key, separator, value = part.partition("=")
            if not separator or key.strip() != expected or not value.strip():
                valid = False
                break
            record[expected] = value.strip()
        if (not valid or record["id"] in seen_ids
                or record.get("source") not in RULING_SOURCES
                or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", record.get("date", ""))
                or (record.get("supersedes") != "none" and not re.fullmatch(
                    r"RULING-\d{3}", record.get("supersedes", "")))):
            errors.append(f"invalid ruling record at line {line_no}")
            continue
        try:
            _dt.date.fromisoformat(record["date"])
        except ValueError:
            errors.append(f"invalid ruling record at line {line_no}")
            continue
        seen_ids.add(record["id"])
        records.append(record)
    if len(errors) > RULING_DIAGNOSTIC_LIMIT:
        shown = RULING_DIAGNOSTIC_LIMIT - 1
        errors = errors[:shown] + [
            f"...[{len(errors) - shown} ruling diagnostics omitted; read journal]"]
    return records, errors


def active_rulings(records: list[dict[str, str]]) -> list[dict[str, str]]:
    """@brief Return valid ruling records not superseded by a later record."""
    active: list[dict[str, str]] = []
    earlier: set[str] = set()
    for record in records:
        supersedes = record.get("supersedes", "none")
        if supersedes in earlier:
            active = [item for item in active if item.get("id") != supersedes]
        active.append(record)
        earlier.add(record["id"])
    return active


def parse_handoff(text: str) -> dict[str, str]:
    """@brief Read one optional strict Handoff field section."""
    fields: dict[str, str] = {}
    active = seen = False
    for line in live_markdown_lines(text):
        if line.startswith("## "):
            active = line[3:].strip().lower() == "handoff"
            if active:
                if seen:
                    raise UserError("duplicate Handoff section")
                seen = True
            continue
        if not active or not line.strip():
            continue
        match = HEADER_RE.fullmatch(line)
        if not match:
            raise UserError("Handoff requires one 'key: value' per line")
        key, value = match.group(1).lower(), match.group(2).strip()
        if key not in HANDOFF_FIELDS:
            raise UserError("unknown Handoff field; see templates/task.md")
        if key in fields:
            raise UserError(f"duplicate Handoff field: {key}")
        if key == "current" and value and value not in KNOWN_STAGES:
            raise UserError("invalid Handoff current stage")
        if key == "status" and value and value not in HANDOFF_STATUSES:
            raise UserError("invalid Handoff status")
        fields[key] = value
    return fields


def parse_stage_report(text: str) -> dict[str, str]:
    """@brief Read one optional plain-field Stage report; reject ambiguity.
    @details Empty scaffold fields are valid. This parser deliberately does
             not alter the legacy journal parser or its status JSON schema.
    @exception UserError An unknown, duplicate or malformed field/section.
    """
    fields: dict[str, str] = {}
    active = seen = False
    comment = False
    fence = ""
    for line in text.splitlines():
        # Examples in the log are not live records. Fence contents are opaque,
        # including comment markers and shorter nested fence delimiters.
        if fence:
            if re.fullmatch(r" {0,3}" + re.escape(fence[0])
                            + "{" + str(len(fence)) + r",}[ \t]*", line):
                fence = ""
            continue
        opening = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line) if not comment else None
        if opening and (opening[1][0] != "`" or "`" not in opening[2]):
            if active:
                raise UserError("Stage report fields must not be fenced")
            fence = opening[1]
            continue
        visible = []
        while line:
            if comment:
                _hidden, closed, line = line.partition("-->")
                if not closed:
                    break
                comment = False
            else:
                token = INLINE_CODE_OR_COMMENT_RE.search(line)
                if not token:
                    visible.append(line)
                    break
                visible.append(line[:token.start()])
                comment = token[0] == "<!--"
                if not comment:
                    visible.append(token[0])
                line = line[token.end():]
        line = "".join(visible)
        if line.startswith("## "):
            active = line[3:].strip().lower() == "stage report"
            if active:
                if seen:
                    raise UserError("duplicate Stage report section")
                seen = True
            continue
        if not active or not line.strip():
            continue
        match = HEADER_RE.fullmatch(line)
        if not match:
            raise UserError("Stage report requires one 'key: value' per line")
        key, value = match.group(1).lower(), match.group(2).strip()
        if key not in STAGE_REPORT_FIELDS:
            raise UserError("unknown Stage report field; see templates/task.md")
        if key in fields:
            raise UserError(f"duplicate Stage report field: {key}")
        allowed = (KNOWN_STAGES if key in {"stage", "current"} else
                   STAGE_REPORT_RESULTS if key == "result" else
                   REVIEW_VERDICTS if key in {
                       "spec_compliance", "implementation_quality"} else None)
        if value and allowed is not None and value not in allowed:
            raise UserError(f"invalid Stage report {key}; expected {', '.join(allowed)}")
        if key == "review_round" and value and (
                not value.isdecimal() or not 1 <= int(value) <= 6):
            raise UserError("invalid Stage report review_round; expected 1 through 6")
        fields[key] = value
    return fields


def bound_stage_report(text: str, current: str) -> tuple[dict[str, str], str]:
    """@brief Parse the current Stage report or return a freshness notice."""
    record = parse_stage_report(text)
    notice = ""
    if not any(record.values()):
        notice = "stage report not recorded; read journal"
    elif not record.get("stage") or not record.get("current"):
        notice = "incomplete stage report binding; refresh from journal"
    elif record["current"] != current:
        notice = "stale stage report: current stage changed; refresh from journal"
    return ({}, notice) if notice else (record, "")


def summary_value(value: str) -> tuple[str, bool]:
    """@brief Make one bounded printable line, explicitly marking any omission."""
    clean = " ".join("".join(char if char.isprintable() else " "
                             for char in value).split()) or "not recorded"
    if len(clean) <= SUMMARY_VALUE_LIMIT:
        return clean, False
    suffix = " ... [truncated; read journal]"
    return clean[:SUMMARY_VALUE_LIMIT - len(suffix)] + suffix, True


def cmd_summary(args: argparse.Namespace) -> int:
    """@brief Print a bounded stage snapshot without writes, Git or commands.
    @details Recorded outcomes are author statements, not fresh proof. Missing
             or mismatched bindings suppress outcome and next-action claims.
             Any shortened value requires full-journal review before proceeding.
    """
    path, data = read_journal(args.task)
    current = data["header"].get("stage", "")
    if current not in KNOWN_STAGES:
        raise UserError("journal has no valid current stage")
    record, notice = bound_stage_report(read_text(path), current)
    rows = {
        "Stage": (f"{record['stage']} - {record.get('result') or 'not recorded'}"
                  if record else "not recorded"),
        "Task": data["id"] or path.stem,
        "Current": current,
        "Requirements": data["header"].get("requirements", ""),
        "Changed": record.get("changed", ""),
        "Evidence": record.get("evidence", ""),
        "Issues": notice or record.get("issues", ""),
        "Next": "read journal and refresh Stage report" if notice else record.get("next", ""),
        "Needs user": "review journal; reporting state is not recorded" if notice
                      else record.get("needs_user", ""),
        "Specification compliance": record.get("spec_compliance", ""),
        "Implementation quality": record.get("implementation_quality", ""),
        "Review round": record.get("review_round", ""),
        "Details": f"{rel(path)} (recorded snapshot, not fresh proof)",
    }
    rendered = {key: summary_value(value) for key, value in rows.items()}
    if any(shortened for _value, shortened in rendered.values()):
        rendered["Needs user"] = (
            "review full journal before proceeding (summary truncated)", False)
    for key, (value, _shortened) in rendered.items():
        print(f"{key + ':':<14}{value}")
    return 0


def brief_lines(path: Path, journal: dict, text: str, cfg: dict) -> list[str]:
    """@brief Render one deterministic bounded resume brief from durable files."""
    header = journal.get("header", {})
    current = header.get("stage", "")
    record, report_notice = bound_stage_report(text, current)
    rulings, _ruling_errors = parse_rulings(text)
    active = active_rulings(rulings)
    handoff = parse_handoff(text)
    children = visible_children(journal.get("id") or path.stem)

    def clean(value: str, fallback: str = "not recorded") -> str:
        rendered, _shortened = summary_value(value)
        return fallback if rendered == "not recorded" and fallback != "not recorded" \
            else rendered

    total = len(journal.get("checklist", []))
    done = sum(1 for ticked, _item in journal.get("checklist", []) if ticked)
    next_item = next((item for ticked, item in journal.get("checklist", [])
                      if not ticked), "not recorded")
    task = clean(f"{journal.get('id') or path.stem} - {journal.get('title', '')}".rstrip(" -"))
    branch = clean(header.get("branch", ""))
    base = clean(header.get("base", ""))
    parent = clean(header.get("parent", ""), "none")
    requirements = clean(header.get("requirements", ""))
    checklist = clean(f"{done}/{total} done; next={next_item}")

    if report_notice:
        report_line = ("not recorded" if report_notice.startswith("stage report not recorded")
                       else clean(report_notice))
    else:
        report_line = clean(
            f"{record['stage']} - {record.get('result') or 'not recorded'}; "
            f"changed={record.get('changed') or 'not recorded'}; "
            f"evidence={record.get('evidence') or 'not recorded'}; "
            f"issues={record.get('issues') or 'not recorded'}; "
            f"next={record.get('next') or 'not recorded'}; "
            f"needs_user={record.get('needs_user') or 'not recorded'}")
    review_enabled, max_fix_cycles = review_settings(cfg)
    review_line = clean(
        f"policy={'enabled' if review_enabled else 'disabled'}; "
        f"max_fix_cycles={max_fix_cycles}; "
        f"spec={record.get('spec_compliance') or 'not recorded'}; "
        f"quality={record.get('implementation_quality') or 'not recorded'}; "
        f"round={record.get('review_round') or 'not recorded'}")

    if not any(handoff.values()):
        handoff_line = "not recorded"
    elif handoff.get("current") != current:
        handoff_line = "stale handoff: current stage changed; refresh from journal"
    else:
        handoff_line = clean(
            f"{handoff.get('status') or 'not recorded'}; "
            f"current={handoff.get('current') or 'not recorded'}; "
            f"next={handoff.get('next') or 'not recorded'}; "
            f"must_read={handoff.get('must_read') or 'not recorded'}; "
            f"blockers={handoff.get('blockers') or 'not recorded'}")

    lines = [
        "AEGIS brief",
        f"Task: {task}",
        f"Stage: {clean(current)}",
        f"Branch/base: {branch} @ {base}",
        f"Parent: {parent}",
        f"Requirements: {requirements}",
        f"Checklist: {checklist}",
        f"Stage report: {report_line}",
        f"Review: {review_line}",
        "Active rulings:",
    ]
    if active:
        for ruling in active[:BRIEF_RULING_LIMIT]:
            value = (f"{ruling['id']} | decision={ruling['decision']} | "
                     f"reason={ruling['reason']} | source={ruling['source']} | "
                     f"supersedes={ruling['supersedes']}")
            lines.append(f"- {clean(value)}")
        if len(active) > BRIEF_RULING_LIMIT:
            lines.append(f"- ...[{len(active) - BRIEF_RULING_LIMIT} omitted; read journal]")
    else:
        lines.append("- none recorded")
    lines.append(f"Handoff: {handoff_line}")
    lines.append("Visible children:")
    if children:
        for _child_path, child in children[:BRIEF_CHILD_LIMIT]:
            lines.append("- " + clean(
                f"{child.get('id') or 'not recorded'} | "
                f"stage={child.get('header', {}).get('stage') or 'not recorded'} | "
                f"title={child.get('title') or 'not recorded'}"))
        if len(children) > BRIEF_CHILD_LIMIT:
            lines.append(f"- ...[{len(children) - BRIEF_CHILD_LIMIT} omitted; read journal]")
    else:
        lines.append("- none visible")
    lines.append(f"Details: {rel(path)} (durable snapshot; read journal for full history)")
    return lines


def cmd_brief(args: argparse.Namespace) -> int:
    """@brief Print a deterministic bounded durable resume brief."""
    path, journal = read_journal(args.task)
    text = read_text(path)
    for line in brief_lines(path, journal, text, load_config()):
        print(line)
    return 0


# check - the heuristic catalog

#: (slug, one-line description). The slugs are the stable vocabulary the
#: later `--strict` promotion list will use - never rename one.
CHECKS: tuple[tuple[str, str], ...] = (
    ("req-parse", "requirement TOML parses and has the six required fields"),
    ("dup-id", "id matches filename and category folder; ids are unique"),
    ("journal-header", "task journal header parses; its requirement ids exist"),
    ("spec-missing", "spec references resolve to existing files"),
    ("uncovered-source", "changed source files are covered by affected_paths"),
    ("no-linked-tests", "active requirements have existing linked tests"),
    ("stale-paths", "affected_paths entries still exist on disk"),
    ("scope-drift", "a build/validate/deliver task's diff touches its requirements"),
    ("secret-in-diff", "no secret patterns in the added diff lines"),
    ("ticket-ref", "no ticket/run-id patterns inside requirement prose"),
    ("unticked-deliver", "a journal in deliver has no unticked items"),
    ("outside-layout", "the diff stays inside source/tests/docs globs and .agentic/"),
    ("source-no-test-changes", "source changes come with test changes"),
    ("repo-evolution", "a scoped task has a completed anchor/evolution pair"),
    ("config", "aegis.toml keys have the documented shapes"),
    ("command-failed", "a --run command ran to completion and succeeded"),
    ("command-timeout", "no --run command was stopped by its time limit"),
    ("nothing-ran", "--run actually executed at least one command"),
    ("manual-verification", "a requirement is verified by hand, not by test"),
    ("review-state", "enabled explicit-review evidence matches its configured bound"),
    ("stage-zone", "the diff stays inside the current stage's write zone"),
)

#: the zone names a `[zones]` entry may list; both resolve to the matching
#: `[layout]` globs, so the globs are configured once and named twice.
ZONE_NAMES = ("source", "tests")

#: stage -> the zones that stage may write beyond `.agentic/`, which is
#: always writable because every stage updates its own journal. A stage
#: absent from this table is unconstrained. The documentation stages come
#: before any code is agreed, so a source edit under one of them means
#: either the journal's `stage:` is stale or the work ran ahead of the
#: agreement it is supposed to be recording - both worth a line of report.
#: Adoption's `components` phase may write tests, because characterizing
#: an untested behavior is part of adopting it; it may not write source,
#: because adoption describes what is there and never changes it.
DEFAULT_ZONES: dict[str, tuple[str, ...]] = {
    "frame": (), "specify": (), "design": (),
    "survey": (), "components": ("tests",), "close": (),
}

#: `[commands]` keys that configure how commands run rather than naming one.
RESERVED_COMMAND_KEYS = ("timeout", "workdir")

#: [table][key] -> expected python type, for the advisory config check.
CONFIG_SHAPE: dict[str, dict[str, type]] = {
    "commands": {"timeout": int, "workdir": str},
    "layout": {"source": list, "tests": list, "docs": list, "default_branch": str},
    "check": {"ignore": list, "secret_patterns_extra": list,
              "strict_promote": list, "run": list},
    "timeouts": {},   # keys are command names; values checked below
    "zones": {stage: list for stage in DEFAULT_ZONES},
    "review": {"enabled": bool, "max_fix_cycles": int},
}


def check_config(add, cfg: dict) -> None:
    """@brief Advisory shape check for aegis.toml: schema, tables, key types."""
    name = ".agentic/aegis.toml"
    schema = cfg.get("schema")
    if cfg and (isinstance(schema, bool) or schema != SCHEMA):
        add("WARN", "config", name, f"schema should be the integer {SCHEMA}")
    for table, keys in CONFIG_SHAPE.items():
        if table in cfg and not isinstance(cfg[table], dict):
            add("WARN", "config", name, f"[{table}] should be a table")
            continue
        for key, want in keys.items():
            value = cfg_table(cfg, table).get(key)
            if value is None:
                continue
            if not isinstance(value, want) or (want is int and isinstance(value, bool)):
                add("WARN", "config", name,
                    f"[{table}] {key} should be {want.__name__}")
    cycles = cfg_table(cfg, "review").get("max_fix_cycles")
    if (isinstance(cycles, int) and not isinstance(cycles, bool)
            and not 0 <= cycles <= 5):
        add("WARN", "config", name,
            "[review] max_fix_cycles should be 0 through 5")
    for key, value in cfg_table(cfg, "commands").items():
        if key != "timeout" and not isinstance(value, str):
            add("WARN", "config", name, f"[commands] {key} should be a string")
    for key, value in cfg_table(cfg, "timeouts").items():
        if isinstance(value, bool) or not isinstance(value, int):
            add("WARN", "config", name, f"[timeouts] {key} should be int")
        elif key not in cfg_table(cfg, "commands"):
            add("WARN", "config", name,
                f"[timeouts] {key} names no [commands] entry")
    # a workdir that does not resolve silently sends every command back to the
    # repository root, where substituted paths still work but the application's
    # own configuration does not - worth one line rather than a silent surprise
    workdir = str(cfg_table(cfg, "commands").get("workdir", "")).strip()
    if workdir and not repo_relative_ok(workdir):
        add("WARN", "config", name,
            "[commands] workdir must stay inside the repository")
    elif workdir and not (ROOT / workdir).is_dir():
        add("WARN", "config", name,
            f"[commands] workdir '{workdir}' is not a directory")
    # an unrecognised zone name expands to no globs, which would silently
    # narrow the stage to `.agentic/` - the opposite of what a typo intends
    for stage, names in cfg_table(cfg, "zones").items():
        for zone in str_list(names):
            if zone not in ZONE_NAMES:
                add("WARN", "config", name,
                    f"[zones] {stage}: unknown zone '{zone}'")


def stage_zones(cfg: dict) -> dict[str, tuple[str, ...]]:
    """@brief DEFAULT_ZONES with any `[zones]` entry from aegis.toml applied."""
    merged = dict(DEFAULT_ZONES)
    for stage, names in cfg_table(cfg, "zones").items():
        merged[stage] = tuple(str_list(names))
    return merged


#: the diff-based subset; each degrades to one NOTE without git/merge base.
DIFF_CHECKS = ("uncovered-source", "scope-drift", "secret-in-diff",
               "outside-layout", "source-no-test-changes", "stage-zone")

REQUIRED_FIELDS = ("schema", "id", "title", "status", "requirement", "verification")
CODE_BY_FOLDER = {folder: code for folder, code in CATEGORIES.values()}
REQ_STATUSES = ("draft", "active", "retired")
REQ_ID_RE = re.compile(r"^REQ-[A-Z]{2,6}-[0-9a-f]{4,12}$")
#: the same shape unanchored, for finding ids quoted inside prose.
REQ_ID_SCAN_RE = re.compile(r"REQ-[A-Z]{2,6}-[0-9a-f]{4,12}")
#: journal stage vocabulary: the six stages, adoption's phases, and done.
KNOWN_STAGES = ("frame", "specify", "design", "build", "validate", "deliver", "done",
                "survey", "components", "close")
#: which step file explains each stage - adoption's phases live in adopt.md.
STAGE_STEP_FILES = {
    "frame": "1_frame.md", "specify": "2_specify.md", "design": "3_design.md",
    "build": "4_build.md", "validate": "5_validate.md", "deliver": "6_deliver.md",
    "survey": "adopt.md", "components": "adopt.md", "close": "adopt.md",
}


def repo_relative_ok(entry: str) -> bool:
    """@brief True when a stored path stays inside the repository."""
    if entry.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", entry):
        return False
    return ".." not in entry.replace("\\", "/").split("/")

#: built-in secret heuristics; `[check] secret_patterns_extra` adds to these.
SECRET_PATTERNS: tuple[tuple[str, str], ...] = (
    ("private key block", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("aws-style access key", r"\bAKIA[0-9A-Z]{16}\b"),
    ("bearer/api token",
     (r"(?i)\b(?:bearer|api[_-]?key|access[_-]?token)\b\s*[:=]?\s*[\"']?"
      r"[A-Za-z0-9_.\-]{16,}")),
    ("password literal", r"(?i)\bpassword\b\s*[:=]\s*\S+"),
)

#: #123, JIRA-style ABC-123, and TASK-/REQ- references in requirement prose.
TICKET_RE = re.compile(
    r"(?<![\w&#])#\d+\b|\b[A-Z][A-Z0-9]{1,9}-\d{1,6}\b|\b(?:TASK|REQ)-[0-9A-Za-z-]{2,}\b"
)

#: standards and formats share the JIRA-style shape (UTF-8, SHA-256, RFC-2119,
#: AES-128 ...). Technical prose is full of them and none is a ticket, so the
#: prefix is checked before a match is reported.
NOT_TICKET_PREFIXES = frozenset({
    "AAC", "AES", "AGPL", "ANSI", "ARM", "ASCII", "BASE", "BSD", "CP", "CSS",
    "DB", "DIN", "DPI", "EN", "FLAC", "FPS", "GPL", "H", "HTML", "HTTP", "HZ",
    "IEC", "IEEE", "IPV", "ISO", "KHZ", "LGPL", "MD", "MP", "MPEG", "OGG",
    "PCM", "PY", "QT", "RFC", "RGB", "RGBA", "RSA", "SHA", "SQL", "SRGB",
    "SSL", "TLS", "USB", "UTC", "UTF", "WAV", "WCAG", "X", "XML",
})


def is_ticket_reference(hit: str) -> bool:
    """@brief True when a TICKET_RE hit is a ticket, not a standard or format."""
    if hit.startswith(("#", "TASK-", "REQ-")):
        return True
    return hit.split("-", 1)[0].upper() not in NOT_TICKET_PREFIXES

DIFF_HEADER_RE = re.compile(r"^diff --git a/(.*) b/(.*)$")

CHECK_EPILOG = (
    f"the {len(CHECKS)} checks (slug - what silent means):\n"
    + "\n".join(f"  {slug:<24}{desc}" for slug, desc in CHECKS)
    + """

diff basis: `git diff` against `git merge-base HEAD <default branch>`.
default branch resolution order: `[layout] default_branch` from
aegis.toml always wins when set; else the branch origin/HEAD points at;
else a local `master`, then `main`. Without git or a merge base, each diff-based check
reports one NOTE line and everything else still runs. Lines longer
than 100 columns are truncated with `...`.

findings never make it exit non-zero - only --strict does, when there are
errors, failed --run commands, or warnings whose slug is listed in
[check] strict_promote. --run executes every plain [commands] entry
(template entries containing `{` are skipped, as are the reserved
`timeout` and `workdir` keys and side-effect-looking names unless
[check] run lists them); a failing
command is an ERROR (`command-failed`), and running nothing at all is
also an ERROR (`nothing-ran`), so --strict fails on it without needing a
promotion entry - silence never counts as proof. Note that --run proves
only what your [commands] actually cover: a `[check] run` list that
omits the test command means the suite did not run, and the skip is
printed as `run: <name> skipped`.

output is capped at the first 40 findings; --full (implied by --strict)
prints them all.

a usage error - an unknown task id, an unreadable aegis.toml - exits 1
whatever the findings say: that is the command failing to run, not a
judgement on the repository.
"""
)


def str_list(value: object) -> list[str]:
    """@brief A TOML value as a list of strings, tolerating a scalar."""
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value]
    return [str(value)] if value else []


def split_ids(value: str) -> list[str]:
    """@brief Split a `requirements:` header value into individual ids."""
    return [part for part in re.split(r"[\s,]+", value.strip()) if part]


def match_path(path: str, pattern: str) -> bool:
    """
    @brief One layout/affected_paths entry against one repo-relative path.
    @details A trailing `/` or a bare directory name matches by prefix; an
             entry with glob characters matches by fnmatchcase - the
             case-sensitive variant, so Windows and Linux agree; else exact.
    """
    if pattern.endswith("/"):
        # the directory itself is inside its own entry, not just its children
        return path.startswith(pattern) or path == pattern.rstrip("/")
    if any(char in pattern for char in "*?["):
        return fnmatch.fnmatchcase(path, pattern)
    return path == pattern or path.startswith(pattern + "/")


def match_any(path: str, patterns: list[str]) -> bool:
    """@brief True when any entry of `patterns` matches `path`."""
    return any(match_path(path, pattern) for pattern in patterns)


def default_branch(cfg: dict) -> str:
    """
    @brief The ref the diff is based on; "" when none can be resolved.
    @details Resolution order (documented in `check --help`): an explicit
             `[layout] default_branch` always wins; else the branch
             origin/HEAD points at; else a local `master`, then `main`.
    """
    configured = str(cfg_table(cfg, "layout").get("default_branch", "") or "")
    if configured:
        return configured
    out = run_git("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if out and out[0] == 0 and out[1].strip():
        return out[1].strip().removeprefix("refs/remotes/")
    for name in ("master", "main"):
        out = run_git("rev-parse", "--verify", "--quiet", f"refs/heads/{name}")
        if out and out[0] == 0:
            return name
    return ""


#: bound on how much of an untracked file the hygiene checks will read.
MAX_SCAN_BYTES = 262_144
#: findings printed before `check` summarises the rest (--full shows all).
FINDING_CAP = 40
#: cap on per-file re-diffs used to attribute git-quoted filenames.
MAX_REDIFF_FILES = 25
#: version of the `--json` envelopes. Consumers should refuse an unknown
#: value rather than guess: that is the point of publishing it.
JSON_SCHEMA = 1


def emit_json(payload: dict) -> None:
    """
    @brief Print one JSON document as the command's entire stdout.
    @details Every envelope carries `schema` so a consumer fails loudly on a
             contract change instead of silently misparsing. Human progress
             lines go to stderr under `--json`, keeping stdout a single
             parseable document.
    """
    print(json.dumps({"schema": JSON_SCHEMA, **payload},
                     ensure_ascii=False, indent=2, sort_keys=False))
#: task journals listed by `status` before it summarises the rest.
STATUS_CAP = 20


def untracked_files() -> list[str]:
    """@brief Relevant untracked, non-ignored files, decoded NUL-safely."""
    out = run_git("ls-files", "--others", "--exclude-standard", "-z")
    if not out or out[0] != 0:
        return []
    return [name for name in out[1].split("\0")
            if name and not generated_python_cache(name)]


def added_lines_of(file: str) -> list[tuple[str, str]]:
    """
    @brief Every line of an untracked text file, treated as an added line.
    @details Bounded (`MAX_SCAN_BYTES`) and binary-safe: oversized or binary
             files contribute their name to the file list but no text.
    """
    path = ROOT / file
    try:
        if path.stat().st_size > MAX_SCAN_BYTES:
            return []
        data = path.read_bytes()
    except OSError:
        return []
    if b"\0" in data[:4096]:
        return []
    return [(file, line) for line in
            data.decode("utf-8", errors="replace").splitlines()]


def diff_base(cfg: dict, revision: str = "") -> tuple[str, str]:
    """
    @brief The revision every diff is taken against, and why it failed.
    @details Without an explicit revision this is the merge base with the
             default branch - right for reviewing a whole branch. An explicit
             revision (`--base HEAD` during the edit-run loop) is used as
             given, so only work after that point counts as changed.
    """
    probe = run_git("rev-parse", "--git-dir")
    if probe is None:
        return "", "git executable not found"
    if probe[0] != 0:
        return "", "not a git repository"
    if revision:
        resolved = run_git("rev-parse", "--verify", f"{revision}^{{commit}}")
        if not resolved or resolved[0] != 0 or not resolved[1].strip():
            return "", f"unknown base revision '{revision}'"
        return resolved[1].strip(), ""
    branch = default_branch(cfg)
    if not branch:
        return "", "no default branch (origin/HEAD, master, main)"
    base = run_git("merge-base", "HEAD", branch)
    if not base or base[0] != 0 or not base[1].strip():
        return "", f"no merge base between HEAD and {branch}"
    return base[1].strip(), ""


def collect_diff(cfg: dict,
                 revision: str = "") -> tuple[list[str], list[tuple[str, str]],
                                              list[str], str]:
    """
    @brief Changed files and added lines versus the diff base.
    @details File names come from `git diff --name-only -z` (robust against
             quoted/non-ASCII paths); added text from the patch for tracked
             files plus bounded reads of untracked files, so work in progress
             is visible before it is ever staged. Returns (files, added
             (file, text) pairs, gaps, reason); gaps name files whose added
             content could not be scanned, and a non-empty reason means the
             diff-based checks must degrade to NOTE lines.
    """
    resolved, reason = diff_base(cfg, revision)
    if reason:
        return [], [], [], reason
    names = run_git("diff", "--name-only", "-z", resolved, "--")
    if not names or names[0] != 0:
        return [], [], [], "git diff failed"
    files = [name for name in names[1].split("\0")
             if name and not generated_python_cache(name)]

    added: list[tuple[str, str]] = []
    gaps: list[str] = []
    seen_in_patch: set[str] = set()
    # quotepath=false keeps non-ASCII names unquoted so header attribution
    # works for them; names with quotes or backslashes stay quoted and are
    # picked up by the per-file fallback below.
    patch = run_git("-c", "core.quotepath=false", "diff", resolved, "--")
    if patch and patch[0] == 0:
        current = ""
        for line in patch[1].split("\n"):
            if line.startswith("diff --git "):
                # a header we cannot parse (git-quoted name) must clear the
                # attribution, never leave it pointing at the previous file
                match = DIFF_HEADER_RE.match(line)
                current = match.group(2) if match else ""
                if current and generated_python_cache(current):
                    current = ""
                if current:
                    seen_in_patch.add(current)
            elif line.startswith("+") and not line.startswith("+++ ") and current:
                added.append((current, line[1:]))

    # tracked files the header parse could not attribute (git-quoted names):
    # diff them one at a time, where the name is known from the file list.
    unattributed = [f for f in files if f not in seen_in_patch]
    for name in unattributed[:MAX_REDIFF_FILES]:
        one = run_git("diff", resolved, "--", name)
        if one and one[0] == 0:
            added.extend((name, line[1:]) for line in one[1].split("\n")
                         if line.startswith("+") and not line.startswith("+++ "))
        else:
            gaps.append(name)
    gaps.extend(unattributed[MAX_REDIFF_FILES:])  # never silently skipped

    for name in untracked_files():
        if name not in files:
            files.append(name)
            lines = added_lines_of(name)
            added.extend(lines)
            if not lines and (ROOT / name).is_file():
                gaps.append(name)  # too large or binary: not content-scanned
    return files, added, gaps, ""


def scan_requirements(add, skip) -> list[tuple[str, Path, dict]]:
    """
    @brief Single pass over the requirement tree: checks 1 and 2.
    @details Returns the parsed records for the link checks; files that fail
             to parse at all are reported and dropped from the records.
    """
    records: list[tuple[str, Path, dict]] = []
    by_id: dict[str, list[str]] = {}
    for path in sorted((AGENTIC / "requirements").glob("**/*.toml")):
        relpath = rel(path)
        if skip(relpath):
            continue
        try:
            data = tomllib.loads(read_text(path))
        except UserError:
            add("ERROR", "req-parse", relpath, "not valid UTF-8")
            continue
        except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
            add("ERROR", "req-parse", relpath, f"not valid TOML: {exc}")
            continue
        missing = [f for f in REQUIRED_FIELDS if not str(data.get(f, "") or "").strip()]
        if missing:
            add("ERROR", "req-parse", relpath, "missing/empty: " + ", ".join(missing))
        schema_val = data.get("schema")
        if "schema" not in missing and (isinstance(schema_val, bool)
                                        or schema_val != SCHEMA):
            add("ERROR", "req-parse", relpath, f"schema must be the integer {SCHEMA}")
        for field in ("id", "title", "status", "requirement", "verification"):
            if field not in missing and not isinstance(data.get(field), str):
                add("ERROR", "req-parse", relpath, f"{field} must be a string")
        status = str(data.get("status", "") or "")
        if "status" not in missing and status not in REQ_STATUSES:
            add("ERROR", "req-parse", relpath,
                f"status '{status}' not in {'|'.join(REQ_STATUSES)}")
        records.append((relpath, path, data))
        rid = str(data.get("id", "") or "")
        if not rid:
            continue
        if not REQ_ID_RE.fullmatch(rid):
            add("ERROR", "req-parse", relpath,
                "id does not match REQ-<CODE>-<hex id>")
        by_id.setdefault(rid, []).append(relpath)
        if path.stem != rid:
            add("ERROR", "dup-id", relpath, "id does not match filename")
        expected = CODE_BY_FOLDER.get(path.parent.name)
        parts = rid.split("-")
        if expected and len(parts) == 3 and parts[1] != expected:
            add("ERROR", "dup-id", relpath,
                f"id says {parts[1]}, folder expects {expected}")
    for rid, paths in by_id.items():
        for relpath in (paths if len(paths) > 1 else []):
            add("ERROR", "dup-id", relpath, f"duplicate id ({len(paths)} files)")
    return records


#: prefixes that declare `verification` as a by-hand method, not a test.
MANUAL_PREFIXES = ("Manual:", "Inspection:")


def manual_method(verification: str) -> str:
    """
    @brief The declared by-hand method, or "" when none is declared.
    @details Some behaviors no test can settle - a look-and-see judgement, an
             install on clean hardware, a printed page. Naming the method
             after `Manual:` or `Inspection:` records it as a deliberate
             choice, and check reports check 19 instead of check 6: still
             printed, still counted, but a NOTE, so it never fails --strict
             and never joins the standing list of tests still owed. The
             prefix alone does not count - it has to name a method.
    """
    text = " ".join(verification.split())
    for prefix in MANUAL_PREFIXES:
        if text.startswith(prefix) and text[len(prefix):].strip():
            return text[len(prefix):].strip()
    return ""


def link_failure(entry: str) -> str:
    """
    @brief Why one `linked_tests` entry does not resolve, or "" when it does.
    @details The single place a linked test is judged to exist, so a finding
             and a coverage class can never disagree about one. An entry with
             no file part at all - a bare `::name` - is nobody's evidence of
             anything, but it is also not a broken path, so it is passed over
             rather than reported.
    """
    file = entry.split("::", 1)[0]
    if not file:
        return ""
    if not repo_relative_ok(file):
        return f"{file} escapes the repository"
    if not (ROOT / file).is_file():
        return f"{file} does not exist"
    return ""


def coverage_class(record: dict) -> str:
    """
    @brief Which coverage class one requirement record belongs to.
    @details The single place the precedence lives, so that every reader of a
             record - `check`, the diagram, `explain` - reaches the same
             verdict. The ladder is `check`'s own: a withdrawn behavior first,
             then one still in draft, which `check` deliberately says nothing
             about; then, among active records, a linked test that does not
             resolve, which is a warning and not evidence, then a declared
             by-hand method where nothing is linked, then nothing at all.
             A broken link outranks a `Manual:` method beside it, because the
             record claims a test that is not there - the claim is the finding.
    """
    status = str(record.get("status", "") or "")
    if status == "retired":
        return "retired"
    if status != "active":
        return "draft"
    linked = str_list(record.get("linked_tests"))
    if not linked:
        return "manual" if manual_method(
            str(record.get("verification", "") or "")) else "uncovered"
    return "broken" if any(link_failure(entry) for entry in linked) else "tested"


def check_requirement_links(add, records) -> None:
    """@brief Per-requirement checks 4, 6, 7, 10 and 19 over the parsed records."""
    for relpath, _path, data in records:
        spec_ref = str(data.get("spec", "") or "").strip()
        if spec_ref and not repo_relative_ok(spec_ref):
            add("ERROR", "spec-missing", relpath, f"{spec_ref} escapes the repository")
        elif spec_ref and not (AGENTIC / spec_ref).is_file():
            add("ERROR", "spec-missing", relpath, f"{spec_ref} does not resolve")
        status = str(data.get("status", "") or "")
        if status == "active":
            # one class, one finding: `manual` is the NOTE, `uncovered` and
            # `broken` are the warning, `tested` is the silence. The diagram
            # labels the same verdict, which is what keeps the picture honest
            klass = coverage_class(data)
            if klass == "manual":  # 19: manual-verification
                method = manual_method(str(data.get("verification", "") or ""))
                add("NOTE", "manual-verification", relpath,
                    "by hand: " + method[:60])
            elif klass == "uncovered":
                add("WARN", "no-linked-tests", relpath, "empty linked_tests")
            for entry in str_list(data.get("linked_tests")):
                reason = link_failure(entry)
                if reason:
                    add("WARN", "no-linked-tests", relpath, reason)
        if status != "retired":
            for entry in str_list(data.get("affected_paths")):
                if not repo_relative_ok(entry):
                    add("WARN", "stale-paths", relpath,
                        f"{entry} escapes the repository")
                    continue
                try:
                    if any(char in entry for char in "*?["):
                        exists = next(ROOT.glob(entry), None) is not None
                    else:
                        exists = (ROOT / entry).exists()
                except (ValueError, OSError, NotImplementedError):
                    exists = False
                if not exists:
                    add("WARN", "stale-paths", relpath,
                        f"{entry} no longer exists")
        hits = set(TICKET_RE.findall(str(data.get("requirement", ""))))
        for hit in sorted(h for h in hits if is_ticket_reference(h)):
            add("WARN", "ticket-ref", relpath, f"ticket pattern: {hit}")


def scan_journals(add, skip, req_ids: set[str]) -> list[tuple[str, dict]]:
    """@brief Single pass over the task journals: checks 3 and 11."""
    journals: list[tuple[str, dict]] = []
    for path in sorted((AGENTIC / "tasks").glob("TASK-*.md")):
        relpath = rel(path)
        if skip(relpath):
            continue
        try:
            text = read_text(path)
            data = parse_journal(text)
        except UserError:  # corrupt encoding: report, keep scanning
            add("ERROR", "journal-header", relpath, "not valid UTF-8")
            continue
        if not data["id"]:
            add("ERROR", "journal-header", relpath,
                "no '# TASK-<id> - <title>' heading")
            continue
        if "stage" not in data["header"]:
            add("ERROR", "journal-header", relpath, "no 'stage:' header line")
            continue
        if data["header"]["stage"] not in KNOWN_STAGES:
            add("WARN", "journal-header", relpath,
                f"unknown stage '{data['header']['stage']}'")
        if data["id"] != path.stem:
            add("ERROR", "journal-header", relpath,
                f"heading id {data['id']} does not match the filename")
        for key in ("type", "branch", "opened"):
            if key not in data["header"]:
                add("WARN", "journal-header", relpath,
                    f"missing '{key}:' header line")
        journals.append((relpath, data))
        rulings, ruling_errors = parse_rulings(text)
        for error in ruling_errors:
            add("WARN", "journal-header", relpath, error)
        known_rulings: set[str] = set()
        for ruling in rulings:
            supersedes = ruling.get("supersedes", "none")
            if supersedes != "none" and supersedes not in known_rulings:
                add("WARN", "journal-header", relpath,
                    f"{ruling['id']} supersedes unknown earlier {supersedes}")
            known_rulings.add(ruling["id"])
        try:
            handoff = parse_handoff(text)
        except UserError as exc:
            add("WARN", "journal-header", relpath, str(exc))
            handoff = {}
        handoff_current = handoff.get("current", "")
        if handoff_current and handoff_current != data["header"]["stage"]:
            add("WARN", "journal-header", relpath,
                f"stale Handoff current {handoff_current} != {data['header']['stage']}")
        for rid in split_ids(data["header"].get("requirements", "")):
            if rid not in req_ids:
                add("ERROR", "journal-header", relpath, f"unknown requirement {rid}")
        if data["header"]["stage"] == "deliver":
            open_items = sum(1 for ticked, _i in data["checklist"] if not ticked)
            if open_items:
                add("WARN", "unticked-deliver", relpath,
                    f"{open_items} unticked item(s) in deliver")
    by_id = {data["id"].upper(): (relpath, data) for relpath, data in journals}
    children: dict[str, list[tuple[str, dict]]] = {}
    for relpath, data in journals:
        parent = data["header"].get("parent", "").strip()
        if not parent:
            continue
        if not re.fullmatch(r"TASK-[0-9A-Fa-f]{4,12}", parent):
            add("WARN", "journal-header", relpath,
                "malformed parent visible in this checkout")
            continue
        target = by_id.get(parent.upper())
        if target is None:
            add("WARN", "journal-header", relpath,
                f"unknown parent {parent} visible in this checkout")
            continue
        if target[1]["header"].get("parent", "").strip():
            add("WARN", "journal-header", relpath,
                f"parent {parent} is itself a child visible in this checkout")
            continue
        children.setdefault(parent.upper(), []).append((relpath, data))
    for parent_id, visible in children.items():
        parent_path, parent = by_id[parent_id]
        unfinished = [data for _path, data in visible
                      if data["header"].get("stage") != "done"]
        if parent["header"].get("stage") == "done" and unfinished:
            add("WARN", "journal-header", parent_path,
                f"done parent has {len(unfinished)} unfinished child visible in this checkout")
    return journals


def check_review_state(add, cfg: dict, journals: list[tuple[str, dict]]) -> None:
    """@brief Check enabled explicit-review evidence against its finite policy."""
    enabled, max_fix_cycles = review_settings(cfg)
    if not enabled:
        return
    for relpath, journal in journals:
        stage = journal.get("header", {}).get("stage", "")
        if stage not in {"validate", "deliver"}:
            continue
        try:
            text = read_text(ROOT / relpath)
            record, notice = bound_stage_report(text, stage)
        except UserError:
            add("WARN", "review-state", relpath,
                "enabled review has malformed verdict evidence")
            continue
        if notice:
            add("WARN", "review-state", relpath,
                f"enabled review evidence not current: {notice}")
            continue
        spec = record.get("spec_compliance", "")
        quality = record.get("implementation_quality", "")
        round_text = record.get("review_round", "")
        enabled_verdicts = {"approved", "changes_required"}
        if spec not in enabled_verdicts or quality not in enabled_verdicts or not round_text:
            add("WARN", "review-state", relpath,
                "enabled review has incomplete verdict evidence")
        if round_text and int(round_text) > 1 + max_fix_cycles:
            add("WARN", "review-state", relpath,
                f"review_round {round_text} exceeds configured total "
                f"{1 + max_fix_cycles}")
        if (journal.get("header", {}).get("stage") == "deliver"
                and (spec, quality) != ("approved", "approved")):
            add("WARN", "review-state", relpath,
                "deliver requires two current approved verdicts")


def check_diff(add, skip, cfg, records, journals, scope) -> None:
    """
    @brief Diff-based checks 5, 8, 9, 12, 13 and 20.
    @details `scope` is the parsed journal of `--task` or None; it narrows
             check 5's coverage set and checks 8 and 20 to that one task, and
             its `base:` header - the commit the task started from - becomes
             the diff basis, so the findings describe that task rather than
             everything its branch has done. Without a usable diff every check
             here emits one NOTE and returns.
    """
    base = str(scope["header"].get("base", "")).strip() if scope else ""
    files, added, gaps, reason = collect_diff(cfg, base)
    if reason:
        for slug in DIFF_CHECKS:
            add("NOTE", slug, "(diff)", f"skipped: {reason}")
        return
    # WARN, not NOTE: a team that promotes `secret-in-diff` in CI is asking
    # for the secret scan to be trusted, and an unscanned file is precisely
    # when it cannot be - so the gap must be promotable too.
    gaps = [name for name in gaps if not skip(name)]
    for name in gaps[:5]:  # a partial scan must say so, never read as clean
        add("WARN", "secret-in-diff", name, "added lines not scanned")
    if len(gaps) > 5:
        add("WARN", "secret-in-diff", "(diff)",
            f"{len(gaps) - 5} further file(s) not content-scanned")
    files = [f for f in files if not skip(f)]
    layout = cfg_table(cfg, "layout")
    source_globs = str_list(layout.get("source"))
    tests_globs = str_list(layout.get("tests"))
    docs_globs = str_list(layout.get("docs"))
    info = {str(d.get("id", "")): (relpath, str_list(d.get("affected_paths")))
            for relpath, _p, d in records}

    if scope:
        rids = split_ids(scope["header"].get("requirements", ""))
        cover = [p for rid in rids for p in info.get(rid, ("", []))[1]]
        drift_journals = [(rp, d) for rp, d in journals if d["id"] == scope["id"]]
    else:
        cover = [p for _rp, _p, d in records
                 if str(d.get("status", "")) != "retired"
                 for p in str_list(d.get("affected_paths"))]
        drift_journals = journals

    for file in files:  # 5: uncovered-source
        # a deleted file is still in the diff, but demanding a requirement
        # cover a file that no longer exists is an unactionable finding
        if not (ROOT / file).is_file():
            continue
        if match_any(file, source_globs) and not match_any(file, cover):
            add("WARN", "uncovered-source", file,
                "not covered by any requirement affected_paths")

    for relpath, data in drift_journals:  # 8: scope-drift
        stage = data["header"].get("stage", "")
        if stage not in ("build", "validate", "deliver") or not files:
            continue
        # targets are the linked requirements' affected_paths only - the
        # requirement TOML itself is usually created on this same branch and
        # would make the check permanently silent if it counted as "touched"
        targets: list[str] = []
        for rid in split_ids(data["header"].get("requirements", "")):
            if rid in info:
                targets.extend(info[rid][1])
        if not any(match_any(file, targets) for file in files):
            add("WARN", "scope-drift", relpath,
                f"{stage} diff touches no linked requirement")

    patterns = [(name, re.compile(regex)) for name, regex in SECRET_PATTERNS]
    for extra in str_list(cfg_table(cfg, "check").get("secret_patterns_extra")):
        try:
            patterns.append(("secret_patterns_extra", re.compile(extra)))
        except re.error as exc:
            add("NOTE", "secret-in-diff", "(config)",
                f"invalid secret_patterns_extra regex: {exc}")
    seen: set[tuple[str, str]] = set()
    for file, text in added:  # 9: secret-in-diff
        if skip(file):
            continue
        for name, regex in patterns:
            if (file, name) not in seen and regex.search(text):
                seen.add((file, name))
                add("WARN", "secret-in-diff", file, f"possible secret ({name})")

    for file in files:  # 12: outside-layout
        # the root pointer files are ours - init creates them, so flagging
        # them would greet every new install with three false warnings
        if file in POINTER_FILES:
            continue
        if not (match_any(file, source_globs) or match_any(file, tests_globs)
                or match_any(file, docs_globs)
                or file.startswith(".agentic/")):
            add("WARN", "outside-layout", file,
                "outside source/tests/docs globs and .agentic/")

    source_changed = [f for f in files if match_any(f, source_globs)]
    if source_changed and not any(match_any(f, tests_globs) for f in files):
        add("WARN", "source-no-test-changes", "(diff)",  # 13
            f"{len(source_changed)} source file(s) changed, no test changes")

    zones = stage_zones(cfg)
    current = git_branch()
    zone_journals = [
        (relpath, data) for relpath, data in drift_journals
        if data["header"].get("stage", "") in zones
    ]
    if current == "unknown" and scope is None and zone_journals:
        add("NOTE", "stage-zone", "(diff)",
            "skipped: current branch unavailable; use --task on detached HEAD")
        zone_journals = []
    for relpath, data in zone_journals:  # 20: stage-zone
        stage = data["header"].get("stage", "")
        recorded = data["header"].get("branch", "")
        if recorded and current not in ("unknown", recorded):
            continue  # this journal describes some other branch's diff
        allowed: list[str] = []
        for zone in zones[stage]:
            # an unrecognised name contributes nothing; check 15 reports it
            if zone == "source":
                allowed.extend(source_globs)
            elif zone == "tests":
                allowed.extend(tests_globs)
        named = ", ".join((".agentic/",) + tuple(zones[stage]))
        for file in files:
            if not (match_any(file, source_globs) or match_any(file, tests_globs)):
                continue  # outside the layout entirely - that is check 12
            if not match_any(file, allowed):
                add("WARN", "stage-zone", file,
                    f"edited in stage '{stage}', whose write zone is {named}")


def run_checks(cfg: dict, task: str | None) -> list[tuple[str, str, str, str]]:
    """
    @brief Collect the full findings list of the check catalog.
    @details Shared by `check` and `report`. `task` scopes the diff-based
             checks to that journal exactly as `check --task` does.
    """
    ignore = str_list(cfg_table(cfg, "check").get("ignore"))
    findings: list[tuple[str, str, str, str]] = []

    def add(level: str, slug: str, path: str, message: str) -> None:
        findings.append((level, slug, path, message))

    def skip(path: str) -> bool:
        return match_any(path, ignore)

    check_config(add, cfg)
    scope_path, scope = read_journal(task) if task else (None, None)
    if scope:
        recorded, current = scope["header"].get("branch", ""), git_branch()
        if recorded and current not in ("unknown", recorded):
            add("WARN", "journal-header", "(task)",
                f"journal branch '{recorded}' != current '{current}' - "
                "diff checks reflect the current branch")
    records = scan_requirements(add, skip)
    check_requirement_links(add, records)
    req_ids = {str(d.get("id", "")) for _r, _p, d in records} - {""}
    journals = scan_journals(add, skip, req_ids)
    check_review_state(add, cfg, journals)
    check_diff(add, skip, cfg, records, journals, scope)
    if scope_path is not None and scope is not None:
        check_repo_evolution(add, scope_path, scope)
    return findings


def check_repo_evolution(add, journal: Path, scope: dict) -> None:
    """@brief Report missing or unreadable state records for one scoped task."""
    task = journal.stem
    anchor_file = state_path(journal, "anchor")
    history_file = state_path(journal, "evolution")
    if not anchor_file.is_file():
        add("NOTE", "repo-evolution", rel(journal),
            "no anchor recorded for task")
        return
    try:
        anchor = validate_anchor(read_json_file(anchor_file, "anchor"),
                                 task, anchor_file)
    except UserError as exc:
        add("WARN", "repo-evolution", rel(anchor_file), str(exc))
        return
    if not history_file.is_file():
        add("NOTE", "repo-evolution", rel(journal),
            "active anchor has no completed evolution")
        return
    try:
        history = validate_history(read_json_file(history_file, "evolution"),
                                   task, history_file)
    except UserError as exc:
        add("WARN", "repo-evolution", rel(history_file), str(exc))
        return
    if not any(isinstance(report, dict)
               and report.get("anchor_id") == anchor["anchor_id"]
               for report in history["reports"]):
        stage = scope.get("header", {}).get("stage", "")
        add("NOTE", "repo-evolution", rel(journal),
            f"active anchor has no completed evolution (stage {stage or '?'})")


def command_timeout(cfg: dict, name: str = "") -> int | None:
    """
    @brief The limit for one command in seconds, or None for no limit.
    @details `[timeouts] <name>` wins, then the shared `[commands] timeout`,
             and absent means None: nothing shipped may stop a command the
             repository believes is healthy. A suite that legitimately runs
             for an hour is the repository's business, and a limit low enough
             to cut it short would report a failure that never happened. Zero,
             negative and unreadable values all mean no limit too, so the only
             way to get one is to ask for it.
    """
    table = cfg_table(cfg, "timeouts")
    raw = table.get(name) if name and name in table else \
        cfg_table(cfg, "commands").get("timeout")
    if isinstance(raw, bool):
        return None
    try:
        value = int(raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return value if value > 0 else None


def command_workdir(cfg: dict) -> Path:
    """
    @brief Where configured commands run: `[commands] workdir`, else the root.
    @details A repository whose application sits below the root would
             otherwise have to embed a directory change in the command
             string, which silently invalidates every path substituted into
             that command. An absent, escaping, or missing directory falls
             back to the root - the `config` check reports it; nothing here
             blocks.
    """
    raw = str(cfg_table(cfg, "commands").get("workdir", "")).strip()
    if not raw or not repo_relative_ok(raw):
        return ROOT
    target = ROOT / raw
    return target if target.is_dir() else ROOT


def runnable_commands(cfg: dict) -> list[tuple[str, str]]:
    """
    @brief The `[commands]` entries that can run as-is, in file order.
    @details The reserved keys - which name configuration, not commands -
             and template entries containing `{` (such as `test_impacted`)
             are not directly runnable and are skipped.
    """
    return [
        (name, value)
        for name, value in cfg_table(cfg, "commands").items()
        if name not in RESERVED_COMMAND_KEYS and isinstance(value, str)
        and value.strip() and "{" not in value
    ]


def kill_tree(proc: subprocess.Popen) -> bool:
    """
    @brief Kill a timed-out command and its descendants, per platform.
    @details Returns True when the platform reported a successful tree kill;
             False means descendants may have survived (restricted sandboxes
             can deny `taskkill`) and the caller must say so.
    """
    if sys.platform == "win32":
        killed = False
        try:
            result = subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                                    check=False,   # a failed kill is reported, not raised
                                    capture_output=True, timeout=20)
            killed = result.returncode == 0
        except (OSError, subprocess.SubprocessError):
            killed = False  # taskkill missing, denied, or itself hung
        proc.kill()  # the shell itself, regardless of taskkill's outcome
        return killed
    import os
    import signal
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        return True
    except (OSError, ProcessLookupError):
        proc.kill()
        return False


def run_command(command: str, timeout: int | None, capture: bool = True,
                cwd: Path | None = None) -> tuple[int, float, list[str], bool]:
    """
    @brief Run one configured shell command, by default in the repo root.
    @details Returns (exit code, seconds, captured output tail, stopped). The
             `stopped` flag says the limit ended the command, which the exit
             code alone cannot: a command is free to exit 124 by itself, and a
             caller reporting whether anything was proven must not guess. Exit
             124 on timeout: the command's process tree is killed where the platform
             allows it (`taskkill /F /T` on Windows, the session group on
             POSIX), and when that kill is refused - restricted sandboxes do
             refuse it - the shell is still killed and the returned tail says
             descendants may have survived. Exit 127 when the command could
             not be launched at all. With capture=False the output streams to
             the console and the tail is empty - used by `aegis test`, where
             live output matters. Captured output goes to a temporary file,
             so memory stays flat whatever the command emits and only the
             last 4 KiB is ever read back. The cost moves to the temp
             volume - note this is a cost capture *adds*: run in a terminal
             the same output would stream and be discarded, so a
             pathologically noisy command can fill the temp volume here
             when it would not have filled anything there.
    """
    start = time.monotonic()
    kwargs: dict = {"cwd": str(cwd or ROOT), "shell": True}
    sink = None
    if capture:
        # a temp file, not a pipe: output of any size costs disk, not memory,
        # and only its tail is ever read back.
        # SIM115 is suppressed below: the handle outlives this block by design
        # - it is handed to the child as stdout and closed after the process
        # is reaped.
        sink = tempfile.TemporaryFile(mode="w+", encoding="utf-8",  # noqa: SIM115
                                      errors="replace", newline="")
        kwargs.update(stdout=sink, stderr=subprocess.STDOUT)
    if sys.platform != "win32":
        kwargs["start_new_session"] = True
    try:
        proc = subprocess.Popen(command, **kwargs)
    except OSError as exc:
        if sink is not None:
            sink.close()
        return 127, time.monotonic() - start, [str(exc)], False

    note, stopped = "", False
    try:
        code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stopped = True
        killed = kill_tree(proc)
        try:
            proc.wait(timeout=5)
        except (subprocess.SubprocessError, OSError):
            pass
        code = 124
        note = f"timed out after {timeout}s"
        if not killed:
            note += "; descendants may have survived the kill"

    output = ""
    if sink is not None:
        try:
            sink.seek(max(0, sink.tell() - 4096))
            output = sink.read()
        except OSError:
            output = ""
        finally:
            sink.close()
    if note:
        output = f"{output}\n{note}"
    tail = [line for line in output.strip().split("\n") if line.strip()][-8:]
    return code, time.monotonic() - start, tail, stopped


#: command names that suggest side effects beyond verification - skipped by
#: `check --run` unless explicitly listed in `[check] run`.
SIDE_EFFECT_NAME_RE = re.compile(r"deploy|migrat|publish|release|push|upload",
                                 re.IGNORECASE)


def run_configured_commands(cfg: dict, findings: list,
                            stream=None) -> list[dict]:
    """
    @brief Execute the verification `[commands]` entries for `check --run`.
    @details `check --run` is a verification pass, not a deployment tool: an
             explicit `[check] run` list restricts execution to those names;
             without one, every plain entry runs except names that look like
             side effects (deploy/migrate/publish/release/push/upload), which
             are skipped with a visible line. Progress prints as each command
             finishes rather than at the end, so a long suite does not look
             hung. Each failure appends an ERROR finding (`command-failed`),
             and running *nothing* appends an ERROR (`nothing-ran`), which
             fails strict mode on its own - silence must never read as proof
             that the suite passed. What *did* run is only ever what
             `[commands]` (minus `[check] run` exclusions) covers.
    @details Progress goes to `stream` (stdout by default; stderr under
             `--json`, so stdout stays one parseable document). Returns one
             record per configured command for the JSON envelope.
    """
    entries = runnable_commands(cfg)
    allowed = str_list(cfg_table(cfg, "check").get("run"))
    out = stream if stream is not None else sys.stdout
    results: list[dict] = []
    workdir = command_workdir(cfg)
    ran = 0

    def say(text: str) -> None:
        print(text, file=out, flush=True)  # live: each command lands visibly

    for name, command in entries:
        if allowed and name not in allowed:
            say(f"run: {name} skipped (not listed in [check] run)")
            results.append({"name": name, "status": "skipped",
                            "reason": "not listed in [check] run"})
            continue
        if not allowed and SIDE_EFFECT_NAME_RE.search(name):
            say(f"run: {name} skipped (name suggests side effects - "
                "list it in [check] run to include it)")
            results.append({"name": name, "status": "skipped",
                            "reason": "name suggests side effects"})
            continue
        say(f"run: {name} started")  # a 20-minute suite must not look hung
        limit = command_timeout(cfg, name)
        code, seconds, tail, stopped = run_command(command, limit, cwd=workdir)
        ran += 1
        if stopped:
            # a command that was cut off returned no verdict at all: calling
            # that a failure invents evidence, calling it a pass hides that
            # nothing was checked. It stays an ERROR because an unfinished
            # proof is not a proof.
            say(f"run: {name} stopped at its {limit}s limit ({seconds:.1f}s)"
                " - nothing proven")
            for text in tail:
                say(f"  | {text}")
            findings.append(("ERROR", "command-timeout", "(run)",
                             (f"{name} reached its {limit}s limit - nothing "
                              "proven; raise [timeouts] if it needs longer")))
        elif code == 0:
            say(f"run: {name} ok ({seconds:.1f}s)")
        else:
            say(f"run: {name} FAIL exit {code} ({seconds:.1f}s)")
            for text in tail:
                say(f"  | {text}")
            findings.append(("ERROR", "command-failed", "(run)",
                             f"{name} exit {code}"))
        status = "stopped" if stopped else ("ok" if code == 0 else "failed")
        results.append({"name": name, "status": status,
                        "exit": code, "seconds": round(seconds, 1),
                        "tail": tail})
    if not ran:
        say("run: nothing ran")
        # ERROR, not WARN: --run promised verification and delivered none, so
        # strict mode must fail without needing a promotion entry. Advisory
        # runs still exit 0 - errors inform there, they do not block.
        findings.append(("ERROR", "nothing-ran", "(run)",
                         "--run executed no command - nothing was verified"))
    return results


def cmd_check(args: argparse.Namespace) -> int:
    """
    @brief Run the check catalog and print the findings report.
    @details Advisory by design: exits 0 - except with --strict (the CI
             mode), which exits 1 on errors, failed --run commands, and
             warnings promoted via `[check] strict_promote`. One finding per
             line, `LEVEL  CHECK-ID  path - message`, sorted by path, capped
             at 100 columns; then two summary lines.
    """
    cfg = load_config()
    findings = run_checks(cfg, args.task)
    # under --json stdout must stay one parseable document, so live progress
    # goes to stderr instead of being lost.
    runs = (run_configured_commands(cfg, findings,
                                    sys.stderr if args.json else None)
            if args.run else [])

    counts = {"ERROR": 0, "WARN": 0, "NOTE": 0}
    promoted = set(str_list(cfg_table(cfg, "check").get("strict_promote")))
    promoted_warns = 0
    ordered = sorted(findings, key=lambda f: (f[2], f[1], f[3]))
    for level, slug, _path, _message in ordered:
        counts[level] += 1
        promoted_warns += level == "WARN" and slug in promoted
    worst = next((lv for lv in ("ERROR", "WARN", "NOTE") if counts[lv]), "")
    failed = bool(args.strict and (counts["ERROR"] or promoted_warns))

    if args.json:  # a machine consumer always gets the complete set
        emit_json({
            "command": "check",
            "task": args.task or None,
            "findings": [{"level": level, "check": slug, "path": path,
                          "message": message}
                         for level, slug, path, message in ordered],
            "summary": {"errors": counts["ERROR"], "warnings": counts["WARN"],
                        "notes": counts["NOTE"]},
            "result": worst or "ok",
            "run": runs,
            "strict": {"enabled": bool(args.strict),
                       "promoted_warnings": promoted_warns,
                       "passed": not failed} if args.strict else None,
        })
        return 1 if failed else 0

    shown = 0
    # a small-context model should not be handed hundreds of lines; CI and
    # --full want everything.
    cap = None if (args.full or args.strict) else FINDING_CAP
    for level, slug, path, message in ordered:
        if cap is not None and shown >= cap:
            continue
        shown += 1
        line = f"{level:<5}  {slug}  {path} - {message}"
        print(line if len(line) <= 100 else line[:97] + "...")
    if cap is not None and len(findings) > shown:
        print(f"... {len(findings) - shown} more finding(s) - use --full")
    print(f"summary: errors={counts['ERROR']} warnings={counts['WARN']} "
          f"notes={counts['NOTE']}")
    print(f"result: {worst or 'ok'}")

    if args.strict:
        if failed:
            print(f"strict: exit 1 ({counts['ERROR']} error(s), "
                  f"{promoted_warns} promoted warning(s))")
            return 1
        print("strict: ok")
    return 0


# test / report


#: shape of a substitutable test reference: safe characters only, and it may
#: not start with `-` (an option-like ref could alter the runner's behavior).
#: Anything else falls back to the full suite instead of reaching the shell.
SAFE_TEST_REF_RE = re.compile(r"^[A-Za-z0-9_./][A-Za-z0-9_.:\[\]/=-]*$")

#: How long a substituted command may get before the platform refuses to
#: launch it. Windows caps a process command line at 32767 characters and the
#: shell that actually receives it at rather less, so this stays conservative:
#: a focused set is worth nothing if the command cannot start. Exceeding it is
#: not an error - it selects a coarser set (whole test files), then the full
#: suite.
COMMAND_LENGTH_LIMIT = 8000


def rebase_ref(entry: str, workdir: Path) -> str:
    """
    @brief One repository-relative test reference, seen from `workdir`.
    @details References are stored repository-relative so they stay
             comparable whatever a repository configures; only substitution
             knows where the command will run. Returns "" when the reference
             lies outside the working directory, where the command could not
             reach it.
    """
    if workdir == ROOT:
        return entry
    path, _, selector = entry.partition("::")
    try:
        relative = (ROOT / path).resolve().relative_to(workdir.resolve())
    except (ValueError, OSError):
        return ""
    rebased = relative.as_posix()
    return f"{rebased}::{selector}" if selector else rebased


def impacted_tests(cfg: dict, revision: str = "") -> tuple[list[str], str]:
    """
    @brief The focused regression set: diff -> requirements -> linked_tests.
    @details The traceability mapping driven in reverse, with two safety
             rules. Completeness: every changed source file must be covered
             by some requirement's affected_paths, otherwise the focused set
             would silently skip the uncovered work and the caller falls back
             to the full suite. Hygiene: any test reference containing shell
             metacharacters (spaces, quotes, `;`, `&`, redirects) also forces
             the fallback - references are substituted into a shell command
             and must never be able to alter it.
    """
    files, _added, _gaps, reason = collect_diff(cfg, revision)
    if reason:
        return [], reason
    source_globs = str_list(cfg_table(cfg, "layout").get("source"))
    source_changed = [file for file in files if match_any(file, source_globs)]
    if not source_changed:
        return [], "no changed source files to map"

    records = [
        (str_list(data.get("affected_paths")), str_list(data.get("linked_tests")))
        for _relpath, _path, data in
        scan_requirements(lambda *_a: None, lambda _p: False)
        if str(data.get("status", "")) != "retired"
    ]
    tests: list[str] = []
    for file in source_changed:
        covered, file_tests = False, []
        for paths, linked in records:
            if match_any(file, paths):
                covered = True
                file_tests.extend(entry for entry in linked if entry)
        if not covered:
            return [], f"changed source not fully covered ({file})"
        if not file_tests:  # covered on paper, but nothing would test it
            return [], f"no linked tests for changed source ({file})"
        for entry in file_tests:
            if entry not in tests:
                tests.append(entry)
    for entry in tests:
        if not SAFE_TEST_REF_RE.fullmatch(entry):
            return [], f"unsafe test reference '{entry}'"
        if not repo_relative_ok(entry.split("::", 1)[0]):
            return [], f"test reference escapes the repository ('{entry}')"

    workdir = command_workdir(cfg)
    rebased = []
    for entry in tests:
        seen_from = rebase_ref(entry, workdir)
        if not seen_from:
            return [], ("test reference is outside the command working "
                        f"directory ('{entry}')")
        rebased.append(seen_from)
    return rebased, ""


def fit_impacted(template_cmd: str, tests: list[str],
                 reason: str) -> tuple[str, list[str], str]:
    """
    @brief Substitute the focused set, coarsening it until it can launch.
    @details A selector list long enough to exceed the platform's command
             line cannot start at all, which is a worse outcome than running
             a slightly wider set. So the ladder is: exact selectors, then
             each distinct test file once, then the caller's full-suite
             fallback. Returns (command, references used, reason); an empty
             command means the caller must fall back and say why.
    """
    if not tests:
        return "", tests, reason
    command = template_cmd.replace("{tests}", " ".join(tests))
    if len(command) <= COMMAND_LENGTH_LIMIT:
        return command, tests, ""

    files: list[str] = []
    for entry in tests:
        path = entry.partition("::")[0]
        if path not in files:
            files.append(path)
    command = template_cmd.replace("{tests}", " ".join(files))
    if len(command) <= COMMAND_LENGTH_LIMIT:
        print(f"impacted: too long to launch - reduced to {len(files)} "
              f"test file(s) from {len(tests)} selector(s)")
        return command, files, ""
    return "", files, ("still too long to launch after reduction to "
                       f"{len(files)} test file(s)")


def append_log(task_id: str, message: str) -> None:
    """
    @brief Append one dated log line at the end of the journal's Log section.
    @details The Log section may not be the last section once a delivery
             report has been appended, so the line is inserted before the
             next `## ` heading rather than blindly at end of file.
    """
    path, _data = read_journal(task_id)
    text = read_text(path)
    line = f"- {today()} {message}"
    heading = re.search(r"^## Log[ \t]*$", text, re.MULTILINE)
    following = re.search(r"^## ", text[heading.end():], re.MULTILINE) if heading else None
    if heading and following:
        pos = heading.end() + following.start()
        head = text[:pos].rstrip("\n")
        write_text(path, f"{head}\n{line}\n\n{text[pos:]}")
    else:
        if not text.endswith("\n"):
            text += "\n"
        write_text(path, f"{text}{line}\n")


def cmd_test(args: argparse.Namespace) -> int:
    """
    @brief Convenience runner for one configured command (default: test).
    @details Output streams live; the exit code mirrors the command's own
             result. --impacted substitutes the focused regression set into
             the `test_impacted` template and falls back to the full `test`
             command - saying why - whenever the set cannot be used.
    """
    cfg = load_config()
    commands = cfg_table(cfg, "commands")
    if args.impacted and args.name != "test":
        raise UserError("--impacted only applies to the 'test' command")
    command = commands.get(args.name)
    if (args.name in RESERVED_COMMAND_KEYS or not isinstance(command, str)
            or not command.strip() or "{" in command):
        raise UserError(
            f"no runnable [commands] entry named '{args.name}' in aegis.toml")

    label = args.name
    if args.impacted:
        template_cmd = commands.get("test_impacted")
        if not isinstance(template_cmd, str) or "{tests}" not in template_cmd:
            print("impacted: no test_impacted template in aegis.toml"
                  " - running the full test command")
        else:
            tests, reason = impacted_tests(cfg, getattr(args, "base", "") or "")
            substituted, tests, reason = fit_impacted(template_cmd, tests, reason)
            if substituted:
                command = substituted
                label = f"test --impacted ({len(tests)} test ref(s))"
            else:
                print(f"impacted: {reason} - running the full test command")

    if args.task:  # validate before running: a typo must not cost a suite run
        read_journal(args.task)

    print(f"$ {command}", flush=True)
    code, seconds, _tail, stopped = run_command(
        command, command_timeout(cfg, args.name), capture=False,
        cwd=command_workdir(cfg))
    if stopped:
        label = f"{label} stopped at its limit - nothing proven"
    print(f"{label}: exit {code} ({seconds:.1f}s)")
    if args.task:
        append_log(args.task, f"test: {label} exit {code} ({seconds:.1f}s)")
    return code


#: One fill and stroke per `coverage_class`, in the order a reader scans for
#: trouble. Green and blue are settled, amber and red are the two shapes of
#: `check`'s warning, and the two greys are the records it stays silent about.
COVERAGE_CLASSES = (
    ("tested", "#2f8f5b", "#1c6640"),
    ("manual", "#3a6ea8", "#254a73"),
    ("broken", "#c07a2c", "#8a5316"),
    ("uncovered", "#b03a3a", "#7d2626"),
    ("draft", "#6a6f7a", "#474b53"),
    ("retired", "#8a8a8a", "#5c5c5c"),
)

#: how wide a requirement title may be before the node label truncates it.
LABEL_WIDTH = 38


def mermaid_label(text: str) -> str:
    """
    @brief One requirement title, safe inside a quoted Mermaid node label.
    @details Mermaid reads `"` and `#` inside a label as syntax, so both are
             replaced rather than escaped - a label is a caption, and a
             caption that breaks the drawing is worse than one that lost a
             quotation mark.
    """
    flat = " ".join(str(text).split()).replace('"', "'").replace("#", "no.")
    return flat[:LABEL_WIDTH - 1] + "…" if len(flat) > LABEL_WIDTH else flat


def mermaid_id(text: str) -> str:
    """@brief A Mermaid node or subgraph id: letters, digits and underscores."""
    return re.sub(r"[^A-Za-z0-9]", "_", str(text)) or "node"


def knowledge_components(on_error=None) -> list[tuple[str, str, list[str]]]:
    """
    @brief Every component page as (stem, display name, claimed requirement ids).
    @details Only two things are read out of the prose, both by strict
             pattern: the first `# ` heading for the name, and the requirement
             ids under `## Key behaviors`. The template calls those sections
             recommended rather than mandatory, so nothing load-bearing is
             parsed out of a page - a page missing its heading is still listed,
             under its file name. A caller providing on_error may report and
             skip unreadable pages; otherwise the existing error propagates.
    """
    components: list[tuple[str, str, list[str]]] = []
    for path in sorted((AGENTIC / "knowledge").glob("*.md")):
        try:
            text = read_text(path)
        except (UserError, OSError) as exc:
            if on_error is None:
                raise
            on_error(path, exc)
            continue
        heading = re.search(r"^# (.+)$", text, re.MULTILINE)
        name = heading.group(1).strip() if heading else path.stem
        claimed: list[str] = []
        for block in re.split(r"^## +", text, flags=re.MULTILINE)[1:]:
            title, _, body = block.partition("\n")
            if title.strip().lower() != "key behaviors":
                continue
            for rid in REQ_ID_SCAN_RE.findall(body):
                if rid not in claimed:
                    claimed.append(rid)
        components.append((path.stem, name, claimed))
    return components


def diagram_scope(args: argparse.Namespace,
                  components: list[tuple[str, str, list[str]]]) -> set[str] | None:
    """
    @brief The requirement ids the diagram is restricted to, or None for all.
    @raises UserError when both scopes are named at once, or when the named
            component or task does not exist, so an unknown scope reads as a
            mistake instead of an empty register.
    """
    if args.component and args.task:
        # one scope at a time: silently honoring one and dropping the other
        # would answer a question the operator did not ask
        raise UserError("--component and --task cannot be combined")
    if args.component:
        wanted = args.component.removesuffix(".md")
        for stem, name, claimed in components:
            if wanted in (stem, name):
                return set(claimed)
        known = ", ".join(stem for stem, _n, _c in components) or "none"
        raise UserError(f"no knowledge page for '{args.component}' (have: {known})")
    if args.task:
        _path, data = read_journal(args.task)
        return set(split_ids(data["header"].get("requirements", "")))
    return None


def render_diagram(records: list[tuple[str, Path, dict]],
                   components: list[tuple[str, str, list[str]]],
                   scope: set[str] | None) -> str:
    """
    @brief The coverage flowchart for `records`, grouped by claiming component.
    @details Left to right so the component groups sit side by side and each
             one stacks its own behaviors; every node carries the class its
             record earned. Requirements no page claims are grouped last
             rather than dropped, because an unclaimed behavior is exactly
             what a reader needs to see.
    """
    by_id = {str(data.get("id", "") or ""): data for _relpath, _path, data in records}
    in_scope = {rid: data for rid, data in by_id.items()
                if rid and (scope is None or rid in scope)}
    lines = ["flowchart LR"]
    grouped: set[str] = set()
    # ids must stay unique: Mermaid silently merges same-id subgraphs, so two
    # stems that sanitize alike (io-utils, io.utils) would share one group
    used_ids = {"unclaimed"}

    for stem, name, claimed in components:
        members = [rid for rid in claimed if rid in in_scope and rid not in grouped]
        if not members:
            continue
        grouped.update(members)
        sid = mermaid_id(stem)
        while sid in used_ids:
            sid += "_"
        used_ids.add(sid)
        lines.append(f'    subgraph {sid}["{mermaid_label(name)}"]')
        lines.append("        direction TB")
        for rid in members:
            label = mermaid_label(in_scope[rid].get("title", ""))
            lines.append(f'        {mermaid_id(rid)}["{rid}<br/>{label}"]'
                         f":::{coverage_class(in_scope[rid])}")
        lines.append("    end")

    loose = [rid for rid in sorted(in_scope) if rid not in grouped]
    if loose:
        lines.append('    subgraph unclaimed["(no knowledge page)"]')
        lines.append("        direction TB")
        for rid in loose:
            label = mermaid_label(in_scope[rid].get("title", ""))
            lines.append(f'        {mermaid_id(rid)}["{rid}<br/>{label}"]'
                         f":::{coverage_class(in_scope[rid])}")
        lines.append("    end")

    for name, fill, stroke in COVERAGE_CLASSES:
        lines.append(f"    classDef {name} fill:{fill},stroke:{stroke},color:#fff")
    return "\n".join(lines) + "\n"


def cmd_diagram(args: argparse.Namespace) -> int:
    """
    @brief Draw the requirement register as a Mermaid coverage flowchart.
    @details Derived entirely from records already in the repository, so it
             needs no model, no network and no renderer: the output is text
             that Git diffs and that Markdown viewers draw for themselves.
             `--out` writes the file as UTF-8 explicitly - printing it would
             leave the characters at the mercy of the console code page.
    """
    components = knowledge_components()
    scope = diagram_scope(args, components)
    records = scan_requirements(lambda *_a: None, lambda _p: False)
    text = render_diagram(records, components, scope)
    if not args.out:
        print(text, end="")
        return 0
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")
    print(f"diagram written to {rel(target)}")
    return 0


#: the folder order a traceability record is written in — first appearance in
#: CATEGORIES, which is the order `req` documents, so the export and the CLI
#: reference cannot drift apart.
TRACE_CATEGORIES = list(dict.fromkeys(
    folder for folder, _code in CATEGORIES.values()))

#: (CSV header, Markdown header) per column, in output order. The CSV name is
#: the requirement's own TOML key, so the file is self-describing against the
#: records it came from and diffs against them cleanly; the Markdown name is
#: the label a reviewer or an assessor reads.
TRACE_COLUMNS: tuple[tuple[str, str], ...] = (
    ("id", "Requirement ID"),
    ("category", "Category"),
    ("status", "Status"),
    ("coverage", "Coverage"),
    ("component", "Component"),
    ("title", "Title"),
    ("requirement", "Requirement"),
    ("verification", "Verification"),
    ("spec", "Spec"),
    ("test_count", "Tests"),
    ("linked_tests", "Verified By"),
    ("path_count", "Files"),
    ("affected_paths", "Implemented In"),
)


def flat(value: object) -> str:
    """@brief One record field as a single line, however TOML wrapped it."""
    return " ".join(str(value or "").split())


def trace_rows(records: list[tuple[str, Path, dict]],
               components: list[tuple[str, str, list[str]]]) -> list[dict]:
    """
    @brief One row per requirement, ordered by category and then by id.
    @details List columns stay lists here and are joined by each renderer,
             because the separator belongs to the format rather than to the
             record. Nothing is shortened anywhere in this path: `summary`
             and `brief` bound their values because they are resume views for
             a context-limited reader, whereas this is a durable artifact
             whose whole point is completeness, and a clipped path list reads
             as the whole list to the person it was written for.
             Every status is carried, draft and retired included — they are
             part of what the register holds, and dropping either would
             misreport it.
    """
    owner: dict[str, str] = {}
    for _stem, name, claimed in components:
        for rid in claimed:
            owner.setdefault(rid, name)

    rows: list[dict] = []
    for _relpath, path, data in records:
        rid = str(data.get("id", "") or "")
        placement = path.relative_to(AGENTIC / "requirements").parts
        category = placement[0] if len(placement) > 1 else "(no category)"
        tests = str_list(data.get("linked_tests"))
        paths = str_list(data.get("affected_paths"))
        rows.append({
            "id": rid,
            "category": category,
            "status": flat(data.get("status")),
            # never re-derived: `check` and the diagram read the same
            # classifier, so three readers of one record cannot disagree
            "coverage": coverage_class(data),
            "component": owner.get(rid, "(no knowledge page)"),
            "title": flat(data.get("title")),
            "requirement": flat(data.get("requirement")),
            "verification": flat(data.get("verification")),
            "spec": flat(data.get("spec")),
            "test_count": str(len(tests)),
            "linked_tests": tests,
            "path_count": str(len(paths)),
            "affected_paths": paths,
        })
    # Unknown or absent category folders sort last without hiding their rows.
    return sorted(rows, key=lambda row: (
        TRACE_CATEGORIES.index(row["category"])
        if row["category"] in TRACE_CATEGORIES else len(TRACE_CATEGORIES),
        row["id"]))


def trace_cell(row: dict, key: str, joiner: str) -> str:
    """@brief One column of one row, with list columns joined for the format."""
    value = row[key]
    return joiner.join(value) if isinstance(value, list) else str(value)


def render_trace_csv(rows: list[dict]) -> str:
    """
    @brief The traceability record as comma-separated values.
    @details Header row and data only — no summary block, no preamble, so a
             spreadsheet's autofilter and sort apply to the whole file. The
             standard-library writer owns the quoting rules, which is what
             keeps a statement holding a comma, a quote or a line break from
             silently becoming extra columns.
    """
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow([name for name, _label in TRACE_COLUMNS])
    for row in rows:
        writer.writerow([trace_cell(row, name, "; ")
                         for name, _label in TRACE_COLUMNS])
    return buffer.getvalue()


def trace_markdown_text(value: object) -> str:
    """
    @brief Literal, single-line cell text with no active inline Markdown.
    @details Entities preserve backslashes, table delimiters and markup as
             text; renderer-owned list breaks are inserted only afterwards.
    """
    return "".join(f"&#{ord(char)};" if char in "&<>\\`*_[]|~" else char
                   for char in flat(value))


def render_trace_md(rows: list[dict], unreadable: list[str]) -> str:
    """
    @brief The traceability record as a Markdown table under a summary block.
    @details Each scalar and list entry is flattened and escaped as literal
             text before list entries are joined with renderer-owned `<br>`
             breaks. User text cannot add table cells, HTML or inline markup.
    """
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["coverage"]] = counts.get(row["coverage"], 0) + 1
    by_category: dict[str, int] = {name: 0 for name in TRACE_CATEGORIES}
    for row in rows:
        by_category[row["category"]] = by_category.get(row["category"], 0) + 1
    # a folder outside the documented set is still counted where a reader can
    # see it: it is carried in the table and in the total, so leaving it out
    # of the breakdown would print a line that does not add up to its own total
    listed = TRACE_CATEGORIES + sorted(set(by_category) - set(TRACE_CATEGORIES))

    total = f"{len(rows)} requirement" + ("" if len(rows) == 1 else "s")
    if unreadable:
        total += f" — {len(unreadable)} file(s) unreadable and not listed"
    lines = [
        "# Requirements Traceability Matrix",
        "",
        total + " - " + ", ".join(
            f"{name} {counts.get(name, 0)}" for name, _f, _s in COVERAGE_CLASSES),
        "",
        # a category with nothing in it is still named: an empty security or
        # NFR register is a fact worth seeing, not an absence worth hiding
        "by category — " + ", ".join(
            f"{trace_markdown_text(name)} {by_category.get(name, 0)}" for name in listed),
        "",
        "| " + " | ".join(label for _name, label in TRACE_COLUMNS) + " |",
        "|" + "---|" * len(TRACE_COLUMNS),
    ]
    for row in rows:
        cells = ["<br>".join(trace_markdown_text(entry) for entry in row[name])
                 if isinstance(row[name], list) else trace_markdown_text(row[name])
                 for name, _label in TRACE_COLUMNS]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def cmd_trace(args: argparse.Namespace) -> int:
    """
    @brief Emit the requirement register as a flat traceability record.
    @details The third reader of the register, and the only one that leaves
             the repository: `diagram` groups it into a picture that stops
             being legible past a few dozen nodes, `explain` answers about one
             path, and this narrows nothing. Because it is handed on rather
             than read in place, it is also the only one owing an escaping and
             encoding contract.
             A requirement file that will not parse is named on stderr and
             omitted rather than dropped in silence — `check` is the authority
             on findings and already errors on that file, so this stays
             advisory, but an export that quietly under-reports is worse than
             one that admits the gap.
    """
    findings: dict[str, list[str]] = {}

    def note(level: str, _rule: str, relpath: str, message: str) -> None:
        if level == "ERROR":
            findings.setdefault(relpath, []).append(message)

    records = scan_requirements(note, lambda _p: False)
    listed = {relpath for relpath, _path, _data in records}
    unreadable = [path for path in findings if path not in listed]
    for path, messages in findings.items():
        label = ("listed with validation errors" if path in listed
                 else "not listed, does not parse")
        print(f"warning: {label}: {path}: {'; '.join(messages)}", file=sys.stderr)

    knowledge_errors: list[str] = []

    def knowledge_error(path: Path, error: Exception) -> None:
        """@brief Report missing ownership evidence without discarding rows."""
        knowledge_errors.append(rel(path))
        print(f"warning: knowledge page unavailable: {rel(path)}: {error}; "
              "component claims may be incomplete", file=sys.stderr)

    rows = trace_rows(records, knowledge_components(on_error=knowledge_error))
    if knowledge_errors:
        for row in rows:
            if row["component"] == "(no knowledge page)":
                row["component"] = "(knowledge incomplete)"

    if args.format == "csv":
        text = render_trace_csv(rows)
        encoding = "utf-8-sig"
    else:
        text = render_trace_md(rows, unreadable)
        encoding = "utf-8"

    if not args.out:
        print(text, end="")
        return 0
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    # the byte-order mark on the CSV is what stops a spreadsheet guessing the
    # system code page; the register already holds characters it guesses wrong
    target.write_text(text, encoding=encoding, newline="\n")
    print(f"trace written to {rel(target)}")
    return 0


#: the token an agent writes into the journal when it records a judgement call.
DEVIATION_TOKEN = "DEVIATION"
#: the token as a marker, not a mention: the standalone word, a stage this
#: workflow knows, and the `:` or ` - ` introducing the recorded text - which
#: is exactly the shape AGENTS.md prints and nothing else. The stage is what
#: does the work: any word at all is a shape ordinary prose reaches by
#: accident ("the DEVIATION policy: one line"), and so is no word at all, as
#: soon as a journal quotes the marker itself. Requiring a real stage also
#: rejects the literal `DEVIATION <stage>:` of the contract line, so a journal
#: explaining the rule does not report itself as having broken it.
DEVIATION_RE = re.compile(
    rf"(?<![\w-]){DEVIATION_TOKEN}[ \t]+"
    rf"(?=(?:{'|'.join(KNOWN_STAGES)})\b[ \t]*(?::|[ \t][-–—][ \t]))")


def recorded_deviations(text: str) -> list[str]:
    """
    @brief Every deviation a journal records, in the order it recorded them.
    @details Reads the whole journal rather than only its `## Log` section: a
             deviation filed under the wrong heading is still one the approver
             has to see, and a delivery report that quietly dropped it would
             be worse than no report. A bare line counts as much as a bullet,
             because that is the shape AGENTS.md prints. Wrapped lines are
             rejoined, so a deviation is carried whole rather than cut at the
             margin. Only the contract's own shape is harvested -
             `DEVIATION <stage>: ...` or its ` - ` spelling - never a sentence
             that merely mentions the word, and the token is stripped from
             what is returned, which is also what stops a second report from
             re-listing the first one's.
    """
    entries: list[str] = []
    current = ""
    for raw in text.replace("\r\n", "\n").split("\n"):
        stripped = raw.lstrip()
        if stripped.startswith("- "):
            entries.append(current)
            current = stripped[2:].strip()
        elif current and stripped and raw[:1].isspace():
            current += " " + stripped
        else:
            # a non-bullet line opens an entry of its own rather than being
            # dropped: the contract's own example is an unbulleted line, and
            # its indented continuations still join it through the branch above
            entries.append(current)
            current = stripped
    entries.append(current)
    found = []
    for entry in entries:
        match = DEVIATION_RE.search(entry)
        if match:
            found.append(" ".join(entry[match.end():].split()))
    return found


def repo_path_arg(value: str) -> str:
    """
    @brief One operator-supplied path as a repository-relative POSIX string.
    @raises UserError when the path resolves outside the repository.
    @details Takes whatever the shell handed over - native separators, an
             absolute path, a leading `./` - because an operator pastes what
             their terminal printed. Backslashes are translated on every
             platform, not only on Windows, so the same argument means the
             same thing in a Linux CI job as on the machine it was copied from.
    """
    raw = Path(value.strip().strip('"').replace("\\", "/"))
    if raw.is_absolute():
        try:
            raw = raw.resolve().relative_to(ROOT)
        except ValueError:
            raise UserError(f"{value} is outside this repository") from None
    text = raw.as_posix()
    if re.match(r"[A-Za-z]:", text):
        # a drive-letter path that did not read as absolute here - a POSIX
        # host, or a drive-relative `C:name` - is never inside this repo
        raise UserError(f"{value} is outside this repository")
    # normalize `.` and `..` segment by segment, so equivalent spellings of
    # one file match the same globs, and an escaping `..` is an error rather
    # than a string no requirement happens to cover
    parts: list[str] = []
    for part in text.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                raise UserError(f"{value} is outside this repository")
            parts.pop()
        else:
            parts.append(part)
    if not parts:
        raise UserError(f"{value} is outside this repository")
    return "/".join(parts)


def cmd_explain(args: argparse.Namespace) -> int:
    """
    @brief Report what governs one repository path, and what delivered it.
    @details The register is written once per behavior and read almost never,
             because nothing leads from a file back to it. This is that way
             round: path to requirements, grouped by the component claiming
             each, with how it is verified and the journals that carry it.
             A path no requirement covers is stated plainly - ungoverned code
             is a finding, not an empty answer.
    """
    target = repo_path_arg(args.path)
    layout = cfg_table(load_config(), "layout")
    area = file_area(target, str_list(layout.get("source")),
                     str_list(layout.get("tests")))
    records = scan_requirements(lambda *_a: None, lambda _p: False)

    owner: dict[str, str] = {}
    for _stem, name, claimed in knowledge_components():
        for rid in claimed:
            owner.setdefault(rid, name)

    matched: list[tuple[str, dict]] = []
    for _relpath, _path, data in records:
        rid = str(data.get("id", "") or "")
        if rid and match_any(target, str_list(data.get("affected_paths"))):
            matched.append((rid, data))

    exists = "" if (ROOT / target).exists() else "  (no longer in the tree)"
    print(f"{target}  [{area}]{exists}")
    if not matched:
        print("\nno requirement covers this path.")
        if area != "other":
            print("that is a finding: it sits inside the configured "
                  f"{area} globs, so something is expected to govern it.")
        return 0

    print(f"\ngoverned by {len(matched)} requirement(s):")
    groups: dict[str, list[tuple[str, dict]]] = {}
    for rid, data in matched:
        groups.setdefault(owner.get(rid, "(no knowledge page)"), []).append((rid, data))
    for name in sorted(groups, key=lambda n: (n == "(no knowledge page)", n)):
        print(f"\n  {name}")
        for rid, data in groups[name]:
            print(f"    {rid}  {data.get('status', '')!s:8} "
                  f"{coverage_class(data):9}  {data.get('title', '')}")
            method = " ".join(str(data.get("verification", "") or "").split())
            # ASCII: this output only ever reaches a console, and a console
            # under a legacy code page mangles anything else
            print(f"      verified by: {method[:76]}"
                  + ("..." if len(method) > 76 else ""))
            spec = str(data.get("spec", "") or "").strip()
            if spec:
                print(f"      spec: {spec}")

    ids = {rid for rid, _data in matched}
    listed = []
    for _relpath, data in scan_journals(lambda *_a: None, lambda _p: False,
                                        {str(d.get("id", "")) for _r, _p, d in records}):
        if ids.intersection(split_ids(data["header"].get("requirements", ""))):
            listed.append(data)
    if not listed:
        print("\nno task journal lists these requirements.")
        return 0
    print(f"\ndelivered by {len(listed)} task(s):")
    for data in listed:
        print(f"  {data['id']}  {data['header'].get('stage', '?'):9} "
              f"{data['header'].get('opened', '?')}  {data['title']}")
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """
    @brief Append the delivery summary section to a task journal.
    @details Gathers the journal state, the linked requirement titles, the
             diff shape versus the merge base and the check counts (scoped to
             this task). Append-only: repeated runs add dated sections and the
             journal keeps its history.
    """
    cfg = load_config()
    path, data = read_journal(args.task)
    header = data["header"]
    text = read_text(path)
    deviations = recorded_deviations(text)
    review_enabled, _max_fix_cycles = review_settings(cfg)
    if not review_enabled:
        review_line = "- explicit review: disabled; existing validation remains required"
    else:
        try:
            review_record, review_notice = bound_stage_report(
                text, header.get("stage", ""))
        except UserError:
            review_record, review_notice = {}, "malformed verdict evidence; read journal"
        if review_notice:
            review_line = f"- explicit review: enabled; evidence={review_notice}"
        else:
            review_line = (
                "- explicit review: enabled; "
                f"spec_compliance={review_record.get('spec_compliance') or 'not recorded'}; "
                "implementation_quality="
                f"{review_record.get('implementation_quality') or 'not recorded'}; "
                f"review_round={review_record.get('review_round') or 'not recorded'}")

    titles = {
        str(record.get("id", "")): str(record.get("title", ""))
        for _relpath, _p, record
        in scan_requirements(lambda *_a: None, lambda _p: False)
    }
    req_lines = [
        f"  - {rid} - {titles.get(rid, '(unknown requirement)')}"
        for rid in split_ids(header.get("requirements", ""))
    ]

    # the task's own starting commit when it recorded one: a report measured
    # from the branch's fork point counts every earlier commit as this task's
    # work, and a human approving the task reads that number
    base = str(header.get("base", "")).strip()
    basis = f"task base {base[:7]}" if base else "merge base"
    files, added, gaps, reason = collect_diff(cfg, base)
    diff_line = (f"unavailable ({reason})" if reason else
                 f"{len(files)} file(s) changed, {len(added)} line(s) added"
                 + (f"; {len(gaps)} file(s) not content-scanned" if gaps else ""))
    counts = {"ERROR": 0, "WARN": 0, "NOTE": 0}
    for level, _slug, _path, _message in run_checks(cfg, args.task):
        counts[level] += 1
    done = sum(1 for ticked, _item in data["checklist"] if ticked)
    unticked = [item for ticked, item in data["checklist"] if not ticked]

    lines = [
        "",
        f"## Delivery report ({today()})",
        "",
        (f"- stage: {header.get('stage', '?')}; type: {header.get('type', '?')};"
         f" path: {header.get('path', '?')}; branch: {header.get('branch', '?')}"),
        "- requirements:" if req_lines else "- requirements: none linked",
        *req_lines,
        # judgement before totals: a warning count says how much happened,
        # never which calls were made on the approver's behalf
        (f"- deviations: {len(deviations)} recorded" if deviations
         else "- deviations: none recorded"),
        *[f"  - {entry}" for entry in deviations],
        review_line,
        f"- diff vs {basis}: {diff_line}",
        (f"- checks: errors={counts['ERROR']} warnings={counts['WARN']}"
         f" notes={counts['NOTE']}"),
        f"- checklist: {done}/{len(data['checklist'])} done"
        + (f"; open: {'; '.join(unticked)}" if unticked else ""),
    ]
    if data["components"]:
        adopted = sum(1 for ticked, _item in data["components"] if ticked)
        open_comps = [item for ticked, item in data["components"] if not ticked]
        lines.append(f"- components: {adopted}/{len(data['components'])} adopted"
                     + (f"; open: {'; '.join(open_comps)}" if open_comps else ""))
    if not text.endswith("\n"):
        text += "\n"
    write_text(path, text + "\n".join(lines) + "\n")
    print(f"report appended to {rel(path)}")
    return 0


# entry point


def build_parser() -> argparse.ArgumentParser:
    """@brief The argparse tree for every implemented command."""
    parser = argparse.ArgumentParser(
        prog="aegis",
        description="AEGIS companion CLI - a scaffolder and a reporter.",
    )
    parser.add_argument("--version", action="version", version=f"aegis {VERSION}")
    subs = parser.add_subparsers(dest="command", required=True)

    init = subs.add_parser("init", help="finish installing the payload in this repo")
    init.add_argument("--git", action="store_true",
                      help="run git init when Git is installed but no repository exists")
    init.set_defaults(func=cmd_init)

    task = subs.add_parser("task", help="create a task journal")
    task.add_argument("title")
    task.add_argument("--type", choices=TASK_TYPES, default="feature")
    task.add_argument("--parent", help="optional visible top-level TASK-<id>")
    task.set_defaults(func=cmd_task)

    req = subs.add_parser("req", help="create a requirement file")
    req.add_argument("category", help=", ".join(sorted(CATEGORIES)))
    req.add_argument("title")
    req.set_defaults(func=cmd_req)

    anchor = subs.add_parser(
        "anchor", help="record Git-visible repository state for one task")
    anchor.add_argument("--task", required=True, help="TASK-<id> or <id>")
    anchor.add_argument("--json", action="store_true",
                        help="emit one JSON document on stdout")
    anchor.set_defaults(func=cmd_anchor)

    evolution = subs.add_parser(
        "evolution", help="compare repository state with a task anchor")
    evolution.add_argument("--task", required=True, help="TASK-<id> or <id>")
    evolution.add_argument("--json", action="store_true",
                           help="emit one JSON document on stdout")
    evolution.set_defaults(func=cmd_evolution)

    check = subs.add_parser(
        "check",
        help="run the heuristic check catalog (advisory: findings never fail it)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=CHECK_EPILOG,
    )
    check.add_argument("--task", help="scope the diff-based checks to this task")
    check.add_argument("--strict", action="store_true",
                       help="CI mode: exit 1 on errors and promoted warnings")
    check.add_argument("--run", action="store_true",
                       help="also execute the [commands] entries from aegis.toml")
    check.add_argument("--full", action="store_true",
                       help=f"print every finding (default caps at {FINDING_CAP};"
                            " --strict implies --full)")
    check.add_argument("--json", action="store_true",
                       help="emit one JSON document on stdout (always complete;"
                            " --run progress goes to stderr)")
    check.set_defaults(func=cmd_check)

    test = subs.add_parser(
        "test", help="run a configured command (default: test); exit mirrors it")
    test.add_argument("name", nargs="?", default="test",
                      help="a [commands] entry name (default: test)")
    test.add_argument("--impacted", action="store_true",
                      help="run only the tests linked to requirements the diff touches")
    test.add_argument("--base", default="",
                      help="diff against this revision instead of the merge base"
                           " (--base HEAD selects only uncommitted work)")
    test.add_argument("--task", help="append the result to this task journal's log")
    test.set_defaults(func=cmd_test)

    report = subs.add_parser(
        "report", help="append the delivery summary to a task journal")
    report.add_argument("task", help="TASK-<id> or <id>")
    report.set_defaults(func=cmd_report)

    summary = subs.add_parser(
        "summary", help="print a compact recorded stage summary (read-only)")
    summary.add_argument("task", help="TASK-<id> or <id>")
    summary.set_defaults(func=cmd_summary)

    brief = subs.add_parser("brief", help="print a bounded durable resume brief")
    brief.add_argument("task", help="TASK-<id> or <id>")
    brief.set_defaults(func=cmd_brief)

    diagram = subs.add_parser(
        "diagram", help="draw the requirement register as a Mermaid coverage map")
    # the one-scope-at-a-time conflict is judged in diagram_scope, not by an
    # argparse group, so it exits 1 with one line like every expected error
    diagram.add_argument("--component",
                         help="restrict to one knowledge page, by file stem or name")
    diagram.add_argument("--task", help="restrict to one journal's requirements")
    diagram.add_argument("--out", help="write UTF-8 to this path instead of stdout")
    diagram.set_defaults(func=cmd_diagram)

    trace = subs.add_parser(
        "trace", help="export the requirement register as a traceability matrix")
    trace.add_argument("--format", choices=("md", "csv"), default="md",
                       help="output format (default: md)")
    trace.add_argument("--out", help="write to this path instead of stdout")
    trace.set_defaults(func=cmd_trace)

    explain = subs.add_parser(
        "explain", help="show what governs one repository path")
    explain.add_argument("path", help="a repo-relative or absolute file or folder")
    explain.set_defaults(func=cmd_explain)

    status = subs.add_parser("status", help="list open task journals, or show one")
    status.add_argument("task", nargs="?", help="TASK-<id> or <id>")
    status.add_argument("--all", action="store_true",
                        help="include journals whose stage is done")
    status.add_argument("--json", action="store_true",
                        help="emit one JSON document on stdout (always complete)")
    status.set_defaults(func=cmd_status)
    return parser


def main(argv: list[str] | None = None) -> int:
    """@brief Parse arguments and dispatch; expected errors exit 1, no traceback."""
    for stream in (sys.stdout, sys.stderr):
        try:  # a title may hold characters the console encoding cannot render
            stream.reconfigure(errors="replace")
        except (AttributeError, OSError):  # pragma: no cover - non-tty streams
            pass
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except UserError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:  # I/O and encoding failures stay one-line too
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
