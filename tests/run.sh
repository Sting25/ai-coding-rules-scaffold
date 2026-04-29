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

# 6. clean code passes
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

echo ""
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL
