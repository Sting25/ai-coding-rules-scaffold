# shellcheck shell=bash
# cases/56-fail-closed-canaries.sh: one refusing fixture per gate, plus the
# strict and summary paths (#210). Sourced into the driver's shell, so
# PASS/FAIL/SKIP/HOOK_OUT/SCAFFOLD_DIR and the fixture_* helpers are in scope.
#
# WHY. A gate that skips or evaluates nothing prints the same silence as a gate
# that passed. Every gate now ends in lib/gate-status, which reports
# `gate=<name> status=ran|skipped|empty checked=<n>` and fails a `ran` with 0
# items (and, under SCAFFOLD_GATE_STRICT=1, any `skipped` that is not a recorded
# `disabled:` decision). These are the canaries: each gate is handed an input it
# must refuse and one it must report as empty, and the skip and strict paths are
# exercised end to end, so a gate that is quietly gutted turns this file red.
#
#   (a) the helper's own contract            (e) the local one-line summary
#   (b) each shell gate: refuse + empty      (f) red-green: zero collected
#   (c) gitleaks: skipped, strict            (g) mutation-diff: fail closed
#   (d) pre-commit in CI mode, per tool      (h) the workflow templates' shape
#
# Gates run from the INSTALLED copy (.githooks/lib/<gate>), with a NUL list on
# stdin and the status env scrubbed, so only what each assertion sets is in play.

echo "cases/56: fail-closed canaries, one refusing fixture per gate (#210)"

c56_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
c56_bad() { echo "  ✗ $1"; sed 's/^/      /' "$HOOK_OUT" | head -20; FAIL=$((FAIL + 1)); }

# c56_has <fixed-string>...: every string appears in $HOOK_OUT.
c56_has() { local s; for s in "$@"; do grep -qF -- "$s" "$HOOK_OUT" || return 1; done; }

# c56_expect <description> <want-rc> <fixed-string>...: the last run's exit code
# and output both match. The output is checked too, so a verdict never passes on
# the exit code alone while the message says something else.
c56_expect() {
  local desc=$1 want=$2
  shift 2
  if [ "$C56_RC" -eq "$want" ] && c56_has "$@"; then c56_ok "$desc"
  else c56_bad "$desc (want exit $want, got $C56_RC)"; fi
}

# c56_run <dir> <stdin-mode> <cmd...>: run a command in <dir> with the status
# env scrubbed. stdin-mode "-" is empty stdin; anything else is the staged path
# list, NUL separated. Sets C56_RC; stdout+stderr land in $HOOK_OUT.
c56_run() {
  local dir=$1 mode=$2 rc=0
  shift 2
  if [ "$mode" = "-" ]; then
    ( cd "$dir" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT "$@" </dev/null ) >"$HOOK_OUT" 2>&1 || rc=$?
  else
    local -a paths; read -ra paths <<<"$mode"
    ( cd "$dir" && printf '%s\0' "${paths[@]}" | env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT "$@" ) >"$HOOK_OUT" 2>&1 || rc=$?
  fi
  C56_RC=$rc
}

# --- (a) the helper's own contract -------------------------------------------
GSX="$SCAFFOLD_DIR/githooks/lib/gate-status.template"
c56_gs() { local rc=0; env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT "$@" >"$HOOK_OUT" 2>&1 || rc=$?; C56_RC=$rc; }

c56_gs bash "$GSX" x ran 0 r
c56_expect "gate-status: ran with 0 items fails and says so" 1 "evaluated 0 items"
c56_gs env SCAFFOLD_GATE_STRICT=1 bash "$GSX" x skipped 0 "tool missing"
c56_expect "gate-status: a skip under SCAFFOLD_GATE_STRICT=1 fails" 1 "::error::gate=x skipped"
c56_gs env SCAFFOLD_GATE_STRICT=1 bash "$GSX" x skipped 0 "disabled: .scaffold.toml [rules.x]"
c56_expect "gate-status: a recorded disabled: skip passes under strict" 0 "status=skipped"
c56_gs bash "$GSX" x empty 0 r
c56_expect "gate-status: empty passes and prints its line" 0 "gate=x status=empty checked=0 reason=r"
c56_gs bash "$GSX" x ran 3 "" 1
c56_expect "gate-status: the gate's own rc passes through" 1 "gate=x status=ran checked=3"
C56_LOG=$(mktemp)
C56_STDOUT=$(env -u SCAFFOLD_GATE_STRICT SCAFFOLD_GATE_LOG="$C56_LOG" bash "$GSX" x ran 2 r 2>&1 || true)
if [ -z "$C56_STDOUT" ] && [ "$(cat "$C56_LOG")" = "gate=x status=ran checked=2 reason=r" ]; then
  c56_ok "gate-status: with SCAFFOLD_GATE_LOG it prints nothing and appends the line"
else
  : >"$HOOK_OUT"; printf 'stdout=[%s] log=[%s]\n' "$C56_STDOUT" "$(cat "$C56_LOG")" >"$HOOK_OUT"
  c56_bad "gate-status: SCAFFOLD_GATE_LOG must capture the line and silence stdout"
fi
rm -f "$C56_LOG"
c56_gs bash "$GSX" x bogus 0 r
c56_expect "gate-status: a bad status is a usage error (exit 2)" 2 "bad status"

# --- (b) one refusing fixture per shell gate ---------------------------------
fixture_repo C56
fixture_install "$C56" --python --no-verify --gitleaks-hook
python3 -c "print('\n'.join('x%d = %d' % (i, i) for i in range(501)))" >"$C56/big.py"
head -c 614400 /dev/zero >"$C56/big.bin"
: >"$C56/.env"
printf 'key = "AKIA''IOSFODNN7EXAMPLE"\n' >"$C56/aws.txt"
printf 'a\n<<<<<<< HEAD\nb\n' >"$C56/conflict.txt"
printf 'print("x")\n' >"$C56/app.py"
printf '# docs\n' >"$C56/README.md"
git -C "$C56" add -A

c56_run "$C56" big.py .githooks/lib/check-size
c56_expect "size refuses a 501-line .py and reports ran 1" 1 "gate=size status=ran checked=1"
c56_run "$C56" big.bin .githooks/lib/check-large-files
c56_expect "large-files refuses a 600 KB blob" 1 "gate=large-files status=ran checked=1"
c56_run "$C56" .env .githooks/lib/check-filenames
c56_expect "filenames refuses .env" 1 "gate=filenames status=ran checked=1"
c56_run "$C56" aws.txt .githooks/lib/check-secrets
c56_expect "secrets refuses an AWS-shaped key" 1 "gate=secrets status=ran checked=1"
c56_run "$C56" conflict.txt .githooks/lib/check-hygiene
c56_expect "hygiene refuses a merge-conflict marker" 1 "gate=hygiene status=ran checked=1"
c56_run "$C56" app.py .githooks/lib/check-patterns
c56_expect "patterns refuses print() in a .py" 1 "gate=patterns status=ran"

c56_run "$C56" README.md .githooks/lib/check-size
c56_expect "size: only a .md staged is empty, exit 0" 0 "gate=size status=empty checked=0"
c56_run "$C56" README.md .githooks/lib/check-patterns
c56_expect "patterns: only a .md staged is empty, exit 0" 0 "gate=patterns status=empty checked=0"
c56_run "$C56" - .githooks/lib/check-hygiene
c56_expect "hygiene: empty stdin is empty, exit 0" 0 "gate=hygiene status=empty checked=0"
c56_run "$C56" - .githooks/lib/check-secrets
c56_expect "secrets: empty stdin is empty, exit 0" 0 "gate=secrets status=empty checked=0"
c56_run "$C56" - .githooks/lib/check-filenames
c56_expect "filenames: empty stdin is empty, exit 0" 0 "gate=filenames status=empty checked=0"

# --- (c) gitleaks: skipped without the binary, failed under strict ------------
C56_NOGL=$(mktemp -d)
for t in bash env cat tr wc; do ln -sf "$(command -v $t)" "$C56_NOGL/$t"; done
if ( hash -r; PATH="$C56_NOGL" command -v gitleaks ) >/dev/null 2>&1; then
  echo "  - SKIP: gitleaks is reachable on the isolated PATH, so the skip path cannot be exercised"
  SKIP=$((SKIP + 2))
else
  c56_run "$C56" README.md env PATH="$C56_NOGL" SCAFFOLD_GATE_STRICT=1 .githooks/lib/check-gitleaks
  c56_expect "gitleaks absent under SCAFFOLD_GATE_STRICT=1 fails, naming gitleaks" 1 "::error::gate=gitleaks skipped"
  c56_run "$C56" README.md env PATH="$C56_NOGL" .githooks/lib/check-gitleaks
  c56_expect "gitleaks absent without strict passes as skipped" 0 "gate=gitleaks status=skipped"
fi

# --- (d)(e) pre-commit in CI mode, once per tool; the local summary -----------
# An isolated PATH with the plumbing the hook needs and none of the tools under
# test, so each tool is genuinely unreachable.
C56_B=$(mktemp -d)
for t in bash env git awk tr wc cat mktemp rm sed grep head tail sort uniq cut basename dirname ls mkdir cp mv date printf sh tee xargs find stat id uname readlink ln touch chmod cmp diff; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$C56_B/$t"
done
C56_UNREACHABLE=1
for t in ruff python3 php phpcs npx node; do
  # hash -r: bash would otherwise answer from commands the driver already ran.
  if ( hash -r; PATH="$C56_B" command -v "$t" ) >/dev/null 2>&1; then C56_UNREACHABLE=0; fi
done

# c56_tool <tool> <setup-fn>: fresh --shell fixture, <setup-fn> stages one file
# plus its config, then the hook runs under strict and must name <tool>.
c56_tool() {
  local tool=$1 setup=$2 d rc=0
  if [ "$C56_UNREACHABLE" -eq 0 ]; then
    echo "  - SKIP: a tool is reachable on the isolated PATH here, so $tool cannot be made unreachable"
    SKIP=$((SKIP + 1)); return 0
  fi
  fixture_repo d
  echo '#!/usr/bin/env bash' >"$d/run.sh"
  fixture_install "$d" --shell --no-verify
  ( cd "$d" && "$setup" && git add -A ) >/dev/null 2>&1
  ( cd "$d" && env -u VIRTUAL_ENV -u SCAFFOLD_GATE_LOG PATH="$C56_B" SCAFFOLD_GATE_STRICT=1 .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || rc=$?
  C56_RC=$rc
  c56_expect "pre-commit in CI mode fails when $tool cannot run, naming it" 1 "::error::gate=$tool skipped"
  C56_LAST_DIR=$d
}
c56_s_ruff() { echo 'x = 1' >a.py; echo '# cfg' >ruff.toml; }
c56_s_eslint() { echo 'const a = 1;' >a.ts; echo '{"name":"p"}' >package.json; }
c56_s_prettier() { echo 'const a = 1;' >a.ts; echo '{}' >.prettierrc; }
c56_s_tsc() { echo 'const a = 1;' >a.ts; echo '{}' >tsconfig.json; }
# shellcheck disable=SC2016  # $a is PHP source, not a shell expansion
c56_s_php() { printf '<?php\n$a = 1;\n' >a.php; }
# shellcheck disable=SC2016
c56_s_phpcs() { printf '<?php\n$a = 1;\n' >a.php; echo '{}' >composer.json; }

c56_tool ruff c56_s_ruff
C56_RUFF_DIR=${C56_LAST_DIR:-}
c56_tool eslint c56_s_eslint
c56_tool prettier c56_s_prettier
c56_tool typescript c56_s_tsc
c56_tool php c56_s_php
c56_tool phpcs c56_s_phpcs

# (e) the same ruff fixture without strict: exit 0, ONE summary line, and none
# of the per-gate status lines on the terminal.
if [ "$C56_UNREACHABLE" -eq 0 ] || [ -z "$C56_RUFF_DIR" ]; then
  echo "  - SKIP: no unreachable-tool fixture here, so the local summary cannot be exercised"
  SKIP=$((SKIP + 1))
else
  rc=0
  ( cd "$C56_RUFF_DIR" && env -u VIRTUAL_ENV -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT PATH="$C56_B" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && c56_has "note: 1 gate(s) skipped: ruff (" && ! grep -q '^gate=' "$HOOK_OUT"; then
    c56_ok "local hook: a skipped ruff exits 0 with one summary line and no gate= lines"
  else
    C56_RC=$rc; c56_bad "local hook: expected exit 0, 'note: 1 gate(s) skipped: ruff (' and no gate= line (got exit $rc)"
  fi
fi

# --- (f)(g) red-green zero-collected, mutation-diff fail-closed ----------------
C56_RG=$(mktemp -d)
(
  cd "$C56_RG" || exit 1
  git init --quiet
  git config user.email "test@test.local"
  git config user.name "Scaffold Test"
  printf '[project]\nname = "c56"\nversion = "0"\n' >pyproject.toml
  : >conftest.py
  mkdir tests
  printf 'def test_a():\n    assert 1 == 1\n' >tests/test_a.py
  "$SCAFFOLD_DIR/install.sh" --python --no-verify --test-guard
  git add -A
  git commit --quiet -m base --no-verify  # scaffold-allow: test fixture
) >"$HOOK_OUT" 2>&1 || { c56_bad "could not build the red-green fixture"; }
C56_BASE=$(git -C "$C56_RG" rev-parse HEAD 2>/dev/null || true)

if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  echo "  - SKIP: pytest not importable, so the 2 red-green zero-collected assertions did NOT run"
  SKIP=$((SKIP + 2))
else
  printf 'X = 1\n' >"$C56_RG/tests/test_a.py"
  git -C "$C56_RG" commit --quiet -am "empty the test file" --no-verify  # scaffold-allow: test fixture
  c56_run "$C56_RG" - python3 .githooks/lib/check-red-green --base "$C56_BASE"
  c56_expect "red-green: a changed test file that collects 0 tests fails as ran 0" 1 \
    "gate=red-green status=ran checked=0" "evaluated 0 items"
  git -C "$C56_RG" reset --quiet --hard "$C56_BASE"
  printf 'def test_a():\n    assert 2 == 2\n' >"$C56_RG/tests/test_a.py"
  git -C "$C56_RG" commit --quiet -am "edit the body only" --no-verify  # scaffold-allow: test fixture
  c56_run "$C56_RG" - python3 .githooks/lib/check-red-green --base "$C56_BASE"
  c56_expect "red-green: an honest edit that adds no test is empty, exit 0" 0 \
    "gate=red-green status=empty" "no new test node IDs"
fi

if python3 -c 'import mutmut' >/dev/null 2>&1; then
  echo "  - SKIP: mutmut is importable here, so the fail-closed path cannot be exercised"
  SKIP=$((SKIP + 1))
else
  c56_run "$C56_RG" - python3 .githooks/lib/check-mutation-diff --base HEAD
  c56_expect "mutation-diff: mutmut absent is exit 2 naming mutmut, never a pass" 2 "mutmut"
fi

# --- (i)-(iv) the review-round paths ------------------------------------------
# (i) a changed non-.py file under tests/ in a project whose pyproject exists
# only for ruff is not "pytest collected 0": empty, exit 0.
if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  echo "  - SKIP: pytest not importable, so the red-green non-.py assertion did NOT run"
  SKIP=$((SKIP + 1))
else
  git -C "$C56_RG" reset --quiet --hard "$C56_BASE"
  printf '#!/bin/sh\n' >"$C56_RG/tests/run.sh"
  git -C "$C56_RG" add tests/run.sh
  git -C "$C56_RG" commit --quiet -m "add a shell helper under tests/" --no-verify  # scaffold-allow: test fixture
  c56_run "$C56_RG" - python3 .githooks/lib/check-red-green --base "$C56_BASE"
  c56_expect "red-green: a changed tests/run.sh (no .py) is empty, exit 0" 0 \
    "gate=red-green status=empty" "no changed .py test files"
fi

# (ii) a base that does not resolve is exit 2 naming the base, never a pass.
c56_run "$C56_RG" - python3 .githooks/lib/check-red-green --base no-such-ref-c56
c56_expect "red-green: an unresolvable --base is exit 2 naming the base" 2 "no-such-ref-c56"
# check-mutation-diff runs verify_mutmut() first, so without mutmut it exits 2
# for that reason before it ever looks at the base; only assert it when mutmut is
# importable, and count a SKIP otherwise.
if python3 -c 'import mutmut' >/dev/null 2>&1; then
  c56_run "$C56_RG" - python3 .githooks/lib/check-mutation-diff --base no-such-ref-c56
  c56_expect "mutation-diff: an unresolvable --base is exit 2 naming the base" 2 "no-such-ref-c56"
else
  echo "  - SKIP: mutmut not importable, so mutation-diff's bad-base path is shadowed by verify_mutmut()"
  SKIP=$((SKIP + 1))
fi

# (iii) no pattern file selected: skipped locally (exit 0), a failure under strict.
c56_run "$C56" README.md env CHECK_PATTERNS_INCLUDE=nope.txt .githooks/lib/check-patterns
c56_expect "patterns: no pattern file selected is skipped, exit 0 locally" 0 "gate=patterns status=skipped"
c56_run "$C56" README.md env CHECK_PATTERNS_INCLUDE=nope.txt SCAFFOLD_GATE_STRICT=1 .githooks/lib/check-patterns
c56_expect "patterns: no pattern file selected fails under SCAFFOLD_GATE_STRICT=1" 1 "::error::gate=patterns skipped"

# (iv) the hook refuses to run without its status helper.
fixture_repo C56_NG
# shellcheck disable=SC2153  # C56_NG is assigned by fixture_repo
echo '#!/usr/bin/env bash' >"$C56_NG/run.sh"
fixture_install "$C56_NG" --shell --no-verify
rm -f "$C56_NG/.githooks/lib/gate-status"
echo '# docs' >"$C56_NG/README.md"
git -C "$C56_NG" add README.md
c56_run "$C56_NG" - .githooks/pre-commit
c56_expect "pre-commit without .githooks/lib/gate-status exits 1, naming it" 1 "gate-status is missing"
rm -rf "$C56_NG"

# (v) colocated tests (src/pkg/test_a.py, no tests/ dir) emptied at HEAD: the old
# "no tests/ directory" early return reported empty here and passed.
if ! python3 -c 'import pytest' >/dev/null 2>&1; then
  echo "  - SKIP: pytest not importable, so the colocated-tests red-green assertion did NOT run"
  SKIP=$((SKIP + 1))
else
  C56_SRC=$(mktemp -d)
  (
    cd "$C56_SRC" || exit 1
    git init --quiet
    git config user.email "test@test.local"
    git config user.name "Scaffold Test"
    printf '[project]\nname = "c56src"\nversion = "0"\n' >pyproject.toml
    mkdir -p src/pkg
    printf 'def test_a():\n    assert 1 == 1\n' >src/pkg/test_a.py
    "$SCAFFOLD_DIR/install.sh" --python --no-verify --test-guard
    git add -A
    git commit --quiet -m base --no-verify  # scaffold-allow: test fixture
    printf 'X = 1\n' >src/pkg/test_a.py
    git commit --quiet -am "empty the colocated test" --no-verify  # scaffold-allow: test fixture
  ) >"$HOOK_OUT" 2>&1 || c56_bad "could not build the colocated-tests fixture"
  c56_run "$C56_SRC" - python3 .githooks/lib/check-red-green --base HEAD~1
  c56_expect "red-green: colocated tests emptied (no tests/ dir) fail as ran 0" 1 \
    "gate=red-green status=ran checked=0" "evaluated 0 items"
  rm -rf "$C56_SRC"
fi

# (vi) CDPATH=. makes `cd` print the directory it lands in, which turned a
# gate's SELF_DIR into two lines and its gate-status path into garbage, so a
# clean file was refused. Every installed shell gate, called by a relative path
# with CDPATH set, must still pass a staged README.
fixture_repo C56_CD
fixture_install "$C56_CD" --python --no-verify --gitleaks-hook
echo '# docs' >"$C56_CD/README.md"
git -C "$C56_CD" add README.md
for c56_g in "$C56_CD"/.githooks/lib/check-*; do
  c56_n=${c56_g##*/}
  # check-clean-tree reads `git status`, not the staged list: the staged README is a dirty tree to it (#219).
  case $c56_n in check-red-green | check-mutation-diff | check-clean-tree) continue ;; esac
  c56_run "$C56_CD" README.md env CDPATH=. ".githooks/lib/$c56_n"
  c56_expect "$c56_n with CDPATH=. passes a clean staged README (exit 0)" 0 "gate=${c56_n#check-} status="
done
rm -rf "$C56_CD"

# (vii) the TypeScript red-green twin ends through gate-status too. A stub `npx`
# stands in for Vitest (real Vitest is case 59's, behind SCAFFOLD_TS_TOOLS): its
# `vitest list --json` reports no tests, which is exactly "a test file changed
# but nothing was collected".
if ! command -v node >/dev/null 2>&1; then
  echo "  - SKIP: node not on PATH, so the 3 TypeScript red-green assertions did NOT run"
  SKIP=$((SKIP + 3))
else
  C56_STUB=$(mktemp -d)
  printf '#!/bin/sh\necho "[]"\n' >"$C56_STUB/npx"; chmod +x "$C56_STUB/npx"
  git -C "$C56_RG" reset --quiet --hard "$C56_BASE"
  mkdir -p "$C56_RG/node_modules" "$C56_RG/src"
  printf '{"name":"c56ts","devDependencies":{"vitest":"1"}}\n' >"$C56_RG/package.json"
  printf 'export const b = 1;\n' >"$C56_RG/src/b.ts"
  git -C "$C56_RG" add package.json src/b.ts
  git -C "$C56_RG" commit --quiet -m "vitest project, no test change" --no-verify  # scaffold-allow: test fixture
  c56_run "$C56_RG" - env PATH="$C56_STUB:$PATH" node .githooks/lib/check-red-green-ts --base "$C56_BASE"
  c56_expect "red-green-ts: no changed test file is empty, exit 0" 0 \
    "gate=red-green-ts status=empty" "no changed test files"
  printf 'export {};\n' >"$C56_RG/src/a.test.ts"
  git -C "$C56_RG" add src/a.test.ts
  git -C "$C56_RG" commit --quiet -m "a test file that holds no tests" --no-verify  # scaffold-allow: test fixture
  c56_run "$C56_RG" - env PATH="$C56_STUB:$PATH" node .githooks/lib/check-red-green-ts --base "$C56_BASE"
  c56_expect "red-green-ts: a changed test file that lists 0 tests fails as ran 0" 1 \
    "gate=red-green-ts status=ran checked=0" "evaluated 0 items"
  c56_run "$C56_RG" - env PATH="$C56_STUB:$PATH" node .githooks/lib/check-red-green-ts --base no-such-ref-c56
  c56_expect "red-green-ts: an unresolvable --base is exit 2 naming the base" 2 "no-such-ref-c56"
  rm -rf "$C56_STUB"
fi

# (viii) a missing gate-status is exit 2 with a named cause, for both TypeScript
# twins (not bash's bare 127, and never mutation-diff's 1 = "declined for size").
# A directory with no vitest project reaches the helper on the first branch.
for c56_t in check-red-green-ts check-mutation-diff-ts; do
  if ! command -v node >/dev/null 2>&1; then
    echo "  - SKIP: node not on PATH, so $c56_t without gate-status did NOT run"
    SKIP=$((SKIP + 1)); continue
  fi
  C56_NH=$(mktemp -d)
  cp "$SCAFFOLD_DIR/githooks/lib/$c56_t.template" "$C56_NH/$c56_t"
  c56_run "$C56_NH" - node "$c56_t" --base HEAD
  c56_expect "$c56_t without gate-status exits 2 naming it unusable" 2 "gate-status unusable"
  rm -rf "$C56_NH"
done

# --- (h) the workflow templates carry the strict variable ----------------------
WF="$SCAFFOLD_DIR/.github/workflows"
C56_STRICT='SCAFFOLD_GATE_STRICT: "1"'
c56_count() { grep -cF -- "$C56_STRICT" "$1"; }
if [ "$(c56_count "$WF/test-guard.yml.template")" -eq 4 ]; then
  c56_ok "test-guard.yml.template sets the strict variable on all four steps (Python and TypeScript)"
else : >"$HOOK_OUT"; c56_bad "test-guard.yml.template must set $C56_STRICT on the four red-green and mutation steps"; fi
if awk '/^  guardrails:/ { g = 1 } g' "$WF/lint.yml.template" | grep -qF -- "$C56_STRICT" \
   && ! awk '/^  guardrails:/ { exit } { print }' "$WF/lint.yml.template" | grep -qF -- "$C56_STRICT"; then
  c56_ok "lint.yml.template sets the strict variable in the guardrails job only"
else : >"$HOOK_OUT"; c56_bad "lint.yml.template must set $C56_STRICT in the guardrails job"; fi
# tests.yml: pytest, vitest and one clean-tree step per job (4); coverage.yml: its
# two test steps and one clean-tree step (3). The clean-tree steps are #219.
for c56_w in tests:4 coverage:3; do
  if [ "$(c56_count "$WF/${c56_w%%:*}.yml.template")" -eq "${c56_w##*:}" ] \
     && grep -qF 'gate-status pytest' "$WF/${c56_w%%:*}.yml.template" \
     && grep -qF 'gate-status vitest' "$WF/${c56_w%%:*}.yml.template" \
     && grep -qF 'check-clean-tree --ci' "$WF/${c56_w%%:*}.yml.template"; then
    c56_ok "${c56_w%%:*}.yml.template: strict on the test and clean-tree steps, each ending in gate-status"
  else : >"$HOOK_OUT"; c56_bad "${c56_w%%:*}.yml.template must set strict on the pytest, vitest and clean-tree steps"; fi
done
# --- (i) clean-tree (#219) and branch (#220): refuse + empty -------------------
fixture_repo C56_CT
fixture_install "$C56_CT" --python --no-verify
fixture_repo C56_E
# shellcheck disable=SC2153  # C56_E is assigned by fixture_repo
c56_run "$C56_E" - "$C56_CT/.githooks/lib/check-clean-tree"
c56_expect "clean-tree: no tracked files is empty, exit 0" 0 "gate=clean-tree status=empty checked=0"
c56_run "$C56_CT" - .githooks/lib/check-branch
c56_expect "branch: an unborn branch (first commit) is empty, exit 0" 0 "gate=branch status=empty checked=0"
git -C "$C56_CT" add -A
git -C "$C56_CT" commit --quiet -m "base"
c56_run "$C56_CT" - .githooks/lib/check-clean-tree
c56_expect "clean-tree: a clean tree is ran N, exit 0" 0 "gate=clean-tree status=ran checked="
printf 'leaked\n' >"$C56_CT/leaked-by-tests.txt"
c56_run "$C56_CT" - .githooks/lib/check-clean-tree
c56_expect "clean-tree refuses an untracked file the suite left behind" 1 "leaked-by-tests.txt" "gate=clean-tree status=ran"
rm -f "$C56_CT/leaked-by-tests.txt"
git -C "$C56_CT" checkout --quiet -b main
c56_run "$C56_CT" - .githooks/lib/check-branch
c56_expect "branch refuses a commit on main" 1 "refusing to commit on the default branch" "gate=branch status=ran checked=1"
c56_run "$C56_CT" - env SCAFFOLD_GATE_STRICT=1 .githooks/lib/check-branch
c56_expect "branch: refusal stands under SCAFFOLD_GATE_STRICT=1" 1 "gate=branch status=ran"

# --- (j) the one exit that does not end in gate-status: SIGTERM (#221) ---------
# A terminated Python gate exits through its SIGTERM handler, not gate-status.
# That path must be non-zero (143), or a killed gate would read as a pass. The
# live signal run is in cases/66; this pins the handler's exit code in both.
for c56_t in check-red-green check-mutation-diff; do
  : >"$HOOK_OUT"
  if grep -qF 'SIGTERM, lambda *_: sys.exit(143)' "$SCAFFOLD_DIR/githooks/lib/$c56_t.template"; then
    c56_ok "$c56_t: SIGTERM leaves through a handler that exits 143, never 0"
  else c56_bad "$c56_t must install a SIGTERM handler that exits non-zero (143)"; fi
done

rm -rf "$C56_RG" "$C56_NOGL" "$C56_B" "$C56_CT" "$C56_E"
