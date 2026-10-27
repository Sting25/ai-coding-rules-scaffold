# shellcheck shell=bash
# cases/52-claude-only-scope.sh: the project targets Claude Code only. Cursor
# support (the --cursor flag, cursor-hooks.json.template, the Cursor payload
# branches of agent-precheck) was removed in phase 6; this case keeps it from
# creeping back in. Sourced into the driver's shell, so PASS/FAIL/SKIP/HOOK_OUT/
# SCAFFOLD_DIR are in scope.
#   (a) the two Cursor-only templates are gone
#   (b) no shipped file mentions the removed agent (CHANGELOG.md and
#       SECURITY_AUDIT.md are history and keep their wording)
#   (c) the installer rejects the removed flag instead of ignoring it

echo "cases/52: Claude Code only, no Cursor support"

# (a)
if [ ! -e "$SCAFFOLD_DIR/cursor-hooks.json.template" ] \
   && [ ! -e "$SCAFFOLD_DIR/githooks/lib/credential-read-patterns.txt.template" ]; then
  echo "  ✓ the Cursor-only templates are not shipped"; PASS=$((PASS + 1))
else
  echo "  ✗ cursor-hooks.json.template or credential-read-patterns.txt.template is back"
  FAIL=$((FAIL + 1))
fi

# (b) Match on the tracked-file list, minus the historical docs and this file,
# which names the word on purpose. -I skips binaries.
CO_HITS=$(mktemp)
CO_LIST=$(mktemp)
if git -C "$SCAFFOLD_DIR" ls-files >"$CO_LIST" 2>/dev/null && [ -s "$CO_LIST" ]; then
  ( cd "$SCAFFOLD_DIR" \
    && grep -vxF -e CHANGELOG.md -e SECURITY_AUDIT.md -e tests/cases/52-claude-only-scope.sh "$CO_LIST" \
    | while IFS= read -r co_f; do [ -f "$co_f" ] && printf '%s\n' "$co_f"; done \
    | xargs grep -liI cursor ) >"$CO_HITS" 2>&1 || true
  if [ ! -s "$CO_HITS" ]; then
    echo "  ✓ no shipped file mentions Cursor"; PASS=$((PASS + 1))
  else
    echo "  ✗ these shipped files still mention Cursor:"
    sed 's/^/      /' "$CO_HITS"; FAIL=$((FAIL + 1))
  fi
else
  echo "  - skipped the Cursor-mention scan (SCAFFOLD_DIR is not a git checkout)"
  SKIP=$((SKIP + 1))
fi
rm -f "$CO_HITS" "$CO_LIST"

# (c) An unknown argument is a hard error, before anything is written.
CO_D=$(mktemp -d)
co_rc=0
( cd "$CO_D" && git init --quiet && "$SCAFFOLD_DIR/install.sh" --cursor --no-verify ) >"$HOOK_OUT" 2>&1 || co_rc=$?
if [ "$co_rc" -ne 0 ] && grep -qF "unknown argument: --cursor" "$HOOK_OUT" && [ ! -e "$CO_D/.cursor" ]; then
  echo "  ✓ install.sh --cursor is rejected as an unknown argument"; PASS=$((PASS + 1))
else
  echo "  ✗ install.sh --cursor should exit non-zero with 'unknown argument' (rc=$co_rc)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$CO_D"
