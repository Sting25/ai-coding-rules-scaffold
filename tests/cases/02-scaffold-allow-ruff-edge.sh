# shellcheck shell=bash
# cases/02-scaffold-allow-ruff-edge.sh — scaffold-allow markers (10–12), ruff
# integration (13), and edge cases (14–18). Sourced into the driver's shell.

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
assert_rejects "scaffold-allow does not whitelist whole file" "structlog"

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
  assert_rejects "ruff catches unsorted imports" "I001"
else
  echo "  - skipped ruff test (ruff not installed)"
fi

# 14. unicode filename — `core.quotepath=on` (git default) would emit the
#     name as a C-quoted string, the downstream `[ -f "$file" ]` check
#     would fail, and the file would slip past every scanner. The hook
#     now uses `-c core.quotepath=off` so this case rejects.
echo 'pri''nt("debug")' >café.py
git add café.py
assert_rejects "unicode filename does not bypass scan" "structlog"

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

# 18. workflow validity — the rendered .github/workflows/lint.yml must be a
#     VALID GitHub Actions workflow. A job-level `if: hashFiles(...)` (or any
#     context-availability error) makes GitHub reject the whole file, silently
#     disabling every job — the failure mode that shipped a no-op lint workflow
#     to consumers for weeks. actionlint catches this class. shellcheck/pyflakes
#     integration is disabled: this guard is about Actions semantics, not shell
#     or Python style (those have their own checks). Skipped if actionlint is
#     absent locally; CI installs it so the guard always runs there.
if command -v actionlint >/dev/null 2>&1; then
  if actionlint -shellcheck= -pyflakes= .github/workflows/lint.yml >"$HOOK_OUT" 2>&1; then
    echo "  ✓ rendered lint.yml is a valid GitHub Actions workflow"
    PASS=$((PASS + 1))
  else
    echo "  ✗ rendered lint.yml failed actionlint validation"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  - skipped workflow validation (actionlint not installed)"
fi
