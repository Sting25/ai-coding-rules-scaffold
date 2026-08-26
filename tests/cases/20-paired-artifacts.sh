# shellcheck shell=bash
# cases/20-paired-artifacts.sh — install-lib.sh's check_paired_artifacts must
# report every half-installed pair issue #96 named (a config half without its
# CI-enforcement half, a local hook half without the CI half it defers to,
# or the tests.yml/coverage.yml selection state from #97) and stay silent on
# a matched or deliberately-chosen pair. Exercised through scaffold-doctor.sh
# (the primary consumer, section "paired artifacts") and once through
# install.sh's own end-of-run summary, so a regression in either caller's
# wiring is caught, not just the shared function in isolation.
#
# Every "reports a finding" assertion below is mutation-shaped: commenting
# out scaffold-doctor.sh's `check_paired_artifacts gap doctor_pair_note` call
# turns every one of them into a failure (verified by hand while writing this
# file — the silence assertions still pass, since silence is also what a
# script with no such call produces, which is exactly why both kinds of
# assertion are needed together).

echo "cases/20 — paired-artifact half-install detection (#96)"

pa_python_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet \
    && echo 'name = "test"' >pyproject.toml \
    && "$SCAFFOLD_DIR/install.sh" --python --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

pa_shell_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet \
    && echo '#!/usr/bin/env bash' >run.sh \
    && "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

pa_frontend_coverage_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet \
    && echo '{"name":"t"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --coverage-gate --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# Mutations that need a variable expanded at run time are shell FUNCTIONS, not
# `bash -c '...'` (same reasoning as cases/18: a single-quoted bash -c with a
# "$VAR" trips SC2016 under CI's `shellcheck -S info`).
pa_add_coverage_gate_rm_rc()  { "$SCAFFOLD_DIR/install.sh" --coverage-gate --no-verify >/dev/null 2>&1 && rm -f .coveragerc; }
pa_add_coverage_gate_keep_rc() { "$SCAFFOLD_DIR/install.sh" --coverage-gate --no-verify >/dev/null 2>&1; }
pa_gitleaks_hook_only() {
  cp "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" .githooks/lib/check-gitleaks \
    && chmod +x .githooks/lib/check-gitleaks
}
pa_gitleaks_ci_only() { cp "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template" .github/workflows/gitleaks.yml; }
pa_gitleaks_both()    { pa_gitleaks_hook_only && pa_gitleaks_ci_only; }
pa_add_coverage_yml_keep_tests() { cp "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template" .github/workflows/coverage.yml; }
pa_rm_tests_yml()     { rm -f .github/workflows/tests.yml; }

# pa_case <name> <project-fn> <want-exit> <expect-substring> <mutation cmd...>
# The mutation runs inside a fresh project built by project-fn; `true` means
# "leave it healthy".
pa_case() {
  local name=$1 projfn=$2 want=$3 expect=$4
  shift 4
  local t rc=0
  t=$("$projfn")
  ( cd "$t" && "$@" ) >/dev/null 2>&1 || true
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ] && grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name (exit $rc, wanted $want, or missing: $expect)"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$t"
}

# pa_case_absent <name> <project-fn> <not-expect-substring> <mutation cmd...>
# Proves a matched/healthy pair state produces NO paired-artifacts finding —
# silence is the assertion, not merely a passing exit code (plenty of other
# things also exit 0).
pa_case_absent() {
  local name=$1 projfn=$2 not_expect=$3
  shift 3
  local t rc=0
  t=$("$projfn")
  ( cd "$t" && "$@" ) >/dev/null 2>&1 || true
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || rc=$?
  if ! grep -qF "$not_expect" "$HOOK_OUT"; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name (found unexpected: $not_expect)"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$t"
}

# (A) .coveragerc <-> coverage.yml. install.sh writes .coveragerc for every
# Python install regardless of --coverage-gate, so the common default state
# (coveragerc present, no coverage.yml) must be a note, not a gap — a doctor
# that gapped on this would be red on nearly every default Python install.
pa_case "a default Python install's .coveragerc-without-coverage.yml is a note" \
  pa_python_project 0 "it has no effect until the patch-coverage gate is installed too" true

# The inverse direction is the real anomaly: coverage.yml only ever lands via
# --coverage-gate, which writes .coveragerc for a Python project in that same
# run, so a Python project with coverage.yml but no .coveragerc means the
# config half was deleted or never restored.
pa_case "coverage.yml without .coveragerc on a Python project is a gap" \
  pa_python_project 1 "pytest-cov has no local config to read coverage settings from" \
  pa_add_coverage_gate_rm_rc

pa_case_absent "coveragerc + coverage.yml together produce no paired-artifact finding (note)" \
  pa_python_project "it has no effect until the patch-coverage gate is installed too" \
  pa_add_coverage_gate_keep_rc
pa_case_absent "coveragerc + coverage.yml together produce no paired-artifact finding (gap)" \
  pa_python_project "pytest-cov has no local config to read coverage settings from" \
  pa_add_coverage_gate_keep_rc

# A frontend-only --coverage-gate install legitimately has coverage.yml with
# no .coveragerc (vitest coverage does not read it) — must NOT be a gap.
pa_case_absent "coverage.yml without .coveragerc on a non-Python project is not a gap" \
  pa_frontend_coverage_project "pytest-cov has no local config to read coverage settings from" true

# (B) local gitleaks hook <-> gitleaks CI workflow. check-gitleaks tells every
# commit that CI is the authoritative gate; if CI does not exist, that is a
# promise nothing keeps.
pa_case "a local gitleaks hook without the CI gate is a gap" \
  pa_shell_project 1 "there is no CI gate behind it" pa_gitleaks_hook_only

# The inverse (CI-only, no local pass) is a documented, valid strategy —
# CI remains the unskippable, authoritative gate — so it is a note.
pa_case "the gitleaks CI workflow without a local hook is a note (CI-only is valid)" \
  pa_shell_project 0 "valid CI-only posture" pa_gitleaks_ci_only

pa_case_absent "gitleaks hook + CI together produce no paired-artifact finding (gap)" \
  pa_shell_project "there is no CI gate behind it" pa_gitleaks_both
pa_case_absent "gitleaks hook + CI together produce no paired-artifact finding (note)" \
  pa_shell_project "valid CI-only posture" pa_gitleaks_both

# (C) tests.yml <-> coverage.yml (#97's default-on test execution): never
# both (they would run the suite twice — a note, both DO still run), never
# neither in a repo that has scaffold CI at all (a gap — exactly #97's bug,
# now detectable after the fact instead of only at install time).
pa_case "both tests.yml and coverage.yml present is a note, not a gap" \
  pa_shell_project 0 "this push/PR's suite runs twice" pa_add_coverage_yml_keep_tests

pa_case "no test-execution workflow while lint.yml exists is a gap" \
  pa_shell_project 1 "CI runs lint checks only, and no test ever executes" pa_rm_tests_yml

pa_case_absent "the default tests.yml-only state produces no paired-artifact finding (both)" \
  pa_shell_project "this push/PR's suite runs twice" true
pa_case_absent "the default tests.yml-only state produces no paired-artifact finding (neither)" \
  pa_shell_project "CI runs lint checks only, and no test ever executes" true

# (D) install.sh's own end-of-run summary must report the SAME finding, not
# just scaffold-doctor.sh — proves the shared function is actually wired into
# both callers, not merely defined and used by one of them.
IT=$(mktemp -d)
inst_rc=0
( cd "$IT" && git init --quiet && git config user.email t@test.local && git config user.name Test \
  && echo '#!/usr/bin/env bash' >run.sh \
  && "$SCAFFOLD_DIR/install.sh" --shell --gitleaks-hook --no-verify ) >"$HOOK_OUT" 2>&1 || inst_rc=$?
if [ "$inst_rc" -eq 0 ] && grep -qF "warning: the local gitleaks pre-commit pass is installed" "$HOOK_OUT"; then
  echo "  ✓ install.sh's own end-of-run summary reports the same gap (advisory: exit stays 0)"
  PASS=$((PASS + 1))
else
  echo "  ✗ install.sh did not report the paired-artifact gap in its own summary (exit $inst_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$IT"

reset_repo
