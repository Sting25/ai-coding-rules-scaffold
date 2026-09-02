# shellcheck shell=bash
# cases/19-test-workflow.sh: default-on test-execution CI workflow (#97) and
# the two robustness fixes it shares with coverage.yml (#96: project install
# before pytest, vitest gated on being declared rather than package.json
# merely existing). Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR/WORK) and helpers are already in scope. Its
# own file rather than appended to cases/09 or cases/16, both near the
# 500-line cap.
#
# Every assertion here is mutation-shaped: a plain install must WRITE
# tests.yml (removing the install.sh call site would fail it), --coverage-gate
# must yield coverage.yml WITHOUT the plain tests.yml (reverting the
# priority-order fix would fail it), and --no-test-workflow must both skip the
# workflow AND print the recorded-skip line the "capture what you notice and what you defer" rule
# demands (removing either half fails it).

echo "cases/19: default-on test workflow (#97) + robustness fixes (#96)"

TESTS_TPL="$SCAFFOLD_DIR/.github/workflows/tests.yml.template"
COV_TPL="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"

# --- (A) default install writes tests.yml, not coverage.yml ----------------
A=$(mktemp -d)
( cd "$A" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo 'name = "x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$A/.github/workflows/tests.yml" ] \
   && cmp -s "$TESTS_TPL" "$A/.github/workflows/tests.yml" \
   && [ ! -f "$A/.github/workflows/coverage.yml" ] \
   && grep -qF "CI test state: tests run in CI via tests.yml" "$HOOK_OUT"; then
  echo "  ✓ a plain install writes tests.yml and reports the state (#97)"
  PASS=$((PASS + 1))
else
  echo "  ✗ a plain install did not write tests.yml as expected"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$A"

# --- (B) --no-test-workflow installs neither AND records a loud skip -------
B=$(mktemp -d)
( cd "$B" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo 'name = "x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify --no-test-workflow ) >"$HOOK_OUT" 2>&1
if [ ! -f "$B/.github/workflows/tests.yml" ] && [ ! -f "$B/.github/workflows/coverage.yml" ] \
   && grep -qF "SKIPPED: test-execution CI workflow" "$HOOK_OUT" \
   && grep -qF "CI test state: NO test execution in CI (--no-test-workflow given)" "$HOOK_OUT"; then
  echo "  ✓ --no-test-workflow installs neither workflow and records a loud skip"
  PASS=$((PASS + 1))
else
  echo "  ✗ --no-test-workflow did not skip + record as expected"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$B"

# --- (C) --coverage-gate yields coverage.yml WITHOUT the plain tests.yml ---
C=$(mktemp -d)
( cd "$C" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo 'name = "x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify --coverage-gate ) >"$HOOK_OUT" 2>&1
if [ -f "$C/.github/workflows/coverage.yml" ] && [ ! -f "$C/.github/workflows/tests.yml" ] \
   && grep -qF "CI test state: tests + patch-coverage gate via coverage.yml" "$HOOK_OUT"; then
  echo "  ✓ --coverage-gate installs coverage.yml, never alongside tests.yml"
  PASS=$((PASS + 1))
else
  echo "  ✗ --coverage-gate did not produce coverage.yml-without-tests.yml"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$C"

# --- (D) upgrading a default install to --coverage-gate retires the now- ---
#         redundant tests.yml (backed up, not silently deleted) instead of
#         leaving both in place to double-run the suite.
D=$(mktemp -d)
( cd "$D" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo 'name = "x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify --coverage-gate ) >"$HOOK_OUT" 2>&1
if [ -f "$D/.github/workflows/coverage.yml" ] && [ ! -f "$D/.github/workflows/tests.yml" ] \
   && [ -f "$D/.github/workflows/tests.yml.scaffold-bak" ] \
   && grep -qF "removed:      .github/workflows/tests.yml" "$HOOK_OUT"; then
  echo "  ✓ adding --coverage-gate on a later run retires a prior tests.yml (backed up)"
  PASS=$((PASS + 1))
else
  echo "  ✗ upgrade to --coverage-gate did not retire the stale tests.yml as expected"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# --- (E) --no-test-workflow overriding an explicit --coverage-gate is noted,
#         not silently one-or-the-other.
E=$(mktemp -d)
( cd "$E" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo 'name = "x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python --no-verify --coverage-gate --no-test-workflow ) >"$HOOK_OUT" 2>&1
if [ ! -f "$E/.github/workflows/coverage.yml" ] && [ ! -f "$E/.github/workflows/tests.yml" ] \
   && grep -qF "warning: --no-test-workflow overrides --coverage-gate" "$HOOK_OUT"; then
  echo "  ✓ --no-test-workflow overrides --coverage-gate, visibly"
  PASS=$((PASS + 1))
else
  echo "  ✗ combining both flags did not behave / warn as expected"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$E"

# --- (F) vitest job gating: lift the detect step's REAL shell body out of the
#     shipped YAML (same technique as cases/16) and run it against fixture
#     package.json files. Asserting on file TEXT ("grep for present=true")
#     would pass against a rewrite that reintroduced the hole (gating on
#     package.json existing) by another route; running the body cannot.
# $1 = template file, $2 = which `- id: detect` step to lift (1-indexed; both
# templates have exactly one vitest-relevant detect step: in
# tests.yml.template it's the 2nd (the vitest job's, after the pytest job's);
# in coverage.yml.template it's the only one and covers both stacks at once).
_vitest_detect_body() {
  local tpl=$1 target=$2
  awk -v target="$target" '
    /- id: detect/ { seen++ }
    seen == target && /run: \|/ { inrun = 1; next }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 !~ /^          /) exit
      sub(/^          /, "")
      print
    }
  ' "$tpl"
}

_run_detect_with_pkg() {
  # $1 = step body, $2 = package.json content ("" = no package.json at all).
  local body=$1 pkg=$2
  local d out result
  d=$(mktemp -d)
  if [ -n "$pkg" ]; then
    printf '%s\n' "$pkg" >"$d/package.json"
  fi
  out=$(mktemp)
  printf '%s\n' "$body" >"$d/step.sh"
  ( cd "$d" && GITHUB_OUTPUT="$out" bash -e "$d/step.sh" ) >/dev/null 2>&1 || true
  result=$(cat "$out")
  rm -rf "$d" "$out"
  printf '%s' "$result"
}

PKG_NO_VITEST='{"name":"x","devDependencies":{"eslint":"9.0.0"}}'
PKG_WITH_VITEST_DEP='{"name":"x","devDependencies":{"vitest":"^2.0.0"}}'
PKG_WITH_VITEST_SCRIPT='{"name":"x","scripts":{"test":"vitest run"}}'

# _check_vitest_gating LABEL TEMPLATE STEP-INDEX OUTPUT-KEY: a function
# rather than a `for` loop over packed strings, so it never touches this
# shell's positional parameters (this file is SOURCED into the shared driver
# shell, not run as its own process). tests.yml's vitest job writes
# `present=true`; coverage.yml's single combined detect step writes
# `frontend=true` for the same condition.
_check_vitest_gating() {
  local label=$1 tpl=$2 target=$3 key=$4
  local BODY R
  BODY=$(_vitest_detect_body "$tpl" "$target")
  if [ -z "$BODY" ]; then
    echo "  ✗ could not lift the vitest detect step out of $label (step renamed?)"
    FAIL=$((FAIL + 1))
    return
  fi

  R=$(_run_detect_with_pkg "$BODY" "")
  if ! printf '%s' "$R" | grep -qF "${key}=true"; then
    echo "  ✓ [$label] no package.json at all: vitest job stays gated off"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] no package.json still produced: $R"
    FAIL=$((FAIL + 1))
  fi

  R=$(_run_detect_with_pkg "$BODY" "$PKG_NO_VITEST")
  if ! printf '%s' "$R" | grep -qF "${key}=true"; then
    echo "  ✓ [$label] package.json WITHOUT vitest declared stays gated off (#96)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] package.json without vitest still set: $R"
    FAIL=$((FAIL + 1))
  fi

  R=$(_run_detect_with_pkg "$BODY" "$PKG_WITH_VITEST_DEP")
  if printf '%s' "$R" | grep -qF "${key}=true"; then
    echo "  ✓ [$label] vitest in devDependencies is detected"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] vitest in devDependencies was NOT detected"
    FAIL=$((FAIL + 1))
  fi

  R=$(_run_detect_with_pkg "$BODY" "$PKG_WITH_VITEST_SCRIPT")
  if printf '%s' "$R" | grep -qF "${key}=true"; then
    echo "  ✓ [$label] a scripts.test invoking vitest is detected"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] scripts.test invoking vitest was NOT detected"
    FAIL=$((FAIL + 1))
  fi
}

_check_vitest_gating tests "$TESTS_TPL" 2 present
_check_vitest_gating coverage "$COV_TPL" 1 frontend

# --- (G) "Install project" step: the requirements-loop exit-code bug and the
#     installable-pyproject guard. Lifts the REAL step body (same technique as
#     (F) above and cases/16) and runs it under `bash -e` with a fake `pip`
#     that logs its own argv instead of touching the network, so both the
#     step's EXIT CODE and WHICH pip commands it ran are observable.
#
# The bug this regresses: the requirements loop's body used to be
# `[ -f "$req" ] && pip install -r "$req"`, whose own exit status (1, from the
# failed `[ -f ]` test) becomes the exit status of the whole step under
# `bash -e` whenever the LAST candidate file is absent, which is nearly
# always, so the default pytest job would fail for virtually every Python
# consumer even though nothing went wrong. Scenario (c) below is that exact case.
_install_project_body() {
  awk -v step="      - name: Install project (so tests importing the package can collect)" '
    $0 == step { found = 1 }
    found && /run: \|/ { inrun = 1; next }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 !~ /^          /) exit
      sub(/^          /, "")
      print
    }
  ' "$TESTS_TPL"
}

# _run_with_fake_pip BODY [FIXTURE_FILE=CONTENT ...]: writes each fixture
# file, then runs BODY under `bash -e` from that same directory with a fake
# `pip` on PATH that appends its argv to pip.log and exits 0. Sets
# INSTALL_RC (the step's exit code) and INSTALL_LOG (every pip invocation,
# empty if pip was never called) as globals, since a shell function can only
# return a single exit-code integer.
_run_with_fake_pip() {
  local body=$1; shift
  local d fixture path content
  d=$(mktemp -d)
  mkdir -p "$d/bin"
  {
    printf '#!/bin/sh\n'
    printf 'echo "pip $*" >>"%s/pip.log"\n' "$d"
    printf 'exit 0\n'
  } >"$d/bin/pip"
  chmod +x "$d/bin/pip"
  for fixture in "$@"; do
    path=${fixture%%=*}
    content=${fixture#*=}
    printf '%s\n' "$content" >"$d/$path"
  done
  printf '%s\n' "$body" >"$d/step.sh"
  ( cd "$d" && PATH="$d/bin:$PATH" bash -e "$d/step.sh" ) >/dev/null 2>&1
  INSTALL_RC=$?
  INSTALL_LOG=$(cat "$d/pip.log" 2>/dev/null || true)
  rm -rf "$d"
}

IBODY=$(_install_project_body)
if [ -z "$IBODY" ]; then
  echo "  ✗ could not lift the 'Install project' step out of tests.yml.template (step renamed?)"
  FAIL=$((FAIL + 1))
else
  # (a) An installable pyproject.toml alone: exits 0, and DOES run the
  #     editable install (no dev extra declared, so plain `pip install -e .`).
  _run_with_fake_pip "$IBODY" 'pyproject.toml=[project]
name = "x"
version = "0.1"
'
  if [ "$INSTALL_RC" -eq 0 ] && printf '%s' "$INSTALL_LOG" | grep -qF "pip install -e ."; then
    echo "  ✓ (a) installable pyproject.toml alone: exits 0 and runs the editable install"
    PASS=$((PASS + 1))
  else
    echo "  ✗ (a) installable pyproject.toml: rc=$INSTALL_RC log=[$INSTALL_LOG]"
    FAIL=$((FAIL + 1))
  fi

  # (b) requirements.txt alone, no pyproject.toml/setup.py at all: exits 0,
  #     skips the editable install, and DOES install the requirements file.
  _run_with_fake_pip "$IBODY" 'requirements.txt=pytest==9.1.1
'
  if [ "$INSTALL_RC" -eq 0 ] \
     && printf '%s' "$INSTALL_LOG" | grep -qF "pip install -r requirements.txt" \
     && ! printf '%s' "$INSTALL_LOG" | grep -qF "install -e"; then
    echo "  ✓ (b) requirements.txt alone: exits 0 and installs it, no editable install attempted"
    PASS=$((PASS + 1))
  else
    echo "  ✗ (b) requirements.txt alone: rc=$INSTALL_RC log=[$INSTALL_LOG]"
    FAIL=$((FAIL + 1))
  fi

  # (c) THE REGRESSION CASE: nothing at all (no pyproject.toml, no setup.py,
  #     no requirements file). Every candidate in the loop is absent, so under
  #     the old `[ -f "$req" ] && pip install -r "$req"` body this exited 1
  #     even though the step correctly did nothing. Must exit 0 with no pip
  #     invocation at all.
  _run_with_fake_pip "$IBODY"
  if [ "$INSTALL_RC" -eq 0 ] && [ -z "$INSTALL_LOG" ]; then
    echo "  ✓ (c) nothing present: exits 0 with no pip invocation (regression fixed)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ (c) nothing present: rc=$INSTALL_RC (want 0) log=[$INSTALL_LOG] (want empty)"
    FAIL=$((FAIL + 1))
  fi

  # (d) A pyproject.toml that holds only tool config (no [project] table) and
  #     no setup.py: exits 0, and must NOT attempt an editable install; there
  #     is no build backend for `pip install -e .` to target.
  _run_with_fake_pip "$IBODY" 'pyproject.toml=[tool.pytest.ini_options]
testpaths = ["tests"]
'
  if [ "$INSTALL_RC" -eq 0 ] && ! printf '%s' "$INSTALL_LOG" | grep -qF "install -e"; then
    echo "  ✓ (d) tool-config-only pyproject.toml: exits 0, editable install correctly skipped"
    PASS=$((PASS + 1))
  else
    echo "  ✗ (d) tool-config-only pyproject.toml: rc=$INSTALL_RC log=[$INSTALL_LOG]"
    FAIL=$((FAIL + 1))
  fi
fi

# --- (H) tests.yml.template is a valid GitHub Actions workflow -------------
if command -v actionlint >/dev/null 2>&1; then
  G=$(mktemp -d); mkdir -p "$G/.github/workflows"
  cp "$TESTS_TPL" "$G/.github/workflows/tests.yml"
  if ( cd "$G" && actionlint -shellcheck= -pyflakes= .github/workflows/tests.yml ) >"$HOOK_OUT" 2>&1; then
    echo "  ✓ tests.yml.template is a valid GitHub Actions workflow"
    PASS=$((PASS + 1))
  else
    echo "  ✗ tests.yml.template failed actionlint"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$G"
else
  echo "  - skipped tests.yml validation (actionlint not installed)"
fi

reset_repo
