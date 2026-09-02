# shellcheck shell=bash
# install-manifest.sh — the install manifest: how an upgrade tells "the scaffold
# wrote this and nobody touched it" from "you edited this".
#
# SOURCED (not exec'd) by install.sh before install-lib.sh, so these run in that
# shell with its globals (SCAFFOLD_DIR) and its `set -euo pipefail`.
#
# THE PROBLEM. cp_pattern and cp_scaffold_preserve decide by comparing the
# installed file against the CURRENT template. That answers "is this the same as
# what I ship today", which is not the question being asked. An UNTOUCHED
# install of an OLDER scaffold version differs from today's template for exactly
# the same reason a hand-edit does, so it took the drift branch every time: the
# file was preserved, the run printed "your customizations are kept" to someone
# who had customized nothing, and the new content never arrived. Measured (audit
# hist-01, hist-03, upgrade-path-1, upgrade-path-3): a v0.12.0 install upgraded
# to HEAD keeps a lint.yml with zero check-large-files call sites and pinned
# action SHAs a major version behind; a v0.6.0 install keeps 26 of 37 secret
# patterns, so a SendGrid key still commits clean afterwards, while
# scaffold-doctor.sh reports "0 gaps".
#
# THE FIX is provenance, not more comparing. Every file the installer writes is
# recorded in .githooks/.scaffold-manifest as
#
#     <sha256 of exactly what was written> <scaffold version> <path>
#
# On a later run the installed file is hashed again and compared with the
# RECORDED hash, never with a template:
#
#   same    -> nobody has touched it since we wrote it, so it is ours: refresh
#              it to the shipped version and re-record. No backup is taken,
#              because the bytes being replaced are provably a released scaffold
#              file (and .scaffold-bak litter is its own problem: upgrade-path-2).
#   differs -> a genuine hand-edit: preserve and notify, exactly as before.
#   absent  -> a pre-manifest install, or a file the user created: fall back to
#              today's compare-against-the-template behavior, so nothing
#              regresses for an install that predates the manifest.
#
# SCOPE. Only the two drift-preserving policies (cp_pattern,
# cp_scaffold_preserve) consult the manifest, because they are the two that
# mistake an old version for a hand-edit. cp_scaffold already refreshes
# unconditionally, and cp_safe deliberately never auto-replaces a USER-OWNED
# file (ruff.toml, coding-rules.md, .scaffold.toml, the rules docs): that is a
# documented ownership decision, not the bug this fixes, so it is left alone.
# Both still RECORD what they write, so the manifest stays complete.
#
# It also gives every install a recorded version, which nothing on disk carried
# before (audit enh-upgrade-1).

# Defaults mirror install-lib.sh's `: "${FORCE:=0}"` so this file behaves if it
# is ever sourced without install.sh having set the globals first.
: "${SCAFFOLD_DIR:=.}"

# In .githooks/ because that directory exists in every install, is committed by
# every consumer (git needs the hooks in the tree), and is already scaffold
# territory: the manifest is not something a project should have to look at.
SCAFFOLD_MANIFEST=".githooks/.scaffold-manifest"

# Records accumulate here and are written ONCE at the end of the run
# (manifest_flush), rather than rewriting the file per copied file: an install
# writes ~35 files, and three extra processes each is a cost for nothing.
_MANIFEST_PENDING=""

# _sha256 FILE — portable content hash, printed bare. GNU coreutils sha256sum
# where it exists (Linux), otherwise the perl `shasum` that ships with macOS.
# Returns non-zero when neither exists or the file cannot be read, and EVERY
# caller treats that as "no manifest information available", so a host with
# neither tool keeps the pre-manifest behavior instead of losing an install.
_sha256() {
  local out=''
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(sha256sum "$1" 2>/dev/null) || return 1
  elif command -v shasum >/dev/null 2>&1; then
    out=$(shasum -a 256 "$1" 2>/dev/null) || return 1
  else
    return 1
  fi
  out=${out%% *}
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# _scaffold_version — the version being installed, from the package metadata
# that ships in every distribution path (npm tarball, Homebrew libexec, git
# clone). "unknown" when it cannot be read: an entry with an unknown version
# still carries a usable hash, which is the load-bearing half.
_scaffold_version() {
  local v=''
  if [ -f "$SCAFFOLD_DIR/package.json" ]; then
    v=$(awk -F'"' '/^[[:space:]]*"version"[[:space:]]*:/ { print $4; exit }' \
        "$SCAFFOLD_DIR/package.json" 2>/dev/null) || v=''
  fi
  printf '%s' "${v:-unknown}"
}

SCAFFOLD_VERSION="$(_scaffold_version)"

_manifest_header() {
  cat <<'MANIFEST_HEADER'
# ai-coding-rules-scaffold install manifest — written by install.sh, do not edit.
#
# One line per file the installer wrote:  <sha256> <scaffold version> <path>
#
# It records PROVENANCE, so a later upgrade can tell "the scaffold wrote this
# and nobody has touched it" (refresh it: you want the new checks) apart from
# "you edited this" (keep it, and say so). Without it, an untouched install of
# an older version looked exactly like a hand-edit, and so never received new
# guardrail call sites, new secret detectors, or updated pinned action SHAs.
#
# COMMIT THIS FILE. It is how every clone of this repo, and every later upgrade,
# knows what it is looking at. Delete it and the installer falls back to
# comparing against the current templates, which is where the problem started.
MANIFEST_HEADER
}

# manifest_record PATH — remember exactly what was just written there. Silent
# no-op when the file cannot be hashed; a missing entry only costs the old
# behavior.
manifest_record() {
  local dst=$1 hash
  hash=$(_sha256 "$dst") || return 0
  _MANIFEST_PENDING="${_MANIFEST_PENDING}${hash} ${SCAFFOLD_VERSION} ${dst}
"
}

# _manifest_hash PATH — the hash recorded for PATH by an EARLIER run (this run's
# records are still pending in memory), or non-zero when there is none.
_manifest_hash() {
  [ -f "$SCAFFOLD_MANIFEST" ] || return 1
  awk -v p="$1" 'NF == 3 && $3 == p { print $1; found = 1; exit }
                 END { exit(found ? 0 : 1) }' "$SCAFFOLD_MANIFEST"
}

# manifest_says_ours PATH — true only when PATH is byte-identical to what this
# scaffold last wrote there, i.e. nobody has edited it since. False (so: keep
# the user's file) whenever there is any doubt at all: no manifest, no entry, no
# hashing tool, an unreadable file.
manifest_says_ours() {
  local dst=$1 recorded current
  recorded=$(_manifest_hash "$dst") || return 1
  [ -n "$recorded" ] || return 1
  current=$(_sha256 "$dst") || return 1
  if [ "$current" = "$recorded" ]; then
    return 0
  fi
  return 1
}

# manifest_flush — write the run's records, merged with the entries an earlier
# run made for files this run did not touch. Sorted by path so a re-run produces
# a stable diff rather than a reshuffled file.
manifest_flush() {
  local tmp new
  [ -n "$_MANIFEST_PENDING" ] || return 0
  _mkdir_safe "$(dirname "$SCAFFOLD_MANIFEST")" || return 0
  new="${SCAFFOLD_MANIFEST}.new.$$"
  tmp="${SCAFFOLD_MANIFEST}.tmp.$$"
  printf '%s' "$_MANIFEST_PENDING" >"$new" || return 0
  _manifest_header >"$tmp" || { rm -f "$new"; return 0; }
  {
    if [ -f "$SCAFFOLD_MANIFEST" ]; then
      awk 'NR == FNR { if (NF == 3) seen[$3] = 1; next }
           substr($0, 1, 1) == "#" { next }
           NF == 3 && !($3 in seen)' "$new" "$SCAFFOLD_MANIFEST"
    fi
    cat "$new"
  } | LC_ALL=C sort -k3,3 >>"$tmp"
  mv -f "$tmp" "$SCAFFOLD_MANIFEST"
  rm -f "$new"
  _MANIFEST_PENDING=""
  echo "recorded:     $SCAFFOLD_MANIFEST (scaffold version $SCAFFOLD_VERSION), commit it"
}
