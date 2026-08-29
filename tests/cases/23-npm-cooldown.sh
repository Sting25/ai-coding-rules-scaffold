# shellcheck shell=bash
# cases/23-npm-cooldown.sh: the opt-in npm install-layer cooldown
# (--npm-cooldown, #117). .npmrc is USER-OWNED (a project may already have
# one, or may hand-edit the shipped copy), so it installs via cp_safe, not
# cp_scaffold_preserve like the CI-workflow opt-ins cases/21 already covers:
# install if absent, skip on drift unless --force (back up first), never a
# drift NOTE. Sourced into the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/
# HOOK_OUT are already in scope.

echo "cases/23: --npm-cooldown opt-in flag (#117)"

_npmc_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$@" ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) a default install (no flag) writes no .npmrc: stays opt-in.
D=$(_npmc_fixture)
if [ ! -e "$D/.npmrc" ]; then
  echo "  ✓ a default install creates no .npmrc"; PASS=$((PASS + 1))
else
  echo "  ✗ a default install should not create .npmrc"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) --npm-cooldown installs .npmrc with min-release-age=7, byte-identical
# to the shipped template.
N=$(_npmc_fixture --npm-cooldown)
if [ -f "$N/.npmrc" ] && grep -q '^min-release-age=7$' "$N/.npmrc" \
   && cmp -s "$SCAFFOLD_DIR/.npmrc.template" "$N/.npmrc"; then
  echo "  ✓ --npm-cooldown installs .npmrc with min-release-age=7"; PASS=$((PASS + 1))
else
  echo "  ✗ --npm-cooldown should install .npmrc matching the shipped template"; FAIL=$((FAIL + 1))
fi
rm -rf "$N"

# (T) cp_safe semantics: a hand-edited .npmrc is left alone on a plain
# re-run (no drift note, no backup), and --force backs it up then replaces
# it with the shipped version.
S=$(_npmc_fixture --npm-cooldown)
printf '\n# local override\nregistry=https://example.invalid/\n' >>"$S/.npmrc"
( cd "$S" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --npm-cooldown ) >"$HOOK_OUT" 2>&1
if grep -qF "local override" "$S/.npmrc" && [ ! -e "$S/.npmrc.scaffold-bak" ] \
   && grep -q "skip (exists): .npmrc" "$HOOK_OUT"; then
  echo "  ✓ a hand-edited .npmrc is left alone on a plain re-run (cp_safe)"; PASS=$((PASS + 1))
else
  echo "  ✗ a hand-edited .npmrc should be skipped, not replaced, on a plain re-run"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
( cd "$S" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --npm-cooldown --force ) >"$HOOK_OUT" 2>&1
if [ -f "$S/.npmrc.scaffold-bak" ] && grep -qF "local override" "$S/.npmrc.scaffold-bak" \
   && cmp -s "$SCAFFOLD_DIR/.npmrc.template" "$S/.npmrc"; then
  echo "  ✓ --force backs up the edited .npmrc then installs the shipped version"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should back up the edited .npmrc then replace it"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$S"

# (T) uninstall.sh removes an unmodified .npmrc.
U=$(_npmc_fixture --npm-cooldown)
( cd "$U" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$U/.npmrc" ]; then
  echo "  ✓ uninstall.sh removes an unmodified .npmrc"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall.sh should remove an unmodified .npmrc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$U"
