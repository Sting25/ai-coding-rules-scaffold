# shellcheck shell=bash
# uninstall-drop-lang.sh: `uninstall.sh --drop-lang=<name>`, the one supported
# way to say "this project has deliberately stopped using this language".
#
# SOURCED (not exec'd) by uninstall.sh, on demand, so it runs in that shell with
# its globals (DRY_RUN) and its `set -euo pipefail`, and calls its force_remove.
# Extracted rather than inlined to keep uninstall.sh under the scaffold's own
# 500-line cap, the same reason install.sh sources install-lib.sh.
#
# THE PROBLEM. check-patterns fails CLOSED when .githooks/.scaffold-manifest
# records a .forbidden-patterns/<name>.txt that is no longer in the checkout
# (#159). It has to: auto-discovery can only iterate files that EXIST, so a
# config someone untracked with `git rm --cached` is indistinguishable from a
# language the project never installed — both absent, both scanning nothing,
# both exiting 0 — and every rule that file carried stops running in CI and in
# every fresh clone with no output anywhere. The manifest entry is the one thing
# on disk that tells the two apart, so entry-plus-no-file is a REMOVAL and
# fails.
#
# The cost of that, before this file existed: there was no legitimate way to
# drop a language. install.sh is purely additive (no negative flag) and
# manifest_flush merges forward every entry a run did not touch, so a project
# that genuinely stopped using Go and deleted go.txt kept a stale entry and
# failed the guard FOREVER, with no route out but hand-editing the manifest —
# a file whose own header says "do not edit", and the last habit this scaffold
# should be teaching, since a hand-edited manifest is also how a real
# customization gets relabelled as "ours" and overwritten (see install-manifest.sh).
#
# THE FIX is an EXPLICIT statement of intent, which is what this call is. It
# removes the pattern file and its manifest entry TOGETHER, leaving exactly the
# "never installed" state the guard is documented to stay silent about.
#
# WHAT THIS DELIBERATELY IS NOT. It is not a prune, and nothing infers it. An
# entry whose file is absent IS the signal the guard fires on, so having
# manifest_flush (or any install/upgrade path) drop such entries automatically
# would mean `git rm --cached .forbidden-patterns/backend.txt` plus any later
# run silently disarms every backend rule again — #159 reopened with extra
# steps. Silence must never be readable as intent: absence is never
# self-authorising, only this call is. That is also why it lives behind a flag
# on the REMOVAL script, cannot be reached from install.sh at all, and cannot be
# combined with --all (which drops every language at once by removing
# .forbidden-patterns/ and the manifest outright).
#
# OUT OF SCOPE: secrets.txt and shell.txt. install.sh writes both
# unconditionally, in every mode and for every stack, so neither is a language a
# project can stop using; refusing them here is refusing an incoherent request,
# not withholding a capability.

# Mirrors install-manifest.sh's constant. Not sourced from there: that module is
# install.sh's, carries install-time globals, and its write helpers depend on
# install-lib.sh, none of which uninstall.sh has.
SCAFFOLD_MANIFEST=".githooks/.scaffold-manifest"

# drop_lang NAME: remove .forbidden-patterns/<NAME>.txt and its manifest entry.
# Either half already being gone is fine — what is specified is the END state,
# not a starting one, so the usual case (file already deleted, entry left
# behind, guard failing) and a clean drop are the same call. Neither half
# present is a reported no-op, never a silent one. Honors --dry-run throughout.
# Returns non-zero only for a request that cannot be served: a malformed name, a
# non-optional pattern file, or a manifest that cannot be rewritten.
drop_lang() {
  local name=$1 cfg tmp entry=0 did=0
  # The guard prints a PATH, so accept what a user copies straight out of it as
  # readily as a bare language name; validation runs after normalising.
  case "$name" in .forbidden-patterns/*) name=${name#.forbidden-patterns/} ;; esac
  name=${name%.txt}
  case "$name" in
    '' | *[!A-Za-z0-9_-]*)
      echo "error: --drop-lang takes one bare language name (letters, digits, '_', '-')," >&2
      echo "       e.g. --drop-lang=go for .forbidden-patterns/go.txt." >&2
      return 1 ;;
    secrets | shell)
      echo "error: $name.txt is not optional — install.sh writes it in every mode, for every" >&2
      echo "       stack, so there is no 'this project stopped using it' state to reach:" >&2
      echo "       its rules apply whatever language the project is written in." >&2
      echo "       To remove the whole scaffold instead: uninstall.sh --all" >&2
      return 1 ;;
  esac
  cfg=".forbidden-patterns/$name.txt"
  # Same posture as manifest_flush: a symlink or a directory at the manifest
  # path is never rewritten, because `mv -f` would replace someone's link, or
  # move the rewrite INSIDE the directory and report success.
  if [ -L "$SCAFFOLD_MANIFEST" ] \
     || { [ -e "$SCAFFOLD_MANIFEST" ] && [ ! -f "$SCAFFOLD_MANIFEST" ]; }; then
    echo "error: $SCAFFOLD_MANIFEST exists and is not a regular file — refusing to rewrite it." >&2
    return 1
  fi
  # The same `NF == 3` line shape and comment skip install-manifest.sh's readers
  # and check-patterns' guard use, so all three agree on what an entry is.
  if [ -f "$SCAFFOLD_MANIFEST" ] && awk -v p="$cfg" '
       substr($0, 1, 1) == "#" { next }
       NF == 3 && $3 == p { found = 1 }
       END { exit(found ? 0 : 1) }' "$SCAFFOLD_MANIFEST"; then
    entry=1
  fi
  if [ -e "$cfg" ] || [ -L "$cfg" ]; then
    force_remove "$cfg"
    did=1
  fi
  if [ "$entry" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would update: $SCAFFOLD_MANIFEST (drops the $cfg entry)"
    else
      # Written to a temp and moved into place, so a failure mid-rewrite cannot
      # truncate the manifest. The scratch name is one install.sh already
      # gitignores and sweeps, so an interrupted rewrite leaves nothing a
      # routine `git add -A` can commit.
      tmp="${SCAFFOLD_MANIFEST}.tmp.$$"
      if awk -v p="$cfg" '
           substr($0, 1, 1) == "#" { print; next }
           NF == 3 && $3 == p { next }
           { print }' "$SCAFFOLD_MANIFEST" >"$tmp" && mv -f "$tmp" "$SCAFFOLD_MANIFEST"; then
        echo "updated:      $SCAFFOLD_MANIFEST (dropped the $cfg entry)"
      else
        rm -f "$tmp"
        echo "error:        failed to rewrite $SCAFFOLD_MANIFEST — left untouched" >&2
        return 1
      fi
    fi
    did=1
  fi
  if [ "$did" -eq 0 ]; then
    echo "nothing to do: $name was never installed here — no $cfg, and no entry"
    echo "               for it in $SCAFFOLD_MANIFEST. Nothing was changed."
    return 0
  fi
  echo "Commit the removal and the manifest change TOGETHER: check-patterns goes"
  echo "quiet only once neither the file nor its entry is in the checkout."
  return 0
}
