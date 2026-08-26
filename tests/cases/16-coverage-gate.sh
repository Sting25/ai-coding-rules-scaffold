# shellcheck shell=bash
# cases/16-coverage-gate.sh — the opt-in patch-coverage workflow must fail on
# FAILING tests, not just on uncovered lines (issue #71). Sourced into the
# driver's shell, so the globals (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) are in scope.
#
# What #71 was: the pytest and vitest steps ended in `|| true`. The intent was to
# tolerate pytest's exit 5 (no tests collected) so an empty suite didn't mask the
# diff-cover verdict — but `|| true` swallows exit 1 too, so a PR with failing
# tests went green. Worse than merely not gating: a failing test still EXECUTES
# the lines it touches and so still writes them into coverage.xml, meaning a PR
# whose new code is covered only by a red test PASSED the patch-coverage gate on
# the strength of that very test.
#
# These assertions run the step's REAL shell body, lifted out of the shipped
# YAML, against a fake pytest with a chosen exit code. Asserting on the text
# ("no `|| true` present") would pass against any rewrite that reintroduced the
# hole by another route; running it cannot.

echo "cases/16 — patch-coverage gate fails on failing tests (#71)"

COV_TPL="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"

# Lift the shell body of a `run: |` step out of the workflow, dedented. The
# `pip install` line is dropped: the point is the exit-code logic around the
# test command, and the test must not reach the network.
_run_block() {
  awk -v step="      - name: $1" '
    $0 == step { found = 1 }
    found && /run: \|/ { inrun = 1; next }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 !~ /^          /) exit
      sub(/^          /, "")
      if ($0 ~ /^pip install/) next
      print
    }
  ' "$COV_TPL"
}

# Run a step body under `bash -e` — the default shell GitHub gives a `run:` step
# — with a fake $2 on PATH exiting $3. Echoes the body's exit status.
#
# `bash -e` is load-bearing, not incidental: under -e the obvious `pytest …;
# rc=$?` never reaches the assignment, so a fix written that way fails the job on
# exit 5 and undoes the tolerance the block exists to provide. Running the body
# under any other shell would hide that.
_run_step_with_fake() {
  local body=$1 tool=$2 code=$3
  local d; d=$(mktemp -d)
  printf '#!/bin/sh\nexit %s\n' "$code" >"$d/$tool"
  chmod +x "$d/$tool"
  # npx is invoked as `npx --no-install vitest …`; fake it as a shim that runs
  # the tool name it was handed, so the real command line is exercised.
  if [ "$tool" = "vitest" ]; then
    printf '#!/bin/sh\nshift\nexec "$@"\n' >"$d/npx"
    chmod +x "$d/npx"
  fi
  printf '%s\n' "$body" >"$d/step.sh"
  local rc=0
  # cd into the SAME empty dir the fake binaries live in, not $WORK, which the
  # driver's bootstrap seeds with a throwaway pyproject.toml (#96/#97). Running
  # from an empty dir makes the body's `[ -f pyproject.toml ]` project-install
  # guard evaluate false on its own, so the real `pip install -e .` it gates
  # never fires here; no per-line filtering of those calls is needed on top of
  # the unconditional `pip install pytest…` line _run_block already drops.
  ( cd "$d" && PATH="$d:$PATH" bash -e "$d/step.sh" ) >/dev/null 2>&1 || rc=$?
  rm -rf "$d"
  printf '%s' "$rc"
}

PYBODY=$(_run_block "Run Python tests with coverage")
JSBODY=$(_run_block "Run frontend tests with coverage")

if [ -z "$PYBODY" ] || [ -z "$JSBODY" ]; then
  echo "  ✗ could not lift the test steps out of coverage.yml.template (step renamed?)"; FAIL=$((FAIL + 1))
else
  # (T) THE BUG: pytest exit 1 (tests FAILED) must fail the job. Under the old
  #     `|| true` this was 0 and the PR went green.
  R=$(_run_step_with_fake "$PYBODY" pytest 1)
  if [ "$R" -ne 0 ]; then
    echo "  ✓ pytest exit 1 (failing tests) fails the coverage job"; PASS=$((PASS + 1))
  else
    echo "  ✗ failing pytest still produced a green coverage job (#71)"; FAIL=$((FAIL + 1))
  fi

  # (T) ...while exit 5 (no tests collected) is still tolerated, which is the
  #     entire reason the original `|| true` was there. A fix that gates on
  #     failure by ALSO failing here would have traded one bug for another.
  R=$(_run_step_with_fake "$PYBODY" pytest 5)
  if [ "$R" -eq 0 ]; then
    echo "  ✓ pytest exit 5 (no tests collected) is still tolerated"; PASS=$((PASS + 1))
  else
    echo "  ✗ exit 5 now fails the job — the no-tests tolerance regressed (rc=$R)"; FAIL=$((FAIL + 1))
  fi

  # (T) A clean run stays clean, so diff-cover gets its say.
  R=$(_run_step_with_fake "$PYBODY" pytest 0)
  if [ "$R" -eq 0 ]; then
    echo "  ✓ pytest exit 0 passes through to the diff-cover gate"; PASS=$((PASS + 1))
  else
    echo "  ✗ a passing pytest failed the step (rc=$R)"; FAIL=$((FAIL + 1))
  fi

  # (T) Every other non-zero code fails too — 2 interrupted, 3 internal error,
  #     4 usage. 4 is the one that matters most in practice: a typo'd pytest
  #     invocation collecting nothing would otherwise look like an empty suite.
  R=$(_run_step_with_fake "$PYBODY" pytest 4)
  if [ "$R" -ne 0 ]; then
    echo "  ✓ pytest exit 4 (usage error) fails rather than reading as 'no tests'"; PASS=$((PASS + 1))
  else
    echo "  ✗ pytest usage error was swallowed — only 5 may be tolerated"; FAIL=$((FAIL + 1))
  fi

  # (T) The frontend half: a failing vitest run must fail the job as well.
  #     vitest has no distinct no-tests-collected code, so there is nothing to
  #     tolerate here — --passWithNoTests covers the empty case by exiting 0.
  R=$(_run_step_with_fake "$JSBODY" vitest 1)
  if [ "$R" -ne 0 ]; then
    echo "  ✓ vitest exit 1 (failing tests) fails the coverage job"; PASS=$((PASS + 1))
  else
    echo "  ✗ failing vitest still produced a green coverage job (#71)"; FAIL=$((FAIL + 1))
  fi

  # (T) ...and the empty-suite case is handled by the flag, not by swallowing.
  if printf '%s' "$JSBODY" | grep -qF -- "--passWithNoTests"; then
    echo "  ✓ vitest empty suite handled by --passWithNoTests, not a swallowed exit"; PASS=$((PASS + 1))
  else
    echo "  ✗ vitest step lacks --passWithNoTests — an empty suite would fail the job"; FAIL=$((FAIL + 1))
  fi
fi

reset_repo
