# shellcheck shell=bash
# cases/25-interactive-install.sh: the --interactive/-i wizard
# (install-interactive.sh). Reads come from fd 3 bound to $SCAFFOLD_TTY, not
# stdin, so these tests feed canned answers through a plain file instead of
# a real terminal — see install-interactive.sh's own header for why. Sourced
# into the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/HOOK_OUT are already in
# scope.

echo "cases/25: --interactive/-i wizard"

_iact_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) no readable tty and no SCAFFOLD_TTY override: errors loudly, installs
# nothing, rather than hanging or silently degrading to a non-interactive
# install.
N=$(_iact_fixture)
if ( cd "$N" && SCAFFOLD_TTY=/nonexistent-for-tests "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1; then
  echo "  ✗ --interactive with no readable tty should error, not succeed"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif ! grep -q "needs a terminal" "$HOOK_OUT" || [ -e "$N/coding-rules.md" ]; then
  echo "  ✗ --interactive with no readable tty should error before installing anything"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
else
  echo "  ✓ --interactive with no readable tty errors and installs nothing"; PASS=$((PASS + 1))
fi
rm -rf "$N"

# (T) every prompt answered empty (bare Enter): each takes its stated
# default — accept the detected stack, every opt-in stays off, the default
# test-execution workflow (plain tests.yml, no coverage gate) is installed.
D=$(_iact_fixture)
: >"$D/answers.txt"  # 14 empty lines: one per prompt in the default flow
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf '\n' >>"$D/answers.txt"; done
( cd "$D" && SCAFFOLD_TTY="$D/answers.txt" "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1 || true
if [ -f "$D/.github/workflows/tests.yml" ] && [ ! -e "$D/.github/workflows/coverage.yml" ] \
   && [ ! -e "$D/.claude/settings.json" ] && [ ! -e "$D/.cursor/hooks.json" ] \
   && [ ! -e "$D/.npmrc" ] && grep -q "Detected stack: frontend" "$HOOK_OUT"; then
  echo "  ✓ an all-default wizard run installs the default frontend + plain tests.yml, no opt-ins"; PASS=$((PASS + 1))
else
  echo "  ✗ an all-default wizard run should install detected-stack + tests.yml with nothing opt-in"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) opting into a feature (--claude equivalent) and the coverage gate: 'y'
# for claude, 'n' for the rest, 'y'/'y' for test-workflow/coverage-gate.
C=$(_iact_fixture)
cat >"$C/answers.txt" <<'EOF'
y
y
n
n
n
n
n
n
n
n
n
n
n
y
y
EOF
( cd "$C" && SCAFFOLD_TTY="$C/answers.txt" "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1 || true
if [ -f "$C/.claude/settings.json" ] && [ -f "$C/.github/workflows/coverage.yml" ] \
   && [ ! -e "$C/.github/workflows/tests.yml" ] && [ ! -e "$C/.cursor/hooks.json" ]; then
  echo "  ✓ wizard 'y' answers map to --claude + --coverage-gate, others stay off"; PASS=$((PASS + 1))
else
  echo "  ✗ wizard 'y' answers should install --claude + --coverage-gate only"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$C"

# (T) answering 'n' to the detected stack switches MODE via the follow-up
# prompt — a frontend-manifest project explicitly picking "shell" installs
# shell-only patterns, not frontend's.
S=$(_iact_fixture)
cat >"$S/answers.txt" <<'EOF'
n
shell
n
n
n
n
n
n
n
n
n
n
n
n
EOF
( cd "$S" && SCAFFOLD_TTY="$S/answers.txt" "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1 || true
if [ ! -e "$S/eslint.config.js" ] && [ ! -e "$S/.forbidden-patterns/frontend.txt" ] \
   && [ -f "$S/.forbidden-patterns/shell.txt" ] && grep -q "Done (mode: shell)" "$HOOK_OUT"; then
  echo "  ✓ declining the detected stack and picking 'shell' installs shell mode"; PASS=$((PASS + 1))
else
  echo "  ✗ declining the detected stack should switch MODE to the picked stack"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$S"

# (T) an unrecognized stack name at the follow-up prompt errors instead of
# silently guessing or installing a mismatched config.
B=$(_iact_fixture)
printf 'n\nbogus\n' >"$B/answers.txt"
if ( cd "$B" && SCAFFOLD_TTY="$B/answers.txt" "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1; then
  echo "  ✗ an unrecognized stack pick should error, not succeed"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif ! grep -q "unrecognized stack 'bogus'" "$HOOK_OUT" || [ -e "$B/coding-rules.md" ]; then
  echo "  ✗ an unrecognized stack pick should error before installing anything"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
else
  echo "  ✓ an unrecognized stack pick errors before installing anything"; PASS=$((PASS + 1))
fi
rm -rf "$B"

# (T) answering 'n' to the test-workflow question sets --no-test-workflow:
# neither tests.yml nor coverage.yml is installed, and the loud skip banner
# fires (matching the flag path cases/19 already covers).
W=$(_iact_fixture)
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13; do printf '\n' >>"$W/answers.txt"; done
printf 'n\n' >>"$W/answers.txt"
( cd "$W" && SCAFFOLD_TTY="$W/answers.txt" "$SCAFFOLD_DIR/install.sh" --interactive --no-verify ) >"$HOOK_OUT" 2>&1 || true
if [ ! -e "$W/.github/workflows/tests.yml" ] && [ ! -e "$W/.github/workflows/coverage.yml" ] \
   && grep -q "SKIPPED: test-execution CI workflow" "$HOOK_OUT"; then
  echo "  ✓ declining a test-execution workflow sets --no-test-workflow with a loud skip"; PASS=$((PASS + 1))
else
  echo "  ✗ declining a test-execution workflow should skip loudly, installing neither CI file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$W"
