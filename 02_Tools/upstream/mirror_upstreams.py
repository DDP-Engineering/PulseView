# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Mirror the pinned sigrok upstreams into the local Gitea.

The point is an offline build: once these mirrors exist, nothing in the
toolchain needs github.com again. Full history is preserved with
`git clone --mirror` so tags and every branch survive, not just the pinned
commit.

Each source in upstreams.lock.toml is cloned bare into .work/mirrors/, checked
to confirm the pinned commit is actually present, then pushed to Gitea. The
pin is verified before the push, not after - a mirror that does not contain
the commit we build from is worthless.

The bare clones under .work/ are only a transport staging area and can be
deleted once pushed. The repositories you actually build from live in
05_Software/ as submodules whose remote is Gitea, never github.com, so a
fresh checkout of this project needs no internet.

Usage:
    uv run mirror_upstreams.py --check       # verify pins, clone nothing
    uv run mirror_upstreams.py --clone       # clone/update local bare mirrors
    uv run mirror_upstreams.py --push        # create Gitea repos and push
    uv run mirror_upstreams.py --submodules  # wire 05_Software/<name>
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LOCK = REPO_ROOT / "02_Tools" / "upstream" / "upstreams.lock.toml"
# Transport staging only - safe to delete once the Gitea push has happened.
MIRRORS = REPO_ROOT / ".work" / "mirrors"
# The trees we actually build from.
UPSTREAM = REPO_ROOT / "05_Software"

GITEA_SSH = "ssh://git@192.168.1.15:2222/dpasare"
GITEA_OWNER = "dpasare"


def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> str:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{p.stdout}\n{p.stderr}")
    return (p.stdout + p.stderr).strip()


def sources() -> list[dict]:
    with LOCK.open("rb") as fh:
        return tomllib.load(fh)["source"]


def mirror_name(src: dict) -> str:
    """Gitea repo name. Prefixed so mirrors never collide with our own work."""
    return f"mirror-{src['name']}"


def clone(src: dict) -> Path:
    dest = MIRRORS / f"{src['name']}.git"
    if dest.exists():
        print(f"  updating {dest.name}")
        run(["git", "remote", "update", "--prune"], cwd=dest)
    else:
        print(f"  cloning {src['canonical_url']}")
        MIRRORS.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--mirror", src["canonical_url"], str(dest)])
    return dest


def has_commit(bare: Path, commit: str) -> bool:
    out = run(["git", "cat-file", "-t", commit], cwd=bare, check=False)
    return out.strip() == "commit"


def add_submodule(src: dict) -> None:
    """Wire 05_Software/<name> to the Gitea mirror at the pinned commit."""
    rel = f"05_Software/{src['name']}"
    path = REPO_ROOT / rel
    url = f"{GITEA_SSH}/{mirror_name(src)}.git"
    if not path.exists():
        print(f"  adding submodule {rel}")
        run(["git", "submodule", "add", "--force", url, rel], cwd=REPO_ROOT)
    run(["git", "fetch", "origin"], cwd=path, check=False)
    # Detach at the pin. Submodules record a commit, so a branch would let the
    # build drift the next time anyone runs `git submodule update --remote`.
    run(["git", "checkout", "--detach", src["commit"]], cwd=path)
    print(f"  {rel} at {src['commit'][:12]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--clone", action="store_true")
    ap.add_argument("--push", action="store_true")
    ap.add_argument("--submodules", action="store_true")
    ap.add_argument("--only", help="restrict to one source name")
    args = ap.parse_args()
    if not (args.check or args.clone or args.push or args.submodules):
        print(__doc__)
        return 2

    srcs = sources()
    if args.only:
        srcs = [s for s in srcs if s["name"] == args.only]

    failures = []
    for src in srcs:
        name, commit = src["name"], src["commit"]
        print(f"\n=== {name}  {commit[:12]}")

        if args.submodules and not (args.clone or args.push or args.check):
            add_submodule(src)
            continue

        if args.clone or args.push:
            bare = clone(src)
        else:
            bare = MIRRORS / f"{name}.git"
            if not bare.exists():
                print("  not cloned yet")
                continue

        if not has_commit(bare, commit):
            print(f"  PIN MISSING: {commit} is not in the mirror")
            failures.append(name)
            continue
        print(f"  pin present")

        if args.push:
            target = f"{GITEA_SSH}/{mirror_name(src)}.git"
            # No --owner: tea resolves it as an organisation, and dpasare is a
            # user, so passing it fails with GetOrgByName. Omitting it creates
            # the repo under the authenticated user, which is what we want.
            out = run(["tea", "repos", "create", "--name", mirror_name(src),
                       "--private", "--description",
                       f"Offline mirror of {src['canonical_url']} "
                       f"pinned at {commit[:12]}"], check=False)
            if "already exists" in out:
                print("  repo already present")
            print(f"  pushing to {target}")
            # Not --mirror: that would also push GitHub's refs/pull/* refs,
            # which Gitea owns and rejects with "hook declined to update".
            # Branches and tags are the whole of the real history.
            run(["git", "push", "--prune", target,
                 "refs/heads/*:refs/heads/*", "refs/tags/*:refs/tags/*"],
                cwd=bare)
            print("  pushed")

        if args.submodules:
            add_submodule(src)

    if failures:
        print(f"\nFAILED pin verification: {', '.join(failures)}", file=sys.stderr)
        return 1
    print("\nall pins verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
