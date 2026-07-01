# shellcheck shell=bash
# install-lib.sh — file-write policy helpers for install.sh.
#
# SOURCED (not executed) by install.sh, so these functions run in that script's
# shell under its `set -euo pipefail` and read its globals (FORCE). Extracted here
# so install.sh stays under the scaffold's own 500-line module-size cap — the
# guardrail the scaffold enforces on every project it installs into, itself
# included. Behavior is identical to when these lived inline in install.sh.

# Default the caller-provided global so this file also lints/behaves standalone.
# install.sh always sets FORCE before sourcing, so this is a no-op there; if the
# lib is ever sourced without it, 0 (= not --force) is the safe default.
: "${FORCE:=0}"

# --- file ownership & the install/upgrade model -----------------------------
# Re-running install.sh is the supported UPGRADE path, so each destination is
# copied through the policy its OWNERSHIP demands:
#
#   cp_scaffold  scaffold-owned CODE — scanners, libs, hooks, CI workflows. These
#                carry security fixes, so a plain re-run REFRESHES them whenever
#                they differ from the shipped version (no --force needed); that's
#                how an upgrader who just re-runs install.sh actually receives the
#                fixes. The prior bytes are recoverable from git + the scaffold,
#                so a routine refresh writes no backup (only --force does).
#   cp_safe      USER-OWNED files — ruff.toml, eslint config, .scaffold.toml,
#                dependabot.yml, the rules docs, etc. A project customizes these,
#                so they're never auto-replaced: skip unless --force (which backs
#                up first). CLAUDE.md / AGENTS.md have their own merge handlers.
#   cp_pattern   .forbidden-patterns/*.txt — the hard case: scaffold-SHIPPED yet
#                user-EXTENDED (teams append their own rows). Auto-overwriting
#                would clobber those rows, so a re-run only NOTIFIES on drift and
#                keeps the user's file; --force backs up + replaces so the user's
#                additions survive in .scaffold-bak for manual merge-back.
#
# The three policies share one write MECHANISM (_cp_replace) and one backup
# routine (_backup), so the A7 symlink defenses live in exactly one place.

# _cp_replace SRC DST — the actual write. `[ -e ]` alone is false for a DANGLING
# symlink and follows a LIVE one, so a pre-existing symlink at a scaffold path
# used to make `cp` follow it and write the scanner to the link's target OUTSIDE
# the repo. We `rm -f` the destination first (dropping any symlink) so we always
# write a real regular file IN the tree, never THROUGH a link.
_cp_replace() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  rm -f "$dst"
  cp "$src" "$dst"
}

# _backup DST — copy an existing file/symlink aside to <dst>.scaffold-bak[.N]
# before it is replaced, so no local edit is ever silently destroyed. `-P` backs
# up a symlink AS the link, never the dereferenced target content. Returns non-zero
# when all >99 slots are taken; callers treat that as "skip this one file, keep
# going" (`|| return 0`) — never abort, and never overwrite without a backup.
_backup() {
  local dst=$1
  local bak="${dst}.scaffold-bak" n=0
  while [ -e "$bak" ] || [ -L "$bak" ]; do
    n=$((n + 1))
    if [ "$n" -gt 99 ]; then
      echo "error: too many .scaffold-bak files for $dst — clean some up." >&2
      echo "       Skipping this one file (left untouched); re-run after cleanup." >&2
      return 1
    fi
    bak="${dst}.scaffold-bak.${n}"
  done
  cp -P "$dst" "$bak"
  echo "backed up:    $dst -> $bak"
}

# cp_safe SRC DST — USER-OWNED file. Install if absent; otherwise leave it alone
# unless --force (which backs up the differing file, then replaces it).
cp_safe() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst — left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        echo "skip (exists): $dst  — left untouched (use --force to replace)"
      fi
      return
    fi
    # --force: back up before overwriting, but only when it actually differs. A
    # symlink is never compared through (`-L` short-circuits) and always replaced.
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# cp_scaffold SRC DST — SCAFFOLD-OWNED code. Refreshes on diff so security fixes
# reach upgraders on a plain re-run. Identical → silent no-op. A symlink planted
# at a scaffold-owned path is always replaced with the real scanner (better than
# leaving a dead link there) and never written through. No backup on a routine
# refresh — the prior bytes are scaffold code, recoverable from git history and
# the scaffold repo; --force still backs up first for parity with cp_safe.
cp_scaffold() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # Already current? Never compare THROUGH a symlink (A7).
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    [ "$FORCE" -eq 1 ] && { _backup "$dst" || return 0; }
    _cp_replace "$src" "$dst"
    echo "updated:      $dst (refreshed to the shipped version)"
    return
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# cp_pattern SRC DST — .forbidden-patterns/*.txt. Install if absent; if it drifts
# from the shipped version, NOTIFY (the user may have added rows; new shipped
# rules may be worth merging) but keep the user's file. --force backs up + writes
# the shipped version, so the user's additions survive in .scaffold-bak.
cp_pattern() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst — left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        echo "note (drift):  $dst differs from the shipped patterns — your customizations are kept. Diff against forbidden-patterns/$(basename "$dst").template for new rules to merge, or re-run with --force to replace (backs yours up to .scaffold-bak)."
      fi
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# chmod +x only a real regular file. A scaffold path that cp_safe deliberately
# SKIPPED because it's a (possibly dangling) symlink must not abort the install
# via a chmod that follows a broken link and fails under set -e — nor should we
# flip the mode of a skipped, user-owned file.
mkx() { if [ -f "$1" ]; then chmod +x "$1"; fi; }
