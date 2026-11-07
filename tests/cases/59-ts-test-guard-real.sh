# shellcheck shell=bash
# cases/59-ts-test-guard-real.sh: the TypeScript test-guard twin against the
# REAL tools (#205), the repeatable counterpart of case 58's stubbed section.
# Sourced into the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR are in scope.
#
# Gated on SCAFFOLD_TS_TOOLS: a directory whose node_modules holds vitest,
# @stryker-mutator/core and @stryker-mutator/vitest-runner (at the versions
# the scripts pin; Stryker 10 needs Node 22). The suite never npm-installs,
# so without it every assertion here is SKIPped and counted, never silently
# dropped. The repo's own CI installs them from the committed lockfile in
# tests/fixtures/ts-tools; locally:
#   npm ci --prefix tests/fixtures/ts-tools --ignore-scripts --no-audit --no-fund
#   SCAFFOLD_TS_TOOLS="$PWD/tests/fixtures/ts-tools" bash tests/run.sh
#
# Scenarios (one scratch repo, one branch per scenario off the same base):
#   (a) a new function plus a test that fails on base: red-green exit 0, the
#       mutation layer evaluates it
#   (b) a new test that passes on base: red-green exit 1, green-on-base
#   (c) only an untested new source file: mutation stays ADVISORY exit 0 via
#       the report summary (survived/no tests); the no-related-tests notice
#       fires only when Stryker ran zero test files
#   (d) a one-hunk edit inside a multi-function file: the mutate entry is a
#       line range, not the whole file
#   (e) a glob-metacharacter path (src/[id]/page.ts): escaped, so Stryker
#       really instruments it (>= 1 mutant), not "0 mutants" from a no-match
#   (f) a root file named !x.ts: a leading "!" is an exclusion pattern with no
#       literal form, so the script refuses it with exit 2 naming the path and
#       saying the other changed source files went unevaluated
#   (g) refusal log lines for both twins (red-green and mutation)
#   (h) added it.skip / it.todo: a notice that vitest list does not list them

echo "cases/59: TypeScript test-guard twin against real Vitest and Stryker (#205)"

_ts59_n=23
_ts59_t="${SCAFFOLD_TS_TOOLS:-}"
if [ -z "$_ts59_t" ] \
   || ! command -v node >/dev/null 2>&1 \
   || [ ! -d "$_ts59_t/node_modules/vitest" ] \
   || [ ! -d "$_ts59_t/node_modules/@stryker-mutator/core" ] \
   || [ ! -d "$_ts59_t/node_modules/@stryker-mutator/vitest-runner" ]; then
  echo "  - SKIP: SCAFFOLD_TS_TOOLS not set to a node_modules parent with vitest and Stryker ($_ts59_n assertions)"
  SKIP=$((SKIP + _ts59_n))
else
  _ts59_d=$(mktemp -d)
  _ts59_g() { git -C "$_ts59_d" -c user.email=t@t -c user.name=t "$@"; }
  _ts59_commit() { _ts59_g add -A && _ts59_g commit -qm "$1"; }
  _ts59_run() { # script args... ; sets _ts59_rc and _ts59_out
    local s="$1"; shift
    _ts59_rc=0
    _ts59_out=$(cd "$_ts59_d" && node ".githooks/lib/$s" "$@" 2>&1) || _ts59_rc=$?
  }
  _ts59_check() { # label, ok-flag
    if [ "$2" = 1 ]; then echo "  ✓ $1"; PASS=$((PASS + 1))
    else echo "  ✗ $1"; printf '%s\n' "$_ts59_out" | tail -15 | sed 's/^/      /'; FAIL=$((FAIL + 1)); fi
  }

  git init -q "$_ts59_d"
  mkdir -p "$_ts59_d/src" "$_ts59_d/.githooks/lib"
  echo '{"name":"fx","private":true,"type":"module","devDependencies":{"vitest":"5.1.0"}}' >"$_ts59_d/package.json"
  ln -s "$_ts59_t/node_modules" "$_ts59_d/node_modules"
  printf 'node_modules\n.scaffold-*\n' >"$_ts59_d/.gitignore"
  for _ts59_s in check-red-green-ts check-mutation-diff-ts; do
    cp "$SCAFFOLD_DIR/githooks/lib/$_ts59_s.template" "$_ts59_d/.githooks/lib/$_ts59_s"
    chmod +x "$_ts59_d/.githooks/lib/$_ts59_s"
  done
  # Both twins end through the sibling gate-status (#210); without it they exit 2.
  cp "$SCAFFOLD_DIR/githooks/lib/gate-status.template" "$_ts59_d/.githooks/lib/gate-status"
  chmod +x "$_ts59_d/.githooks/lib/gate-status"
  cat >"$_ts59_d/src/calc.ts" <<'TS'
export function add(a: number, b: number): number {
  return a + b;
}

export function sub(a: number, b: number): number {
  return a - b;
}

export function neg(a: number): number {
  return -a;
}
TS
  cat >"$_ts59_d/src/calc.test.ts" <<'TS'
import { describe, expect, it } from "vitest";
import { add } from "./calc";

describe("calc", () => {
  it("adds", () => {
    expect(add(1, 2)).toBe(3);
  });
});
TS
  _ts59_commit base
  _ts59_base=$(_ts59_g rev-parse HEAD)

  # --- (a) red test plus new code ------------------------------------------
  _ts59_g checkout -q -B scen-a "$_ts59_base"
  printf '\nexport function mul(a: number, b: number): number {\n  return a * b;\n}\n' >>"$_ts59_d/src/calc.ts"
  sed -i.bak 's#import { add }#import { add, mul }#' "$_ts59_d/src/calc.test.ts" && rm -f "$_ts59_d/src/calc.test.ts.bak"
  sed -i.bak '$d' "$_ts59_d/src/calc.test.ts" && rm -f "$_ts59_d/src/calc.test.ts.bak"
  printf '  it("multiplies", () => {\n    expect(mul(2, 3)).toBe(6);\n  });\n});\n' >>"$_ts59_d/src/calc.test.ts"
  _ts59_commit "add mul"
  _ts59_run check-red-green-ts --base "$_ts59_base"
  _ts59_check "(a) red-green accepts a new test that fails on base (exit 0)" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(a) red-green counts it as 1 red, 0 characterization" "$(printf '%s' "$_ts59_out" | grep -q '(1 red, 0 characterization' && echo 1 || echo 0)"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(a) mutation layer evaluates the change and exits 0" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(a) mutation layer prints a verdict (mutation OK or mutation summary)" "$(printf '%s' "$_ts59_out" | grep -Eq 'mutation (OK|summary):|gate=mutation-diff-ts status=ran' && echo 1 || echo 0)"

  # --- (b) green on base ---------------------------------------------------
  _ts59_g checkout -q -B scen-b "$_ts59_base"
  sed -i.bak '$d' "$_ts59_d/src/calc.test.ts" && rm -f "$_ts59_d/src/calc.test.ts.bak"
  printf '  it("adds zero", () => {\n    expect(add(0, 4)).toBe(4);\n  });\n});\n' >>"$_ts59_d/src/calc.test.ts"
  _ts59_commit "add passing test"
  _ts59_run check-red-green-ts --base "$_ts59_base"
  _ts59_check "(b) a new test that passes on base is refused (exit 1)" "$([ "$_ts59_rc" = 1 ] && echo 1 || echo 0)"
  _ts59_check "(b) the refusal is reported as green-on-base" "$(printf '%s' "$_ts59_out" | grep -q 'green-on-base:' && echo 1 || echo 0)"

  # --- (c) untested new file: advisory, never exit 2 -----------------------
  _ts59_g checkout -q -B scen-c "$_ts59_base"
  printf 'export function negate(a: number): number {\n  return -a;\n}\n' >"$_ts59_d/src/neg.ts"
  _ts59_commit "add untested neg"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(c) an untested-only PR stays advisory (exit 0, not 2)" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(c) the output still carries a verdict for src/neg.ts, not a crash" "$(printf '%s' "$_ts59_out" | grep -Eq 'mutating: src/neg.ts$' && printf '%s' "$_ts59_out" | grep -Eq 'mutation (summary|notice):|mutation OK:|gate=mutation-diff-ts status=(ran|empty)' && echo 1 || echo 0)"

  # --- (d) line-range scoping ----------------------------------------------
  _ts59_g checkout -q -B scen-d "$_ts59_base"
  sed -i.bak 's#^  return a - b;#  const r = a - b;\n  return r;#' "$_ts59_d/src/calc.ts" && rm -f "$_ts59_d/src/calc.ts.bak"
  _ts59_commit "touch sub only"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(d) a one-hunk edit runs and exits 0" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(d) the mutate entry is the changed line range src/calc.ts:6-7, not the whole file" "$(printf '%s' "$_ts59_out" | grep -q 'mutating: src/calc.ts:6-7$' && echo 1 || echo 0)"

  # --- (e) glob metacharacters in the path ---------------------------------
  _ts59_g checkout -q -B scen-e "$_ts59_base"
  mkdir -p "$_ts59_d/src/[id]"
  printf 'export function double(x: number): number {\n  return x * 2;\n}\n' >"$_ts59_d/src/[id]/page.ts"
  printf 'import { expect, it } from "vitest";\nimport { double } from "./page";\n\nit("doubles", () => {\n  expect(double(4)).toBe(8);\n});\n' >"$_ts59_d/src/[id]/page.test.ts"
  _ts59_commit "add bracket path"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(e) a [id] path evaluates and exits 0" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(e) at least 1 mutant was generated for the [id] path (escape works)" "$(printf '%s' "$_ts59_out" | grep -Eq 'gate=mutation-diff-ts status=ran checked=[1-9]|mutation summary: [0-9]+ killed, [0-9]+ not killed \(([1-9][0-9]*) total' && echo 1 || echo 0)"

  # --- (f) a leading "!" is an exclusion pattern: refused, never 0-mutants-OK --
  _ts59_g checkout -q -B scen-f "$_ts59_base"
  printf 'export function neg(x: number): number {\n  return -x;\n}\n' >"$_ts59_d/!x.ts"
  printf 'import { expect, it } from "vitest";\nimport { neg } from "../!x";\n\nit("negates", () => {\n  expect(neg(2)).toBe(-2);\n});\n' >"$_ts59_d/src/bang.test.ts"
  printf 'export function pos(x: number): number {\n  return +x;\n}\n' >"$_ts59_d/src/other.ts"
  _ts59_commit "add bang path"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(f) a path starting with ! is exit 2, not a silent 0-mutant pass" "$([ "$_ts59_rc" = 2 ] && echo 1 || echo 0)"
  _ts59_check "(f) the refusal names the path" "$(printf '%s' "$_ts59_out" | grep -q '!x.ts: a path starting with' && echo 1 || echo 0)"
  _ts59_check "(f) the refusal says the other changed source file went unevaluated (#260)" "$(printf '%s' "$_ts59_out" | grep -q '1 other changed source file(s) went unevaluated' && echo 1 || echo 0)"

  # --- (g) refusal log: the offender run writes one line; a missing logger
  #         never changes the verdict (fail open) -------------------------
  _ts59_g checkout -q scen-b
  cp "$SCAFFOLD_DIR/githooks/lib/refusal-log.template" "$_ts59_d/.githooks/lib/refusal-log"
  chmod +x "$_ts59_d/.githooks/lib/refusal-log"
  rm -f "$_ts59_d/.git/scaffold-blocks.log"
  _ts59_run check-red-green-ts --base "$_ts59_base"
  _ts59_check "(g) an offender run logs one check-red-green-ts green-on-base-or-cap line" "$([ "$_ts59_rc" = 1 ] && [ "$(grep -c "$(printf 'check-red-green-ts\tgreen-on-base-or-cap\t-\t1')" "$_ts59_d/.git/scaffold-blocks.log" 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
  _ts59_check "(g) the exit-1 refusal ends with the class (a) trailer (#259)" "$([ "$(printf '%s\n' "$_ts59_out" | tail -n 1)" = "refusal class (a): this check failed on your own change. Fix the file, never the gate." ] && echo 1 || echo 0)"
  rm -f "$_ts59_d/.githooks/lib/refusal-log" "$_ts59_d/.git/scaffold-blocks.log"
  _ts59_run check-red-green-ts --base "$_ts59_base"
  _ts59_check "(g) without the logger the verdict is unchanged: exit 1, nothing written" "$([ "$_ts59_rc" = 1 ] && [ ! -e "$_ts59_d/.git/scaffold-blocks.log" ] && echo 1 || echo 0)"

  # The mutation twin's own log lines (#260 item 6): the size decline (exit 1,
  # --max-mutants 1 against scenario (a)'s several mutants) and the exit-2
  # refusal (scenario (f)).
  cp "$SCAFFOLD_DIR/githooks/lib/refusal-log.template" "$_ts59_d/.githooks/lib/refusal-log"
  chmod +x "$_ts59_d/.githooks/lib/refusal-log"
  _ts59_g checkout -q scen-a
  rm -f "$_ts59_d/.git/scaffold-blocks.log"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base" --max-mutants 1
  _ts59_check "(g) a mutation run over --max-mutants logs one check-mutation-diff-ts max-mutants line" "$([ "$_ts59_rc" = 1 ] && [ "$(grep -c "$(printf 'check-mutation-diff-ts\tmax-mutants\t-\t1')" "$_ts59_d/.git/scaffold-blocks.log" 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
  _ts59_check "(g) the mutation twin's exit-1 refusal ends with the class (a) trailer" "$([ "$(printf '%s\n' "$_ts59_out" | tail -n 1)" = "refusal class (a): this check failed on your own change. Fix the file, never the gate." ] && echo 1 || echo 0)"
  _ts59_g checkout -q scen-f
  rm -f "$_ts59_d/.git/scaffold-blocks.log"
  _ts59_run check-mutation-diff-ts --base "$_ts59_base"
  _ts59_check "(g) a mutation setup refusal logs one check-mutation-diff-ts setup-error line" "$([ "$_ts59_rc" = 2 ] && [ "$(grep -c "$(printf 'check-mutation-diff-ts\tsetup-error\t-\t2')" "$_ts59_d/.git/scaffold-blocks.log" 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
  rm -f "$_ts59_d/.githooks/lib/refusal-log" "$_ts59_d/.git/scaffold-blocks.log"

  # --- (h) skip and todo are invisible to vitest list: a notice, same exit ---
  _ts59_g checkout -q -B scen-h "$_ts59_base"
  # One listed red test beside them: a file with only skips lists 0 tests,
  # which the gate-status contract (#210) already refuses on its own.
  printf 'import { expect, it } from "vitest";\n\nit("is red", () => {\n  expect(1).toBe(2);\n});\nit.skip("later", () => {});\nit.todo("someday");\n' >"$_ts59_d/src/skipped.test.ts"
  _ts59_commit "add skipped tests"
  _ts59_run check-red-green-ts --base "$_ts59_base"
  _ts59_check "(h) added it.skip and it.todo do not change the verdict (exit 0)" "$([ "$_ts59_rc" = 0 ] && echo 1 || echo 0)"
  _ts59_check "(h) the output counts 2 added skip/todo lines as not listed" "$(printf '%s' "$_ts59_out" | grep -q '2 added line(s) use skip or todo' && echo 1 || echo 0)"

  rm -rf "$_ts59_d"
fi
