# shellcheck shell=bash
# cases/21-lint-workflow-drift.sh — cp_scaffold_preserve, install-lib.sh's
# drift-preserving policy for .github/workflows/lint.yml (#105). Sourced into
# the driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and helpers are
# already in scope.
#
# What #105 was: lint.yml used cp_scaffold (scaffold-owned, refreshed on a
# plain re-run) even though it is the file a project commonly hand-edits to
# add local CI steps (e.g. setup-node for a local.d check). A re-run silently
# discarded that edit; a real downstream repo measured 23 deletions, 0
# insertions from one upgrade, with no signal beyond a log line and no way
# back except the .scaffold-bak. lint.yml now goes through
# cp_scaffold_preserve: drift is kept and notified, same shape as
# .forbidden-patterns/*.txt via cp_pattern; --force still replaces it, backed
# up first.

echo "cases/21 — lint.yml drift-preserving install policy (#105)"

_lwd_fixture() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) drifted lint.yml is PRESERVED and the drift note is printed, with no
#     .scaffold-bak — cp_scaffold_preserve only backs up under --force, same
#     as cp_pattern.
LWD1=$(_lwd_fixture)
printf '\n# local CI customization: setup-node for a local.d check\n' >>"$LWD1/.github/workflows/lint.yml"
( cd "$LWD1" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if grep -qF "local CI customization" "$LWD1/.github/workflows/lint.yml" \
   && grep -q 'note (drift):.*lint.yml' "$HOOK_OUT" \
   && ! cmp -s "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" "$LWD1/.github/workflows/lint.yml" \
   && [ ! -e "$LWD1/.github/workflows/lint.yml.scaffold-bak" ]; then
  echo "  ✓ a drifted lint.yml is kept, with a drift note and no backup"; PASS=$((PASS + 1))
else
  echo "  ✗ drifted lint.yml should be kept with a drift note (#105)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$LWD1"

# (T) --force on a drifted lint.yml backs up the user's version, then installs
#     the shipped one — the documented escape hatch from the drift note,
#     mirroring cp_pattern's --force behavior on forbidden-patterns files.
LWD2=$(_lwd_fixture)
printf '\n# local CI customization: setup-node for a local.d check\n' >>"$LWD2/.github/workflows/lint.yml"
( cd "$LWD2" && "$SCAFFOLD_DIR/install.sh" --frontend --force --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$LWD2/.github/workflows/lint.yml.scaffold-bak" ] \
   && grep -qF "local CI customization" "$LWD2/.github/workflows/lint.yml.scaffold-bak" \
   && cmp -s "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" "$LWD2/.github/workflows/lint.yml"; then
  echo "  ✓ --force backs up a drifted lint.yml then installs the shipped one"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should back up then replace a drifted lint.yml"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$LWD2"

# (T) a PRISTINE (unchanged) lint.yml is a silent no-op on re-run — matches
#     the shipped version, so nothing is "updated:", no drift note fires, and
#     the file is untouched. Guards against cp_scaffold_preserve churning an
#     already-current install (same guarantee cp_scaffold and cp_pattern give).
LWD3=$(_lwd_fixture)
( cd "$LWD3" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if cmp -s "$SCAFFOLD_DIR/.github/workflows/lint.yml.template" "$LWD3/.github/workflows/lint.yml" \
   && ! grep -q 'lint.yml' "$HOOK_OUT" \
   && [ ! -e "$LWD3/.github/workflows/lint.yml.scaffold-bak" ]; then
  echo "  ✓ a pristine lint.yml is a clean no-op on re-run"; PASS=$((PASS + 1))
else
  echo "  ✗ re-run should leave a pristine lint.yml alone with no output"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$LWD3"

reset_repo
