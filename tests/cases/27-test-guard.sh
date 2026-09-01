# shellcheck shell=bash
# cases/27-test-guard.sh: the opt-in red-green test-integrity gate
# (--test-guard, #140 item 2, plus the advisory mutation layer from #145).
# Four artifacts, three copy policies: .githooks/lib/check-red-green and
# .githooks/lib/check-mutation-diff are both scaffold-owned (cp_scaffold +
# mkx, refreshed on upgrade), test-guard.yml is a drift-preserving CI
# workflow (cp_scaffold_preserve; the drift semantics themselves are proven
# by cases/21's _wd_case, not re-proven here), and the rules section is an
# append-if-marker-absent merge into user-owned coding-rules.md, the same
# pattern as install-claude.sh's CLAUDE.md merge, so a re-run must never
# append twice. check-mutation-diff's own honesty contract is exercised
# directly below: verify_mutmut() runs before anything else in main(),
# including the "nothing to mutate" early return, so in this suite's
# environment, which has no mutmut installed (measured, not assumed),
# invoking the installed check with a real --base must exit 2 with a
# distinctive "mutmut is not importable" message, never a false 0. Sourced
# into the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/HOOK_OUT are already
# in scope.

echo "cases/27: --test-guard opt-in red-green gate (#140)"

_tg_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$@" ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) a default install (no flag) creates none of the four artifacts:
# stays opt-in.
D=$(_tg_fixture)
if [ ! -e "$D/.githooks/lib/check-red-green" ] && [ ! -e "$D/.githooks/lib/check-mutation-diff" ] \
   && [ ! -e "$D/.github/workflows/test-guard.yml" ] \
   && ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$D/coding-rules.md"; then
  echo "  ✓ a default install creates no test-guard artifacts"; PASS=$((PASS + 1))
else
  echo "  ✗ a default install should create no test-guard artifacts"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) --test-guard installs all four: both checks (executable,
# byte-identical to their shipped templates), the workflow (byte-identical),
# and the rules section appended to coding-rules.md exactly once, with the
# original coding-rules.md content still in place above it.
T=$(_tg_fixture --test-guard)
if [ -x "$T/.githooks/lib/check-red-green" ] \
   && cmp -s "$SCAFFOLD_DIR/githooks/lib/check-red-green.template" "$T/.githooks/lib/check-red-green" \
   && [ -x "$T/.githooks/lib/check-mutation-diff" ] \
   && cmp -s "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" "$T/.githooks/lib/check-mutation-diff" \
   && cmp -s "$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template" "$T/.github/workflows/test-guard.yml" \
   && grep -q '^# Coding rules$' "$T/coding-rules.md" \
   && [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$T/coding-rules.md")" -eq 1 ]; then
  echo "  ✓ --test-guard installs both checks, the workflow, and the rules section"; PASS=$((PASS + 1))
else
  echo "  ✗ --test-guard should install both checks + workflow + appended rules section"; FAIL=$((FAIL + 1))
fi

# (T) the installed check is runnable python3 and exits 0 in a repo with no
# tests/ directory (its documented nothing-to-verify path): the positive
# assertion that the artifact executes, not just that no error appeared.
if ( cd "$T" && python3 .githooks/lib/check-red-green --base HEAD ) >"$HOOK_OUT" 2>&1; then
  echo "  ✓ installed check-red-green runs and exits 0 with no tests directory"; PASS=$((PASS + 1))
else
  echo "  ✗ installed check-red-green should exit 0 with no tests directory"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) the installed check-mutation-diff is runnable python3 and honors its
# documented exit contract: verify_mutmut() runs before anything else in
# main(), including the "nothing to mutate" early return, so with mutmut
# not importable it must exit 2 naming that reason, never a false 0 or a
# generic crash. Guarded on a live re-check of the assumption (this suite's
# environment has no mutmut installed) so environment drift fails loudly
# here instead of silently validating the wrong path.
if python3 -c 'import mutmut' >/dev/null 2>&1; then
  echo "  ✗ check-mutation-diff honesty-contract assertion assumes mutmut is not importable here, but it now is; this assertion needs the other deterministic path"; FAIL=$((FAIL + 1))
else
  mut_rc=0
  ( cd "$T" && python3 .githooks/lib/check-mutation-diff --base HEAD ) >"$HOOK_OUT" 2>&1 || mut_rc=$?
  if [ "$mut_rc" -eq 2 ] && grep -q 'mutmut is not importable' "$HOOK_OUT"; then
    echo "  ✓ installed check-mutation-diff exits 2 naming mutmut not importable"; PASS=$((PASS + 1))
  else
    echo "  ✗ installed check-mutation-diff should exit 2 naming mutmut not importable (got exit $mut_rc)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
fi

# (T) a re-run with the same flag appends nothing: the marker section must
# appear exactly once afterwards, and the run must not back coding-rules.md
# up (nothing was replaced).
( cd "$T" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --test-guard ) >"$HOOK_OUT" 2>&1
if [ "$(grep -c 'ai-coding-rules-scaffold:test-guard:begin' "$T/coding-rules.md")" -eq 1 ] \
   && [ ! -e "$T/coding-rules.md.scaffold-bak" ]; then
  echo "  ✓ a re-run never appends the rules section twice"; PASS=$((PASS + 1))
else
  echo "  ✗ a re-run should leave exactly one appended rules section"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$T"

# (T) uninstall.sh removes the unmodified checks and workflow, and leaves
# coding-rules.md (user-owned) with the appended section intact.
U=$(_tg_fixture --test-guard)
( cd "$U" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$U/.githooks/lib/check-red-green" ] && [ ! -e "$U/.githooks/lib/check-mutation-diff" ] \
   && [ ! -e "$U/.github/workflows/test-guard.yml" ] \
   && grep -q 'ai-coding-rules-scaffold:test-guard:begin' "$U/coding-rules.md"; then
  echo "  ✓ uninstall.sh removes both checks + workflow, keeps the user-owned rules file"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall.sh should remove both checks + workflow and keep coding-rules.md"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$U"
