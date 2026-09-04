#!/usr/bin/env bash
# tests/run.sh: verify the scaffold's pre-commit hook actually rejects bad
# code. Creates a throwaway git repo in a temp dir, installs the scaffold,
# stages known-bad and known-good fixtures, and asserts the hook's verdict.
# Exits non-zero on any failed assertion.
#
# Run locally:  ./tests/run.sh
# Run in CI:    same, see .github/workflows/test.yml
#
# This is a thin driver: it resolves the scaffold root, sources the shared
# library (lib/common.sh: globals, the EXIT trap, the assertion helpers, and
# the bootstrap install), then sources each cases/*.sh test-area file in order.
# Everything runs in THIS shell process, so the globals (PASS/FAIL/WORK/...) and
# helper functions stay visible to every case file. Keep the case files sourced
# (not executed) so they share that state.

set -euo pipefail

# Resolve the scaffold root the SAME way the original single-file harness did
# (run.sh lives in tests/, so the root is its parent). Export it BEFORE sourcing
# common.sh: the bootstrap install block and several cases read $SCAFFOLD_DIR.
SCAFFOLD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SCAFFOLD_DIR

HERE="$(cd "$(dirname "$0")" && pwd)"

# --- the case list, and the per-case assertion floor -----------------------
# Order is preserved from the original single-file harness: some cases are
# order-sensitive (shared temp repo state), so only ever APPEND.
#
# Each entry is "<case file>:<floor>", the minimum number of assertions that
# file must contribute. "0 failed" alone cannot tell a complete run from a
# truncated one: a case file that stops early (a stray `return`, a guard that
# turns out false, an edit that drops half the file) takes its assertions with
# it and the run still prints "0 failed". Prepending `return 0` to
# cases/07-agent-commit.sh is the reference reproduction, and a per-case floor
# is what turns it red: that ONE file drops to 0 while every other file still
# meets its own number, so the run fails and names the file that went quiet.
#
# A single global floor cannot do that. One number below the whole suite's total
# only fires once the suite has shrunk past it, so it stays green through the
# loss of an entire case file whenever the rest of the suite is bigger than the
# gap (a MIN_PASS of 383 against a real count of 498 tolerated losing 115
# assertions). Per-file numbers make each file's contribution non-optional,
# whatever the rest of the suite does.
#
# WHAT A FLOOR COUNTS is assertions ATTEMPTED: passed, plus the ones a case
# reported as a COUNTED skip (see the SKIP counter below). The two are the same
# number for every case that does not touch SKIP, so the floors in the list
# below are unchanged by this. It matters for a case whose whole body sits
# behind an optional tool AND which says how many assertions that costs —
# cases/35 (14 workflows, actionlint; plus 1 ungated structural check) and cases/36 (3 verdicts, pytest).
# Counting only passes would force those floors to 0, the bare machine's
# number, and a 0 floor guards nothing: the file could be emptied and the run
# would still be green.
# Counting the declared skips lets them carry their real numbers on every
# machine, so an early stop is caught whether the tool was there or not. A case
# that skips without saying how much it skipped still has to use a 0 floor
# (cases/11, entirely inside a `command -v npm && command -v jq` gate).
#
# Otherwise the floors are MEASURED with the optional, `command -v`-gated tools
# ABSENT from PATH (ruff, actionlint, jq, php, tsc, prettier), because those
# legitimately skip assertions on a bare machine. A machine that has them
# reports MORE for that file, never fewer, so a floor can never fire by luck on
# a complete run.
#
# BUMPING THEM: adding assertions to a case file is expected to raise its
# number. Re-measure with
#     SCAFFOLD_TEST_CASE_COUNTS=1 ./tests/run.sh
# which prints "case-count <file> <assertions>" per file on stderr, run with
# those tools off PATH, and update the entry in the same commit that adds the
# assertions. Never lower a number to make a red run green: below a floor the
# question is which case stopped running.
CASE_FLOORS=(
  "01-size-patterns.sh:22"
  "02-scaffold-allow-ruff-edge.sh:15"
  "03-binary-defense.sh:37"
  "04-shell-config-rename.sh:47"
  "05-frontend-typescript.sh:25"
  "06-hygiene-multilang.sh:38"
  "07-agent-commit.sh:13"
  "08-overrides-gitleaks.sh:14"
  "09-toolchain-clobber.sh:33"
  "10-ci-diff-scope.sh:12"
  "11-npm-bundle.sh:0"
  "12-install-backup-cap.sh:4"
  "13-devsetup-guards.sh:12"
  "14-shell-install-mode.sh:5"
  "15-local-checks.sh:7"
  "16-coverage-gate.sh:6"
  "17-whole-tree-configs.sh:11"
  "18-doctor.sh:36"
  "19-test-workflow.sh:17"
  "20-paired-artifacts.sh:19"
  "21-ci-workflow-drift.sh:25"
  "22-large-file-guard.sh:6"
  "23-npm-cooldown.sh:5"
  "24-claude-skill.sh:5"
  "25-interactive-install.sh:6"
  "26-repo-adaptation-warn.sh:6"
  "27-test-guard.sh:9"
  "28-check-patterns-scope.sh:26"
  "29-install-symlink-dirs.sh:4"
  "30-install-manifest.sh:15"
  "31-install-verify-offer.sh:5"
  "32-uninstall-report.sh:6"
  "33-harness-self-checks.sh:12"
  "34-shipped-pattern-files.sh:11"
  "35-workflow-template-validity.sh:15"
  "36-red-green-verdict.sh:3"
  "37-doctor-content-drift.sh:8"
  "38-components-catalog.sh:33"
  "39-scaffold-assess.sh:10"
  "40-doctor-required-checks.sh:6"
  "41-tsconfig-monorepo.sh:6"
)

# A case file that exists but is NOT in the list above contributes nothing and
# has no floor to miss, so the per-case check cannot see it: adding a file to
# cases/ without wiring it in is the one silent loss the floors do not cover.
# Checked here, BEFORE lib/common.sh installs anything, so a wiring mistake
# costs a second rather than a suite.
_hfloor_unlisted=""
for _hfloor_path in "$HERE"/cases/*.sh; do
  _hfloor_name=${_hfloor_path##*/}
  _hfloor_seen=0
  for _hfloor_entry in "${CASE_FLOORS[@]}"; do
    if [ "${_hfloor_entry%%:*}" = "$_hfloor_name" ]; then
      _hfloor_seen=1
    fi
  done
  if [ "$_hfloor_seen" -eq 0 ]; then
    _hfloor_unlisted="${_hfloor_unlisted}  cases/${_hfloor_name}
"
  fi
done
if [ -n "$_hfloor_unlisted" ]; then
  echo "ERROR: these case files are not in run.sh's CASE_FLOORS list, so they" >&2
  echo "       never run and nothing notices:" >&2
  printf '%s' "$_hfloor_unlisted" >&2
  echo "       Add each one with the assertion count it contributes." >&2
  exit 1
fi

# Shared library: globals, EXIT-trap cleanup, helpers, and the bootstrap that
# installs the scaffold into a throwaway repo and cd's into $WORK.
# shellcheck source=lib/common.sh disable=SC1091
. "$HERE/lib/common.sh"

# --- the skip counter ------------------------------------------------------
# common.sh owns PASS and FAIL; SKIP is the driver's, because it exists for the
# result line printed here. A case whose optional tool is missing (actionlint,
# pytest, ...) prints a "- SKIP:" line and adds the assertions it did NOT run to
# this counter.
#
# WHY IT IS REPORTED. A skipped assertion did not run, and an assertion that
# never ran must not look identical to one that passed. With only "N passed, N
# failed" on the result line, a case that skips its whole body — actionlint off
# PATH, pytest not importable — is indistinguishable from a clean green run: the
# guard is not armed, nothing failed, and the summary says so in the same words
# it uses when the guard did fire. Printing the skips keeps that distinction
# visible in the one line people actually read (and in CI logs, where a skip
# that should never happen on a provisioned runner is the signal that a tool
# install step was dropped).
#
# It is deliberately NOT an error: skipping on a bare machine is the intended
# behaviour. It is not free either — a counted skip still has to meet the case's
# floor (see "WHAT A FLOOR COUNTS" above), so a case may say "these N did not
# run" but may not quietly stop saying how many there were.
SKIP=0

# Bootstrap left us in $WORK; make sure every case file runs from there (some
# cases cd into their own temp dirs and cd back to "$WORK").
cd "$WORK"

# Source each test-area file in order, recording what each one contributed.
SHORT_CASES=""
FLOOR_TOTAL=0
for _hfloor_entry in "${CASE_FLOORS[@]}"; do
  _hfloor_name=${_hfloor_entry%%:*}
  _hfloor_min=${_hfloor_entry##*:}
  # PASS + SKIP: assertions attempted. See "WHAT A FLOOR COUNTS" above.
  _hfloor_before=$((PASS + SKIP))
  # shellcheck source=/dev/null
  . "$HERE/cases/$_hfloor_name"
  _hfloor_ran=$((PASS + SKIP - _hfloor_before))
  FLOOR_TOTAL=$((FLOOR_TOTAL + _hfloor_min))
  if [ -n "${SCAFFOLD_TEST_CASE_COUNTS:-}" ]; then
    printf 'case-count %s %s\n' "$_hfloor_name" "$_hfloor_ran" >&2
  fi
  if [ "$_hfloor_ran" -lt "$_hfloor_min" ]; then
    SHORT_CASES="${SHORT_CASES}  cases/${_hfloor_name}: ran ${_hfloor_ran} assertions, floor is ${_hfloor_min}
"
  fi
done

# --- result and exit status ------------------------------------------------
echo ""
# ${SKIP:-0}: cases/33 re-runs everything below this banner as a standalone
# script with only PASS/FAIL/SHORT_CASES/FLOOR_TOTAL preset, so under `set -u` a
# bare $SKIP would abort that check rather than test it.
_result_skipped=${SKIP:-0}

# The skip clause is appended only when something was actually skipped. A run
# that skipped nothing has no exception to report, and cases/33 reads the count
# back out of a control run with an anchored `passed, 0 failed$`, so a run with
# nothing to say keeps the shape that check pins.
if [ "$_result_skipped" -gt 0 ]; then
  echo "Result: $PASS passed, $FAIL failed, $_result_skipped skipped"
else
  echo "Result: $PASS passed, $FAIL failed"
fi

# A file that went quiet is a red run even with nothing failing: those
# assertions did not fail, they never ran, and "0 failed" over a suite that
# stopped early proves nothing at all.
if [ -n "$SHORT_CASES" ]; then
  echo "" >&2
  echo "ERROR: a case file ran fewer assertions than its floor:" >&2
  printf '%s' "$SHORT_CASES" >&2
  echo "       Find where that file stops early before touching the floor in" >&2
  echo "       tests/run.sh; a floor lowered to fit a short run guards nothing." >&2
  exit 1
fi

# Backstop on the same guarantee: the per-case floors sum to this, so a total
# under it means a floor was skipped rather than met. Same measure as the
# per-case check above — passed plus counted-skipped — so a machine without
# actionlint or pytest is not accused of a short run for skipping them.
if [ "$((PASS + _result_skipped))" -lt "$FLOOR_TOTAL" ]; then
  echo "" >&2
  echo "ERROR: only $((PASS + _result_skipped)) assertions ran or were counted as" >&2
  echo "       skipped; the case floors sum to $FLOOR_TOTAL." >&2
  exit 1
fi

# `exit "$FAIL"` would wrap: an exit status is taken mod 256, so exactly 256
# failing assertions exits 0 and CI goes green on a fully broken suite (and
# 394 would report 138). The count is already printed above; the status only
# has to answer pass/fail, so clamp it to 1.
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
