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

# --- doctor: a tuned threshold is a note, a dead gate is a gap --------------------
# coverage.yml.template tells the reader to lower DIFF_COVER_FAIL_UNDER to adopt
# an existing codebase and ratchet up, so 1-99 is legitimate tuning: a NOTE that
# names the value, exit 0. The gap stays for the states where the gate is inert:
# 0 (cannot fail), no variable, or no number in it. AGENTS.md makes every session
# report every gap, so a gap that can never be cleared is a standing false alarm.
echo "cases/16 — doctor classifies DIFF_COVER_FAIL_UNDER (note 1-99, gap otherwise)"

# cov_doctor <value-or-"-"> : fresh project with the coverage gate installed, the
# env value rewritten to $1 ("-" deletes the line), doctor run; sets COV_RC and
# leaves its output in HOOK_OUT.
cov_doctor() {
  local val=$1 t
  fixture_repo t
  echo '#!/usr/bin/env bash' >"$t/run.sh"
  fixture_install "$t" --shell --no-verify --coverage-gate
  if [ "$val" = "-" ]; then
    sed '/^[[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:/d' "$t/.github/workflows/coverage.yml" >"$t/cov.tmp"
  else
    sed "s/^\([[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:\).*/\1 \"$val\"/" "$t/.github/workflows/coverage.yml" >"$t/cov.tmp"
  fi
  mv "$t/cov.tmp" "$t/.github/workflows/coverage.yml"
  COV_RC=0
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || COV_RC=$?
  rm -rf "$t"
}

cov_doctor 90
if [ "$COV_RC" -eq 0 ] && grep -qF "! coverage gate set to 90, not 100" "$HOOK_OUT" \
   && ! grep -q '✗' "$HOOK_OUT"; then
  echo "  ✓ threshold 90: a note naming the value, no gap, doctor exits 0"; PASS=$((PASS + 1))
else
  echo "  ✗ threshold 90 should be a note and exit 0 (got exit $COV_RC)"; grep -i 'coverage\|✗' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

for v in 1 99; do
  cov_doctor "$v"
  if [ "$COV_RC" -eq 0 ] && grep -qF "coverage gate set to $v, not 100" "$HOOK_OUT"; then
    echo "  ✓ threshold $v (edge of the 1-99 band) is a note, exit 0"; PASS=$((PASS + 1))
  else
    echo "  ✗ threshold $v should be a note and exit 0 (got exit $COV_RC)"; grep -i 'coverage\|✗' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
  fi
done

cov_doctor 100
if [ "$COV_RC" -eq 0 ] && grep -qF "✓ patch coverage: 100% of changed lines" "$HOOK_OUT" \
   && ! grep -qF "coverage gate set to" "$HOOK_OUT"; then
  echo "  ✓ threshold 100 stays a plain armed line, no note"; PASS=$((PASS + 1))
else
  echo "  ✗ threshold 100 should be armed with no note (got exit $COV_RC)"; grep -i 'coverage' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

cov_doctor 0
if [ "$COV_RC" -eq 1 ] && grep -qF "✗ DIFF_COVER_FAIL_UNDER is 0" "$HOOK_OUT"; then
  echo "  ✓ threshold 0 is still a gap (the gate cannot fail), exit 1"; PASS=$((PASS + 1))
else
  echo "  ✗ threshold 0 should be a gap and exit 1 (got exit $COV_RC)"; grep -i 'coverage\|✗' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

cov_doctor abc
if [ "$COV_RC" -eq 1 ] && grep -qF "✗ coverage.yml has no DIFF_COVER_FAIL_UNDER" "$HOOK_OUT"; then
  echo "  ✓ non-numeric threshold is still a gap, exit 1"; PASS=$((PASS + 1))
else
  echo "  ✗ non-numeric threshold should be a gap and exit 1 (got exit $COV_RC)"; grep -i 'coverage\|✗' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

cov_doctor -
if [ "$COV_RC" -eq 1 ] && grep -qF "✗ coverage.yml has no DIFF_COVER_FAIL_UNDER" "$HOOK_OUT"; then
  echo "  ✓ missing threshold variable is still a gap, exit 1"; PASS=$((PASS + 1))
else
  echo "  ✗ missing threshold variable should be a gap and exit 1 (got exit $COV_RC)"; grep -i 'coverage\|✗' "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi
unset -f cov_doctor

reset_repo
