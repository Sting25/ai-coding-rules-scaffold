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
  ( cd "$t" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
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

# (T) the marker is matched after ANY comment lead-in, not only `#` (audit
# code-install-policy-4). The pattern used to be the literal string
# `# Repo adaptation:`, so the one warning that exists to stop a marked
# divergence disappearing could never fire for a file that is not #-commented.
# Measured: with a `# Repo adaptation:` line in lint.yml and a
# `// Repo adaptation:` line in eslint.config.js, `install.sh --frontend --force`
# warned by name about the first and overwrote the second in total silence; the
# marker was afterwards found only in eslint.config.js.scaffold-bak.
JS=$(_radapt_fixture)
printf '\n// Repo adaptation: relaxed no-console for the vendored worker\n' >>"$JS/eslint.config.js"
( cd "$JS" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate --force ) >"$HOOK_OUT" 2>&1
if grep -q "warning: eslint.config.js carried 1 'Repo adaptation' line(s)" "$HOOK_OUT" \
   && grep -q 'relaxed no-console for the vendored worker' "$HOOK_OUT" \
   && grep -qF "eslint.config.js.scaffold-bak" "$HOOK_OUT" \
   && grep -qF '// Repo adaptation: relaxed no-console for the vendored worker' "$JS/eslint.config.js.scaffold-bak"; then
  echo "  ✓ a '//' Repo-adaptation marker in a JS config warns by name when overwritten"; PASS=$((PASS + 1))
else
  echo "  ✗ a '//' Repo-adaptation marker should warn by name, not be dropped silently"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$JS"

# (T) JSON files cannot carry a `#` comment at all, so the documented form for
# tsconfig.json / .prettierrc.json / the agent configs is a `//`-prefixed KEY,
# which is valid JSON and must be matched by the same pattern. Inserted after
# the opening brace, where the shipped tsconfig.json already carries `//` lines.
JN=$(_radapt_fixture)
awk 'NR == 1 { print; print "  \"// Repo adaptation: kept ES2019 for the vendored runtime\": true," ; next } { print }' \
  "$JN/tsconfig.json" >"$JN/tsconfig.next" && mv "$JN/tsconfig.next" "$JN/tsconfig.json"
( cd "$JN" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate --force ) >"$HOOK_OUT" 2>&1
if grep -q "warning: tsconfig.json carried 1 'Repo adaptation' line(s)" "$HOOK_OUT" \
   && grep -q 'kept ES2019 for the vendored runtime' "$HOOK_OUT"; then
  echo "  ✓ a JSON '// Repo adaptation:' key warns by name when overwritten"; PASS=$((PASS + 1))
else
  echo "  ✗ a JSON '// Repo adaptation:' key should warn by name when overwritten"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$JN"

# (T) the broadened pattern still requires the marker to FOLLOW the comment
# leader: a line that merely mentions it mid-sentence, and a URL's '//', stay
# quiet. Without this the warning would fire on prose and stop meaning anything.
JQ=$(_radapt_fixture)
printf '\n# notes: Repo adaptation: this one is recorded elsewhere\n' >>"$JQ/.githooks/pre-commit"
printf '# see https://example.invalid/docs for the convention\n' >>"$JQ/.githooks/pre-commit"
( cd "$JQ" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --coverage-gate ) >"$HOOK_OUT" 2>&1
if ! grep -q "carried .* 'Repo adaptation' line(s)" "$HOOK_OUT" \
   && grep -q 'backed up:    .githooks/pre-commit' "$HOOK_OUT"; then
  echo "  ✓ a mention that does not directly follow a comment leader stays quiet"; PASS=$((PASS + 1))
else
  echo "  ✗ the broadened marker pattern should not fire on a mid-sentence mention"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$JQ"
