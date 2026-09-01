# shellcheck shell=bash
# cases/26-repo-adaptation-warn.sh: _backup warns when an overwritten file
# carried a `# Repo adaptation:` marker (#127). Root cause was that
# coverage.yml/tests.yml/gitleaks.yml used cp_scaffold (unconditional
# refresh) before #110 switched them to cp_scaffold_preserve; that switch
# already fixed the "no --force" silent-overwrite case (case 21 covers it).
# This is the remaining gap: even a WANTED overwrite (cp_scaffold's refresh,
# or --force on a drift-preserving file) still silently dropped the marked
# block with nothing but a generic "backed up:" line. Every cp_* overwrite
# funnels through the shared _backup helper, so testing it once here covers
# every call site. Sourced into the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/
# HOOK_OUT are already in scope.

echo "cases/26: _backup warns on a dropped '# Repo adaptation:' marker (#127)"

_radapt_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) cp_scaffold_preserve's --force path: a coverage.yml with a marked line
# is overwritten (that's the point of --force), but now warns by name and
# points at the backup, instead of a bare "backed up:"/"installed:" pair.
F=$(_radapt_fixture)
sed -i.bak '1a\
      # Repo adaptation: gate frontend on vitest actually being declared
' "$F/.github/workflows/coverage.yml" && rm -f "$F/.github/workflows/coverage.yml.bak"
( cd "$F" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate --force ) >"$HOOK_OUT" 2>&1
if grep -q "warning: .github/workflows/coverage.yml carried 1 'Repo adaptation' line(s)" "$HOOK_OUT" \
   && grep -q "gate frontend on vitest actually being declared" "$HOOK_OUT" \
   && grep -qF "coverage.yml.scaffold-bak" "$HOOK_OUT" \
   && grep -qF "# Repo adaptation: gate frontend on vitest actually being declared" "$F/.github/workflows/coverage.yml.scaffold-bak"; then
  echo "  ✓ --force on a drifted coverage.yml warns which Repo-adaptation line it dropped"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should warn about the dropped Repo-adaptation line and name the backup"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$F"

# (T) cp_scaffold's unconditional-refresh path (.githooks/pre-commit): the
# same warning fires even without --force, since cp_scaffold always
# refreshes a drifted scaffold-owned file.
P=$(_radapt_fixture)
sed -i.bak '2a\
# Repo adaptation: local hook tweak
' "$P/.githooks/pre-commit" && rm -f "$P/.githooks/pre-commit.bak"
( cd "$P" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate ) >"$HOOK_OUT" 2>&1
if grep -q "warning: .githooks/pre-commit carried 1 'Repo adaptation' line(s)" "$HOOK_OUT" \
   && grep -qF "# Repo adaptation: local hook tweak" "$P/.githooks/pre-commit.scaffold-bak"; then
  echo "  ✓ cp_scaffold's unconditional refresh (no --force) also warns on a dropped marker"; PASS=$((PASS + 1))
else
  echo "  ✗ cp_scaffold's refresh should warn on a dropped Repo-adaptation line even without --force"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$P"

# (T) no marker present: an ordinary drifted-file overwrite stays exactly as
# before, no warning noise for the common case.
N=$(_radapt_fixture)
printf '\n# ordinary local edit, no marker\n' >>"$N/.githooks/pre-commit"
( cd "$N" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate ) >"$HOOK_OUT" 2>&1
if ! grep -q "Repo adaptation" "$HOOK_OUT" && grep -q "backed up:    .githooks/pre-commit" "$HOOK_OUT"; then
  echo "  ✓ an ordinary drifted file (no marker) is backed up/refreshed with no extra warning"; PASS=$((PASS + 1))
else
  echo "  ✗ a marker-free drift should refresh quietly, no Repo-adaptation warning"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$N"
