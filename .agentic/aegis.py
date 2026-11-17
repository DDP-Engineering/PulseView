#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 DDP Engineering
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""
The AEGIS companion CLI: a scaffolder and a reporter.

Single file, stdlib only, Python >= 3.11. Invoked as
`python .agentic/aegis.py <cmd>` from the repo root on Windows and
Linux alike; it locates its own `.agentic` directory from
`__file__`, never from the working directory. Commands exit 0 on
success and 1 with a one-line message on user error - no
tracebacks for expected failures.

The ownership split is law here: `requirements/`,
`specs/`, `tasks/` and `knowledge/` are user data and are only
ever created as empty folders; `context/` holds project-owned
Markdown scaffolds. Context files and `aegis.toml` are written only
when absent; root pointer files are appended to under a marker.
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

VERSION = "0.16.1"
SCHEMA = 1

AGENTIC = Path(__file__).resolve().parent
ROOT = AGENTIC.parent

DATA_DIRS = ("requirements", "specs", "tasks", "knowledge", "context")
CONTEXT_FILES = ("project.md", "environment.md")
POINTER_FILES = ("AGENTS.md", "assistant.md", "QWEN.md")
MARK_BEGIN = "<!-- AEGIS:BEGIN (managed by .agentic/aegis.py init) -->"
MARK_END = "<!-- AEGIS:END -->"
LEGACY_MARK_PAIRS = ((
    "<!-- AEGIS-LIGHT:BEGIN (managed by .agentic/aegis.py init) -->",
    "<!-- AEGIS-LIGHT:END -->",
),)
IGNORE_FILE = ".gitignore"
IGNORE_MARK_BEGIN = "# AEGIS:BEGIN (managed by .agentic/aegis.py init)"
IGNORE_MARK_END = "# AEGIS:END"
#: anchor/evolution sidecars are local evidence: the journal log line is the
#: durable record. They stay out of git unless `[records] commit_fingerprints`
#: is true.
FINGERPRINT_PATTERNS = (".agentic/tasks/*.anchor.json",
                        ".agentic/tasks/*.evolution.json")

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
# nothing (`command-timeout`) - never as a failed test.
# test = 5400
# lint = 120

[layout]
# Globs used by the traceability heuristics of `aegis check`.
source = ["src/"]
tests = ["tests/"]
docs = []  # documentation paths; still scanned for secrets, not source
# default_branch = "develop"            # the ref every diff is measured from
#
# Set this when the branch your work merges into is not the one AEGIS would
# find on its own. Without it the base is whatever `origin/HEAD` points at,
# then a local `master`, then a local `main`. It decides what `check`,
# `test --impacted` and `report` consider changed.

[interaction]
# false stops at every completed stage and presents the next choices.
# true flows between stages, but never bypasses publication approval.
autopilot = false

[review]
enabled = false
max_fix_cycles = 2

[diagrams]
# true has design draw Mermaid diagrams of the proposed implementation into
# .agentic/tasks/diagram_TASK-<id>.md for the human, shown at the design
# checkpoint. Missing, false, or any non-boolean value draws none, and no
# stage, review or check depends on a diagram.
enabled = false
# The diagrams design may draw: "structure", "sequence", "state". Missing or
# not a list means ["structure"]; a list with no known name draws none.
types = ["structure"]

[records]
# Anchor and evolution sidecars under .agentic/tasks/ are local evidence.
# false keeps them out of git through a managed block in .gitignore that
# init maintains; true removes that block so they are committed with the
# journal. The journal log line is the durable record either way.
commit_fingerprints = false

[context]
# Size budget in KB for .agentic/context/project.md, environment.md and each
# knowledge page. These pages are read at every frame, so edit sections in
# place instead of adding one per task; check reports a page above the
# budget as `context-size`. 0, or no page_kb at all, means no budget.
page_kb = 24

[zones]
# What each stage may write besides `.agentic/`, which every stage may
# always write. Values name the globs above: "source", "tests". A stage
# left out entirely may write anywhere - that is why build and validate are
# not listed. Advisory like everything else: check reports an edit
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

This repository uses AEGIS for changes that add or change a durable product
rule: logic, data, security, performance, integrations, or a product-wide UI
rule such as a theme, layout system, accessibility or interaction
convention. For those, read `.agentic/AGENTS.md` first; it routes you to one
step file per stage.

Make other changes directly, with no journal or requirement: a bug fix that
restores intended behavior, a local UI adjustment (one element's position,
spacing, wording or style), a refactor with no behavior change, or a test,
docs or tooling fix. A fix that contradicts an active requirement, adds
behavior, or touches security or data handling uses AEGIS. The user's
explicit choice wins; otherwise start with one line,
`LANE: direct|aegis - <why>`.

- New AEGIS work: run `python .agentic/aegis.py status` (an open task may
  cover it), then follow `.agentic/steps/1_frame.md`.
- An existing task: run `python .agentic/aegis.py brief TASK-<id>` and read
  what its `Read next` line names.

Stages: frame -> specify -> design -> build -> validate -> done; specify and
design have skip rules for work that does not need them. The CLI writes the
journal state:
`advance` finishes a stage, `pause` stops for the user, `log` and `ruling`
record events and decisions. End every session with `advance` or `pause`.

AEGIS guides and never blocks; `python .agentic/aegis.py check` is advisory.
Commits, pushes, merges, tickets, releases and packaging follow the
repository's own procedures, not AEGIS.

Say a deviation when you record one, as one line -
`DEVIATION <stage>: <what> - <why accepted, or what it costs>` - then carry on.
"""


class UserError(Exception):
    """An expected failure, reported as one line without a traceback."""


def today() -> str:
    """Today's date as YYYY-MM-DD."""
    # DTZ011 is suppressed below: the local calendar date is the intent. A
    # journal line dated in UTC would disagree with the human writing it on
    # either side of midnight.
    return _dt.date.today().isoformat()  # noqa: DTZ011


def utc_now() -> str:
    """Current UTC time as a stable ISO 8601 string."""
    return (_dt.datetime.now(_dt.timezone.utc).isoformat(timespec="microseconds")
            .replace("+00:00", "Z"))


def rel(path: Path) -> str:
    """Repo-relative path with forward slashes, for output and storage."""
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def generated_python_cache(path: str) -> bool:
    """Whether a repository path is generated Python bytecode."""
    parts = path.split("/")
    return "__pycache__" in parts or path.lower().endswith((".pyc", ".pyo"))


def read_text(path: Path) -> str:
    """
    Read UTF-8 text with newlines normalised to LF.

    A corrupt (non-UTF-8) artifact is a one-line user error, not a
    traceback - `check` must be able to report it like any other
    broken file.
    """
    try:
        return path.read_text(encoding="utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as exc:
        raise UserError(f"{rel(path)} is not valid UTF-8: {exc}") from None


def read_raw_text(path: Path) -> str:
    """Read UTF-8 text with its newlines untouched, for a file `init` edits in place."""
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            return handle.read()  # newline="" disables universal-newline translation
    except UnicodeDecodeError as exc:
        raise UserError(f"{rel(path)} is not valid UTF-8; save it as UTF-8 and "
                        f"run init again ({exc})") from None


def write_text(path: Path, text: str) -> None:
    """Write UTF-8 text (no BOM) with LF endings, creating parents."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_new(path: Path, text: str) -> None:
    """
    Create a file exclusively - a concurrent duplicate loses cleanly.

    `open("x")` is the collision backstop behind the id allocator:
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
    """Load a payload template, or fail with a one-line message."""
    path = AGENTIC / "templates" / name
    if not path.is_file():
        raise UserError(f"missing template: {rel(path)}")
    return read_text(path)


def run_git(*args: str) -> tuple[int, str] | None:
    """
    Run git in the repo root with captured output.

    Returns (returncode, stdout), or None when the git binary is
    missing or the call itself failed - callers degrade, never crash.

    Output is held in memory: a very large diff (generated or
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
    The checked-out commit, or "" when there is no history yet.

    Recorded in a task journal at creation so every later
    measurement of what the task changed has an exact starting
    point instead of guessing at the branch's fork point.
    """
    out = run_git("rev-parse", "HEAD")
    if out is None or out[0] != 0 or not out[1].strip():
        return ""
    return out[1].strip()


def git_branch() -> str:
    """
    Current git branch, or "unknown" when git is absent or fails.

    `branch --show-current`, not `rev-parse --abbrev-ref HEAD`: it
    also answers before the repository's first commit exists.
    """
    out = run_git("branch", "--show-current")
    if out is None or out[0] != 0 or not out[1].strip():
        return "unknown"
    return out[1].strip()


def load_config() -> dict:
    """Parse `.agentic/aegis.toml`; empty dict when it does not exist."""
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
    One top-level config table, tolerating a wrongly typed value.

    `commands = "text"` is valid TOML but not a table; treating it
    as an empty table keeps every caller on the one-line error
    contract instead of raising AttributeError.
    """
    value = cfg.get(name)
    return value if isinstance(value, dict) else {}


def review_settings(cfg: dict) -> tuple[bool, int]:
    """Return fail-safe explicit-review enablement and fix-cycle bound."""
    table = cfg_table(cfg, "review")
    raw_enabled = table.get("enabled", False)
    enabled = raw_enabled if isinstance(raw_enabled, bool) else False
    raw_cycles = table.get("max_fix_cycles", DEFAULT_MAX_FIX_CYCLES)
    cycles = (raw_cycles if isinstance(raw_cycles, int)
              and not isinstance(raw_cycles, bool)
              and 0 <= raw_cycles <= MAX_FIX_CYCLES_LIMIT else 0)
    return enabled, cycles


def autopilot_enabled(cfg: dict) -> bool:
    """Return fail-safe configured autopilot enablement."""
    raw = cfg_table(cfg, "interaction").get("autopilot", False)
    return raw if isinstance(raw, bool) else False


def commit_fingerprints(cfg: dict) -> bool:
    """Whether anchor/evolution sidecars are committed; fail-safe false."""
    raw = cfg_table(cfg, "records").get("commit_fingerprints", False)
    return raw if isinstance(raw, bool) else False


def interaction_mode(cfg: dict, header: dict | None = None) -> str:
    """
    Resolve the durable task mode, then the repository default.

    cfg: Parsed AEGIS configuration.
    header: Optional task-journal header.
    Returns: `checkpoint` or `autopilot`.
    """
    recorded = str((header or {}).get("interaction", "")).strip().lower()
    if recorded in INTERACTION_MODES:
        return recorded
    return "autopilot" if autopilot_enabled(cfg) else "checkpoint"


def toml_string(value: str) -> str:
    """Quote a value as a TOML basic string."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def new_id(taken: set[str]) -> str:
    """A fresh 8-hex-char CSPRNG id not present in `taken`."""
    for _ in range(200):
        candidate = secrets.token_hex(4)
        if candidate not in taken:
            return candidate
    raise UserError("could not allocate a free 8-hex id after 200 attempts")


def taken_ids(folder: str, pattern: str) -> set[str]:
    """The id suffixes of every artifact matching `pattern` under `folder`."""
    return {
        path.stem.rsplit("-", 1)[-1].lower()
        for path in (AGENTIC / folder).glob(pattern)
    }


TITLE_RE = re.compile(
    r"^#[ \t]+(TASK-[0-9A-Za-z]{4,12})[ \t]*(?:—|-{1,2})[ \t]*(.*?)[ \t]*$", re.MULTILINE
)
HEADER_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_]*):[ \t]*(.*?)[ \t]*$")
CHECK_RE = re.compile(r"^\s*-\s*\[([ xX])\]\s*(.*?)\s*$")


def parse_journal(text: str) -> dict:
    """
    Parse a task journal into id, title, header, checklist and log.

    Plain regex over `key: value` lines - no YAML. The header is the
    run of key/value lines that follows the `# TASK-<id> - <title>`
    heading; it ends at the first blank line after it starts or at
    the first line that is not a key/value pair. A repeated key keeps
    its first written value - an empty template line never hides one,
    and `header_with` rewrites the first line - and is listed under
    `repeated`.
    """
    lines = text.replace("\r\n", "\n").split("\n")
    result: dict = {"id": "", "title": "", "header": {}, "repeated": [], "checklist": [],
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
        key = match.group(1).lower()
        if key in result["header"]:
            if key not in result["repeated"]:
                result["repeated"].append(key)
            if result["header"][key]:
                continue
        result["header"][key] = match.group(2)

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
    Locate and parse one journal by id, with or without the prefix.

    The id is validated as pure hex before it touches the
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
    """Return readable child journals visible in this checkout, sorted."""
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


def state_path(journal: Path, kind: str) -> Path:
    """The task-owned anchor or evolution sidecar path."""
    return journal.with_suffix(f".{kind}.json")


def read_json_file(path: Path, label: str) -> dict:
    """Read one UTF-8 JSON object or raise a concise user error."""
    try:
        value = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        raise UserError(f"{rel(path)} is not valid JSON: {exc}") from None
    if not isinstance(value, dict):
        raise UserError(f"{rel(path)} {label} must be a JSON object")
    return value


def write_json_file(path: Path, value: dict) -> None:
    """Atomically write deterministic UTF-8/LF JSON."""
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
    Git-visible paths, excluding AEGIS state and Python bytecode caches.

    `--exclude-standard` honors every normal ignore source. NUL
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
    A stable content identity for a regular file, symlink, or submodule.

    Regular files stream through SHA-256. Symlinks hash their link
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
            # without its own `.git`, `git -C` would answer for the repository
            # above; an uninitialised submodule is the commit the index records
            if (path / ".git").exists():
                head = run_git("-C", name, "rev-parse", "HEAD")
                commit = head[1].strip() if head and head[0] == 0 else ""
            else:
                entry = run_git("ls-files", "--stage", "--", name)
                fields = entry[1].split() if entry and entry[0] == 0 else []
                commit = fields[1] if fields[:1] == ["160000"] else ""
            if commit:
                return {"kind": "submodule", "commit": commit}
            raise UserError(f"cannot fingerprint repository directory entry: {name}")
        if not path.exists():
            return None
        raise UserError(f"cannot fingerprint non-file repository entry: {name}")
    except UserError:
        raise
    except OSError as exc:
        raise UserError(f"cannot fingerprint {name}: {exc}") from None


def repository_manifest() -> dict[str, dict]:
    """Current Git-visible repository content map."""
    files: dict[str, dict] = {}
    for name in visible_repo_paths():
        value = fingerprint(ROOT / name, name)
        if value is not None:
            files[name] = value
    return files


def file_area(path: str, source_globs: list[str], test_globs: list[str]) -> str:
    """Categorize one repository path from the anchor's layout."""
    if match_any(path, test_globs):
        return "tests"
    if match_any(path, source_globs):
        return "source"
    return "other"


def valid_utc(value: object) -> bool:
    """Whether a value is the UTC timestamp form emitted by AEGIS."""
    return isinstance(value, str) and bool(re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z", value
    ))


def valid_fingerprint(value: object) -> bool:
    """Whether a value is a closed schema-1 repository identity."""
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
    """Validate the closed anchor schema used by evolution and check."""
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
    """Validate the compact evolution-history envelope."""
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
    """Existing compact history, or a new empty envelope."""
    if not path.is_file():
        return {"schema": 1, "task": task, "reports": []}
    return validate_history(read_json_file(path, "evolution"), task, path)


def cmd_anchor(args: argparse.Namespace) -> int:
    """Record the current Git-visible repository content for one task."""
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
    """Changed entries and aggregate counts for one anchor comparison."""
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
    """Compare the repository with its active task anchor and save it."""
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
        displayed = ([{key: item[key] for key in ("path", "status", "area")}
                      for item in changes] if args.compact else changes)
        emit_json({
            "command": "evolution", "task": task,
            "file": rel(history_file), "anchor_id": anchor["anchor_id"],
            "evolved_at": evolved, "counts": counts, "changes": displayed,
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


def write_pointer(name: str) -> str:
    """
    Create or update one root pointer file, never clobbering content.

    An existing file keeps every byte outside the marker pair -
    including its newline style: a CRLF file stays CRLF. The managed
    block is appended when absent and replaced exactly between the
    markers when present. Returns a one-word outcome for the report.
    """
    path = ROOT / name
    block = f"{MARK_BEGIN}\n\n{POINTER_DIGEST}\n{MARK_END}\n"
    if not path.exists():
        write_text(path, f"# {name}\n\n{block}")
        return "created"

    raw = read_raw_text(path)
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


def tracked_fingerprints() -> list[str] | None:
    """Sidecar paths git tracks, or None when git cannot answer."""
    out = run_git("ls-files", "-z", "--", *FINGERPRINT_PATTERNS)
    if out is None or out[0] != 0:
        return None
    return sorted(name for name in out[1].split("\0") if name)


def write_ignore_block(commit: bool) -> str:
    """
    Maintain the managed fingerprint block in the root `.gitignore`.

    `commit` false ensures the block is present, creating the file
    when absent; true removes the block and creates nothing. Every
    byte outside the marker pair is preserved, newline style
    included. Returns a one-word outcome for the init report.
    """
    path = ROOT / IGNORE_FILE
    block = "\n".join((IGNORE_MARK_BEGIN, *FINGERPRINT_PATTERNS,
                       IGNORE_MARK_END)) + "\n"
    if not path.exists():
        if commit:
            return "absent"
        write_text(path, block)
        return "created"

    raw = read_raw_text(path)
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")

    spans: list[tuple[int, int]] = []
    cursor = 0
    while (begin := text.find(IGNORE_MARK_BEGIN, cursor)) >= 0:
        end = text.find(IGNORE_MARK_END, begin + len(IGNORE_MARK_BEGIN))
        if end < 0:
            break
        stop = end + len(IGNORE_MARK_END)
        if text[stop : stop + 1] == "\n":
            stop += 1
        spans.append((begin, stop))
        cursor = stop

    if commit:
        if not spans:
            return "unchanged"
        parts, cursor = [], 0
        for begin, stop in spans:
            parts.append(text[cursor:begin])
            cursor = stop
        parts.append(text[cursor:])
        out, outcome = "".join(parts), "removed"
    elif spans:
        begin, stop = spans[0]
        if len(spans) == 1 and text[begin:stop] == block:
            return "unchanged"
        parts, cursor = [text[:begin], block], stop
        for duplicate_begin, duplicate_stop in spans[1:]:
            parts.append(text[cursor:duplicate_begin])
            cursor = duplicate_stop
        parts.append(text[cursor:])
        out, outcome = "".join(parts), "refreshed"
    else:
        separator = "" if text.endswith("\n") or not text else "\n"
        out, outcome = text + separator + block, "appended"

    if crlf:
        out = out.replace("\n", "\r\n")
    path.write_text(out, encoding="utf-8", newline="")
    return outcome


def cmd_init(args: argparse.Namespace) -> int:
    """Finishing step after the payload was copied into a repo."""
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

    for name in CONTEXT_FILES:
        path = AGENTIC / "context" / name
        if path.exists() or path.is_symlink():
            print(f"  {'context/' + name:<24} kept (yours)")
        else:
            content = scaffold_template(name)
            try:
                with path.open("x", encoding="utf-8", newline="\n") as handle:
                    handle.write(content)
            except FileExistsError:
                print(f"  {'context/' + name:<24} kept (yours)")
            else:
                print(f"  {'context/' + name:<24} created (fill from current evidence)")

    config = AGENTIC / "aegis.toml"
    if config.is_file():
        schema = load_config().get("schema", "?")
        print(f"  {'.agentic/aegis.toml':<24} kept (yours; schema {schema})")
    else:
        write_text(config, DEFAULT_CONFIG)
        print(f"  {'.agentic/aegis.toml':<24} created")

    for name in POINTER_FILES:
        print(f"  {name:<16} {write_pointer(name)}")

    commit = commit_fingerprints(load_config())
    print(f"  {IGNORE_FILE:<16} {write_ignore_block(commit)}"
          + ("" if commit else " (anchor/evolution sidecars stay local)"))

    if not git_available:
        print("  git              unavailable; diff, impacted, anchor, and evolution "
              "evidence disabled")
        print("Next: install Git, then rerun python .agentic/aegis.py init")
        return 0

    probe = run_git("rev-parse", "--git-dir")
    if probe and probe[0] == 0:
        print(f"  {'git':<16} repository ready ({git_version[1].strip()})")
        tracked = [] if commit else (tracked_fingerprints() or [])
        if tracked:
            print(f"  {'fingerprints':<16} {len(tracked)} sidecar(s) still tracked; "
                  "AEGIS runs no git write - untrack them yourself with:")
            print("    git rm --cached -- "
                  + " ".join(f"'{pattern}'" for pattern in FINGERPRINT_PATTERNS))
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


#: the payload license block that opens a Markdown or TOML template; records
#: generated from a template belong to the project and do not carry it.
LICENSE_PROLOGUE_RE = re.compile(
    r"\A(?:<!--[^\n]*\n(?:[^\n]*\n)*?[^\n]*SPDX-License-Identifier[^\n]*\n-->\n"
    r"|(?:#[^\n]*\n)*?#[^\n]*SPDX-License-Identifier[^\n]*\n)")


def scaffold_template(name: str) -> str:
    """A new project record from a template: no license block, no authoring notes."""
    text = LICENSE_PROLOGUE_RE.sub("", template(name), count=1)
    text = re.sub(
        r"^<!-- AEGIS:TEMPLATE\n.*?^-->\n|"
        r"^# AEGIS:TEMPLATE-BEGIN\n.*?^# AEGIS:TEMPLATE-END\n",
        "", text, flags=re.MULTILINE | re.DOTALL)
    return text.lstrip("\n")


def cmd_task(args: argparse.Namespace) -> int:
    """Scaffold a task journal from .agentic/templates/task.md."""
    title = one_line(args.title)  # a line break would continue into the header
    if not title:
        raise UserError("task title must not be empty")
    if re.fullmatch(r"TASK-[0-9A-Fa-f]{4,12}", title):
        # a bare ID is a resume attempt, never the title of new work
        raise UserError(f"'task' creates a new journal from a title; resume {title.upper()} "
                        f"with: python .agentic/aegis.py brief {title.upper()}")

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
    mode = interaction_mode(load_config())

    text = scaffold_template("task.md")
    text = TITLE_RE.sub(lambda _m: f"# {task_id} - {title}", text, count=1)
    text = re.sub(r"^type: .*$", f"type: {args.type}", text, count=1, flags=re.MULTILINE)
    text = re.sub(r"^interaction: .*$", f"interaction: {mode}", text, count=1,
                  flags=re.MULTILINE)
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
    stage = "survey" if args.type == "adopt" else "frame"
    text = re.sub(r"^- \d{4}-\d{2}-\d{2} frame:", f"- {stamp} {stage}:", text, count=1,
                  flags=re.MULTILINE)

    path = tasks / f"{task_id}.md"
    if stage != "frame":
        text = header_with(text, "stage", stage)
    checklist = step_checklist("adopt.md") if stage == "survey" else done_when(stage)
    if checklist:
        text = section_with(text, "Done checklist", checklist)
    text = state_with(text, {
        "status": "working", "reported": f"{stage} - in_progress",
        "next": ("complete the Frame card and choose the path" if stage == "frame"
                 else "survey the repository components"),
        "must_read": must_read(path, stage), **review_fields({}, load_config())})
    write_new(path, text)
    print(rel(path))
    return 0


def cmd_req(args: argparse.Namespace) -> int:
    """Scaffold a requirement from templates/requirement.toml."""
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

    text = scaffold_template("requirement.toml")
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


def cmd_status(args: argparse.Namespace) -> int:
    """List task journals, or show one task's state in detail."""
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
    print("Resume one with: python .agentic/aegis.py brief TASK-<id>")
    return 0


def status_one(task_id: str, as_json: bool = False) -> int:
    """Show one journal's header, checklist state and last log lines."""
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
    try:
        record, notice = journal_state(read_text(path), stage)
    except UserError as error:
        record, notice = {}, f"unreadable: {error}"
    if notice:
        print(f"\nstate: {notice}")
    else:
        print(f"\nstate: {record.get('status') or 'not recorded'} "
              f"(reported {record['stage']} - {record.get('result') or 'not recorded'})")
        if record.get("next"):
            print(f"  next: {record['next']}")
    step = STAGE_STEP_FILES.get(stage)
    if stage == "done":
        print("\nthis task is done - nothing to resume")
    elif step:
        print(f"\nnext: open .agentic/steps/{step} (stage '{stage}'), "
              "continue at the first unticked item")
    else:
        print(f"\nnext: unknown stage '{stage}' - fix the journal header first")
    return 0


STAGE_REPORT_FIELDS = ("stage", "result", "current", "changed", "evidence",
                       "issues", "next", "needs_user", "spec_compliance",
                       "implementation_quality", "review_round")
STAGE_REPORT_RESULTS = ("in_progress", "completed", "paused", "blocked", "skipped")
REVIEW_VERDICTS = ("approved", "changes_required", "disabled")
INTERACTION_MODES = ("checkpoint", "autopilot")
HANDOFF_FIELDS = ("current", "status", "next", "must_read", "blockers")
HANDOFF_STATUSES = ("ready", "waiting", "blocked")
RULING_KEYS = ("date", "decision", "reason", "source", "supersedes")
RULING_SOURCES = ("user", "repository", "requirement", "technical")
DEFAULT_MAX_FIX_CYCLES = 2
#: the largest accepted `[review] max_fix_cycles`; total rounds are one more.
MAX_FIX_CYCLES_LIMIT = 255
MAX_REVIEW_ROUNDS = 1 + MAX_FIX_CYCLES_LIMIT
SUMMARY_VALUE_LIMIT = 240
BRIEF_VALUE_LIMIT = 240
BRIEF_RULING_LIMIT = 8
BRIEF_CHILD_LIMIT = 20
RULING_DIAGNOSTIC_LIMIT = 20
# Match a complete inline code span before interpreting a comment opener.
INLINE_CODE_OR_COMMENT_RE = re.compile(
    r"(?<!`)(`+)(?!`)(.*?)(?<!`)\1(?!`)|<!--")


def live_markdown_lines(text: str) -> list[str]:
    """Return visible Markdown lines, excluding fences and comments."""
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
    """Parse valid Rulings in journal order plus bounded diagnostics."""
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
    """Return valid ruling records not superseded by a later record."""
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
    """Read one optional strict Handoff field section."""
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
            raise UserError("unknown Handoff field; see .agentic/templates/task.md")
        if key in fields:
            raise UserError(f"duplicate Handoff field: {key}")
        if key == "current" and value and value not in KNOWN_STAGES:
            raise UserError("invalid Handoff current stage")
        if key == "status" and value and value not in HANDOFF_STATUSES:
            raise UserError("invalid Handoff status")
        fields[key] = value
    return fields


def parse_stage_report(text: str) -> dict[str, str]:
    """Read one optional plain-field Stage report; reject ambiguity.

    Empty scaffold fields are valid. This parser deliberately does
    not alter the legacy journal parser or its status JSON schema.

    Raises UserError: An unknown, duplicate or malformed field/section.
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
            raise UserError("unknown Stage report field; see .agentic/templates/task.md")
        if key in fields:
            raise UserError(f"duplicate Stage report field: {key}")
        allowed = (KNOWN_STAGES if key in {"stage", "current"} else
                   STAGE_REPORT_RESULTS if key == "result" else
                   REVIEW_VERDICTS if key in {
                       "spec_compliance", "implementation_quality"} else None)
        if value and allowed is not None and value not in allowed:
            raise UserError(f"invalid Stage report {key}; expected {', '.join(allowed)}")
        if key == "review_round" and value and (
                not value.isdecimal() or not 1 <= int(value) <= MAX_REVIEW_ROUNDS):
            raise UserError("invalid Stage report review_round; expected 1 through "
                            f"{MAX_REVIEW_ROUNDS}")
        fields[key] = value
    return fields


def bound_stage_report(text: str, current: str) -> tuple[dict[str, str], str]:
    """Parse the current Stage report or return a freshness notice."""
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
    """Make one bounded printable line, explicitly marking any omission."""
    clean = " ".join("".join(char if char.isprintable() else " "
                             for char in value).split()) or "not recorded"
    if len(clean) <= SUMMARY_VALUE_LIMIT:
        return clean, False
    suffix = " ... [truncated; read journal]"
    return clean[:SUMMARY_VALUE_LIMIT - len(suffix)] + suffix, True


#: the `## State` fields, in the order the CLI writes them.
STATE_FIELDS = ("status", "reported", "next", "must_read", "changed", "evidence",
                "issues", "spec_compliance", "implementation_quality", "review_round")
#: working: a stage is in progress; waiting/blocked: the user is needed;
#: ready: the next stage can start; done: implementation guidance is complete.
STATE_STATUSES = ("working", "waiting", "blocked", "ready", "done")
#: the stages every task walks; specify and design may be recorded as skipped.
#: deliver is a legacy stage that closes to done.
WORK_STAGES = ("frame", "specify", "design", "build", "validate", "done")
ADOPT_STAGES = ("survey", "components", "close", "done")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def one_line(value: str | None) -> str:
    """Collapse a command-line value to one printable line for a record field."""
    return " ".join("".join(char if char.isprintable() else " "
                            for char in (value or "")).split())


def section_bounds(text: str, name: str) -> tuple[int, int] | None:
    """
    Line span of the body of the first `## <name>...` section.

    Headings inside fenced blocks are content, not structure. The span
    runs from the line after the heading to the next level-two heading
    or the end of the text.

    Returns: (first body line, end line) indexes into `text.split("\\n")`, or None.
    """
    lines = text.split("\n")
    fence = ""
    start = None
    for index, line in enumerate(lines):
        opening = FENCE_RE.match(line)
        if fence:
            if opening and opening.group(1)[0] == fence[0] and len(opening.group(1)) >= len(fence):
                fence = ""
            continue
        if opening:
            fence = opening.group(1)
            continue
        if line.startswith("## "):
            if start is not None:
                return start, index
            heading, wanted = line[3:].strip().lower(), name.lower()
            if heading == wanted or heading.startswith(wanted + " "):
                start = index + 1
    return (start, len(lines)) if start is not None else None


def section_with(text: str, name: str, body: str) -> str:
    """Replace a section's body, or append the section when it is missing."""
    span = section_bounds(text, name)
    if span is None:
        return text.rstrip("\n") + f"\n\n## {name}\n\n{body.rstrip()}\n"
    lines = text.split("\n")
    start, end = span
    updated = lines[:start] + [""] + body.rstrip().split("\n")
    if end < len(lines):
        updated += [""] + lines[end:]
    result = "\n".join(updated)
    return result if result.endswith("\n") else result + "\n"


def lines_appended(text: str, span: tuple[int, int], line: str) -> str:
    """Insert `line` after the last non-blank line of a section body."""
    lines = text.split("\n")
    start, end = span
    last = end
    while last > start and not lines[last - 1].strip():
        last -= 1
    insert = [line] if last > start else ["", line]
    return "\n".join(lines[:last] + insert + lines[last:])


def section_without(text: str, name: str) -> str:
    """Remove a section, heading included; absent sections leave text unchanged."""
    span = section_bounds(text, name)
    if span is None:
        return text
    lines = text.split("\n")
    start, end = span
    return "\n".join(lines[:start - 1] + lines[end:]).rstrip("\n") + "\n"


def log_with(text: str, message: str) -> str:
    """Append one dated line at the end of the Log section, keeping older lines."""
    line = f"- {today()} {message}"
    span = section_bounds(text, "log")
    return section_with(text, "Log", line) if span is None else lines_appended(text, span, line)


def header_with(text: str, key: str, value: str) -> str:
    """
    Set one journal header line, or add it at the end of the header block.

    The header is read as parse_journal reads it - the key/value lines
    under the title, up to the first blank line - so a same-named
    field in a later section is never touched.
    """
    entry = f"{key}: {value}".rstrip()
    lines = text.split("\n")
    title = next((index for index, line in enumerate(lines) if TITLE_RE.match(line)), None)
    if title is None:
        raise UserError("journal has no '# TASK-<id> - <title>' heading")
    end = None
    for index in range(title + 1, len(lines)):
        line = lines[index]
        if not line.strip():
            if end is not None:
                break
            continue
        match = HEADER_RE.match(line)
        if not match:
            break
        if match.group(1).lower() == key.lower():
            lines[index] = entry
            return "\n".join(lines)
        end = index + 1
    if end is None:  # no header yet: start one under the title
        lines[title + 1:title + 1] = ["", entry]
    else:
        lines[end:end] = [entry]
    return "\n".join(lines)


def has_section(text: str, name: str) -> bool:
    """Whether a live (unfenced, uncommented) `## <name>` heading exists."""
    return any(line.startswith("## ") and line[3:].strip().lower() == name
               for line in live_markdown_lines(text))


def parse_state(text: str) -> dict[str, str]:
    """
    Read the CLI-written `## State` fields; reject ambiguity or invalid values.

    Raises UserError: An unknown, duplicate or malformed field or section.
    """
    fields: dict[str, str] = {}
    active = seen = False
    for line in live_markdown_lines(text):
        if line.startswith("## "):
            active = line[3:].strip().lower() == "state"
            if active:
                if seen:
                    raise UserError("duplicate State section")
                seen = True
            continue
        if not active or not line.strip():
            continue
        match = HEADER_RE.fullmatch(line)
        if not match:
            raise UserError("State requires one 'key: value' per line")
        key, value = match.group(1).lower(), match.group(2).strip()
        if key not in STATE_FIELDS:
            raise UserError("unknown State field; write State with aegis.py pause or advance")
        if key in fields:
            raise UserError(f"duplicate State field: {key}")
        if key == "status" and value and value not in STATE_STATUSES:
            raise UserError(f"invalid State status; expected {', '.join(STATE_STATUSES)}")
        if key == "reported" and value:
            stage, separator, result = value.partition(" - ")
            if not separator or stage not in KNOWN_STAGES or result not in STAGE_REPORT_RESULTS:
                raise UserError("invalid State reported; expected '<stage> - <result>'")
        if key in {"spec_compliance", "implementation_quality"} and value \
                and value not in REVIEW_VERDICTS:
            raise UserError(f"invalid State {key}; expected {', '.join(REVIEW_VERDICTS)}")
        if key == "review_round" and value and (
                not value.isdecimal() or not 1 <= int(value) <= MAX_REVIEW_ROUNDS):
            raise UserError(f"invalid State review_round; expected 1 through {MAX_REVIEW_ROUNDS}")
        fields[key] = value
    return fields


def stored_state(text: str) -> dict[str, str]:
    """Recorded state fields from `## State` or the legacy sections; {} when unreadable."""
    try:
        if has_section(text, "state"):
            return parse_state(text)
        report, handoff = parse_stage_report(text), parse_handoff(text)
    except UserError:
        return {}
    issues = "; ".join(dict.fromkeys(value for value in (report.get("issues", ""),
                                                         handoff.get("blockers", "")) if value))
    reported = (f"{report['stage']} - {report['result']}"
                if report.get("stage") and report.get("result") else "")
    return {"status": handoff.get("status", ""), "reported": reported,
            "next": report.get("next") or handoff.get("next", ""),
            "must_read": handoff.get("must_read", ""), "changed": report.get("changed", ""),
            "evidence": report.get("evidence", ""), "issues": issues,
            **{key: report.get(key, "") for key in
               ("spec_compliance", "implementation_quality", "review_round")}}


def journal_state(text: str, current: str) -> tuple[dict[str, str], str]:
    """
    The journal's current state in Stage-report terms, from either format.

    A `## State` block is authoritative; a journal without one is read
    from its legacy Handoff and Stage report. `needs_user` derives from
    the status, so it is never recorded twice.

    Returns: (record, notice): a missing, incomplete or stale state yields an empty
    record and a notice that tells the reader to refresh it.
    Raises UserError: A malformed State, Handoff or Stage report.
    """
    if not has_section(text, "state"):
        record, notice = bound_stage_report(text, current)
        if notice:
            return {}, notice
        handoff = parse_handoff(text)
        return {**record, "status": handoff.get("status", ""),
                "must_read": handoff.get("must_read", "")}, ""
    state = parse_state(text)
    if not any(state.values()):
        return {}, "state not recorded; read journal"
    stage, _separator, result = state.get("reported", "").partition(" - ")
    if not stage or not state.get("status"):
        return {}, "incomplete state; refresh it with aegis.py pause or advance"
    if stage != current and state["status"] not in {"ready", "done"}:
        return {}, "stale state: current stage changed; refresh it with aegis.py pause or advance"
    return {"stage": stage, "result": result, "current": current, "status": state["status"],
            "needs_user": "yes" if state["status"] in {"waiting", "blocked"} else "no",
            **{key: state.get(key, "") for key in STATE_FIELDS
               if key not in {"status", "reported"}}}, ""


def state_with(text: str, state: dict[str, str]) -> str:
    """Write the State block and retire legacy Handoff and Stage report sections."""
    for legacy in ("handoff", "stage report"):
        text = section_without(text, legacy)
    body = "\n".join(f"{key}: {state.get(key, '')}".rstrip() for key in STATE_FIELDS)
    return section_with(text, "State", body)


def review_fields(previous: dict[str, str], cfg: dict, clear: bool = False) -> dict[str, str]:
    """Review fields from the configuration and the previous state.

    clear: Blank both verdicts while keeping the consumed round, as a
          changed candidate requires.
    """
    enabled, _cycles = review_settings(cfg)
    if not enabled:
        return {"spec_compliance": "disabled", "implementation_quality": "disabled",
                "review_round": ""}
    keep = {key: "" if clear or previous.get(key) == "disabled" else previous.get(key, "")
            for key in ("spec_compliance", "implementation_quality")}
    return {**keep, "review_round": previous.get("review_round", "")}


def must_read(path: Path, stage: str, extra: list[str] | None = None) -> str:
    """The journal, the stage's step file and any named repository paths."""
    items = [rel(path)]
    step = STAGE_STEP_FILES.get(stage)
    if step:
        items.append(f".agentic/steps/{step}")
    for entry in extra or []:
        for part in entry.split(","):
            value = part.strip().replace("\\", "/")
            if not value:
                continue
            if not repo_relative_ok(value):
                raise UserError(f"must-read path must stay inside the repository: {value}")
            if value not in items:
                items.append(value)
    return ", ".join(items)


def step_checklist(step: str) -> str | None:
    """A step file's 'Done when' list; None when the file or the list is missing."""
    path = AGENTIC / "steps" / step
    if not path.is_file():
        return None
    text = read_text(path)
    if "**Done when:**" not in text:
        return None
    body = text.split("**Done when:**", 1)[1]
    body = re.split(r"^\*\*[^*\n]+:\*\*", body, maxsplit=1, flags=re.MULTILINE)[0]
    return body.strip() or None


def done_when(stage: str) -> str | None:
    """The checklist for entering `stage`; adoption phases share one list."""
    step = STAGE_STEP_FILES.get(stage)
    if not step or stage in ADOPT_STAGES:
        return None
    return step_checklist(step)


def stage_order(stage: str) -> tuple[str, ...]:
    """The stage sequence that contains `stage`.

    A legacy deliver stage sits between validate and done, so going
    back to validate from it is a return. A legacy `path:` header line
    no longer changes the order: the old quick path's stages are a
    subset of this one, so its journals still move forward."""
    if stage in ADOPT_STAGES and stage != "done":
        return ADOPT_STAGES
    return WORK_STAGES[:-1] + ("deliver", "done") if stage == "deliver" else WORK_STAGES


def next_stage(stage: str) -> str:
    """The stage that follows `stage`."""
    if stage == "deliver":
        return "done"
    order = stage_order(stage)
    if stage not in order or stage == "done":
        raise UserError(f"no stage follows '{stage}'; name one with --to")
    return order[order.index(stage) + 1]


def recorded_value(value: str | None, previous: dict[str, str], key: str) -> str:
    """A new command-line value, or the previously recorded one when omitted."""
    return one_line(value) if value is not None else previous.get(key, "")


def summary_lines(path: Path) -> list[str]:
    """The bounded stage summary of one journal, one field per line."""
    data = parse_journal(read_text(path))
    current = data["header"].get("stage", "")
    if current not in KNOWN_STAGES:
        raise UserError("journal has no valid current stage")
    record, notice = journal_state(read_text(path), current)
    rows = {
        "Stage": (f"{record['stage']} - {record.get('result') or 'not recorded'}"
                  if record else "not recorded"),
        "Task": data["id"] or path.stem,
        "Current": current,
        "Requirements": data["header"].get("requirements", ""),
        "Changed": record.get("changed", ""),
        "Evidence": record.get("evidence", ""),
        "Issues": notice or record.get("issues", ""),
        "Next": "read journal and refresh the state" if notice else record.get("next", ""),
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
    return [f"{key + ':':<14}{value}" for key, (value, _shortened) in rendered.items()]


def record_reminders(header: dict, repeated: list[str] | tuple, text: str) -> list[str]:
    """
    Records that later stages read and an edit put out of shape - the
    header and the Rulings - printed as reminders, never refusals.
    """
    notes = [f"the header has more than one {key}: line; keep the one with its value and "
             "delete the other" for key in repeated]
    _records, errors = parse_rulings(text)
    if errors:
        notes.append(f"Rulings holds lines `ruling` did not write ({errors[0]}"
                     f"{'; ...' if len(errors) > 1 else ''}); record a settled decision with "
                     "`ruling`, and keep other notes in the Frame or the Log")
    return notes


#: The journal section each early stage writes as an ordinary edit.
STAGE_SECTIONS = {"frame": "Frame", "specify": "Requirement coverage", "design": "Design"}
LABEL_ONLY_RE = re.compile(r"^[A-Z][A-Za-z -]*:$")


def section_reminders(text: str, stage: str) -> list[str]:
    """
    A stage that pauses or completes while its own journal section is
    still empty - comments and bare template labels only - as a
    reminder, never a refusal.
    """
    name = STAGE_SECTIONS.get(stage)
    span = section_bounds(text, name) if name else None
    if span is None:
        return []
    body = re.sub(r"<!--.*?-->", "", "\n".join(text.split("\n")[span[0]:span[1]]),
                  flags=re.DOTALL)
    if any(line.strip() and not LABEL_ONLY_RE.match(line.strip()) for line in body.split("\n")):
        return []
    return [f"the {name} section is still empty; {stage} writes it in the journal as an "
            "ordinary edit" + (", or records why design is skipped" if stage == "design" else "")]


#: The Log labels the stage cards define, and the stage whose work each records.
LOG_LABEL_STAGES = {"red": "build", "green": "build", "final": "validate"}


def log_reminders(header: dict, task: str, message: str) -> list[str]:
    """
    A Log line that records a later stage's work - a red, green or final
    label, or that stage's own name - while the header still names an
    earlier stage: a reminder to advance, never a refusal.

    message: The stage-prefixed line as logged.
    """
    stage = header.get("stage", "")
    if stage not in KNOWN_STAGES:
        return []
    body = message[len(stage) + 1:] if message.lower().startswith(stage + ":") else message
    label = body.split(":", 1)[0].strip().lower()
    owner = LOG_LABEL_STAGES.get(label, label)
    order = stage_order(stage)
    if owner not in STAGE_STEP_FILES or owner not in order or stage not in order \
            or order.index(owner) <= order.index(stage):
        return []
    return [f"this line records {owner} work, but the journal is still at {stage}; once "
            f"{stage} is accepted, run `python .agentic/aegis.py advance {task}` before "
            f"more {owner} work"]


def checkpoint_hint(stage: str, task: str) -> str:
    """
    How a stage waiting on the user resumes when they move on: the
    `advance` that records it. The hint is conditional; it infers no
    approval. Adoption pauses after each component inside `components`,
    where continuing means the next component, so that stage gets none.
    """
    if stage == "components":
        return ""
    try:
        following = next_stage(stage)
    except UserError:
        return ""
    command = f"`python .agentic/aegis.py advance {task}`"
    if following == "done":
        return f"The State waits on the user: when they approve closing the task, run {command}"
    return (f"The State waits on the user: when they continue to {following}, run {command} "
            f"first and read .agentic/steps/{STAGE_STEP_FILES[following]}")


def cmd_pause(args: argparse.Namespace) -> int:
    """
    Record a pause or blocker in the State block, then print the summary.

    Changed, evidence and issues keep their recorded values unless given;
    review fields follow the configuration. The header stage is unchanged.
    """
    path, data = read_journal(args.task)
    text = read_text(path)
    stage = data["header"].get("stage", "")
    if stage not in KNOWN_STAGES:
        raise UserError("journal has no valid current stage")
    following = one_line(args.next)
    if not following:
        raise UserError("--next must name one action or one question")
    previous = stored_state(text)
    blocked = "blocked" if args.blocked else ""
    state = {"status": blocked or "waiting",
             "reported": f"{stage} - {blocked or 'paused'}",
             "next": following, "must_read": must_read(path, stage, args.read),
             **{key: recorded_value(getattr(args, key), previous, key)
                for key in ("changed", "evidence", "issues")},
             **review_fields(previous, load_config())}
    write_text(path, state_with(text, state))
    print("\n".join(summary_lines(path)))
    for note in (section_reminders(text, stage)
                 + record_reminders(data["header"], data["repeated"], text)):
        print(f"Note: {note}")
    return 0


def cmd_advance(args: argparse.Namespace) -> int:
    """
    Record a stage transition: header, Done checklist, Log line and State.

    Without --to the next stage follows the journal's path; --to also
    names a return, which waits for the user and clears enabled review
    verdicts while keeping the consumed round. Advancing never checks
    whether the stage's work was done - that stays the agent's call.
    """
    path, data = read_journal(args.task)
    text = read_text(path)
    header = data["header"]
    stage = header.get("stage", "")
    if stage not in KNOWN_STAGES:
        raise UserError("journal has no valid current stage")
    target = (args.to or next_stage(stage)).strip().lower()
    if target not in KNOWN_STAGES:
        raise UserError(f"unknown stage '{target}'")
    if target == stage:
        raise UserError(f"the task is already at {stage}")
    order = stage_order(stage)
    returning = stage in order and target in order and order.index(target) < order.index(stage)
    previous = stored_state(text)
    cfg = load_config()
    reason = one_line(args.reason)
    # Reminders, never refusals: the Log keeps what was left open.
    notes = []
    unticked = sum(1 for ticked, _item in data["checklist"] if not ticked)
    if unticked and not returning and not args.skipped:
        notes.append(f"{unticked} Done checklist item(s) left unticked")
    if target == "done" and review_settings(cfg)[0] and (
            previous.get("spec_compliance"), previous.get("implementation_quality")
            ) != ("approved", "approved"):
        notes.append("review verdicts not both approved")
    text = header_with(text, "stage", target)
    checklist = done_when(target)
    if checklist:
        text = section_with(text, "Done checklist", checklist)
    verb = ("returned to" if returning else
            "skipped; next" if args.skipped else "completed; next")
    text = log_with(text, f"{stage}: {verb} {target}" + (f" - {reason}" if reason else "")
                    + (f" ({'; '.join(notes)})" if notes else ""))
    if target == "done":
        status, default = "done", ("implementation guidance complete; commit, push and "
                                   "integration belong to the developer")
    elif returning:
        status, default = "waiting", f"continue {target}" + (f": {reason}" if reason else "")
    else:
        step = STAGE_STEP_FILES.get(target)
        status, default = "ready", (f"start {target}: read .agentic/steps/{step}" if step
                                    else f"start {target}")
    # a return waits at the stage it went back to; a forward move reports the
    # stage it finished
    reported = (f"{target} - paused" if returning else
                f"{stage} - {'skipped' if args.skipped else 'completed'}")
    state = {"status": status, "reported": reported,
             "next": one_line(args.next) or default,
             "must_read": must_read(path, target, args.read),
             **{key: recorded_value(getattr(args, key), previous, key)
                for key in ("changed", "evidence", "issues")},
             **review_fields(previous, cfg, clear=returning)}
    write_text(path, state_with(text, state))
    print("\n".join(summary_lines(path)))
    for note in notes:
        print(f"Note: {note}; recorded in the Log")
    for note in ((section_reminders(text, stage) if not (returning or args.skipped) else [])
                 + record_reminders(header, data["repeated"], text)):
        print(f"Note: {note}")
    step = STAGE_STEP_FILES.get(target)
    print(f"Next: read .agentic/steps/{step} and continue {target}" if step and target != "done"
          else "Next: nothing to resume; implementation guidance is complete")
    return 0


def cmd_log(args: argparse.Namespace) -> int:
    """Append one dated, stage-prefixed line to the journal Log."""
    path, data = read_journal(args.task)
    message = one_line(" ".join(args.text))
    if not message:
        raise UserError("log text must not be empty")
    stage = data["header"].get("stage", "")
    if stage and not message.lower().startswith(stage + ":"):
        message = f"{stage}: {message}"
    write_text(path, log_with(read_text(path), message))
    print(f"logged in {rel(path)}")
    for note in log_reminders(data["header"], data["id"] or path.stem, message):
        print(f"Note: {note}")
    return 0


def cmd_ruling(args: argparse.Namespace) -> int:
    """Append one durable decision to Rulings; earlier rulings are never edited."""
    path, _data = read_journal(args.task)
    text = read_text(path)
    records, _errors = parse_rulings(text)
    span = section_bounds(text, "rulings")
    section = "\n".join(text.split("\n")[span[0]:span[1]]) if span else ""
    numbers = [int(number) for number in re.findall(r"RULING-(\d{3})", section)]
    identity = f"RULING-{max(numbers, default=0) + 1:03d}"
    values = {"decision": one_line(args.decision), "reason": one_line(args.reason)}
    for label, value in values.items():
        if not value or "|" in value:
            raise UserError(f"ruling {label} must be one non-empty line without '|'")
    supersedes = (args.supersedes or "none").strip()
    if supersedes != "none":
        supersedes = supersedes.upper()
        if supersedes not in {record["id"] for record in records}:
            raise UserError(f"cannot supersede unknown ruling {supersedes}")
    line = (f"- {identity} | date={today()} | decision={values['decision']} | "
            f"reason={values['reason']} | source={args.source} | supersedes={supersedes}")
    text = section_with(text, "Rulings", line) if span is None else lines_appended(text, span, line)
    write_text(path, text)
    print(f"{identity} recorded in {rel(path)}"
          + (f"; it marks {supersedes} superseded, so leave that line as written"
             if supersedes != "none" else ""))
    return 0


def cmd_verdict(args: argparse.Namespace) -> int:
    """
    Record independent review verdicts and the review round in the State block.

    Verdicts come from the reviewers; this command only records them.
    It refuses while explicit review is disabled, where both verdicts
    stay `disabled`.
    """
    path, data = read_journal(args.task)
    text = read_text(path)
    stage = data["header"].get("stage", "")
    if stage not in KNOWN_STAGES:
        raise UserError("journal has no valid current stage")
    enabled, max_fix_cycles = review_settings(load_config())
    if not enabled:
        raise UserError("explicit review is disabled in .agentic/aegis.toml; "
                        "verdicts stay disabled")
    if args.round is not None and not 1 <= args.round <= 1 + max_fix_cycles:
        raise UserError(f"review round must be 1 through {1 + max_fix_cycles}")
    previous = stored_state(text)
    state = {key: previous.get(key, "") for key in STATE_FIELDS}
    if not state["reported"].startswith(f"{stage} - ") or not state["status"]:
        # A verdict is recorded while the current stage is under review.
        state.update(status="working", reported=f"{stage} - in_progress",
                     next=f"continue {stage}", must_read=must_read(path, stage))
    for key, value in (("spec_compliance", args.spec), ("implementation_quality", args.quality)):
        if value:
            state[key] = value
        elif state[key] == "disabled":
            state[key] = ""
    state["review_round"] = (str(args.round) if args.round is not None
                             else state["review_round"] or "1")
    write_text(path, state_with(text, state))
    print("\n".join(summary_lines(path)))
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    """Print a bounded stage snapshot without writes, Git or commands.

    Recorded outcomes are author statements, not fresh proof. Missing
    or mismatched bindings suppress outcome and next-action claims.
    Any shortened value requires full-journal review before proceeding.
    """
    path, _data = read_journal(args.task)
    print("\n".join(summary_lines(path)))
    return 0


def brief_lines(path: Path, journal: dict, text: str, cfg: dict) -> list[str]:
    """Render one deterministic bounded resume brief from durable files."""
    header = journal.get("header", {})
    current = header.get("stage", "")
    record, state_notice = journal_state(text, current)
    rulings, _ruling_errors = parse_rulings(text)
    active = active_rulings(rulings)
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

    if state_notice:
        state_line = ("not recorded" if " not recorded" in state_notice
                      else clean(state_notice))
        outcome_line = "not recorded"
    else:
        state_line = clean(
            f"{record.get('status') or 'not recorded'}; "
            f"reported={record['stage']} - {record.get('result') or 'not recorded'}; "
            f"next={record.get('next') or 'not recorded'}; "
            f"must_read={record.get('must_read') or 'not recorded'}; "
            f"needs_user={record.get('needs_user') or 'not recorded'}")
        outcome_line = clean(
            f"changed={record.get('changed') or 'not recorded'}; "
            f"evidence={record.get('evidence') or 'not recorded'}; "
            f"issues={record.get('issues') or 'not recorded'}")
    step = STAGE_STEP_FILES.get(current)
    read_next = (f".agentic/steps/{step}, then the State must_read paths" if step
                 else "nothing to resume; implementation guidance is complete")
    hint = (checkpoint_hint(current, journal.get("id") or path.stem)
            if step and not state_notice and record.get("status") == "waiting" else "")
    if hint:
        read_next += f". {hint}"
    review_enabled, max_fix_cycles = review_settings(cfg)
    mode = interaction_mode(cfg, header)
    review_line = clean(
        f"policy={'enabled' if review_enabled else 'disabled'}; "
        f"max_fix_cycles={max_fix_cycles}; "
        f"spec={record.get('spec_compliance') or 'not recorded'}; "
        f"quality={record.get('implementation_quality') or 'not recorded'}; "
        f"round={record.get('review_round') or 'not recorded'}")

    lines = [
        "AEGIS brief",
        f"Task: {task}",
        f"Stage: {clean(current)}",
        f"Branch/base: {branch} @ {base}",
        f"Parent: {parent}",
        f"Requirements: {requirements}",
        "Context: " + "; ".join(
            f"{rel(AGENTIC / 'context' / name)} "
            f"({'present' if (AGENTIC / 'context' / name).is_file() else 'not recorded'})"
            for name in CONTEXT_FILES),
        f"Checklist: {checklist}",
        f"State: {state_line}",
        f"Outcome: {outcome_line}",
        f"Interaction: {mode}",
        f"Review: {review_line}",
        f"Diagrams: {diagram_decision(cfg)}",
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
    lines.append(f"Read next: {read_next}")
    lines.append(f"Details: {rel(path)} (durable snapshot; read journal for full history)")
    return lines


def diagram_decision(cfg: dict) -> str:
    """
    What design draws, computed from `[diagrams]` exactly as diagrams.md
    defines it: only the boolean true enables; a missing or non-list
    `types` means structure; an empty or unknown-only list draws nothing.
    """
    table = cfg_table(cfg, "diagrams")
    if table.get("enabled") is not True:
        return "none (disabled)"
    types = table.get("types")
    if not isinstance(types, list):
        types = ["structure"]
    known = list(dict.fromkeys(t for t in types if t in DIAGRAM_TYPES))
    return ("draw " + ", ".join(known) + " for a substantive design; none for a skipped design"
            if known else "none (no known types configured)")


def cmd_brief(args: argparse.Namespace) -> int:
    """Print a deterministic bounded durable resume brief."""
    path, journal = read_journal(args.task)
    text = read_text(path)
    for line in brief_lines(path, journal, text, load_config()):
        print(line)
    return 0


#: (slug, one-line description). The slugs are the stable vocabulary the
#: later `--strict` promotion list will use - never rename one.
CHECKS: tuple[tuple[str, str], ...] = (
    ("req-parse", "requirement TOML parses and has the six required fields"),
    ("dup-id", "id matches filename and category folder; ids are unique"),
    ("journal-header", "task journal header parses; its requirement ids exist"),
    ("spec-missing", "spec references resolve to existing files"),
    ("uncovered-source", "with --task, changed source files are covered by affected_paths"),
    ("no-linked-tests", "active requirements have existing linked tests"),
    ("stale-paths", "affected_paths entries still exist on disk"),
    ("scope-drift", "a build/validate/deliver task's diff touches its requirements"),
    ("secret-in-diff", "no secret patterns in the added diff lines"),
    ("ticket-ref", "no ticket/run-id patterns inside requirement prose"),
    ("unticked-deliver", "a journal in deliver has no unticked items"),
    ("outside-layout", "the diff stays inside source/tests/docs globs and .agentic/"),
    ("source-no-test-changes", "source changes come with test changes"),
    ("repo-evolution", "a scoped task has a completed anchor/evolution pair"),
    ("fingerprints-tracked",
     "anchor/evolution sidecars are committed only when [records] commit_fingerprints is true"),
    ("config", ".agentic/aegis.toml keys have the documented shapes"),
    ("command-failed", "a --run command ran to completion and succeeded"),
    ("command-timeout", "no --run command was stopped by its time limit"),
    ("nothing-ran", "--run actually executed at least one command"),
    ("manual-verification", "a requirement is verified by hand, not by test"),
    ("review-state", "enabled explicit-review evidence matches its configured bound"),
    ("stage-zone", "the diff stays inside the current stage's write zone"),
    ("context-size", "context and knowledge pages stay within [context] page_kb, when set"),
    ("duplicate-heading", "context and knowledge pages repeat no level-two heading"),
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
    "interaction": {"autopilot": bool},
    "review": {"enabled": bool, "max_fix_cycles": int},
    "diagrams": {"enabled": bool, "types": list},
    "records": {"commit_fingerprints": bool},
    "context": {"page_kb": int},
}

#: the diagram types `[diagrams] types` may name.
DIAGRAM_TYPES = ("structure", "sequence", "state")


def check_config(add, cfg: dict) -> None:
    """Advisory shape check for aegis.toml: schema, tables, key types."""
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
            and not 0 <= cycles <= MAX_FIX_CYCLES_LIMIT):
        add("WARN", "config", name,
            f"[review] max_fix_cycles should be 0 through {MAX_FIX_CYCLES_LIMIT}")
    page_kb = cfg_table(cfg, "context").get("page_kb")
    if isinstance(page_kb, int) and not isinstance(page_kb, bool) and page_kb < 0:
        add("WARN", "config", name, "[context] page_kb should be 0 or more")
    types = cfg_table(cfg, "diagrams").get("types")
    if isinstance(types, list) and any(item not in DIAGRAM_TYPES for item in types):
        add("WARN", "config", name,
            f"[diagrams] types should name only {', '.join(DIAGRAM_TYPES)}")
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
    """DEFAULT_ZONES with any `[zones]` entry from aegis.toml applied."""
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
#: journal stage vocabulary: the five stages, adoption's phases, done, and the
#: legacy deliver stage that older journals may still hold.
KNOWN_STAGES = ("frame", "specify", "design", "build", "validate", "deliver", "done",
                "survey", "components", "close")
#: which step file explains each stage - adoption's phases live in adopt.md;
#: validate explains how a legacy deliver journal closes.
STAGE_STEP_FILES = {
    "frame": "1_frame.md", "specify": "2_specify.md", "design": "3_design.md",
    "build": "4_build.md", "validate": "5_validate.md", "deliver": "5_validate.md",
    "survey": "adopt.md", "components": "adopt.md", "close": "adopt.md",
}


def repo_relative_ok(entry: str) -> bool:
    """True when a stored path stays inside the repository."""
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
    """True when a TICKET_RE hit is a ticket, not a standard or format."""
    if hit.startswith(("#", "TASK-", "REQ-")):
        return True
    return hit.split("-", 1)[0].upper() not in NOT_TICKET_PREFIXES

DIFF_HEADER_RE = re.compile(r"^diff --git a/(.*) b/(.*)$")
#: `git diff` formats for people: a user's `color.ui` or `diff.external` changes
#: what it prints, and a patch the parser cannot read looks like a clean one.
PLAIN_PATCH = ("--no-color", "--no-ext-diff")

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
    """A TOML value as a list of strings, tolerating a scalar."""
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value]
    return [str(value)] if value else []


def split_ids(value: str) -> list[str]:
    """Split a `requirements:` header value into individual ids."""
    return [part for part in re.split(r"[\s,]+", value.strip()) if part]


def match_path(path: str, pattern: str) -> bool:
    """
    One layout/affected_paths entry against one repo-relative path.

    A trailing `/` or a bare directory name matches by prefix; an
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
    """True when any entry of `patterns` matches `path`."""
    return any(match_path(path, pattern) for pattern in patterns)


def default_branch(cfg: dict) -> str:
    """
    The ref the diff is based on; "" when none can be resolved.

    Resolution order (documented in `check --help`): an explicit
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
    Print one JSON document as the command's entire stdout.

    Every envelope carries `schema` so a consumer fails loudly on a
    contract change instead of silently misparsing. Human progress
    lines go to stderr under `--json`, keeping stdout a single
    parseable document.
    """
    print(json.dumps({"schema": JSON_SCHEMA, **payload},
                     ensure_ascii=False, indent=2, sort_keys=False))
#: task journals listed by `status` before it summarises the rest.
STATUS_CAP = 20


def untracked_files() -> list[str]:
    """Relevant untracked, non-ignored files, decoded NUL-safely."""
    out = run_git("ls-files", "--others", "--exclude-standard", "-z")
    if not out or out[0] != 0:
        return []
    return [name for name in out[1].split("\0")
            if name and not generated_python_cache(name)]


def added_lines_of(file: str) -> list[tuple[str, str]]:
    """
    Every line of an untracked text file, treated as an added line.

    Bounded (`MAX_SCAN_BYTES`) and binary-safe: oversized or binary
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
    The revision every diff is taken against, and why it failed.

    Without an explicit revision this is the merge base with the
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
    Changed files and added lines versus the diff base.

    File names come from `git diff --name-only -z` (robust against
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
    patch = run_git("-c", "core.quotepath=false", "diff", *PLAIN_PATCH, resolved, "--")
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
        one = run_git("diff", *PLAIN_PATCH, resolved, "--", name)
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
    Single pass over the requirement tree: checks 1 and 2.

    Returns the parsed records for the link checks; files that fail
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
    The declared by-hand method, or "" when none is declared.

    Some behaviors no test can settle - a look-and-see judgement, an
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
    Why one `linked_tests` entry does not resolve, or "" when it does.

    The single place a linked test is judged to exist, so a finding
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
    Which coverage class one requirement record belongs to.

    The single place the precedence lives, so that every reader of a
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
    """Per-requirement checks 4, 6, 7, 10 and 19 over the parsed records."""
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
    """Single pass over the task journals: checks 3 and 11."""
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
        recorded_mode = data["header"].get("interaction", "").strip().lower()
        if recorded_mode and recorded_mode not in INTERACTION_MODES:
            add("WARN", "journal-header", relpath,
                "interaction should be checkpoint or autopilot")
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
        if has_section(text, "state"):
            try:
                _record, notice = journal_state(text, data["header"]["stage"])
            except UserError as exc:
                add("WARN", "journal-header", relpath, str(exc))
            else:
                if notice.startswith(("stale", "incomplete")):
                    add("WARN", "journal-header", relpath, notice)
            if has_section(text, "handoff") or has_section(text, "stage report"):
                add("WARN", "journal-header", relpath,
                    "legacy Handoff or Stage report beside State is ignored; remove it")
        else:
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
    """Check enabled explicit-review evidence against its finite policy."""
    enabled, max_fix_cycles = review_settings(cfg)
    if not enabled:
        return
    for relpath, journal in journals:
        stage = journal.get("header", {}).get("stage", "")
        if stage not in {"validate", "deliver"}:
            continue
        try:
            text = read_text(ROOT / relpath)
            record, notice = journal_state(text, stage)
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
    Diff-based checks 5, 8, 9, 12, 13 and 20.

    `scope` is the parsed journal of `--task` or None; it narrows
    checks 8 and 20 to that one task, and its `base:` header - the
    commit the task started from - becomes the diff basis, so the
    findings describe that task rather than everything its branch has
    done. Check 5 runs only with a scope: changes made outside AEGIS
    need no requirement, so an unscoped diff says nothing about
    coverage. Without a usable diff every check here emits one NOTE
    and returns.
    """
    base = str(scope["header"].get("base", "")).strip() if scope else ""
    files, added, gaps, reason = collect_diff(cfg, base)
    if reason:
        for slug in DIFF_CHECKS:
            if slug != "uncovered-source" or scope:
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
        cover = []
        drift_journals = journals

    for file in files if scope else []:  # 5: uncovered-source
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


def level_two_headings(text: str) -> list[str]:
    """The `## ` headings of a Markdown page, outside fenced blocks."""
    headings: list[str] = []
    fence = ""
    for line in text.split("\n"):
        opening = FENCE_RE.match(line)
        if fence:
            if opening and opening.group(1)[0] == fence[0] and len(opening.group(1)) >= len(fence):
                fence = ""
            continue
        if opening:
            fence = opening.group(1)
            continue
        if line.startswith("## "):
            headings.append(line[3:].strip())
    return headings


def check_context_pages(add, skip, cfg: dict) -> None:
    """
    Checks 23 and 24: current-state pages stay short and edited in place.

    Project context and knowledge pages are read at every frame, so a
    page that grows by a section per task makes every later task pay
    for it. `context-size` reports a page above `[context] page_kb`
    (0 or no setting means no budget); `duplicate-heading` reports a
    level-two heading written twice, the mark of a section appended
    instead of edited. An unreadable page is skipped here; `components`
    reports a knowledge page it cannot read.
    """
    budget = cfg_table(cfg, "context").get("page_kb")
    if isinstance(budget, bool) or not isinstance(budget, int) or budget < 0:
        budget = 0  # no budget; check_config reports a bad value
    pages: list[tuple[Path, str]] = []
    for name in CONTEXT_FILES:
        path = AGENTIC / "context" / name
        if path.is_file() and not path.is_symlink():
            try:
                pages.append((path, read_text(path)))
            except (UserError, OSError):
                continue
    pages += knowledge_page_texts(on_error=lambda _path, _exc: None)
    for path, text in pages:
        relpath = rel(path)
        if skip(relpath):
            continue
        size_kb = -(-len(text.encode("utf-8")) // 1024)
        if budget and size_kb > budget:
            add("WARN", "context-size", relpath, f"{size_kb} KB > page_kb {budget}")
        counts: dict[str, int] = {}
        for heading in level_two_headings(text):
            counts[heading] = counts.get(heading, 0) + 1
        for heading, count in counts.items():
            if count > 1:
                add("WARN", "duplicate-heading", relpath,
                    f"'## {heading}' appears {count} times")


def run_checks(cfg: dict, task: str | None) -> list[tuple[str, str, str, str]]:
    """
    Collect the full findings list of the check catalog.

    Shared by `check` and `report`. `task` scopes the diff-based
    checks to that journal exactly as `check --task` does.
    """
    ignore = str_list(cfg_table(cfg, "check").get("ignore"))
    findings: list[tuple[str, str, str, str]] = []

    def add(level: str, slug: str, path: str, message: str) -> None:
        findings.append((level, slug, path, message))

    def skip(path: str) -> bool:
        return match_any(path, ignore)

    check_config(add, cfg)
    check_fingerprints(add, cfg)
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
    check_context_pages(add, skip, cfg)
    if scope_path is not None and scope is not None:
        check_repo_evolution(add, scope_path, scope)
    return findings


def check_fingerprints(add, cfg: dict) -> None:
    """
    Report anchor/evolution sidecars whose git state contradicts
    `[records] commit_fingerprints`.

    With the setting false, sidecars still tracked are a warning
    and a missing managed ignore block is a note; with it true, a
    leftover block is a warning. AEGIS never untracks a file: the
    remedy is printed for a human to run.
    """
    commit = commit_fingerprints(cfg)
    path = ROOT / IGNORE_FILE
    present = path.is_file() and IGNORE_MARK_BEGIN in read_text(path)
    if commit:
        if present:
            add("WARN", "fingerprints-tracked", IGNORE_FILE,
                "block present; commit_fingerprints=true - rerun init")
        return
    if not present:
        add("NOTE", "fingerprints-tracked", IGNORE_FILE,
            "no managed sidecar ignore block - run init")
    tracked = tracked_fingerprints()
    if tracked:
        add("WARN", "fingerprints-tracked", ".agentic/tasks",
            f"{len(tracked)} tracked sidecar(s) - untrack: git rm --cached")


def check_repo_evolution(add, journal: Path, scope: dict) -> None:
    """Report missing or unreadable state records for one scoped task."""
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
    The limit for one command in seconds, or None for no limit.

    `[timeouts] <name>` wins, then the shared `[commands] timeout`,
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
    Where configured commands run: `[commands] workdir`, else the root.

    A repository whose application sits below the root would
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
    The `[commands]` entries that can run as-is, in file order.

    The reserved keys - which name configuration, not commands -
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
    Kill a timed-out command and its descendants, per platform.

    Returns True when the platform reported a successful tree kill;
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
    Run one configured shell command, by default in the repo root.

    Returns (exit code, seconds, captured output tail, stopped). The
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


def plan_configured_commands(cfg: dict) -> list[tuple[str, str, str, str]]:
    """
    Decide what `check --run` would execute, without executing it.

    Returns one `(name, command, decision, reason)` per configured
    entry, where `decision` is `run` or `skipped`. Both the preview
    and the real run read this single function, so a `--dry-run`
    plan can never promise a different set than `--run` delivers.
    """
    allowed = str_list(cfg_table(cfg, "check").get("run"))
    plan: list[tuple[str, str, str, str]] = []
    for name, command in runnable_commands(cfg):
        if allowed and name not in allowed:
            plan.append((name, command, "skipped", "not listed in [check] run"))
        elif not allowed and SIDE_EFFECT_NAME_RE.search(name):
            plan.append((name, command, "skipped",
                         ("name suggests side effects - list it in "
                          "[check] run to include it")))
        else:
            plan.append((name, command, "run", ""))
    return plan


def preview_configured_commands(cfg: dict, stream=None) -> list[dict]:
    """
    Print what `check --run` would execute, and run nothing.

    `--run` already prints `run: <name> started` before each command,
    but that reaches a human watching a live terminal - an agent
    calling the command through a shell tool receives all output only
    once the command has returned, by which time an hour-long suite
    has already been spent. A caller that must decide *whether* it can
    afford this proof needs the answer beforehand, so this prints the
    plan and the per-command limit, and returns.

    The limit is the honest duration signal available without running
    anything: `no limit` says the repository believes the command may
    legitimately take as long as it takes.
    """
    out = stream if stream is not None else sys.stdout
    plan = plan_configured_commands(cfg)
    will_run = [entry for entry in plan if entry[2] == "run"]
    print(f"dry-run: check --run would execute {len(will_run)} of {len(plan)} "
          f"[commands] entries; workdir={command_workdir(cfg)}", file=out)

    records: list[dict] = []
    for name, command, decision, reason in plan:
        if decision == "skipped":
            print(f"run: {name} skipped ({reason})", file=out)
            records.append({"name": name, "status": "skipped", "reason": reason})
            continue
        limit = command_timeout(cfg, name)
        print(f"run: {name} would run "
              f"({'no limit' if limit is None else f'limit {limit}s'})", file=out)
        print(f"  $ {command}", file=out)
        records.append({"name": name, "status": "planned", "command": command,
                        "timeout": limit})
    # Same closing sentence as `test --dry-run`, and for the same reason: a
    # preview must never be mistaken for the proof the validate stage requires.
    print("dry-run: no command run; no verification result recorded", file=out)
    return records


def run_configured_commands(cfg: dict, findings: list,
                            stream=None) -> list[dict]:
    """
    Execute the verification `[commands]` entries for `check --run`.

    `check --run` is a verification pass, not a deployment tool: an
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

    Progress goes to `stream` (stdout by default; stderr under
    `--json`, so stdout stays one parseable document). Returns one
    record per configured command for the JSON envelope.
    """
    entries = plan_configured_commands(cfg)
    out = stream if stream is not None else sys.stdout
    results: list[dict] = []
    workdir = command_workdir(cfg)
    ran = 0

    def say(text: str) -> None:
        print(text, file=out, flush=True)  # live: each command lands visibly

    for name, command, decision, reason in entries:
        if decision == "skipped":
            say(f"run: {name} skipped ({reason})")
            results.append({"name": name, "status": "skipped",
                            "reason": reason})
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
    Run the check catalog and print the findings report.

    Advisory by design: exits 0 - except with --strict (the CI
    mode), which exits 1 on errors, failed --run commands, and
    warnings promoted via `[check] strict_promote`. One finding per
    line, `LEVEL  CHECK-ID  path - message`, sorted by path, capped
    at 100 columns; then two summary lines.
    """
    cfg = load_config()
    findings = run_checks(cfg, args.task)
    # under --json stdout must stay one parseable document, so live progress
    # goes to stderr instead of being lost.
    progress = sys.stderr if args.json else None
    if args.dry_run:
        # The preview never appends `nothing-ran`: that ERROR exists because
        # `--run` promised verification and delivered none. `--dry-run`
        # promised a plan, and delivering one is not a failed proof.
        runs = preview_configured_commands(cfg, progress)
    elif args.run:
        runs = run_configured_commands(cfg, findings, progress)
    else:
        runs = []

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
            # explicit, so a consumer can never read a plan as a proof
            "dry_run": bool(args.dry_run),
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
    One repository-relative test reference, seen from `workdir`.

    References are stored repository-relative so they stay
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
    The focused regression set: diff -> requirements -> linked_tests.

    The traceability mapping driven in reverse, with two safety
    rules. Completeness: every changed source file must be covered
    by some requirement's affected_paths, otherwise the focused set
    would silently skip the uncovered work and the caller falls back
    to the full suite. Hygiene: any test reference containing shell
    metacharacters in a path forces fallback. Unsupported selector
    suffixes are discarded in favor of the validated whole file;
    no discarded suffix is substituted into a shell command.
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
    # A human-readable selector is not shell syntax. Broaden only its suffix;
    # the file path still has to satisfy both containment and shell hygiene.
    files_only: set[str] = set()
    for entry in tests:
        path, separator, _selector = entry.partition("::")
        if not repo_relative_ok(path):
            return [], f"test reference escapes the repository ('{entry}')"
        if not SAFE_TEST_REF_RE.fullmatch(entry):
            if not separator or not SAFE_TEST_REF_RE.fullmatch(path):
                return [], f"unsafe test reference '{entry}'"
            files_only.add(path)

    if files_only:
        tests = list(dict.fromkeys(
            entry.partition("::")[0]
            if entry.partition("::")[0] in files_only else entry
            for entry in tests))
        print(f"impacted: unsupported selectors - reduced to file granularity "
              f"for {len(files_only)} test file(s)")

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
    Substitute the focused set, coarsening it until it can launch.

    A selector list long enough to exceed the platform's command
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
    Append one dated log line at the end of the journal's Log section.

    The Log section may not be the last section once a delivery
    report has been appended, so the line is inserted before the
    next `## ` heading rather than blindly at end of file.
    """
    path, _data = read_journal(task_id)
    write_text(path, log_with(read_text(path), message))


def cmd_test(args: argparse.Namespace) -> int:
    """
    Convenience runner for one configured command (default: test).

    Output streams live; the exit code mirrors the command's own
    result. --impacted substitutes the focused regression set into
    the `test_impacted` template and falls back to the full `test`
    command - saying why - whenever the set cannot be used.
    """
    cfg = load_config()
    commands = cfg_table(cfg, "commands")
    if args.impacted and args.name != "test":
        raise UserError("--impacted only applies to the 'test' command")
    if args.no_fallback and not args.impacted:
        raise UserError("--no-fallback requires --impacted")
    command = commands.get(args.name)
    if (args.name in RESERVED_COMMAND_KEYS or not isinstance(command, str)
            or not command.strip() or "{" in command):
        raise UserError(
            f"no runnable [commands] entry named '{args.name}' in .agentic/aegis.toml")

    label = args.name
    fallback = ""
    if args.impacted:
        template_cmd = commands.get("test_impacted")
        if not isinstance(template_cmd, str) or "{tests}" not in template_cmd:
            fallback = "no test_impacted template in .agentic/aegis.toml"
        else:
            tests, reason = impacted_tests(cfg, getattr(args, "base", "") or "")
            substituted, tests, reason = fit_impacted(template_cmd, tests, reason)
            if substituted:
                command = substituted
                label = f"test --impacted ({len(tests)} test ref(s))"
            else:
                fallback = reason

    if fallback:
        if args.no_fallback:
            raise UserError(f"impacted: {fallback} - no command run; "
                            "choose a focused project command or defer full verification")
        action = "would run" if args.dry_run else "running"
        print(f"impacted: {fallback} - {action} the full test command")

    if args.task:  # validate before running: a typo must not cost a suite run
        read_journal(args.task)

    workdir = command_workdir(cfg)
    if args.dry_run:
        print(f"plan: {label}; workdir={workdir}")
        print(f"$ {command}")
        print("dry-run: no command run; no verification result recorded")
        return 0

    print(f"$ {command}", flush=True)
    code, seconds, _tail, stopped = run_command(
        command, command_timeout(cfg, args.name), capture=False,
        cwd=workdir)
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
COMPONENT_TITLE_WIDTH = 80


def mermaid_label(text: str) -> str:
    """
    One requirement title, safe inside a quoted Mermaid node label.

    Mermaid reads `"` and `#` inside a label as syntax, so both are
    replaced rather than escaped - a label is a caption, and a
    caption that breaks the drawing is worse than one that lost a
    quotation mark.
    """
    flat = " ".join(str(text).split()).replace('"', "'").replace("#", "no.")
    return flat[:LABEL_WIDTH - 1] + "…" if len(flat) > LABEL_WIDTH else flat


def mermaid_id(text: str) -> str:
    """A Mermaid node or subgraph id: letters, digits and underscores."""
    return re.sub(r"[^A-Za-z0-9]", "_", str(text)) or "node"


def lexical_repo_path(path: Path) -> str:
    """A repository-relative path that does not resolve symlinks."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def catalogue_path(path: Path) -> str:
    """A printable lexical path safe as one catalogue output field."""
    value = lexical_repo_path(path)
    if not value or any(not char.isprintable() for char in value):
        raise UserError(
            "component knowledge page path contains non-printable characters")
    return value


def knowledge_page_texts(on_error=None) -> list[tuple[Path, str]]:
    """
    Read catalogue pages without interpreting their prose.

    A link may alias another page inside the knowledge directory, but
    may not turn a file elsewhere into component knowledge. Callers
    receive the lexical catalogue path so output never exposes or
    substitutes a resolved target path.
    """
    pages: list[tuple[Path, str]] = []
    knowledge = AGENTIC / "knowledge"
    resolved_knowledge = knowledge.resolve()
    for path in sorted(knowledge.glob("*.md")):
        try:
            path_label = catalogue_path(path)
            try:
                resolved_path = path.resolve()
            except RuntimeError as exc:
                raise UserError(
                    f"{path_label} cannot be resolved: {exc}") from None
            if not resolved_path.is_relative_to(resolved_knowledge):
                raise UserError(
                    f"{path_label} resolves outside "
                    f"{catalogue_path(knowledge)}")
            pages.append((path, read_text(path)))
        except (UserError, OSError) as exc:
            if on_error is None:
                raise
            on_error(path, exc)
    return pages


def component_title(value: str, fallback: str) -> str:
    """One bounded printable component-catalogue title field."""
    def normalized(text: str) -> str:
        return " ".join("".join(char if char.isprintable() else " "
                                 for char in text).split())

    clean = normalized(value) or normalized(fallback) or "component"
    if len(clean) <= COMPONENT_TITLE_WIDTH:
        return clean
    return clean[:COMPONENT_TITLE_WIDTH - 1] + "…"


def knowledge_titles() -> list[tuple[str, str]]:
    """Every page's safe display title and lexical catalogue path."""
    titles: list[tuple[str, str]] = []
    for path, text in knowledge_page_texts():
        path_label = catalogue_path(path)
        heading = re.search(r"^# (.+)$", text, re.MULTILINE)
        raw_title = heading.group(1).strip() if heading else path.stem
        titles.append((component_title(raw_title, path.stem),
                       path_label))
    return titles


def knowledge_components(on_error=None) -> list[tuple[str, str, list[str]]]:
    """
    Every component page as (stem, display name, claimed requirement ids).

    Only two things are read out of the prose, both by strict
    pattern: the first `# ` heading for the name, and the requirement
    ids under `## Key behaviors`. The template calls those sections
    recommended rather than mandatory, so nothing load-bearing is
    parsed out of a page - a page missing its heading is still listed,
    under its file name. A caller providing on_error may report and
    skip unreadable pages; otherwise the existing error propagates.
    """
    components: list[tuple[str, str, list[str]]] = []
    for path, text in knowledge_page_texts(on_error=on_error):
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


def cmd_components(_args: argparse.Namespace) -> int:
    """List every component knowledge page by display name and path."""
    titles = knowledge_titles()
    if not titles:
        print("no component knowledge pages")
        return 0
    for name, path in titles:
        print(f"{name}\t{path}")
    return 0


def diagram_scope(args: argparse.Namespace,
                  components: list[tuple[str, str, list[str]]]) -> set[str] | None:
    """
    The requirement ids the diagram is restricted to, or None for all.
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
    The coverage flowchart for `records`, grouped by claiming component.

    Left to right so the component groups sit side by side and each
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
    Draw the requirement register as a Mermaid coverage flowchart.

    Derived entirely from records already in the repository, so it
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
    """One record field as a single line, however TOML wrapped it."""
    return " ".join(str(value or "").split())


def trace_rows(records: list[tuple[str, Path, dict]],
               components: list[tuple[str, str, list[str]]]) -> list[dict]:
    """
    One row per requirement, ordered by category and then by id.

    List columns stay lists here and are joined by each renderer,
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
    """One column of one row, with list columns joined for the format."""
    value = row[key]
    return joiner.join(value) if isinstance(value, list) else str(value)


def render_trace_csv(rows: list[dict]) -> str:
    """
    The traceability record as comma-separated values.

    Header row and data only — no summary block, no preamble, so a
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
    Literal, single-line cell text with no active inline Markdown.

    Entities preserve backslashes, table delimiters and markup as
    text; renderer-owned list breaks are inserted only afterwards.
    """
    return "".join(f"&#{ord(char)};" if char in "&<>\\`*_[]|~" else char
                   for char in flat(value))


def render_trace_md(rows: list[dict], unreadable: list[str]) -> str:
    """
    The traceability record as a Markdown table under a summary block.

    Each scalar and list entry is flattened and escaped as literal
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
    Emit the requirement register as a flat traceability record.

    The third reader of the register, and the only one that leaves
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
        """Report missing ownership evidence without discarding rows."""
        relpath = lexical_repo_path(path)
        knowledge_errors.append(relpath)
        print(f"warning: knowledge page unavailable: {relpath}: {error}; "
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
    Every deviation a journal records, in the order it recorded them.

    Reads the whole journal rather than only its `## Log` section: a
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
    One operator-supplied path as a repository-relative POSIX string.
    @raises UserError when the path resolves outside the repository.

    Takes whatever the shell handed over - native separators, an
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
    Report what governs one repository path, and what delivered it.

    The register is written once per behavior and read almost never,
    because nothing leads from a file back to it. This is that way
    round: path to requirements, grouped by the component claiming
    each, with how it is verified and the journals that carry it.
    A path no requirement covers is stated plainly: code that only
    direct changes touched has none, and that is not a defect.
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
    Append the delivery summary section to a task journal.

    Gathers the journal state, the linked requirement titles, the
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
            review_record, review_notice = journal_state(text, header.get("stage", ""))
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
         f" branch: {header.get('branch', '?')}"),
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


def state_arguments(parser: argparse.ArgumentParser) -> None:
    """The State options shared by pause and advance; omitted ones keep their value."""
    parser.add_argument("--read", action="append",
                        help="a repository path the next session must read "
                             "(repeatable or comma-separated)")
    parser.add_argument("--changed", help="what changed, one line")
    parser.add_argument("--evidence", help="what shows it works, one line")
    parser.add_argument("--issues", help="open issues or risks, one line")


def build_parser() -> argparse.ArgumentParser:
    """The argparse tree for every implemented command."""
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
    evolution.add_argument("--compact", action="store_true",
                           help="omit fingerprints from JSON output; saved evidence stays complete")
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
                       help="also execute the [commands] entries from .agentic/aegis.toml")
    check.add_argument("--dry-run", action="store_true",
                       help="list what --run would execute, with each command's"
                            " limit, and run none of it")
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
    test.add_argument("--no-fallback", action="store_true",
                      help="with --impacted, exit 1 without running when selection is unavailable")
    test.add_argument("--dry-run", action="store_true",
                      help="preview the selected command and working directory without running or logging")
    test.add_argument("--base", default="",
                      help="diff against this revision instead of the merge base"
                           " (--base HEAD selects only uncommitted work)")
    test.add_argument("--task", help="append the result to this task journal's log")
    test.set_defaults(func=cmd_test)

    report = subs.add_parser(
        "report", help="append the delivery summary to a task journal")
    report.add_argument("task", help="TASK-<id> or <id>")
    report.set_defaults(func=cmd_report)

    pause = subs.add_parser("pause", help="record a pause or blocker in the journal State")
    pause.add_argument("task", help="TASK-<id> or <id>")
    pause.add_argument("--next", required=True,
                       help="the one action or question that resumes the work")
    pause.add_argument("--blocked", action="store_true",
                       help="the work cannot continue until the issue is resolved")
    state_arguments(pause)
    pause.set_defaults(func=cmd_pause)

    advance = subs.add_parser(
        "advance", help="move a task to its next stage and record the State")
    advance.add_argument("task", help="TASK-<id> or <id>")
    advance.add_argument("--to", help="the target stage (default: the next one on the path)")
    advance.add_argument("--reason", help="why, kept in the Log line (returns and skips)")
    advance.add_argument("--skipped", action="store_true",
                         help="the stage was skipped rather than completed")
    advance.add_argument("--next", help="the next action (default: start the next stage)")
    state_arguments(advance)
    advance.set_defaults(func=cmd_advance)

    log = subs.add_parser("log", help="append one dated line to the journal Log")
    log.add_argument("task", help="TASK-<id> or <id>")
    log.add_argument("text", nargs="+", help="the line to append")
    log.set_defaults(func=cmd_log)

    ruling = subs.add_parser("ruling", help="append one durable decision to Rulings")
    ruling.add_argument("task", help="TASK-<id> or <id>")
    ruling.add_argument("--decision", required=True, help="what was decided, one line")
    ruling.add_argument("--reason", required=True, help="why, one line")
    ruling.add_argument("--source", required=True, choices=RULING_SOURCES,
                        help="who or what settled it")
    ruling.add_argument("--supersedes",
                        help="an earlier RULING-NNN this one replaces; the link marks it "
                             "superseded, so the earlier line stays as written")
    ruling.set_defaults(func=cmd_ruling)

    verdict = subs.add_parser(
        "verdict", help="record explicit review verdicts in the journal State")
    verdict.add_argument("task", help="TASK-<id> or <id>")
    verdict.add_argument("--spec", choices=("approved", "changes_required"),
                         help="the specification-compliance reviewer's verdict")
    verdict.add_argument("--quality", choices=("approved", "changes_required"),
                         help="the implementation-quality reviewer's verdict")
    verdict.add_argument("--round", type=int, help="the review round (default: kept, else 1)")
    verdict.set_defaults(func=cmd_verdict)

    summary = subs.add_parser(
        "summary", help="print a compact recorded stage summary (read-only)")
    summary.add_argument("task", help="TASK-<id> or <id>")
    summary.set_defaults(func=cmd_summary)

    brief = subs.add_parser("brief", help="print a bounded durable resume brief")
    brief.add_argument("task", help="TASK-<id> or <id>")
    brief.set_defaults(func=cmd_brief)

    components = subs.add_parser(
        "components", help="list component knowledge titles and paths")
    components.set_defaults(func=cmd_components)

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
    """Parse arguments and dispatch; expected errors exit 1, no traceback."""
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
