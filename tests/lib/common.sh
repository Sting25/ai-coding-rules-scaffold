# shellcheck shell=bash
# tests/lib/common.sh — shared library for the scaffold test suite.
# Sourced (no shebang) by tests/run.sh into a single shell process: defines the
# globals, the EXIT-trap cleanup, the assertion helpers, and the bootstrap that
# installs the scaffold into a throwaway repo. Every cases/*.sh file is sourced
# into that same shell, so these globals and functions stay visible to all of
# them. SCAFFOLD_DIR is exported by the driver BEFORE this file is sourced.

WORK=$(mktemp -d -t coding-rules-test.XXXXXX)
HOOK_OUT=$(mktemp)
trap 'rm -rf "$WORK" "$HOOK_OUT"' EXIT

PASS=0
FAIL=0

reset_repo() {
  git reset --hard HEAD >/dev/null 2>&1
  git clean -fd >/dev/null 2>&1 || true
  # Tests that exercise the stash-based scan may leave a stash if the hook
  # was interrupted; clear so the next case starts clean.
  git stash clear >/dev/null 2>&1 || true
}

assert_rejects() {
  # $1 = case name; optional $2 = substring the hook output must contain, so a
  # case can't pass merely because the hook crashed/exited non-zero for an
  # unrelated reason.
  local name=$1 expect=${2:-}
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✗ $name — hook accepted, expected reject"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  elif [ -n "$expect" ] && ! grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✗ $name — rejected, but expected output missing: $expect"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  fi
  reset_repo
}

assert_passes() {
  local name=$1
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name — hook rejected, expected pass"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  reset_repo
}

# --- bootstrap a temp project + install the scaffold ----------------------
# set -euo pipefail is inherited from the driver (run.sh), so a failed cd aborts
# the whole run — same guarantee the original single-file harness had.
# shellcheck disable=SC2164
cd "$WORK"
git init --quiet
git config user.email "test@test.local"
git config user.name "Scaffold Test"
echo '{"name":"test"}' >package.json
echo 'name = "test"' >pyproject.toml
git add . && git commit --quiet -m "fixture" --no-verify  # scaffold-allow: test fixture

"$SCAFFOLD_DIR/install.sh" --both --all-langs --no-verify >/dev/null
git add . && git commit --quiet -m "install scaffold" --no-verify  # scaffold-allow: test fixture

# The scaffold now ships tsconfig.json / prettier / vitest configs by stack.
# Those gate the OPTIONAL tsc + prettier hook steps, which would otherwise fire
# on the synthetic .ts fixtures below (and on vitest.config.ts) wherever a global
# tsc/prettier is on PATH — e.g. GitHub's ubuntu runner — failing the regex unit
# tests for the wrong reason. Remove them here so the pattern/secret cases stay
# isolated to the layer they test; config DELIVERY is verified in its own fresh
# install near the end, and the dedicated tsc test (case 42) makes its own
# tsconfig.json on demand.
git rm -q tsconfig.json .prettierrc.json .prettierignore vitest.config.ts
git commit --quiet -m "isolate hook unit tests from optional tsc/prettier steps" --no-verify  # scaffold-allow: test fixture
