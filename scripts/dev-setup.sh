#!/usr/bin/env bash
# scripts/dev-setup.sh — bootstrap local dogfooding for the scaffold's OWN repo.
#
# The scaffold can't install itself (install.sh refuses to run with the scaffold
# dir as the target, by design), so a fresh clone has NO active hooks. This
# renders the *.template sources into the gitignored .githooks/ and
# .forbidden-patterns/ — the same files install.sh writes into a consumer project
# and self-lint.yml renders in CI — and points core.hooksPath at .githooks. After
# running it, committing in this repo runs the scaffold's own guardrails,
# including the opt-in commit-msg (Conventional Commits) hook.
#
# Idempotent: re-run any time to refresh after editing a template. The rendered
# files are gitignored build artifacts; only the *.template sources are tracked,
# so there is exactly one source of truth.

set -euo pipefail

# Resolve the repo root from this script's own location, so it works from any cwd.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f githooks/pre-commit.template ]; then
  echo "error: run this from a clone of ai-coding-rules-scaffold (githooks/*.template not found)" >&2
  exit 1
fi

# Mirror install.sh's A7 symlink defenses (_cp_replace). .githooks/ and
# .forbidden-patterns/ are gitignored, so a leftover or planted symlink there
# survives across checkouts; a bare `cp` follows a symlink at a rendered path and
# writes the scanner THROUGH the link to a target OUTSIDE the repo, and `mkdir -p`
# follows a symlinked DIR (sending every scanner outside). Drop any symlink before
# writing so we always land a real file/dir in the tree, never through a link.
_mkdir_safe() {           # create a real dir, never follow a symlink into one
  local d=$1
  if [ -L "$d" ]; then rm -f "$d"; fi
  mkdir -p "$d"
}
_cp() {                   # write a real regular file, never through a symlink
  local src=$1 dst=$2
  rm -f "$dst"
  cp "$src" "$dst"
}

_mkdir_safe .githooks
_mkdir_safe .githooks/lib
_mkdir_safe .forbidden-patterns

# Top-level hooks — including the opt-in commit-msg: the repo dogfoods everything
# it ships, even the hooks that are opt-in for downstream consumers.
_cp githooks/pre-commit.template .githooks/pre-commit
_cp githooks/commit-msg.template .githooks/commit-msg

# Scanner libs + language/secret pattern files.
for t in githooks/lib/*.template; do
  _cp "$t" ".githooks/lib/$(basename "$t" .template)"
done
for t in forbidden-patterns/*.txt.template; do
  _cp "$t" ".forbidden-patterns/$(basename "$t" .template)"
done

chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/lib/*

git config core.hooksPath .githooks

libs=(.githooks/lib/*)
pats=(.forbidden-patterns/*.txt)
echo "✓ dev hooks rendered; core.hooksPath -> .githooks"
echo "  active: pre-commit, commit-msg, ${#libs[@]} scanners, ${#pats[@]} pattern files"
echo "  (gitignored build artifacts — edit the *.template sources, then re-run this script)"
