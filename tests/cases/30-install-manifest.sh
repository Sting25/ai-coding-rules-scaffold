# shellcheck shell=bash
# cases/30-install-manifest.sh: the install manifest (install-manifest.sh), the
# provenance record that lets an upgrade tell "the scaffold wrote this and
# nobody touched it" from "you edited this". Sourced into the driver's shell, so
# PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and reset_repo are already in scope.
#
# What it fixes. cp_pattern and cp_scaffold_preserve compared the installed file
# against the CURRENT template. An UNTOUCHED install of an OLDER scaffold
# version differs from today's template for exactly the same reason a hand-edit
# does, so every upgrade took the drift branch: the file was kept, the run said
# "your customizations are kept" to someone who had customized nothing, and the
# new content never arrived. Measured on real releases (audit hist-01, hist-03,
# upgrade-path-1, upgrade-path-3): a v0.12.0 install upgraded to HEAD keeps a
# lint.yml with zero check-large-files call sites; a v0.6.0 install keeps 26 of
# 37 secret patterns, so a SendGrid key still commits clean, while
# scaffold-doctor.sh reports "0 gaps".
#
# These cases stage the same shape without needing a real old release: install
# with the shipped templates, then hand the installer a scaffold whose templates
# have MOVED ON, which is exactly what an upgrade is.
#
# Known limitation, asserted below rather than left implied: a file that had
# already drifted BEFORE the manifest existed has no entry, so it stays on the
# old keep-and-notify behavior. The manifest cannot retroactively know what an
# install from two years ago wrote. What it does do is stop claiming the file is
# the user's customization when nothing on disk says so.

echo "cases/30: the install manifest refreshes untouched files on upgrade (audit hist-01/hist-03/upgrade-path-1/upgrade-path-3, enh-upgrade-1)"

# _mf_project: a fresh frontend repo with the scaffold installed from HEAD.
_mf_project() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# _mf_sha FILE: the same portable hash install-manifest.sh records, so these
# assertions compare like with like on both macOS (shasum) and Linux
# (sha256sum) instead of assuming one of the two is installed.
_mf_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# _mf_next_scaffold: a copy of the scaffold whose secrets.txt and lint.yml
# templates have gained content, standing in for "the next release".
_mf_next_scaffold() {
  local t; t=$(mktemp -d)
  mkdir -p "$t/sc"
  cp -R "$SCAFFOLD_DIR/." "$t/sc" 2>/dev/null || true
  rm -rf "$t/sc/.git"
  printf '(?-i)mf_newdetector_[A-Za-z0-9]{20,}\tnew detector added by a later release\n' \
    >>"$t/sc/forbidden-patterns/secrets.txt.template"
  printf '\n# mf-new-ci-step: added by a later release\n' \
    >>"$t/sc/.github/workflows/lint.yml.template"
  printf '%s' "$t/sc"
}

MFNEXT=$(_mf_next_scaffold)

# (T) a plain install writes the manifest, records the version, and records the
#     files it wrote. This is enh-upgrade-1: before it, nothing on disk said
#     which scaffold version a repo had.
MF1=$(_mf_project)
MFVER=$(awk -F'"' '/^[[:space:]]*"version"[[:space:]]*:/ { print $4; exit }' "$SCAFFOLD_DIR/package.json")
if [ -f "$MF1/.githooks/.scaffold-manifest" ] \
   && grep -q " $MFVER .githooks/pre-commit\$" "$MF1/.githooks/.scaffold-manifest" \
   && grep -q " $MFVER .forbidden-patterns/secrets.txt\$" "$MF1/.githooks/.scaffold-manifest" \
   && grep -q " $MFVER .github/workflows/lint.yml\$" "$MF1/.githooks/.scaffold-manifest" \
   && [ "$(awk '$3 == ".githooks/pre-commit" { print $1 }' "$MF1/.githooks/.scaffold-manifest")" \
        = "$(_mf_sha "$MF1/.githooks/pre-commit")" ]; then
  echo "  ✓ an install records every file it wrote, with its sha256 and the scaffold version"; PASS=$((PASS + 1))
else
  echo "  ✗ the install manifest should record path, sha256 and version for each written file"
  sed 's/^/      /' "$MF1/.githooks/.scaffold-manifest" 2>/dev/null || true; FAIL=$((FAIL + 1))
fi

# (T) THE FLAGSHIP. An UNTOUCHED .forbidden-patterns/secrets.txt from an earlier
#     version is refreshed silently on upgrade, so a detector added upstream
#     actually reaches the project. Asserts the wanted artifact (the new
#     detector is IN the installed file, and the installed scanner flags it),
#     not merely that no drift note appeared.
# The bytes about to be replaced, captured BEFORE the upgrade so the backup can
# be compared against exactly what it was supposed to save.
MF1_PRE=$(_mf_sha "$MF1/.forbidden-patterns/secrets.txt")
( cd "$MF1" && "$MFNEXT/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'mf_newdetector_' "$MF1/.forbidden-patterns/secrets.txt" \
   && grep -q 'updated:.*secrets.txt' "$HOOK_OUT" \
   && ! grep -q 'note (drift):.*secrets.txt' "$HOOK_OUT"; then
  echo "  ✓ an untouched pattern file is refreshed on upgrade, so new detectors arrive"; PASS=$((PASS + 1))
else
  echo "  ✗ an untouched pattern file should be refreshed on upgrade, not kept as 'drift'"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) same for a CI workflow (cp_scaffold_preserve): an untouched lint.yml from
#     an earlier version gains the upstream step instead of being frozen with
#     stale action pins under a "your customizations" note.
if grep -q 'mf-new-ci-step' "$MF1/.github/workflows/lint.yml" \
   && grep -q 'updated:.*lint.yml' "$HOOK_OUT" \
   && ! grep -q 'note (drift):.*lint.yml' "$HOOK_OUT"; then
  echo "  ✓ an untouched CI workflow is refreshed on upgrade, so upstream CI changes arrive"; PASS=$((PASS + 1))
else
  echo "  ✗ an untouched CI workflow should be refreshed on upgrade, not kept as 'drift'"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) THE DATA-LOSS GUARD, and the reason this case no longer asserts an
#     absence. A manifest-proven refresh is still an overwrite, and the "proof"
#     is a plaintext, unsigned, committed file with no integrity check of its
#     own: an agent regenerating the manifest from the current tree, a botched
#     merge-conflict resolution in it, or a stray sed relabels a real
#     customization as "ours", and the refresh then deletes it with nothing to
#     recover from (audit verify-2, reproduced: a user edit plus a manifest line
#     matching the edited bytes, one plain install, the edit gone). So the
#     replaced bytes go to .scaffold-bak like every other overwrite in this
#     installer. Asserted positively: the backup EXISTS, holds exactly the
#     pre-upgrade bytes (not the new ones), is announced, and is gitignored so
#     it cannot become the committed litter that was the argument for skipping
#     it. The manifest must also re-record the NEW hash, or the next upgrade
#     would read its own refresh as a hand-edit.
MF1_BAK="$MF1/.forbidden-patterns/secrets.txt.scaffold-bak"
MF1_REC=$(awk '$3 == ".forbidden-patterns/secrets.txt" { print $1 }' "$MF1/.githooks/.scaffold-manifest")
if [ -f "$MF1_BAK" ] \
   && [ "$(_mf_sha "$MF1_BAK")" = "$MF1_PRE" ] \
   && ! grep -q 'mf_newdetector_' "$MF1_BAK" \
   && grep -q 'backed up:.*secrets.txt' "$HOOK_OUT" \
   && ( cd "$MF1" && git check-ignore -q .forbidden-patterns/secrets.txt.scaffold-bak ) \
   && [ "$MF1_REC" = "$(_mf_sha "$MF1/.forbidden-patterns/secrets.txt")" ] \
   && [ "$MF1_REC" != "$MF1_PRE" ]; then
  echo "  ✓ a manifest-proven refresh backs the replaced bytes up (gitignored) and re-records the new hash"; PASS=$((PASS + 1))
else
  echo "  ✗ a manifest-proven refresh must back the replaced bytes up and re-record the file"
  echo "      backup: ${MF1_BAK}"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF1"

# (T) a REAL hand-edit is still preserved and still notified: the whole point of
#     the manifest is telling the two apart, so this is the half that must not
#     regress. The user's line survives, the shipped one does not arrive, and
#     the note now says plainly that this is an edit.
MF2=$(_mf_project)
printf '\n(?-i)mf_my_own_rule_[0-9]{6}\ta rule this team added\n' >>"$MF2/.forbidden-patterns/secrets.txt"
( cd "$MF2" && "$MFNEXT/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'mf_my_own_rule_' "$MF2/.forbidden-patterns/secrets.txt" \
   && ! grep -q 'mf_newdetector_' "$MF2/.forbidden-patterns/secrets.txt" \
   && grep -q 'note (drift):.*secrets.txt' "$HOOK_OUT" \
   && grep -q 'what the scaffold last wrote there' "$HOOK_OUT"; then
  echo "  ✓ a real hand-edit is still kept and still notified, now named as an edit"; PASS=$((PASS + 1))
else
  echo "  ✗ a hand-edited pattern file should be kept, notified, and named as an edit"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF2"

# (T) --force still wins over the manifest: it backs the user's version up and
#     installs the shipped one, unchanged from the documented escape hatch.
MF3=$(_mf_project)
printf '\n(?-i)mf_my_own_rule_[0-9]{6}\ta rule this team added\n' >>"$MF3/.forbidden-patterns/secrets.txt"
( cd "$MF3" && "$MFNEXT/install.sh" --frontend --no-verify --force ) >"$HOOK_OUT" 2>&1
if grep -q 'mf_newdetector_' "$MF3/.forbidden-patterns/secrets.txt" \
   && grep -q 'mf_my_own_rule_' "$MF3/.forbidden-patterns/secrets.txt.scaffold-bak"; then
  echo "  ✓ --force still replaces a hand-edited pattern file, backing the edit up"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should still back up a hand-edited pattern file and install the shipped one"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF3"

# (T) the documented FALLBACK: a file that drifted while no manifest existed has
#     no entry, so it is kept exactly as before, but the message no longer
#     claims it is the user's customization, because nothing on disk says that.
#     This is the honest half of the pre-manifest upgrade path.
MF4=$(_mf_project)
printf '\n# an edit made before any manifest existed\n' >>"$MF4/.github/workflows/lint.yml"
rm -f "$MF4/.githooks/.scaffold-manifest"
( cd "$MF4" && "$MFNEXT/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -q 'an edit made before any manifest existed' "$MF4/.github/workflows/lint.yml" \
   && grep -q 'note (drift):.*lint.yml' "$HOOK_OUT" \
   && grep -q 'predates the install manifest' "$HOOK_OUT" \
   && ! grep -q 'customizations are kept' "$HOOK_OUT"; then
  echo "  ✓ a pre-manifest drifted file is kept, and the note admits it cannot tell why"; PASS=$((PASS + 1))
else
  echo "  ✗ a pre-manifest drifted file should be kept with an honest, non-claiming note"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF4"

# (T) a manifest entry is never written for a file the installer did NOT write:
#     recording a drifted file would make the next run believe the scaffold
#     produced those bytes and refresh straight over the user's edit. This is
#     the assertion that stops the mechanism becoming a data-loss path.
MF5=$(_mf_project)
printf '\n# a local CI customization\n' >>"$MF5/.github/workflows/lint.yml"
( cd "$MF5" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
MF5_REC=$(awk '$3 == ".github/workflows/lint.yml" { print $1 }' "$MF5/.githooks/.scaffold-manifest" 2>/dev/null || true)
MF5_NOW=$(_mf_sha "$MF5/.github/workflows/lint.yml")
( cd "$MF5" && "$MFNEXT/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ -n "$MF5_REC" ] && [ "$MF5_REC" != "$MF5_NOW" ] \
   && grep -q 'a local CI customization' "$MF5/.github/workflows/lint.yml"; then
  echo "  ✓ a drifted file is never re-recorded, so a later upgrade cannot overwrite the edit"; PASS=$((PASS + 1))
else
  echo "  ✗ a drifted file must keep its ORIGINAL manifest hash and survive the next upgrade"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF5"

# (T) a manifest write that CANNOT happen is loud and fails the run. Every
#     failure path in manifest_flush used to `return 0`: with .githooks at mode
#     555 the only trace was the shell's own "Permission denied", no summary
#     line mentioned it, and install.sh exited 0, so the project silently
#     reverted to pre-manifest behavior on every later upgrade (audit verify-6).
#     Trigger: something that is not a regular file at the manifest path, which
#     no mode bit can make succeed, so this runs the same way for every user.
MF6=$(_mf_project)
rm -f "$MF6/.githooks/.scaffold-manifest"
mkdir -p "$MF6/.githooks/.scaffold-manifest"
MF6_RC=0
( cd "$MF6" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || MF6_RC=$?
if [ "$MF6_RC" -ne 0 ] \
   && grep -q 'error: could not write .githooks/.scaffold-manifest' "$HOOK_OUT" \
   && grep -q 'INSTALL INCOMPLETE: the install manifest was not written' "$HOOK_OUT" \
   && grep -q 'next upgrade' "$HOOK_OUT"; then
  echo "  ✓ a manifest write that cannot happen names the file, says what it costs, and fails the run"; PASS=$((PASS + 1))
else
  echo "  ✗ a failed manifest write must be named in the summary and must not exit 0 (rc=$MF6_RC)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MF6"

# (T) the same, through the branch the audit actually hit: a read-only
#     .githooks, where the write itself fails rather than being refused up
#     front. A mode bit means nothing to root, so the case asserts whichever
#     outcome is honest for the user running it: the probe decides which.
MF7=$(_mf_project)
chmod 555 "$MF7/.githooks"
MF7_RC=0
if : >"$MF7/.githooks/.scaffold-probe" 2>/dev/null; then
  rm -f "$MF7/.githooks/.scaffold-probe"
  chmod 755 "$MF7/.githooks"
  ( cd "$MF7" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || MF7_RC=$?
  if [ "$MF7_RC" -eq 0 ] && grep -q 'recorded: .*\.githooks/\.scaffold-manifest' "$HOOK_OUT"; then
    echo "  ✓ a writable .githooks records the manifest (mode bits are not enforced for this user)"; PASS=$((PASS + 1))
  else
    echo "  ✗ a writable .githooks must record the manifest (rc=$MF7_RC)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  ( cd "$MF7" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || MF7_RC=$?
  chmod 755 "$MF7/.githooks"
  if [ "$MF7_RC" -ne 0 ] \
     && grep -q 'error: could not write .githooks/.scaffold-manifest' "$HOOK_OUT" \
     && grep -q 'INSTALL INCOMPLETE: the install manifest was not written' "$HOOK_OUT"; then
    echo "  ✓ a read-only .githooks makes the manifest failure loud instead of exiting 0"; PASS=$((PASS + 1))
  else
    echo "  ✗ a read-only .githooks must report the failed manifest write and fail the run (rc=$MF7_RC)"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
fi
chmod 755 "$MF7/.githooks" 2>/dev/null || true
rm -rf "$MF7"

# (T) the scratch files an INTERRUPTED manifest write leaves behind
#     (.scaffold-manifest.new.PID / .tmp.PID) are cleaned up by the next run and
#     covered by the ignore rules meanwhile, so a routine `git add -A` can never
#     commit one. Same class as the .scaffold-bak litter of upgrade-path-2, and
#     it was reintroduced by the manifest itself (audit verify-7). Both halves
#     are asserted, plus the positive outcome that the run still recorded the
#     manifest it was cleaning up around.
MF8=$(_mf_project)
: >"$MF8/.githooks/.scaffold-manifest.new.999999"
: >"$MF8/.githooks/.scaffold-manifest.tmp.999999"
MF8_IGN=0
if ( cd "$MF8" && git check-ignore -q .githooks/.scaffold-manifest.new.999999 \
     && git check-ignore -q .githooks/.scaffold-manifest.tmp.999999 ); then
  MF8_IGN=1
fi
( cd "$MF8" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ "$MF8_IGN" -eq 1 ] \
   && [ ! -e "$MF8/.githooks/.scaffold-manifest.new.999999" ] \
   && [ ! -e "$MF8/.githooks/.scaffold-manifest.tmp.999999" ] \
   && grep -q 'recorded: .*\.githooks/\.scaffold-manifest' "$HOOK_OUT" \
   && grep -q ' .githooks/pre-commit$' "$MF8/.githooks/.scaffold-manifest"; then
  echo "  ✓ an interrupted write's scratch files are gitignored and swept by the next run"; PASS=$((PASS + 1))
else
  echo "  ✗ manifest scratch files must be ignored (ign=$MF8_IGN) and cleaned up by the next run"
  find "$MF8/.githooks" -maxdepth 1 | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi
rm -rf "$MF8"

rm -rf "$(dirname "$MFNEXT")"
reset_repo
