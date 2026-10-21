# shellcheck shell=bash
# cases/46-block-message-bypass.sh: what a hook prints when it blocks must not
# offer the bypass AGENTS.md tells the agent not to take. Sourced into the
# driver's shell, so PASS/FAIL/HOOK_OUT/WORK and reset_repo are in scope.
#
# Why (issue #212): the generic pre-commit failure banner used to print
# `--no-verify` on EVERY failure, and agent-precheck told every blocked agent to
# append a `scaffold-allow` marker. The block message is the one text an agent
# is guaranteed to read at the moment it decides, so the bypass the rules call a
# last resort became the default route. AGENTS.md "Git discipline" allows
# `--no-verify` only when the hook's own refusal prints it (forbidden-pattern
# config removal, a confirmed secret-scan false positive); "Fix the file, not
# the check" says a suppression needs a recorded reason and the user's go-ahead.
#
# The agent-precheck half of this lives in cases/07 (it needs jq, so it sits
# inside that file's existing jq gate).

echo ""
echo "block messages do not offer the bypass:"
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver
cd "$WORK"
reset_repo

# The strings are assembled so this file carries neither the bypass flag nor the
# old phrases verbatim (shell.txt flags a literal `git ... --no-verify`).
BM_FLAG="--no""-verify"
BM_OLD_BANNER="use 'git commit $BM_FLAG' to skip"
BM_OLD_MARKER="append a comment containing 'scaffold""-allow'"

# 46a. A generic failure (a forbidden pattern in a staged file) prints the
#      banner, and the banner does not name the bypass.
echo 'print("debug")' >app.py
git add app.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ generic failure: hook accepted a forbidden pattern, expected reject"; FAIL=$((FAIL + 1))
elif ! grep -qF "Pre-commit failed" "$HOOK_OUT"; then
  echo "  ✗ generic failure: rejected, but the failure banner is missing"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF -e "$BM_FLAG" "$HOOK_OUT"; then
  echo "  ✗ generic failure: the banner still names the bypass flag"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
else
  echo "  ✓ generic pre-commit failure output does not contain the bypass flag"; PASS=$((PASS + 1))
fi

# 46b. The banner tells the reader to fix the cause, fix a wrong check, and
#      report a refusal it cannot resolve (same output as 46a).
if grep -qF "fix the check" "$HOOK_OUT" && grep -qF "report it to the user" "$HOOK_OUT"; then
  echo "  ✓ generic failure banner says to fix the cause or the check, and to report"; PASS=$((PASS + 1))
else
  echo "  ✗ generic failure banner is missing the fix-or-report wording"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 46c. The sanctioned refusal keeps the bypass: removing forbidden-pattern
#      config is one of the two cases AGENTS.md names, so its own refusal prints
#      it.
git rm -q .forbidden-patterns/secrets.txt
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ config removal: hook accepted the deletion, expected reject"; FAIL=$((FAIL + 1))
elif grep -qF "deletes forbidden-pattern config" "$HOOK_OUT" && grep -qF -e "$BM_FLAG" "$HOOK_OUT"; then
  echo "  ✓ forbidden-pattern config removal refusal still offers the bypass flag"; PASS=$((PASS + 1))
else
  echo "  ✗ config removal: refusal lost the sanctioned bypass line"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 46d. Self-check on the SOURCE templates (not an installed copy), so a future
#      edit that restores the old text fails here: neither phrase may appear in
#      any shipped hook or forbidden-patterns file.
BM_HITS=$(grep -rnF -e "$BM_OLD_BANNER" -e "$BM_OLD_MARKER" \
  "$SCAFFOLD_DIR/githooks" "$SCAFFOLD_DIR/forbidden-patterns" || true)
if [ -z "$BM_HITS" ]; then
  echo "  ✓ no shipped hook or pattern file carries the old bypass banner or the append-a-marker instruction"; PASS=$((PASS + 1))
else
  echo "  ✗ shipped text still offers the bypass:"; printf '%s\n' "$BM_HITS" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

# 46e. No forbidden-patterns rule MESSAGE (a non-comment line) mentions
#      scaffold-allow: messages say what to do instead; the marker is documented
#      only in the file-format comments.
BM_RULE_HITS=$(grep -n 'scaffold-allow' "$SCAFFOLD_DIR"/forbidden-patterns/*.template | grep -v '^[^:]*:[0-9]*:#' || true)
if [ -z "$BM_RULE_HITS" ]; then
  echo "  ✓ no forbidden-patterns rule message tells the reader to add scaffold-allow"; PASS=$((PASS + 1))
else
  echo "  ✗ a rule message prescribes the scaffold-allow marker:"; printf '%s\n' "$BM_RULE_HITS" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

unset BM_FLAG BM_OLD_BANNER BM_OLD_MARKER BM_HITS BM_RULE_HITS
reset_repo
