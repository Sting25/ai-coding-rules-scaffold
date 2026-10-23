# shellcheck shell=bash
# cases/48-force-ownership.sh: --force vs --force-all (#190) and the TS-free
# tsconfig skip (#191). Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/
# SCAFFOLD_DIR are in scope. Helpers are prefixed fo_ and the fixtures are this
# file's own.
#
# #190: --force replaced user-owned configs and both rules docs behind the same
# routine "backed up:" line as a byte-identical refresh. --force now replaces
# scaffold-owned files only; --force-all is the explicit opt-in for the rest.
# #191: a root tsconfig.json turns on whole-tree `tsc --noEmit`, so a repo with
# no TypeScript at all must not receive one.

echo "cases/48: --force leaves user-owned files, --force-all replaces them (#190); no tsconfig without TypeScript (#191)"

# The user-owned files an install with these flags writes (the cp_safe set).
FO_OWNED=(coding-rules.md operational-rules.md .scaffold.toml .github/dependabot.yml
  ruff.toml .coveragerc eslint.config.js .prettierignore vitest.config.ts .claude/settings.json)

FO=$(mktemp -d)
FO_MODS=$(mktemp -d)
( cd "$FO" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" \
  && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml && echo 'export const x = 1;' >index.ts \
  && "$SCAFFOLD_DIR/install.sh" --both --claude --no-verify ) >"$HOOK_OUT" 2>&1
fo_i=0
for fo_f in "${FO_OWNED[@]}"; do
  fo_i=$((fo_i + 1))
  printf '\n# LOCAL EDIT 190\n' >>"$FO/$fo_f"
  cp "$FO/$fo_f" "$FO_MODS/$fo_i"
done
# One scaffold-owned file that only --force replaces (a drifted pattern file is
# kept with a note on a plain re-run).
printf '# LOCAL ROW 190\n' >>"$FO/.forbidden-patterns/frontend.txt"

# (T) --force: every edited user-owned file survives byte-for-byte with no
# backup, and the run names each one next to --force-all.
( cd "$FO" && "$SCAFFOLD_DIR/install.sh" --both --claude --no-verify --force ) >"$HOOK_OUT" 2>&1
fo_ok=1 fo_i=0
for fo_f in "${FO_OWNED[@]}"; do
  fo_i=$((fo_i + 1))
  cmp -s "$FO/$fo_f" "$FO_MODS/$fo_i" || { fo_ok=0; echo "      replaced under --force: $fo_f"; }
  [ ! -e "$FO/$fo_f.scaffold-bak" ] || { fo_ok=0; echo "      unexpected backup: $fo_f.scaffold-bak"; }
  grep -E "^kept \(user-owned\): $fo_f .*--force-all" "$HOOK_OUT" >/dev/null || { fo_ok=0; echo "      no hint for: $fo_f"; }
done
if [ "$fo_ok" -eq 1 ]; then
  echo "  ✓ --force leaves ${#FO_OWNED[@]} changed user-owned files in place and prints a --force-all hint for each"; PASS=$((PASS + 1))
else
  echo "  ✗ --force must not replace user-owned files"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) --force still replaces a scaffold-owned file, backed up first.
if ! grep -q 'LOCAL ROW 190' "$FO/.forbidden-patterns/frontend.txt" \
   && grep -q 'LOCAL ROW 190' "$FO/.forbidden-patterns/frontend.txt.scaffold-bak"; then
  echo "  ✓ --force still replaces a scaffold-owned file (the pattern file), backing it up"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should still replace and back up a scaffold-owned file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) --force-all: the same edited files are replaced by the shipped version,
# each edit lands in a .scaffold-bak, and the backup path is printed.
( cd "$FO" && "$SCAFFOLD_DIR/install.sh" --both --claude --no-verify --force-all ) >"$HOOK_OUT" 2>&1
fo_ok=1 fo_i=0
for fo_f in "${FO_OWNED[@]}"; do
  fo_i=$((fo_i + 1))
  { ! cmp -s "$FO/$fo_f" "$FO_MODS/$fo_i"; } || { fo_ok=0; echo "      not replaced under --force-all: $fo_f"; }
  cmp -s "$FO/$fo_f.scaffold-bak" "$FO_MODS/$fo_i" || { fo_ok=0; echo "      backup missing or wrong: $fo_f.scaffold-bak"; }
  grep -qF "backed up:    $fo_f -> $fo_f.scaffold-bak" "$HOOK_OUT" || { fo_ok=0; echo "      backup path not printed: $fo_f"; }
done
if [ "$fo_ok" -eq 1 ]; then
  echo "  ✓ --force-all replaces ${#FO_OWNED[@]} user-owned files, backs each up and prints the backup path"; PASS=$((PASS + 1))
else
  echo "  ✗ --force-all should replace user-owned files with a backup"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) An unchanged user-owned file under --force is silent (no hint, no backup).
( cd "$FO" && "$SCAFFOLD_DIR/install.sh" --both --claude --no-verify --force ) >"$HOOK_OUT" 2>&1
if ! grep -q '^kept (user-owned)' "$HOOK_OUT"; then
  echo "  ✓ --force prints no user-owned hint for files that match the shipped version"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should stay quiet about unchanged user-owned files"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$FO" "$FO_MODS"

# (T) #191: a package.json repo with only JS gets no root tsconfig.json, and
# the skip names the reason. node_modules/dist .ts files do not count.
fo_ts_repo() {
  local __fo_var=$1 t
  fixture_repo t
  ( cd "$t" && echo '{"name":"x"}' >package.json && echo 'export const x = 1;' >app.js )
  printf -v "$__fo_var" '%s' "$t"
}
fo_ts_repo FOJ
mkdir -p "$FOJ/node_modules/dep" "$FOJ/dist"
echo 'export {}' >"$FOJ/node_modules/dep/index.d.ts"
echo 'export {}' >"$FOJ/dist/out.d.ts"
( cd "$FOJ" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
# A second run must decide the same way: the first one placed vitest.config.ts,
# which is the scaffold's own TypeScript, not the project's.
( cd "$FOJ" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ ! -e "$FOJ/tsconfig.json" ] && grep -qF "skip (no tracked TypeScript files): tsconfig.json" "$HOOK_OUT" \
   && [ -f "$FOJ/eslint.config.js" ]; then
  echo "  ✓ a repo with no TypeScript gets no root tsconfig.json, on a re-run too; the skip names the reason"; PASS=$((PASS + 1))
else
  echo "  ✗ a TS-free repo must not receive a root tsconfig.json"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# scaffold-assess must agree with the installer on the same repo.
( cd "$FOJ" && git add -A ) >/dev/null 2>&1 || true
( cd "$FOJ" && "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "tsconfig.json: no TypeScript files" "$HOOK_OUT"; then
  echo "  ✓ scaffold-assess reports the same TS-free verdict as the installer"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-assess should report no TypeScript files for the TS-free repo"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$FOJ"

# (T) #191: one tracked .ts file and the root tsconfig.json is installed.
fo_ts_repo FOT
echo 'export const y: number = 1;' >"$FOT/lib.ts"
( cd "$FOT" && git add lib.ts && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ -f "$FOT/tsconfig.json" ] && grep -qF "installed:    tsconfig.json" "$HOOK_OUT"; then
  echo "  ✓ a repo with a tracked .ts file still gets the root tsconfig.json"; PASS=$((PASS + 1))
else
  echo "  ✗ a repo with a tracked .ts file should receive tsconfig.json"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$FOT"

# (T) #191 outside git: the find fallback installs with a .ts file and skips without one.
FON=$(mktemp -d)
echo '{"name":"x"}' >"$FON/package.json"; echo 'export const z = 1;' >"$FON/a.ts"
( cd "$FON" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
fo_with=0; [ -f "$FON/tsconfig.json" ] && fo_with=1
rm -rf "$FON"; FON=$(mktemp -d)
echo '{"name":"x"}' >"$FON/package.json"; echo 'x' >"$FON/a.js"
( cd "$FON" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1
if [ "$fo_with" -eq 1 ] && [ ! -e "$FON/tsconfig.json" ]; then
  echo "  ✓ outside a git repo the same probe decides: .ts present installs, absent skips"; PASS=$((PASS + 1))
else
  echo "  ✗ the non-git fallback should install with a .ts file and skip without one (with=$fo_with)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$FON"
