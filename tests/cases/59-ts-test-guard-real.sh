# shellcheck shell=bash
# cases/59-ts-test-guard-real.sh: the TypeScript test-guard twin against the
# REAL tools (#205), the repeatable counterpart of case 58's stubbed section.
# Sourced into the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR are in scope.
#
# Gated on SCAFFOLD_TS_TOOLS: a directory whose node_modules holds vitest,
# @stryker-mutator/core and @stryker-mutator/vitest-runner (at the versions
# the scripts pin; Stryker 10 needs Node 22). The suite never npm-installs,
# so without it every assertion here is SKIPped and counted, never silently
# dropped. Typical set-up:
#   mkdir t && cd t && npm init -y >/dev/null &&
#   npm install --ignore-scripts vitest@5.1.0 \
#     @stryker-mutator/core@10.1.1 @stryker-mutator/vitest-runner@10.1.1
#   SCAFFOLD_TS_TOOLS=$PWD bash tests/run.sh
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

echo "cases/59: TypeScript test-guard twin against real Vitest and Stryker (#205)"

_ts59_n=12
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
  _ts59_check "(a) mutation layer prints a verdict (mutation OK or mutation summary)" "$(printf '%s' "$_ts59_out" | grep -Eq 'mutation (OK|summary):' && echo 1 || echo 0)"

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
  _ts59_check "(c) the output still carries a verdict for src/neg.ts, not a crash" "$(printf '%s' "$_ts59_out" | grep -Eq 'mutating: src/neg.ts$' && printf '%s' "$_ts59_out" | grep -Eq 'mutation (summary|notice):|mutation OK:' && echo 1 || echo 0)"

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
  _ts59_check "(e) at least 1 mutant was generated for the [id] path (escape works)" "$(printf '%s' "$_ts59_out" | grep -Eq 'mutation OK: [1-9][0-9]* mutants|mutation summary: [0-9]+ killed, [0-9]+ not killed \(([1-9][0-9]*) total' && echo 1 || echo 0)"

  rm -rf "$_ts59_d"
fi
