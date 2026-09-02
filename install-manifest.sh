# shellcheck shell=bash
# install-manifest.sh: the install manifest, how an upgrade tells "the scaffold
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
#   same    -> nobody has touched it since we wrote it, so it is ours: back the
#              current bytes up like every other overwrite in this installer,
#              refresh it to the shipped version, and re-record. The backup is
#              NOT redundant: this file is plaintext, unsigned and committed, so
#              a manifest regenerated from the current tree, a botched merge
#              conflict in it, or a stray sed relabels a hand-edit as "ours",
#              and without the copy the next upgrade deletes that edit with no
#              way back (audit verify-2, reproduced: a user edit plus a matching
#              manifest line, one plain install, edit gone). The copies are kept
#              out of git by ensure_backup_gitignore below (upgrade-path-2).
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
#
# The other upgrade-artifact question lives here too: ensure_backup_gitignore at
# the bottom, which keeps the artifacts an upgrade leaves behind (the
# *.scaffold-bak copies, and this file's own scratch files) out of git. Same
# subject (what a re-run leaves on disk and how a project reads it), and
# install-lib.sh is at the module cap.

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

# _sha256 FILE: portable content hash, printed bare. GNU coreutils sha256sum
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

# _scaffold_version: the version being installed, from the package metadata
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
# ai-coding-rules-scaffold install manifest. Written by install.sh, do not edit.
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

# manifest_record PATH: remember exactly what was just written there. Silent
# no-op when the file cannot be hashed; a missing entry only costs the old
# behavior.
manifest_record() {
  local dst=$1 hash
  hash=$(_sha256 "$dst") || return 0
  _MANIFEST_PENDING="${_MANIFEST_PENDING}${hash} ${SCAFFOLD_VERSION} ${dst}
"
}

# _manifest_hash PATH: the hash recorded for PATH by an EARLIER run (this run's
# records are still pending in memory), or non-zero when there is none.
_manifest_hash() {
  [ -f "$SCAFFOLD_MANIFEST" ] || return 1
  awk -v p="$1" 'NF == 3 && $3 == p { print $1; found = 1; exit }
                 END { exit(found ? 0 : 1) }' "$SCAFFOLD_MANIFEST"
}

# manifest_says_ours PATH: true only when PATH is byte-identical to what this
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

# Set by _manifest_write_failed to the reason the write failed, empty otherwise.
# print_manifest_failure_summary reads it at the end of the run, called from
# install-lib.sh's print_refused_writes_summary.
SCAFFOLD_MANIFEST_ERROR=""

# _manifest_write_failed WHY: a failed manifest write is not a detail to
# swallow. Every failure path here used to `return 0`, so with .githooks at mode
# 555 the shell's own "Permission denied" was the only trace, no summary line
# mentioned it, and install.sh exited 0; the next upgrade then found no entry
# for any file, fell back to comparing against today's templates, and kept every
# untouched older file as a "customization" again, which is the exact bug the
# manifest exists to fix (audit verify-6). Loud now, in the same shape as the
# symlinked-directory refusal: name the file, say what it costs, say what to do.
_manifest_write_failed() {
  SCAFFOLD_MANIFEST_ERROR=$1
  rm -f "${SCAFFOLD_MANIFEST}.new.$$" "${SCAFFOLD_MANIFEST}.tmp.$$" 2>/dev/null || true
  echo "error: could not write $SCAFFOLD_MANIFEST ($1)." >&2
  echo "       The files above were installed, but nothing on disk now records that the" >&2
  echo "       scaffold wrote them, so the NEXT upgrade cannot tell its own untouched" >&2
  echo "       files from your edits: it will keep every drifted file instead of" >&2
  echo "       refreshing it, and new detectors and updated CI pins will not arrive." >&2
  echo "       Make $(dirname "$SCAFFOLD_MANIFEST") writable (or clear whatever sits at" >&2
  echo "       the manifest path) and re-run install.sh." >&2
}

# print_manifest_failure_summary: the end-of-run half of the same report, so the
# failure survives in the SUMMARY rather than only in scrollback. Returns 1, so
# install.sh's `print_refused_writes_summary || exit 1` fails the run: an
# install that did not record what it wrote is incomplete in the same way as one
# that could not write through a symlinked directory.
print_manifest_failure_summary() {
  [ -n "$SCAFFOLD_MANIFEST_ERROR" ] || return 0
  echo ""
  echo "INSTALL INCOMPLETE: the install manifest was not written: $SCAFFOLD_MANIFEST"
  echo "  Reason: $SCAFFOLD_MANIFEST_ERROR"
  echo "  Without it the next upgrade reads every scaffold file as your edit and stops"
  echo "  refreshing them. Fix that path and re-run install.sh."
  return 1
}

# _manifest_sweep_stale: drop the scratch files an INTERRUPTED earlier run left
# behind. manifest_flush writes <manifest>.new.PID and <manifest>.tmp.PID and
# removes both, but a Ctrl-C or a kill between the two left them in .githooks/,
# where nothing cleaned them up and no ignore rule covered them, so the next
# `git add -A` committed them: the same defect as the .scaffold-bak copies
# (audit upgrade-path-2, verify-7). This run's own files carry THIS pid and are
# created after the sweep, so a sweep can never eat a write in progress.
_manifest_sweep_stale() {
  local f
  for f in "$SCAFFOLD_MANIFEST".new.* "$SCAFFOLD_MANIFEST".tmp.*; do
    { [ -f "$f" ] || [ -L "$f" ]; } || continue
    rm -f "$f" 2>/dev/null || true
  done
}

# manifest_flush: write the run's records, merged with the entries an earlier
# run made for files this run did not touch. Sorted by path so a re-run produces
# a stable diff rather than a reshuffled file. Every step's status is checked:
# see _manifest_write_failed above for why silence was the wrong answer.
manifest_flush() {
  local tmp new dir
  [ -n "$_MANIFEST_PENDING" ] || return 0
  _manifest_sweep_stale
  dir=$(dirname "$SCAFFOLD_MANIFEST")
  new="${SCAFFOLD_MANIFEST}.new.$$"
  tmp="${SCAFFOLD_MANIFEST}.tmp.$$"
  if ! _mkdir_safe "$dir"; then
    _manifest_write_failed "$dir is not a real directory this install can write into"
    return 0
  fi
  # A symlink or a directory at the manifest path: `mv -f` would replace
  # someone's link, or move the new file INSIDE the directory and report
  # success, leaving nothing readable where the next run looks.
  if [ -L "$SCAFFOLD_MANIFEST" ] \
     || { [ -e "$SCAFFOLD_MANIFEST" ] && [ ! -f "$SCAFFOLD_MANIFEST" ]; }; then
    _manifest_write_failed "$SCAFFOLD_MANIFEST exists and is not a regular file"
    return 0
  fi
  if ! printf '%s' "$_MANIFEST_PENDING" >"$new"; then
    _manifest_write_failed "this run's records could not be written to $new"
    return 0
  fi
  if ! _manifest_header >"$tmp"; then
    _manifest_write_failed "the header could not be written to $tmp"
    return 0
  fi
  if ! {
    if [ -f "$SCAFFOLD_MANIFEST" ]; then
      awk 'NR == FNR { if (NF == 3) seen[$3] = 1; next }
           substr($0, 1, 1) == "#" { next }
           NF == 3 && !($3 in seen)' "$new" "$SCAFFOLD_MANIFEST"
    fi
    cat "$new"
  } | LC_ALL=C sort -k3,3 >>"$tmp"; then
    _manifest_write_failed "the merged entries could not be written to $tmp"
    return 0
  fi
  if ! mv -f "$tmp" "$SCAFFOLD_MANIFEST"; then
    _manifest_write_failed "$tmp could not be moved into place"
    return 0
  fi
  rm -f "$new"
  _MANIFEST_PENDING=""
  echo "recorded:     $SCAFFOLD_MANIFEST (scaffold version $SCAFFOLD_VERSION), commit it"
}

# ensure_backup_gitignore: the other half of the same problem. Making the
# backups non-executable stops them being RUN, not being COMMITTED. Nothing in
# the installer had ever touched .gitignore, so every upgrade left untracked
# *.scaffold-bak files that the next `git add -A` swept into the repo (measured:
# 6 of them after a v0.8.0 -> HEAD upgrade, 2 of those in .githooks/). Add the
# two ignore rules once, idempotently, and say so. Appended rather than written,
# because .gitignore is the project's file; a symlinked one is left alone with
# the rules printed instead, the same A7 posture as every other scaffold path.
#
# The rules: the backup copies an overwrite leaves beside the file it replaced,
# and the scratch files an interrupted manifest write leaves in .githooks/
# (verify-7). Both are local state a routine `git add -A` used to commit.
SCAFFOLD_GITIGNORE_RULES='*.scaffold-bak
*.scaffold-bak.*
.githooks/.scaffold-manifest.new.*
.githooks/.scaffold-manifest.tmp.*'

ensure_backup_gitignore() {
  local gi=".gitignore" rule missing=''
  if [ -L "$gi" ]; then
    echo "skip (exists, symlink): .gitignore, left untouched. Add these rules by hand, or an install artifact can be committed:"
    printf '%s\n' "$SCAFFOLD_GITIGNORE_RULES" | sed 's/^/                        /'
    return 0
  fi
  # Per RULE, not per block: an install that predates a rule (the manifest
  # scratch files arrived after the backup copies did) still gets the missing
  # one, and a re-run appends nothing.
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    if [ -f "$gi" ] && grep -qxF "$rule" "$gi"; then
      continue
    fi
    missing="${missing}${rule}
"
  done <<RULES
$SCAFFOLD_GITIGNORE_RULES
RULES
  [ -n "$missing" ] || return 0
  # Append on its own line even if the existing file has no trailing newline.
  if [ -f "$gi" ] && [ -s "$gi" ] && [ -n "$(tail -c 1 "$gi")" ]; then
    printf '\n' >>"$gi"
  fi
  # Delimited, so uninstall.sh can take exactly this block back out again and
  # nothing else (the same begin/end shape as the CLAUDE.md import block).
  {
    echo ""
    echo "# ai-coding-rules-scaffold:begin"
    echo "# Local install artifacts, never something to commit: the copy install.sh"
    echo "# leaves beside a file it replaces, so an edit of yours is always"
    echo "# recoverable, and the scratch files an interrupted manifest write leaves"
    echo "# behind. uninstall.sh removes this block."
    printf '%s' "$missing"
    echo "# ai-coding-rules-scaffold:end"
  } >>"$gi"
  echo "updated:      .gitignore (ignores the backup copies and manifest scratch files install.sh can leave behind)"
}
