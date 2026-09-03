# shellcheck shell=bash
# cases/39-scaffold-assess.sh: scaffold-assess.sh measures a tree that has NOT
# adopted the scaffold, per component, without writing to it. Sourced into the
# driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are already in scope.
#
# WHY. The assessment is the "measure before you adopt" step COMPONENTS.md
# leads with. Its whole value is that a finding it reports is one the hook
# would block, and that a component with no matching files is reported as not
# applicable rather than clean. The first smoke of the script reported every
# scanner clean on a tree with a tracked .env, a 600 KB blob and a
# breakpoint(): the finding count used a bracket expression with a multibyte
# glyph, which is a byte class under a C locale. So this case runs under LC_ALL=C
# as well as the inherited locale, and asserts the counts, not the exit code.
#
# The fixture is one repository with: a tracked .env (check-filenames), a
# 600 KB file (check-large-files), a .py with breakpoint() and print()
# (backend.txt), a .js with console.log (frontend.txt), and no Go files
# (go.txt must read "not applicable"). One untracked file checks the
# not-scanned count. Assertions read the report's own lines.

echo "cases/39: scaffold-assess.sh reports per component, counts findings, writes nothing"

_sa_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init -q && git config user.email t@test.local && git config user.name "Scaffold Test" \
      && mkdir -p src && printf 'import os\nbreakpoint()\nprint("x")\n' > src/app.py \
      && printf 'console.log(1)\n' > src/a.js && printf 'x=1\n' > .env \
      && head -c 600000 /dev/zero > big.bin && git add -f src .env big.bin && git commit -q -m init \
      && printf 'loose\n' > loose.txt )
  printf '%s' "$t"
}

_sa_repo=$(_sa_fixture)
_sa_before=$(cd "$_sa_repo" && git status --porcelain && ls -A)

for _sa_locale in inherit C; do
  if [ "$_sa_locale" = C ]; then
    ( cd "$_sa_repo" && LC_ALL=C LANG=C bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1
  else
    ( cd "$_sa_repo" && bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1
  fi
  _sa_rc=$?
  if [ "$_sa_rc" -eq 0 ] \
     && grep -q '✗ check-filenames: 1 finding' "$HOOK_OUT" \
     && grep -q '✗ check-large-files: 1 finding' "$HOOK_OUT" \
     && grep -q '✗ backend.txt: 2 finding(s) across 1 file' "$HOOK_OUT" \
     && grep -q '✗ frontend.txt: 1 finding(s) across 1 file' "$HOOK_OUT"; then
    echo "  ✓ [$_sa_locale locale] counts: .env, 600 KB blob, 2 backend and 1 frontend findings, exit 0"
    PASS=$((PASS + 1))
  else
    echo "  ✗ [$_sa_locale locale] expected the four finding lines and exit 0 (got exit $_sa_rc)"
    sed 's/^/      /' "$HOOK_OUT" | head -30
    FAIL=$((FAIL + 1))
  fi
done

# The inherited-locale report is still in HOOK_OUT for the structural checks.
( cd "$_sa_repo" && bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -q -- '- go.txt: not applicable (no tracked files with extension: go)' "$HOOK_OUT" \
   && ! grep -q '✓ go.txt' "$HOOK_OUT"; then
  echo "  ✓ a language with no tracked files reads 'not applicable', never 'clean'"
  PASS=$((PASS + 1))
else
  echo "  ✗ go.txt should be reported as not applicable"
  FAIL=$((FAIL + 1))
fi
if grep -q 'tracked files scanned: 4   untracked (not scanned, not in the index): 1' "$HOOK_OUT"; then
  echo "  ✓ the untracked file is counted as not scanned rather than left silent"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected 'tracked files scanned: 4   untracked ...: 1'"
  grep 'tracked files' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi
if grep -q '^      ✗ src/app.py: Remove breakpoint() before committing' "$HOOK_OUT"; then
  echo "  ✓ samples name the file and the rule the hook would cite"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected an indented sample line for src/app.py breakpoint()"
  FAIL=$((FAIL + 1))
fi
_sa_after=$(cd "$_sa_repo" && git status --porcelain && ls -A)
if [ "$_sa_before" = "$_sa_after" ] && [ ! -e "$_sa_repo/.forbidden-patterns" ] && [ ! -e "$_sa_repo/.ruff_cache" ]; then
  echo "  ✓ nothing was written to the target (status and listing identical; no .forbidden-patterns, no .ruff_cache)"
  PASS=$((PASS + 1))
else
  echo "  ✗ the target tree changed:"
  diff <(echo "$_sa_before") <(echo "$_sa_after") | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# Not a git repository: the scanners read the index, so refuse with exit 2.
_sa_plain=$(mktemp -d)
if ( cd "$_sa_plain" && bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1; then
  echo "  ✗ outside a git repository the script should exit 2"
  FAIL=$((FAIL + 1))
else
  if [ $? -eq 2 ] 2>/dev/null || grep -q 'not inside a git repository' "$HOOK_OUT"; then
    echo "  ✓ outside a git repository: refuses with the reason (the scanners read the index)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ wrong failure outside a git repository"; sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$_sa_plain"

# The npm entry point routes `assess` to the script, like `doctor`.
if command -v node >/dev/null 2>&1; then
  if ( cd "$_sa_repo" && node "$SCAFFOLD_DIR/bin/cli.js" assess ) >"$HOOK_OUT" 2>&1 && grep -q '✗ check-filenames: 1 finding' "$HOOK_OUT"; then
    echo "  ✓ 'npx ai-coding-rules-scaffold assess' routes to scaffold-assess.sh"
    PASS=$((PASS + 1))
  else
    echo "  ✗ bin/cli.js assess did not produce the assessment"; sed 's/^/      /' "$HOOK_OUT" | head -5
    FAIL=$((FAIL + 1))
  fi
else
  echo "  - SKIP: node not installed, the cli.js assess route was not exercised"
  SKIP=$((SKIP + 1))
fi

# SCAFFOLD_PATTERNS_DIR: the override the script relies on. A pattern dir
# holding one custom rule flags a tracked file only when the variable points
# at it; unset, the scanners read .forbidden-patterns/ (absent here), so the
# same file passes. Positive on both sides, not "no output".
_sa_alt=$(mktemp -d)
printf 'SCAFFOLDTESTTOKEN\ttest rule from an alternate pattern dir\n' > "$_sa_alt/secrets.txt"
printf '# scaffold-extensions: py\nSCAFFOLDTESTTOKEN\ttest rule from an alternate pattern dir\n' > "$_sa_alt/backend.txt"
( cd "$_sa_repo" && printf 'SCAFFOLDTESTTOKEN = 1\n' > src/alt.py && git add src/alt.py )
# _sa_scan DIR SCANNER: run one scanner over src/alt.py from the fixture with
# SCAFFOLD_PATTERNS_DIR set to DIR (unset when DIR is empty). Output only;
# the scanner's exit status is the finding, not an error.
_sa_scan() {
  local dir=$1; shift
  ( cd "$_sa_repo" || exit 1
    if [ -n "$dir" ]; then export SCAFFOLD_PATTERNS_DIR="$dir"; fi
    printf 'src/alt.py\0' | bash "$@" ) 2>&1 || true
}
_sa_with=$(_sa_scan "$_sa_alt" "$SCAFFOLD_DIR/githooks/lib/check-secrets.template")
_sa_without=$(_sa_scan "" "$SCAFFOLD_DIR/githooks/lib/check-secrets.template")
_sa_pwith=$(_sa_scan "$_sa_alt" "$SCAFFOLD_DIR/githooks/lib/check-patterns.template")
_sa_pwithout=$(_sa_scan "" "$SCAFFOLD_DIR/githooks/lib/check-patterns.template")
if grep -q 'alternate pattern dir' <<<"$_sa_with" && ! grep -q 'alternate pattern dir' <<<"$_sa_without" \
   && grep -q 'alternate pattern dir' <<<"$_sa_pwith" && ! grep -q 'alternate pattern dir' <<<"$_sa_pwithout"; then
  echo "  ✓ SCAFFOLD_PATTERNS_DIR redirects check-secrets and check-patterns; unset, both read the default path"
  PASS=$((PASS + 1))
else
  echo "  ✗ SCAFFOLD_PATTERNS_DIR override not honored by both scanners"
  printf '%s\n' "$_sa_with" "$_sa_without" "$_sa_pwith" "$_sa_pwithout" | sed 's/^/      /' | head -8
  FAIL=$((FAIL + 1))
fi
( cd "$_sa_repo" && git reset -q src/alt.py && rm -f src/alt.py )
rm -rf "$_sa_alt" "$_sa_repo"
unset _sa_repo _sa_before _sa_after _sa_locale _sa_rc _sa_plain _sa_alt _sa_with _sa_without _sa_pwith _sa_pwithout
unset -f _sa_fixture _sa_scan
