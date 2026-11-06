# shellcheck shell=bash
# cases/58-ts-test-guard.sh: the TypeScript/Vitest twin of the test-guard
# checks (#205): githooks/lib/check-red-green-ts and check-mutation-diff-ts,
# plus the workflow steps that run them. Sourced into the driver's shell, so
# PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are already in scope.
#
# Five sections:
#   (A) install/uninstall/doctor wiring (always runs)
#   (B) workflow structure, read off the template's non-comment text (always)
#   (C) the shared neutral-decline posting step and the TypeScript mutation
#       step, run as shell against stubs (posting step always; mutation step
#       needs node for its stub check)
#   (D) both scripts' verdict logic, driven through a bash `npx` shim that
#       returns canned vitest/stryker output (needs node). The fixture project
#       is "type": "module" and the scripts run from its .githooks/lib as
#       extensionless files, which is the shape that exercises the ES-module
#       built-in loader fallback.
#
# THERE IS NO REAL-TOOL SECTION IN THIS FILE ON PURPOSE. This suite never
# npm-installs anything; real Vitest and Stryker runs live in case 59, gated
# on SCAFFOLD_TS_TOOLS; the stubbed section proves the scripts' own logic
# (classification, exit codes, flags, argument order). What the shim cannot prove: that real vitest
# prints what it returns here. The argument shapes it is asserted against
# (`vitest list <files> --json`, `vitest run --reporter=json`) are the ones
# the scripts must send to the real tool.

echo "cases/58: TypeScript test-guard twin (#205)"

_ts58_rg="$SCAFFOLD_DIR/githooks/lib/check-red-green-ts.template"
_ts58_md="$SCAFFOLD_DIR/githooks/lib/check-mutation-diff-ts.template"
_ts58_wf="$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template"

# --- (A) install / uninstall / doctor wiring --------------------------------
fixture_repo TA
echo '{"name":"x"}' >"$TA/package.json"
fixture_install "$TA" --frontend --no-verify --test-guard
if [ -x "$TA/.githooks/lib/check-red-green-ts" ] \
   && cmp -s "$_ts58_rg" "$TA/.githooks/lib/check-red-green-ts" \
   && [ -x "$TA/.githooks/lib/check-mutation-diff-ts" ] \
   && cmp -s "$_ts58_md" "$TA/.githooks/lib/check-mutation-diff-ts"; then
  echo "  ✓ --test-guard installs both TypeScript checks, executable and identical to the templates"; PASS=$((PASS + 1))
else
  echo "  ✗ --test-guard should install check-red-green-ts and check-mutation-diff-ts"; FAIL=$((FAIL + 1))
fi

# fixture_install discards its log on success, so a re-run captures the note.
( cd "$TA" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --test-guard ) >"$HOOK_OUT" 2>&1 || true
if grep -q 'Vitest projects get the same two checks' "$HOOK_OUT" && grep -q "characterization: <reason>" "$HOOK_OUT"; then
  echo "  ✓ the installer note names the Vitest title convention"; PASS=$((PASS + 1))
else
  echo "  ✗ the installer note should mention the 'characterization: <reason>' title convention"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

( cd "$TA" && bash "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
ts58_with=$(grep -c 'TypeScript twin' "$HOOK_OUT" || true)
rm -f "$TA/.githooks/lib/check-red-green-ts"
( cd "$TA" && bash "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
ts58_without=$(grep -c 'TypeScript twin' "$HOOK_OUT" || true)
if [ "$ts58_with" -eq 0 ] && [ "$ts58_without" -ge 1 ]; then
  echo "  ✓ doctor notes a missing TypeScript twin only when test-guard.yml exists without it"; PASS=$((PASS + 1))
else
  echo "  ✗ doctor should print 'TypeScript twin' only when the twin is missing (present: $ts58_with, missing: $ts58_without)"; FAIL=$((FAIL + 1))
fi
rm -rf "$TA"

fixture_repo TU
echo '{"name":"x"}' >"$TU/package.json"
fixture_install "$TU" --frontend --no-verify --test-guard
( cd "$TU" && bash "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$TU/.githooks/lib/check-red-green-ts" ] && [ ! -e "$TU/.githooks/lib/check-mutation-diff-ts" ] \
   && [ ! -e "$TU/.githooks/lib/check-red-green" ]; then
  echo "  ✓ uninstall.sh removes both TypeScript checks"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall.sh should remove both TypeScript checks"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$TU"

# --- (B) workflow structure -------------------------------------------------
ts58_active=$(grep -v '^ *#' "$_ts58_wf")
# <step-start text>: that step's lines, up to the next step ("      - ") of any kind
_ts58_step() { awk -v start="$1" 'index($0, start) { on = 1; next } on && /^      - / { exit } on { print }'; }

if printf '%s\n' "$ts58_active" | grep -q '^      - id: detect_ts$'; then
  echo "  ✓ the workflow has a detect_ts step"; PASS=$((PASS + 1))
else
  echo "  ✗ the workflow should have '- id: detect_ts'"; FAIL=$((FAIL + 1))
fi

ts58_gate=$(printf '%s\n' "$ts58_active" | awk '
  function flush() {
    if (blk != "" && ts) { n++; if (blk !~ /if: steps\.detect_ts\.outputs\.present == .true./) bad++ }
    blk = ""; ts = 0
  }
  /^      - / { flush() }
  /^      - name: .*TypeScript/ { ts = 1 }
  { blk = blk $0 "\n" }
  END { flush(); print n + 0, bad + 0 }')
if [ "$ts58_gate" = "3 0" ]; then
  echo "  ✓ all 3 TypeScript steps are gated on detect_ts"; PASS=$((PASS + 1))
else
  echo "  ✗ expected 3 TypeScript-named steps, 0 ungated (got '$ts58_gate')"; FAIL=$((FAIL + 1))
fi

if printf '%s\n' "$ts58_active" | grep -qF 'uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1  # v7.1.0'; then
  echo "  ✓ setup-node is pinned to the shared SHA with its version comment"; PASS=$((PASS + 1))
else
  echo "  ✗ setup-node should be pinned to 949feb24... with a '# v7.1.0' comment"; FAIL=$((FAIL + 1))
fi

if printf '%s\n' "$ts58_active" | _ts58_step '- name: Resolve base commit' \
   | grep -qF "if: steps.detect.outputs.present == 'true' || steps.detect_ts.outputs.present == 'true'"; then
  echo "  ✓ Resolve base commit runs for either flavour"; PASS=$((PASS + 1))
else
  echo "  ✗ Resolve base commit should be gated on detect OR detect_ts"; FAIL=$((FAIL + 1))
fi

ts58_tok_all=$(printf '%s\n' "$ts58_active" | grep -cE 'GH_TOKEN|github\.token' || true)
ts58_tok_post=$(printf '%s\n' "$ts58_active" | _ts58_step '- name: Post neutral check run' | grep -cE 'GH_TOKEN|github\.token' || true)
if [ "$ts58_tok_post" -ge 1 ] && [ "$ts58_tok_all" -eq "$ts58_tok_post" ]; then
  echo "  ✓ the token appears only inside the posting step"; PASS=$((PASS + 1))
else
  echo "  ✗ GH_TOKEN/github.token should appear only in the posting step (all: $ts58_tok_all, posting: $ts58_tok_post)"; FAIL=$((FAIL + 1))
fi

ts58_mut_ts=$(printf '%s\n' "$ts58_active" | _ts58_step '- name: Mutation testing TypeScript')
if [ -n "$ts58_mut_ts" ] && ! printf '%s\n' "$ts58_mut_ts" | grep -qE 'GH_TOKEN|github\.token'; then
  echo "  ✓ the TypeScript mutation step gets no token"; PASS=$((PASS + 1))
else
  echo "  ✗ the TypeScript mutation step should exist and carry no token"; FAIL=$((FAIL + 1))
fi

ts58_post_if=$(printf '%s\n' "$ts58_active" | _ts58_step '- name: Post neutral check run' | grep '^        if:' || true)
if printf '%s\n' "$ts58_post_if" | grep -qF 'steps.mutation.outputs.declined' \
   && printf '%s\n' "$ts58_post_if" | grep -qF 'steps.mutation_ts.outputs.declined'; then
  echo "  ✓ the posting step is gated on either mutation step declining"; PASS=$((PASS + 1))
else
  echo "  ✗ the posting step's if: should name both mutation outputs (got: $ts58_post_if)"; FAIL=$((FAIL + 1))
fi

if [ "$(printf '%s\n' "$ts58_active" | grep -c 'checks: write')" -eq 1 ]; then
  echo "  ✓ checks: write is granted exactly once"; PASS=$((PASS + 1))
else
  echo "  ✗ checks: write should appear exactly once"; FAIL=$((FAIL + 1))
fi

ts58_pin=$(sed -n 's/^const STRYKER_PIN = "\(.*\)";$/\1/p' "$_ts58_md")
ts58_npm=$(printf '%s\n' "$ts58_mut_ts" | grep 'npm install --no-save' || true)
if [ -n "$ts58_pin" ] \
   && printf '%s\n' "$ts58_npm" | grep -qF "@stryker-mutator/core@$ts58_pin" \
   && printf '%s\n' "$ts58_npm" | grep -qF "@stryker-mutator/vitest-runner@$ts58_pin"; then
  echo "  ✓ the workflow installs both Stryker packages at the script's STRYKER_PIN ($ts58_pin)"; PASS=$((PASS + 1))
else
  echo "  ✗ the npm install line should pin both Stryker packages to the script's STRYKER_PIN ('$ts58_pin')"; FAIL=$((FAIL + 1))
fi

if printf '%s\n' "$ts58_active" | grep -qF 'node .githooks/lib/check-red-green-ts' \
   && printf '%s\n' "$ts58_active" | grep -qF 'node .githooks/lib/check-mutation-diff-ts'; then
  echo "  ✓ the workflow invokes both TypeScript checks with node"; PASS=$((PASS + 1))
else
  echo "  ✗ the workflow should run both TypeScript checks with node"; FAIL=$((FAIL + 1))
fi

# The pre-commit hook loops over .githooks/lib/check-* and would run a twin with
# no arguments (exit 2) unless it is named in the skip case; lint.yml does the same.
ts58_skip_ok=1
for _f in "$SCAFFOLD_DIR/githooks/pre-commit.template" "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"; do
  for _n in check-red-green-ts check-mutation-diff-ts; do
    grep -E 'check-red-green\|' "$_f" | grep -qF "$_n" || ts58_skip_ok=0
  done
done
if [ "$ts58_skip_ok" -eq 1 ]; then
  echo "  ✓ the pre-commit hook and lint.yml skip lines name both TypeScript twins"; PASS=$((PASS + 1))
else
  echo "  ✗ pre-commit.template and lint.yml.template should name check-red-green-ts and check-mutation-diff-ts in their skip case"; FAIL=$((FAIL + 1))
fi

# --- (C) posting step and TypeScript mutation step, run as shell -------------
TC=$(mktemp -d)
mkdir -p "$TC/bin" "$TC/w/.githooks/lib"
_ts58_extract() { # <step name prefix> -> that step's run: block, de-indented
  python3 - "$_ts58_wf" "$1" <<'PYEOF'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"- name: " + re.escape(sys.argv[2]) + r".*?        run: \|[^\n]*\n(.*?)(?=\n      - name:|\Z)", text, re.S)
for line in m.group(1).splitlines():
    print(line[10:] if line.startswith(" " * 10) else line)
PYEOF
}
_ts58_extract 'Post neutral check run' >"$TC/post.sh"
_ts58_extract 'Mutation testing TypeScript' >"$TC/mut.sh"
cat >"$TC/bin/gh" <<'GHEOF'
#!/bin/sh
printf 'CALL\n' >>"$GH_LOG"
printf '%s\n' "$@" >>"$GH_LOG"
exit 0
GHEOF
printf '#!/bin/sh\nexit 0\n' >"$TC/bin/npm"
chmod +x "$TC/bin/gh" "$TC/bin/npm"

_ts58_post() { # <DECLINED_PY> <DECLINED_TS>; sets TC_RC, TC_CALLS
  : >"$TC/gh.log"; TC_RC=0
  ( cd "$TC/w" && PATH="$TC/bin:$PATH" GH_LOG="$TC/gh.log" GITHUB_REPOSITORY=o/r GH_TOKEN=x \
      HEAD_SHA=def DECLINED_PY="$1" DECLINED_TS="$2" bash -e "$TC/post.sh" ) >"$HOOK_OUT" 2>&1 || TC_RC=$?
  TC_CALLS=$(grep -cx CALL "$TC/gh.log" || true)
}

_ts58_post false true
if [ "$TC_RC" -eq 0 ] && [ "$TC_CALLS" -eq 1 ] \
   && grep -qxF 'name=test-guard / mutation-ts (declined: size)' "$TC/gh.log" \
   && grep -qxF 'conclusion=neutral' "$TC/gh.log" \
   && ! grep -qF 'test-guard / mutation (declined: size)' "$TC/gh.log"; then
  echo "  ✓ a TypeScript-only decline posts exactly one neutral check run, named mutation-ts"; PASS=$((PASS + 1))
else
  echo "  ✗ a TypeScript-only decline should post one neutral mutation-ts check run (rc $TC_RC, calls $TC_CALLS)"; sed 's/^/      /' "$TC/gh.log"; FAIL=$((FAIL + 1))
fi

_ts58_post true true
if [ "$TC_RC" -eq 0 ] && [ "$TC_CALLS" -eq 2 ] \
   && grep -qxF 'name=test-guard / mutation (declined: size)' "$TC/gh.log" \
   && grep -qxF 'name=test-guard / mutation-ts (declined: size)' "$TC/gh.log"; then
  echo "  ✓ both flavours declining post two check runs, one per name"; PASS=$((PASS + 1))
else
  echo "  ✗ both declines should post two check runs (rc $TC_RC, calls $TC_CALLS)"; sed 's/^/      /' "$TC/gh.log"; FAIL=$((FAIL + 1))
fi

_ts58_post false false
if [ "$TC_RC" -eq 0 ] && [ "$TC_CALLS" -eq 0 ]; then
  echo "  ✓ no decline posts nothing and exits 0"; PASS=$((PASS + 1))
else
  echo "  ✗ no decline should post nothing (rc $TC_RC, calls $TC_CALLS)"; FAIL=$((FAIL + 1))
fi

if command -v node >/dev/null 2>&1; then
  printf 'process.exit(Number(process.env.STUB_RC));\n' >"$TC/w/.githooks/lib/check-mutation-diff-ts"
  _ts58_mut() { # <stub exit code>; sets TC_RC
    : >"$TC/summary"; : >"$TC/out"; TC_RC=0
    ( cd "$TC/w" && PATH="$TC/bin:$PATH" STUB_RC="$1" GITHUB_STEP_SUMMARY="$TC/summary" \
        GITHUB_OUTPUT="$TC/out" GITHUB_BASE_REF=main BASE_SHA=abc bash -e "$TC/mut.sh" ) >"$HOOK_OUT" 2>&1 || TC_RC=$?
  }
  _ts58_mut 1
  if [ "$TC_RC" -eq 0 ] && grep -qxF 'declined=true' "$TC/out" \
     && grep -q 'check-mutation-diff-ts --base origin/main' "$TC/summary" \
     && grep -q -- '--max-mutants N' "$TC/summary" && grep -q '^::warning::' "$HOOK_OUT"; then
    echo "  ✓ TypeScript mutation exit 1 passes, writes the local command, and sets declined=true"; PASS=$((PASS + 1))
  else
    echo "  ✗ TypeScript mutation exit 1 should pass, summarise and set declined=true (rc $TC_RC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  _ts58_mut 2
  if [ "$TC_RC" -eq 2 ] && [ ! -s "$TC/out" ]; then
    echo "  ✓ TypeScript mutation exit 2 fails the step with that code"; PASS=$((PASS + 1))
  else
    echo "  ✗ TypeScript mutation exit 2 should fail the step with 2 (rc $TC_RC)"; FAIL=$((FAIL + 1))
  fi
  _ts58_mut 0
  if [ "$TC_RC" -eq 0 ] && ! grep -q 'declined=' "$TC/out" && [ ! -s "$TC/summary" ]; then
    echo "  ✓ TypeScript mutation exit 0 passes untouched"; PASS=$((PASS + 1))
  else
    echo "  ✗ TypeScript mutation exit 0 should pass with no output or summary (rc $TC_RC)"; FAIL=$((FAIL + 1))
  fi
else
  echo "  - SKIP: node not on PATH, TypeScript mutation step harness (3 assertions)"; SKIP=$((SKIP + 3))
fi
rm -rf "$TC"

# --- (D) script behaviour against a stubbed npx -----------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "  - SKIP: node not on PATH, check-red-green-ts / check-mutation-diff-ts behaviour (21 assertions)"; SKIP=$((SKIP + 21))
else
  TD=$(mktemp -d)
  mkdir -p "$TD/bin"
  # The shim stands in for `npx --no-install vitest|stryker ...`. Its canned
  # answers: `list` reports calc > adds (and calc > adds again once the file
  # contains that marker; twice, once more, with a DUP marker), plus sq > $STUB_SQ_TITLE; `run` reports per
  # $STUB_SCENARIO; `stryker run` writes a report per $STUB_MUTANTS.
  cat >"$TD/bin/npx" <<'SHIM'
#!/usr/bin/env bash
here=$(pwd -P)
shift # --no-install
tool=$1; shift
if [ "$tool" = vitest ] && [ "$1" = list ]; then
  shift
  echo "list $*" >>"$STUB_LOG"
  [ -n "${STUB_LIST_FAIL:-}" ] && exit 1
  rows=""
  for f in "$@"; do
    [ "$f" = --json ] && continue
    [ -f "$here/$f" ] || continue
    case "$f" in
      *calc.test.ts)
        rows="$rows{\"name\":\"calc > adds\",\"file\":\"$here/$f\"},"
        if grep -q 'adds again' "$here/$f"; then rows="$rows{\"name\":\"calc > adds again\",\"file\":\"$here/$f\"},"; fi
        if grep -q DUP "$here/$f"; then rows="$rows{\"name\":\"calc > adds\",\"file\":\"$here/$f\"},"; fi ;;
      *sq.test.ts) rows="$rows{\"name\":\"sq > ${STUB_SQ_TITLE:-squares}\",\"file\":\"$here/$f\"}," ;;
    esac
  done
  printf '[%s]\n' "${rows%,}"
elif [ "$tool" = vitest ] && [ "$1" = run ]; then
  shift
  echo "run $*" >>"$STUB_LOG"
  out=""; files=()
  for a in "$@"; do
    case "$a" in --outputFile=*) out=${a#--outputFile=} ;; --*) ;; *) files+=("$a") ;; esac
  done
  case "${STUB_SCENARIO:-red}" in
    offender) again=passed; sq=failed ;;
    red) again=failed; sq=failed ;;
    unevaluable) again=failed; sq=none ;;
    char) again=failed; sq=passed ;;
    noreport) exit 1 ;;
    badshape) printf '{"testResults":[null]}\n' >"$out"; exit 1 ;;
  esac
  res=""
  for f in "${files[@]}"; do
    [ -f "$here/$f" ] || continue
    case "$f" in
      *calc.test.ts)
        a="{\"ancestorTitles\":[\"calc\"],\"title\":\"adds\",\"status\":\"passed\"}"
        if grep -q 'adds again' "$here/$f"; then a="$a,{\"ancestorTitles\":[\"calc\"],\"title\":\"adds again\",\"status\":\"$again\"}"; fi
        # a duplicate title: the first instance passes, the second fails
        if grep -q DUP "$here/$f"; then a="$a,{\"ancestorTitles\":[\"calc\"],\"title\":\"adds\",\"status\":\"failed\"}"; fi
        res="$res{\"name\":\"$here/$f\",\"assertionResults\":[$a]}," ;;
      *sq.test.ts)
        if [ "$sq" = none ]; then res="$res{\"name\":\"$here/$f\",\"status\":\"failed\",\"assertionResults\":[]},"
        else res="$res{\"name\":\"$here/$f\",\"assertionResults\":[{\"ancestorTitles\":[\"sq\"],\"title\":\"${STUB_SQ_TITLE:-squares}\",\"status\":\"$sq\"}]},"; fi ;;
    esac
  done
  printf '{"testResults":[%s]}\n' "${res%,}" >"$out"
  exit 1
elif [ "$tool" = stryker ] && [ "$1" = run ]; then
  echo "stryker $*" >>"$STUB_LOG"
  cat "$here/$2" >>"$STUB_LOG"
  [ "${STUB_MUTANTS:-}" = notests ] && { echo "No tests were executed" >&2; exit 1; }
  rep=$(sed -n 's/.*"fileName": *"\([^"]*\)".*/\1/p' "$here/$2")
  mkdir -p "$here/$(dirname "$rep")"
  k='{"status":"Killed"}'
  case "${STUB_MUTANTS:-allkilled}" in
    allkilled) m="$k,$k,$k" ;;
    survivors) m="$k,$k,{\"status\":\"Survived\"},{\"status\":\"NoCoverage\"}" ;;
    many) m="$k,$k,$k,$k,$k" ;;
    none) exit 1 ;;
  esac
  printf '{"files":{"src/calc.ts":{"mutants":[%s]}}}\n' "$m" >"$here/$rep"
else
  echo "unexpected npx call: $tool $*" >&2; exit 99
fi
SHIM
  chmod +x "$TD/bin/npx"

  # A plain git init in a temp dir: no hooks are installed here, so the
  # commits need no bypass flag.
  fixture_repo R
  (
    cd "$R" || exit 1
    mkdir -p src node_modules/@stryker-mutator/core node_modules/@stryker-mutator/vitest-runner
    printf '{"name":"x","type":"module","devDependencies":{"vitest":"^3.0.0"}}\n' >package.json
    printf 'node_modules/\n' >.gitignore
    printf '{"version":"10.1.1"}\n' >node_modules/@stryker-mutator/core/package.json
    printf '{"version":"10.1.1"}\n' >node_modules/@stryker-mutator/vitest-runner/package.json
    printf 'export const add = (a: number, b: number) => a + b;\n' >src/calc.ts
    printf 'describe("calc", () => { it("adds", () => {}); });\n' >src/calc.test.ts
    git add -A && git -c commit.gpgsign=false commit -q -m base
    printf 'export const add = (a: number, b: number) => a + b;\nexport const mul = (a: number, b: number) => a * b;\n' >src/calc.ts
    printf 'describe("calc", () => { it("adds", () => {}); it("adds again", () => {}); });\n' >src/calc.test.ts
    printf 'describe("sq", () => { it("squares", () => {}); });\n' >src/sq.test.ts
    git add -A && git -c commit.gpgsign=false commit -q -m head
    # The scripts as installed: extensionless, inside the "type": "module" project.
    mkdir -p .githooks/lib
    cp "$_ts58_rg" .githooks/lib/check-red-green-ts
    cp "$_ts58_md" .githooks/lib/check-mutation-diff-ts
  ) >/dev/null 2>&1
  _ts58_rgx="$R/.githooks/lib/check-red-green-ts"
  _ts58_mdx="$R/.githooks/lib/check-mutation-diff-ts"

  ts58_log="$TD/npx.log"
  _ts58_go() { # <script> <scenario> <mutants> <sq title> args...; sets TD_RC, output in HOOK_OUT
    local script=$1 scen=$2 muts=$3 title=$4
    shift 4
    TD_RC=0
    ( cd "$R" && PATH="$TD/bin:$PATH" STUB_LOG="$ts58_log" STUB_SCENARIO="$scen" STUB_MUTANTS="$muts" \
        STUB_SQ_TITLE="$title" node "$script" "$@" ) >"$HOOK_OUT" 2>&1 || TD_RC=$?
  }
  : >"$ts58_log"
  _ts58_expect() { # <rc> <fixed string in output> <ok text> <failure text>; reads TD_RC
    if [ "$TD_RC" -eq "$1" ] && grep -qF -- "$2" "$HOOK_OUT"; then
      echo "  ✓ $3"; PASS=$((PASS + 1))
    else
      echo "  ✗ $4 (rc $TD_RC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  }

  _ts58_go "$_ts58_rgx" offender x squares --base HEAD~1
  _ts58_expect 1 'green-on-base: src/calc.test.ts::calc > adds again' "check-red-green-ts rejects a new test that passes on base, naming its ID" "check-red-green-ts should exit 1 naming the green-on-base test"

  _ts58_go "$_ts58_rgx" red x squares --base HEAD~1
  if [ "$TD_RC" -eq 0 ] && grep -qF 'red-green OK: 2 new test(s)' "$HOOK_OUT" \
     && grep -qF '(2 red, 0 characterization' "$HOOK_OUT"; then
    echo "  ✓ check-red-green-ts accepts new tests that fail on base, with the accounting line"; PASS=$((PASS + 1))
  else
    echo "  ✗ check-red-green-ts should exit 0 with 'red-green OK: 2 new test(s) ... (2 red, 0 characterization' (rc $TD_RC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi

  _ts58_go "$_ts58_rgx" unevaluable x squares --base HEAD~1 --strict-unevaluable
  _ts58_expect 1 'src/sq.test.ts (1)' "--strict-unevaluable fails on a file that does not load on base" "--strict-unevaluable should exit 1 naming src/sq.test.ts"

  _ts58_go "$_ts58_rgx" unevaluable x squares --base HEAD~1
  _ts58_expect 0 'could not be executed against base' "without --strict-unevaluable the same file is a notice and exit 0" "an unevaluable file should be a notice with exit 0 by default"

  _ts58_go "$_ts58_rgx" char x 'characterization: pins squares' --base HEAD~1
  _ts58_expect 0 'exempt (characterization): src/sq.test.ts::sq > characterization: pins squares' "a title starting 'characterization: <reason>' is exempt" "a characterization-titled green test should be exempt"

  _ts58_go "$_ts58_rgx" red x squares --base HEAD~1 --max-new 0
  _ts58_expect 1 'exceeds --max-new=0' "a diff with more new tests than --max-new is declined with exit 1" "--max-new 0 should decline with exit 1"

  _ts58_go "$_ts58_rgx" red x squares --base nope
  _ts58_expect 2 "cannot resolve base ref 'nope'" "an unresolvable base is exit 2, not a pass" "--base nope should exit 2"

  _ts58_go "$_ts58_rgx" noreport x squares --base HEAD~1
  _ts58_expect 2 'no readable JSON report' "a vitest run that writes no report is exit 2" "a missing vitest report should exit 2 with 'no readable JSON report'"

  STUB_LIST_FAIL=1 _ts58_go "$_ts58_rgx" red x squares --base HEAD~1
  _ts58_expect 2 'collection failed on HEAD' "a failing vitest list is exit 2, not a pass" "a failing 'vitest list' should exit 2 with 'collection failed on HEAD'"

  _ts58_go "$_ts58_rgx" red x squares --base HEAD~1 --max-new 2
  ts58_rc_new=$TD_RC
  _ts58_go "$_ts58_mdx" x many squares --base HEAD~1 --max-mutants 5
  if [ "$ts58_rc_new" -eq 0 ] && [ "$TD_RC" -eq 0 ]; then
    echo "  ✓ the size limits are inclusive: --max-new 2 with 2 new tests, --max-mutants 5 with 5 mutants"; PASS=$((PASS + 1))
  else
    echo "  ✗ exactly at the limit should pass (--max-new rc $ts58_rc_new, --max-mutants rc $TD_RC)"; FAIL=$((FAIL + 1))
  fi

  # A report with a shape the script does not expect makes it throw; a crash
  # must be exit 2 with the error form, never the exit 1 of an uncaught throw.
  _ts58_go "$_ts58_rgx" badshape x squares --base HEAD~1 --ci
  if [ "$TD_RC" -eq 2 ] && grep -q '^::error::check-red-green-ts internal error, TypeError' "$HOOK_OUT"; then
    echo "  ✓ an internal crash is exit 2 with an ::error:: line, never exit 1"; PASS=$((PASS + 1))
  else
    echo "  ✗ a malformed report should crash to exit 2 with '::error::... internal error' (rc $TD_RC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi

  cp "$R/package.json" "$TD/package.json.keep"
  printf '{"name":"x"}\n' >"$R/package.json"
  _ts58_go "$_ts58_rgx" red x squares --base HEAD~1
  _ts58_expect 0 'no Vitest project detected' "a project that does not declare vitest is skipped with exit 0" "a non-Vitest project should exit 0 with the detection line"
  cp "$TD/package.json.keep" "$R/package.json"

  ts58_runs=$(awk '/^run /{n++; if ($0 !~ /--reporter=json/) bad++} END{print n+0, bad+0}' "$ts58_log")
  ts58_lists=$(awk '/^list /{n++; if ($0 !~ / --json$/) bad++} END{print n+0, bad+0}' "$ts58_log")
  if [ "${ts58_runs%% *}" -ge 1 ] && [ "${ts58_runs##* }" -eq 0 ]; then
    echo "  ✓ every vitest run call used --reporter=json (${ts58_runs%% *} calls)"; PASS=$((PASS + 1))
  else
    echo "  ✗ every vitest run call should use --reporter=json (calls/bad: $ts58_runs)"; FAIL=$((FAIL + 1))
  fi
  if [ "${ts58_lists%% *}" -ge 1 ] && [ "${ts58_lists##* }" -eq 0 ]; then
    echo "  ✓ every vitest list call ended with --json, after the files (${ts58_lists%% *} calls)"; PASS=$((PASS + 1))
  else
    echo "  ✗ every vitest list call should end with --json (calls/bad: $ts58_lists)"; FAIL=$((FAIL + 1))
  fi

  _ts58_go "$_ts58_mdx" x allkilled squares --base HEAD~1
  _ts58_expect 0 'mutation OK: 3 mutants, all killed' "check-mutation-diff-ts reports all-killed as mutation OK, exit 0" "all-killed should exit 0 with 'mutation OK'"

  _ts58_go "$_ts58_mdx" x survivors squares --base HEAD~1
  if [ "$TD_RC" -eq 0 ] && grep -qF 'src/calc.ts: 1 survived, 1 no tests' "$HOOK_OUT" && grep -qF 'mutation summary:' "$HOOK_OUT"; then
    echo "  ✓ survivors warn per file and keep exit 0 (advisory)"; PASS=$((PASS + 1))
  else
    echo "  ✗ survivors should warn per file with a summary and exit 0 (rc $TD_RC)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi

  _ts58_go "$_ts58_mdx" x many squares --base HEAD~1 --max-mutants 1
  _ts58_expect 1 'exceeds --max-mutants=1' "more mutants than --max-mutants is a decline, exit 1" "5 mutants with --max-mutants 1 should exit 1"

  printf '{"version":"9.0.0"}\n' >"$R/node_modules/@stryker-mutator/core/package.json"
  _ts58_go "$_ts58_mdx" x allkilled squares --base HEAD~1
  _ts58_expect 2 'expected 10.1.1' "a Stryker version other than the pin is exit 2" "Stryker 9.0.0 should exit 2 naming the expected version"
  printf '{"version":"10.1.1"}\n' >"$R/node_modules/@stryker-mutator/core/package.json"

  _ts58_go "$_ts58_mdx" x none squares --base HEAD~1
  _ts58_expect 2 'no readable report' "a Stryker run that writes no report is exit 2, never a pass" "a missing report should exit 2 with 'no readable report'"
  _ts58_go "$_ts58_mdx" x notests squares --base HEAD~1
  _ts58_expect 0 'no related tests' "stryker's no-tests-executed failure is advisory, exit 0 (belt for vitest.related=false)" "a no-report run that says 'No tests were executed' should exit 0 with the no-related-tests notice"
  if grep -q '"related": false' "$ts58_log" && grep -Eq '"src/calc\.ts(:[0-9]+-[0-9]+)?"' "$ts58_log"; then
    echo "  ✓ the Stryker config sets vitest.related=false and lists changed source files"; PASS=$((PASS + 1))
  else
    echo "  ✗ the Stryker config should set vitest.related=false and list src/calc.ts"; FAIL=$((FAIL + 1))
  fi
  # Duplicate titles: base has one "calc > adds", head has two; the shim reports
  # the first instance passed and the second failed. A set-based diff would see
  # no new ID at all and miss it.
  (
    cd "$R" || exit 1
    printf 'describe("calc", () => { it("adds", () => {}); it("adds", () => {}); /* DUP */ });\n' >src/calc.test.ts
    git add src/calc.test.ts && git -c commit.gpgsign=false commit -q -m dup
  ) >/dev/null 2>&1
  _ts58_go "$_ts58_rgx" red x squares --base HEAD~1
  _ts58_expect 1 'green-on-base: src/calc.test.ts::calc > adds' "a duplicate title added at HEAD is counted as new and judged per instance" "a duplicated test title with one passing instance should exit 1 naming the ID"
  rm -rf "$TD" "$R"
fi
