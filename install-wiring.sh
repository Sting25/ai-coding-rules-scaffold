#!/usr/bin/env bash
# install-wiring.sh: is a protection actually WIRED IN, and do paired artifacts
# agree with each other?
#
# Extracted from install-lib.sh when that file reached the scaffold's own
# 500-line module cap (issue #84), the same way install-optin.sh and
# install-manifest.sh were before it. The scaffold enforces that cap on its
# users, so it takes the extraction rather than raising the number.
#
# Sourced by install.sh alongside install-lib.sh, and by scaffold-doctor.sh,
# which calls check_paired_artifacts directly.
#
# Why these two belong together: both answer "is this guardrail really running",
# as opposed to "is a file present". A file being on disk is not evidence that
# anything checks anything, which is the confusion that let an install report a
# protection as enabled while nothing was wired in, and let the doctor report
# "0 gaps" over a scanner with no caller.

# _optin_wired FILE NEEDLE: is the protection actually WIRED INTO an existing
# config, or is the file merely present? cp_safe leaves a pre-existing
# .claude/settings.json / .cursor/hooks.json / .npmrc alone, correctly, because
# they are user-owned. So file presence answers "does a config exist here",
# never "does the guardrail run", and both install.sh's summary and
# scaffold-doctor.sh used presence as the signal: with three stub files in
# place, an install printed "skip (exists)" three times, omitted all three from
# its not-enabled list, and the doctor then reported "lib/agent-precheck armed"
# and "0 gaps" while `grep -rl agent-precheck .claude .cursor` found nothing
# (audit code-install-policy-1). Grep for the wiring instead.
_optin_wired() {
  [ -f "$1" ] || return 1
  grep -q "$2" "$1" 2>/dev/null
}

# check_paired_artifacts GAP_FN NOTE_FN (#96): detect scaffold artifacts that
# are meant to arrive in matched pairs (a config half plus the CI half that
# enforces it, or a local hook half plus the CI half it defers to) where only
# one half is on disk. A real downstream repo had `.coveragerc` at root with
# no `.github/workflows/coverage.yml`: every PR showed green CI (lint.yml
# alone) while zero tests had ever executed, and nothing recorded that the
# gate was incomplete. Shared between scaffold-doctor.sh (GAP_FN=gap, affects
# exit status) and install.sh's own end-of-run summary (a plain warn wrapper
# that never fails the run) so the detection logic and the wording live in
# exactly one place.
#
# GAP_FN is called as `fn "<message>" "<fix command>"`, matching the doctor's
# own gap() signature: a half-install that leaves a guardrail's backstop
# silently missing. NOTE_FN is called as `fn "<message>"`, matching note(): a
# state that is worth naming but, measured against what install.sh actually
# does today, is a normal or deliberate outcome rather than a broken one.
check_paired_artifacts() {
  local gap_fn=$1 note_fn=$2
  local looks_python=0
  { [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && looks_python=1

  # 1. .coveragerc vs coverage.yml. install.sh writes .coveragerc for EVERY
  # Python install regardless of --coverage-gate (a harmless standalone
  # config, same policy as ruff.toml), so its presence alone does not mean
  # anyone ever asked for the gate: that is the common, healthy default
  # today, hence a note, not a gap. The inverse is the real anomaly:
  # coverage.yml only ever lands when --coverage-gate is passed, and a
  # Python install writes .coveragerc in that same run, so a Python project
  # with coverage.yml but no .coveragerc means the config half was deleted
  # or never restored. Gated on "looks like a Python project" so a
  # frontend-only --coverage-gate install (which legitimately has no
  # .coveragerc, vitest coverage does not use it) is not misreported.
  if [ -f .coveragerc ] && [ ! -f .github/workflows/coverage.yml ]; then
    "$note_fn" ".coveragerc is present with no .github/workflows/coverage.yml: it has no effect until the patch-coverage gate is installed too (install.sh --coverage-gate)"
  fi
  if [ -f .github/workflows/coverage.yml ] && [ ! -f .coveragerc ] && [ "$looks_python" -eq 1 ]; then
    "$gap_fn" ".github/workflows/coverage.yml is present but .coveragerc is not, and this looks like a Python project: pytest-cov has no local config to read coverage settings from" \
      "re-run install.sh --python (or --both) to restore .coveragerc"
  fi

  # 2. local gitleaks hook vs gitleaks CI workflow. check-gitleaks tells
  # every commit that CI is the authoritative, unskippable gate (see
  # scaffold-doctor.sh's own "opt-in surfaces" section); if that gate does
  # not exist, the hook is making a promise nothing keeps, and --no-verify
  # (or an unwired hooksPath) lets a secret through with nothing behind it.
  # The inverse is a documented, valid strategy: CI-only enforcement, no
  # local friction.
  if [ -f .githooks/lib/check-gitleaks ] && [ ! -f .github/workflows/gitleaks.yml ]; then
    "$gap_fn" "the local gitleaks pre-commit pass is installed (.githooks/lib/check-gitleaks) but .github/workflows/gitleaks.yml is not: every commit is told CI is the authoritative gate, and there is no CI gate behind it" \
      "re-run install.sh --gitleaks-ci"
  fi
  if [ -f .github/workflows/gitleaks.yml ] && [ ! -f .githooks/lib/check-gitleaks ]; then
    "$note_fn" "the gitleaks CI workflow is installed with no local pre-commit pass: CI remains the unskippable, authoritative gate, so this is a valid CI-only posture; add local feedback with install.sh --gitleaks-hook if you want it before push"
  fi

  # 3. tests.yml vs coverage.yml (#97's default-on test execution): never
  # both (they would run the suite twice), never neither in a repo that has
  # scaffold CI at all (lint.yml is the always-installed signal that this IS
  # a scaffold-CI repo). install_test_workflow_ci already prevents "both" on
  # every normal install/upgrade path, so it only reappears via a hand
  # restore; "neither" is exactly the #97 bug restated for detection, and can
  # persist quietly long after a --no-test-workflow install-time notice has
  # scrolled off a terminal.
  if [ -f .github/workflows/tests.yml ] && [ -f .github/workflows/coverage.yml ]; then
    "$note_fn" "both .github/workflows/tests.yml and coverage.yml are installed: coverage.yml already runs the tests, so this push/PR's suite runs twice; remove tests.yml, coverage.yml supersedes it"
  elif [ -f .github/workflows/lint.yml ] \
       && [ ! -f .github/workflows/tests.yml ] \
       && [ ! -f .github/workflows/coverage.yml ]; then
    "$gap_fn" ".github/workflows/lint.yml is installed but neither tests.yml nor coverage.yml is: CI runs lint checks only, and no test ever executes on a PR or push" \
      "re-run install.sh to install the default tests.yml (or install.sh --coverage-gate for the stricter gate)"
  fi

  # 4. agent-precheck vs the runtime config that has to invoke it. --claude and
  # --cursor install .githooks/lib/agent-precheck, but cp_safe SKIPS a
  # pre-existing .claude/settings.json or .cursor/hooks.json, so the precheck
  # ends up on disk and executable with nothing calling it: the one shape where
  # a guardrail is fully installed and cannot possibly run. Exactly the pair
  # this function exists for, and the reason the presence check was never
  # enough (audit code-install-policy-1).
  if [ -f .githooks/lib/agent-precheck ] \
     && ! _optin_wired .claude/settings.json agent-precheck \
     && ! _optin_wired .cursor/hooks.json agent-precheck; then
    "$gap_fn" ".githooks/lib/agent-precheck is installed but nothing invokes it: neither .claude/settings.json nor .cursor/hooks.json mentions agent-precheck, so the agent write/read guard never runs" \
      "merge the hooks block from claude-settings.json.template into .claude/settings.json (or cursor-hooks.json.template into .cursor/hooks.json); install.sh --claude / --cursor only creates those files when they are absent"
  fi
}
