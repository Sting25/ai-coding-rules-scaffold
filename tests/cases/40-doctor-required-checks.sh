# shellcheck shell=bash
# cases/40-doctor-required-checks.sh: scaffold-doctor's required-status-checks
# section (issue #172) says what it could NOT measure instead of staying
# silent, and never turns a missing tool into a false "armed". Sourced into
# the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are in scope.
#
# The live measurement needs the network and a logged-in gh, which a test
# must not depend on. What CAN be asserted offline are the three fallbacks,
# each of which is the honest shape for a check that cannot run: no GitHub
# remote, gh absent, gh present but not logged in. A fourth assertion pins
# that none of them counts as a gap or an ok: a fallback that exited 1 would
# make every offline doctor run red; one that printed ✓ would report a gate
# that was never measured.

echo "cases/40: scaffold-doctor reports what it could not measure about required status checks"

_rc_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init -q && git config user.email t@test.local && git config user.name "Scaffold Test" \
      && "$SCAFFOLD_DIR/install.sh" --shell --no-verify "$@" ) >/dev/null 2>&1
  printf '%s' "$t"
}

# 1. No GitHub remote: a local-only repo, the common case in this suite.
_rc_repo=$(_rc_fixture)
( cd "$_rc_repo" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -q 'required status checks: not checked (remote.origin is not a github.com URL)' "$HOOK_OUT"; then
  echo "  ✓ no GitHub remote: reported as not checked, with the reason"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected the no-remote note"; grep -i 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# 2. GitHub remote but no gh on PATH: a PATH with only the directories the
# doctor's other checks need, minus wherever gh lives.
( cd "$_rc_repo" && git remote add origin git@github.com:example/project.git )
_rc_nogh=$(mktemp -d)
for _rc_tool in bash git grep sed awk sort uniq cut tr wc head tail mktemp basename dirname cat cmp find xargs jq python3 ls test; do
  _rc_path=$(command -v "$_rc_tool" 2>/dev/null || true)
  [ -n "$_rc_path" ] && ln -s "$_rc_path" "$_rc_nogh/$_rc_tool" 2>/dev/null
done
( cd "$_rc_repo" && PATH="$_rc_nogh" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -q 'required status checks: not checked (gh CLI not installed' "$HOOK_OUT"; then
  echo "  ✓ GitHub remote, no gh: reported as not checked, names the missing tool"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected the gh-not-installed note"; grep -i 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# 3. gh present but not logged in: a stub gh whose `auth status` fails.
printf '#!/bin/sh\n[ "$1" = auth ] && exit 1\nexit 1\n' > "$_rc_nogh/gh"; chmod +x "$_rc_nogh/gh"
( cd "$_rc_repo" && PATH="$_rc_nogh" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -q 'required status checks: not checked (gh is not logged in' "$HOOK_OUT"; then
  echo "  ✓ gh present, not logged in: reported as not checked, says how to fix"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected the gh-not-logged-in note"; grep -i 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# 4. None of the three fallbacks is a gap or an ok for this section.
if ! grep -qE '^\s+[✓✗] .*required status checks' "$HOOK_OUT" && ! grep -qE '✗ .*requires NO status checks' "$HOOK_OUT"; then
  echo "  ✓ an unmeasurable check is a note, never a ✓ or a gap"
  PASS=$((PASS + 1))
else
  echo "  ✗ the fallback produced a ✓ or ✗ line for a check that did not run"
  grep -E 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# 5 and 6. The live path, with gh stubbed: zero required checks is a gap
# (exit 1); six is an ok. The stub answers the three gh api calls the section
# makes, keyed on the endpoint, and nothing else.
_rc_stub() {
  printf '#!/bin/sh\ncase "$*" in *"auth status"*) exit 0 ;; *"/protection"*) echo %s ;; *"/rules/branches/"*) echo %s ;; *"repos/"*) echo main ;; esac\n' "$1" "$2" > "$_rc_nogh/gh"
  chmod +x "$_rc_nogh/gh"
}
_rc_stub 0 0
_rc_rc=0; ( cd "$_rc_repo" && PATH="$_rc_nogh" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || _rc_rc=$?
if [ "$_rc_rc" -eq 1 ] && grep -q "requires NO status checks" "$HOOK_OUT" && grep -q 'fix: import .github/rulesets/main-protection.json' "$HOOK_OUT"; then
  echo "  ✓ measured zero required checks: a gap with the fix named, exit 1"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected a gap and exit 1 for zero required checks (got exit $_rc_rc)"; grep -i 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi
_rc_stub 6 0
( cd "$_rc_repo" && PATH="$_rc_nogh" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -q '✓ main requires status checks before merge (6 via branch protection, 0 ruleset rule(s))' "$HOOK_OUT"; then
  echo "  ✓ measured six required checks: reported armed with the counts"
  PASS=$((PASS + 1))
else
  echo "  ✗ expected the armed line with counts"; grep -i 'status checks' "$HOOK_OUT" | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

rm -rf "$_rc_repo" "$_rc_nogh"
unset _rc_repo _rc_nogh _rc_tool _rc_path _rc_rc
unset -f _rc_fixture _rc_stub
