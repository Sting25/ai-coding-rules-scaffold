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

# Strip every directory that provides ruff from the real PATH, rather than
# assuming ruff is absent, so the ruff-unavailable cases below hold on a machine
# that has ruff installed. Computed once, used by 13a2 and 13b.
NOTOOL_PATH=
OLDIFS=$IFS
IFS=:
for rd in $PATH; do
  [ -x "$rd/ruff" ] && continue
  NOTOOL_PATH="$NOTOOL_PATH:$rd"
done
IFS=$OLDIFS
NOTOOL_PATH=${NOTOOL_PATH#:}

# 13. ruff lint integration — the hook should run ruff on staged .py when
#     ruff.toml is present and ruff is resolvable. The guard mirrors the hook's
#     own resolution chain (#144), so a ruff that is only importable as a module
#     (pip install --user, no console script on PATH) still exercises this case
#     instead of skipping it.
if command -v ruff >/dev/null 2>&1 || python3 -m ruff --version >/dev/null 2>&1; then
  cat >badimports.py <<'EOF'
import sys
import os
EOF
  git add badimports.py
  assert_rejects "ruff catches unsorted imports" "I001"
else
  echo "  - skipped ruff test (ruff not installed)"
fi

# 13a1. VENV-ONLY ruff (#144). The overwhelmingly common Python setup is a
#       pip/uv install into the project's .venv with the venv NOT activated:
#       ruff is installed, but not on PATH. The old `command -v ruff` gate
#       printed "not installed" and let real lint errors commit clean. A stub
#       .venv/bin/ruff stands in for the real binary so the case is
#       deterministic everywhere, and it exits non-zero so this also proves the
#       findings still reach FAILED.
mkdir -p .venv/bin
cat >.venv/bin/ruff <<'STUB'
#!/bin/sh
echo "VENV RUFF: F401 unused import"
exit 1
STUB
chmod +x .venv/bin/ruff
echo 'ok = True' >venvruff.py
git add venvruff.py
if PATH="$NOTOOL_PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ venv-only ruff: hook accepted despite a ruff failure"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -qF "VENV RUFF" "$HOOK_OUT"; then
  echo "  ✓ ruff in .venv/bin is found and its findings fail the commit"
  PASS=$((PASS + 1))
else
  echo "  ✗ venv-only ruff: rejected, but .venv/bin/ruff never ran"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf .venv
reset_repo

# 13a2. MODULE-ONLY ruff. `pip install --user` can leave ruff importable with no
#       console script on PATH at all; `python3 -m ruff` is then the only route.
#       Stub python3 (nothing else in the hook's default path shells out to it)
#       so the case is deterministic and does not depend on the host's Python.
PYSTUB=$(mktemp -d)
cat >"$PYSTUB/python3" <<'STUB'
#!/bin/sh
case "$*" in
  "-m ruff --version") echo "ruff 0.0.0-test"; exit 0 ;;
  "-m ruff check"*)    echo "MODULE RUFF: F401 unused import"; exit 1 ;;
esac
exit 1
STUB
chmod +x "$PYSTUB/python3"
echo 'ok = True' >modruff.py
git add modruff.py
if PATH="$PYSTUB:$NOTOOL_PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ module-only ruff: hook accepted despite a ruff failure"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -qF "MODULE RUFF" "$HOOK_OUT"; then
  echo "  ✓ 'python3 -m ruff' is used when no ruff binary exists"
  PASS=$((PASS + 1))
else
  echo "  ✗ module-only ruff: rejected, but python3 -m ruff never ran"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$PYSTUB"
reset_repo

# 13b. skip notice: a staged .py file with ruff unavailable by EVERY route must
#      print a one-line notice to stderr and still exit 0 (pyproject.toml,
#      present since the bootstrap fixture, is enough to satisfy the check's
#      config gate). ruff is stripped from PATH, there is no .venv/venv, and the
#      python3 stub has no ruff module — so the notice is the only correct
#      outcome, not an accident of what the host happens to have installed.
NORUFF=$(mktemp -d)
cat >"$NORUFF/python3" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$NORUFF/python3"
echo 'ok = True' >noruff.py
git add noruff.py
if PATH="$NORUFF:$NOTOOL_PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1 \
   && grep -qF "note: ruff not installed" "$HOOK_OUT"; then
  echo "  ✓ ruff-unavailable skip prints a notice and still exits 0"
  PASS=$((PASS + 1))
else
  echo "  ✗ ruff-unavailable skip: expected a note on stderr and exit 0"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$NORUFF"
reset_repo

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
elif ! grep -qF 'extract a module' "$HOOK_OUT"; then
  # Guard the reject reason (like assert_rejects): without it the case passed on
  # ANY non-zero exit, so a crash unrelated to the size cap counted as a pass.
  echo "  ✗ MAX_LINES=100 — rejected but not for the size cap (unexpected output)"
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

# 18b. CDPATH in the developer's environment must not disarm the hook. `cd`
#      resolves a relative argument through CDPATH and PRINTS the directory it
#      landed in, so `$(cd "$(dirname "$0")" && pwd)` captured that line ahead
#      of pwd's: $LIB became a two-line string, every "$LIB/check-*" launch
#      failed with "No such file or directory", and nothing was ever scanned.
#      Hooks are always invoked by relative path, so a CDPATH in a shell
#      profile hit every commit. Assert the POSITIVE outcome: the pattern scan
#      still fires and the commit is refused.
echo 'pri''nt("debug")' >cdpath.py
git add cdpath.py
if CDPATH=".:$HOME" .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ CDPATH set — hook accepted, expected reject"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -qF "structlog" "$HOOK_OUT"; then
  echo "  ✓ CDPATH does not stop the hook's scanners from launching"
  PASS=$((PASS + 1))
else
  echo "  ✗ CDPATH set — rejected, but not by the pattern scan"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

# 18c. Same guard on a lib check run standalone, the way the CI guardrails job
#      runs it: relative path, NUL list on stdin. check-size resolves its
#      sibling scaffold-config through its own $(cd ... && pwd), and cfg() fails
#      OPEN when that path does not resolve, so a CDPATH-poisoned SELF_DIR
#      silently drops every .scaffold.toml override instead of erroring. Assert
#      the POSITIVE outcome: the per-path cap of 100 from .scaffold.toml is
#      honored under CDPATH, so a 200-line file is refused (the built-in
#      default of 500 would let it through).
mkdir -p cdp
printf '[size]\n"cdp/**" = 100\n' >.scaffold.toml
seq 1 200 >cdp/big.py
git add .scaffold.toml cdp/big.py
if printf '%s\0' cdp/big.py | CDPATH=".:$HOME" .githooks/lib/check-size >"$HOOK_OUT" 2>&1; then
  echo "  ✗ CDPATH set — check-size ignored the .scaffold.toml cap, expected reject"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -qF "extract a module" "$HOOK_OUT"; then
  echo "  ✓ CDPATH does not break a standalone lib check's config lookup"
  PASS=$((PASS + 1))
else
  echo "  ✗ CDPATH set — check-size failed for the wrong reason"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf cdp
reset_repo
