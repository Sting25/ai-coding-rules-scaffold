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

# --- fixture-project helpers ------------------------------------------------
# Case files build their own throwaway projects, install the scaffold into
# them, and assert against the result. Until now that install ran inside
# "( cd "$t" && ... && install.sh ... ) >/dev/null 2>&1", with the whole
# thing called as "T=$(some_helper)": bash disables errexit inside a "$(...)"
# command substitution unless "shopt -s inherit_errexit" is set (this suite
# doesn't set it), so a failing install.sh inside that subshell did not stop
# anything — the helper still reached its final "printf '%s' "$t"" and handed
# the caller a path, exit 0, with the installer's own stderr thrown away by
# ">/dev/null 2>&1". Whatever the case ran next then failed on a fixture that
# was never actually built, for a reason nobody could see.
#
# Measured: CI run 33922341907 (ubuntu) died in cases/37-doctor-content-drift.sh
# with exit 2 and no failing assertion printed, 0.22s after the case's own
# banner. docd_project's install.sh failed silently exactly as above; the next
# unprotected line ran `grep` over a file the failed install never wrote, grep
# exited 2 for the missing file, pipefail carried that 2 out, and run.sh's own
# `set -euo pipefail` (line 17) killed the whole suite with nothing to say why.
#
# fixture_repo and fixture_install replace that pattern. Both are meant to be
# called as bare statements, never wrapped in "$(...)": that is what lets a
# real failure trip the driver's own set -e instead of being absorbed by the
# command-substitution boundary above.

# fixture_repo VAR — creates a throwaway git repo (mktemp -d, git init, the
# fixture test identity used by every case) and assigns its path to the
# variable named VAR via `printf -v`, so callers write `fixture_repo T` instead
# of `T=$(fixture_repo)`. Runs directly in the caller's shell, not inside a
# "( ... )" subshell and not inside "$(...)": a failed git-init here is a bare
# statement under the driver's `set -e`, so it stops the run loudly with git's
# own error on stderr instead of silently handing back an empty or half-built
# path.
fixture_repo() {
  local __fixture_repo_var=$1 __fixture_repo_dir
  __fixture_repo_dir=$(mktemp -d)
  git -C "$__fixture_repo_dir" init --quiet
  git -C "$__fixture_repo_dir" config user.email "test@test.local"
  git -C "$__fixture_repo_dir" config user.name "Scaffold Test"
  printf -v "$__fixture_repo_var" '%s' "$__fixture_repo_dir"
}

# fixture_install DIR ARGS... — runs "$SCAFFOLD_DIR/install.sh" ARGS... inside
# DIR. Combined stdout+stderr is captured to a log file OUTSIDE the fixture
# (its own mktemp file, not something written under DIR), so a failed install
# never leaves a stray log for a case's content checks to trip over.
#
# On a non-zero exit: print the failing command and its exit code, then the
# last 30 lines of the captured log, to stderr, and `exit 1` — ending the
# whole suite, on purpose, the same way any other unguarded failing command
# under run.sh's `set -e` would. A case that deliberately expects install.sh
# to FAIL (a refusal test) must not call this helper for that install; run it
# directly and assert on it instead.
#
# On success: delete the log and return 0.
fixture_install() {
  local dir=$1
  shift
  local log rc=0
  log=$(mktemp)
  # `rc=$?` must be captured via `|| rc=$?` on the command itself, not read
  # back inside an `if ! ( ... ); then` body: `$?` at that point belongs to
  # the negated `if` test (always 0 once the then-branch is entered), not to
  # install.sh. Measured while writing this: the naive `if !` form reported
  # "FIXTURE INSTALL FAILED (exit 0)" for a real non-zero install.sh failure.
  ( cd "$dir" && "$SCAFFOLD_DIR/install.sh" "$@" ) >"$log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FIXTURE INSTALL FAILED (exit $rc): install.sh $* in $dir" >&2
    tail -n 30 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  return 0
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
