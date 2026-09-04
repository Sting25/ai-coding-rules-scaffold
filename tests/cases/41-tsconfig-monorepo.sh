# shellcheck shell=bash
# cases/41-tsconfig-monorepo.sh — where install.sh puts tsconfig.json (#163).
# Sourced into the driver's shell, so the globals (PASS/FAIL/HOOK_OUT/
# SCAFFOLD_DIR) are already in scope.
#
# The root tsconfig.json is the switch that makes the pre-commit hook and
# lint.yml run `tsc --noEmit` over the whole tree. In a workspaces monorepo
# that switch type-checks every workspace with the wrong compiler options and
# blocks every JS/TS commit (12,235 errors measured in #163). So the installer
# must NOT write it when the repo is a workspaces monorepo or already carries
# per-directory tsconfig files, must say so by name, and must still write it,
# with a note about what the hook will now do, for a plain frontend repo.
#
# Helpers are prefixed tsm_ and this file builds its own fixtures rather than
# borrowing another case's, so it also runs on its own.

echo "cases/41 — root tsconfig.json placement in monorepos (#163)"

# A fresh frontend repo: package.json plus one .ts file. Extra fixture files
# are created by the caller before install.sh runs.
_tsm_fixture() {
  local d
  d=$(mktemp -d)
  ( cd "$d" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" \
    && printf '{"name":"fixture","version":"1.0.0","private":true}\n' >package.json \
    && mkdir -p src && echo 'export const x = 1;' >src/index.ts )
  echo "$d"
}

_tsm_install() { ( cd "$1" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1; }

# (T) npm/yarn workspaces key: no root tsconfig.json, and the skip names the
#     file and the reason.
W=$(_tsm_fixture)
printf '{"name":"fixture","version":"1.0.0","private":true,"workspaces":["client","server"]}\n' >"$W/package.json"
mkdir -p "$W/client" "$W/server"
_tsm_install "$W"
if [ ! -e "$W/tsconfig.json" ] && grep -q "skip (workspaces monorepo): tsconfig.json" "$HOOK_OUT" \
   && [ -f "$W/eslint.config.js" ]; then
  echo "  ✓ workspaces key in package.json: no root tsconfig.json, skip printed, the rest of the frontend set still lands"; PASS=$((PASS + 1))
else
  echo "  ✗ workspaces monorepo should not receive a root tsconfig.json (and should say so)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$W"

# (T) pnpm-workspace.yaml is the same signal for pnpm monorepos.
P=$(_tsm_fixture)
printf 'packages:\n  - "packages/*"\n' >"$P/pnpm-workspace.yaml"
_tsm_install "$P"
if [ ! -e "$P/tsconfig.json" ] && grep -q "skip (workspaces monorepo): tsconfig.json" "$HOOK_OUT"; then
  echo "  ✓ pnpm-workspace.yaml: no root tsconfig.json, skip printed"; PASS=$((PASS + 1))
else
  echo "  ✗ pnpm workspace should not receive a root tsconfig.json"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$P"

# (T) No workspaces key, but nested tsconfig.json files already exist: the
#     repo type-checks per directory, so a root config would override that
#     with whole-tree checking. Skip, and name the directories.
N=$(_tsm_fixture)
mkdir -p "$N/client" "$N/server"
echo '{"compilerOptions":{"strict":true}}' >"$N/client/tsconfig.json"
echo '{"compilerOptions":{"strict":true}}' >"$N/server/tsconfig.json"
_tsm_install "$N"
if [ ! -e "$N/tsconfig.json" ] && grep -q "skip (tsconfig.json in client server): tsconfig.json" "$HOOK_OUT"; then
  echo "  ✓ nested client/ and server/ tsconfig.json: no root file, skip names both directories"; PASS=$((PASS + 1))
else
  echo "  ✗ nested tsconfig.json files should suppress the root one and be named"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$N"

# (T) A tsconfig.json under node_modules is a dependency's, not the repo's:
#     it must not count as nested, so a plain repo with installed deps still
#     receives the root file.
D=$(_tsm_fixture)
mkdir -p "$D/node_modules/somelib"
echo '{"compilerOptions":{"strict":false}}' >"$D/node_modules/somelib/tsconfig.json"
_tsm_install "$D"
if [ -f "$D/tsconfig.json" ] && grep -q "installed:    tsconfig.json" "$HOOK_OUT"; then
  echo "  ✓ a dependency's tsconfig.json under node_modules is ignored; the root file is installed"; PASS=$((PASS + 1))
else
  echo "  ✗ node_modules must be pruned from the nested-tsconfig probe"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) Plain frontend repo: the file lands, byte-identical to the template, AND
#     the install output says what the hook will now do and how to undo it.
#     The note is the fix for "the install output does not call out that a
#     root tsconfig.json was placed" (#163).
S=$(_tsm_fixture)
_tsm_install "$S"
if [ -f "$S/tsconfig.json" ] && cmp -s "$S/tsconfig.json" "$SCAFFOLD_DIR/tsconfig.json.template" \
   && grep -q "note:         tsconfig.json installed at the repo root" "$HOOK_OUT" \
   && grep -q "tsc --noEmit" "$HOOK_OUT"; then
  echo "  ✓ plain frontend repo still receives tsconfig.json, with a note that the hook now type-checks the tree"; PASS=$((PASS + 1))
else
  echo "  ✗ plain frontend repo must receive tsconfig.json and a whole-tree type-check note"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$S"

# (T) An existing root tsconfig.json keeps cp_safe's behaviour: untouched,
#     with the usual "skip (exists)" line, not a monorepo message.
E=$(_tsm_fixture)
echo '{"compilerOptions":{"target":"ES2019"}}' >"$E/tsconfig.json"
_tsm_install "$E"
if grep -q '"target":"ES2019"' "$E/tsconfig.json" && grep -q "skip (exists): tsconfig.json" "$HOOK_OUT"; then
  echo "  ✓ an existing root tsconfig.json is left untouched with the ordinary skip line"; PASS=$((PASS + 1))
else
  echo "  ✗ an existing root tsconfig.json must be left alone"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$E"
