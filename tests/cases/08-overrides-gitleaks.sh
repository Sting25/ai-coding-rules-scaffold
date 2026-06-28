# shellcheck shell=bash
# cases/08-overrides-gitleaks.sh — .scaffold.toml per-project overrides (52–59)
# and the opt-in check-gitleaks pass (60–62). Sourced into the driver's shell.

# --- .scaffold.toml per-project overrides (lib/scaffold-config) -------------
# A STAGED .scaffold.toml is what the checks read: the hook stashes unstaged
# changes (--keep-index), so only the indexed copy is on disk during the scan —
# matching how overrides ship (committed). Fixtures use ruff-clean comment
# bodies / bare `print` so the linters don't independently fail an assert_passes
# case (ruff doesn't enable T20; eslint's no-console is why these avoid .ts).

# 52. [size] per-glob cap raises the limit: a 501-line file under the matching
#     glob passes where the default 500 would reject.
printf '[size]\n"legacy/**" = 700\n' >.scaffold.toml
mkdir -p legacy
seq 1 501 | sed 's/^/# /' >legacy/big.py
git add .scaffold.toml legacy/big.py
assert_passes "override: [size] per-glob cap raises the limit"

# 53. [rules.size] disabled turns the size cap off entirely.
printf '[rules.size]\ndisabled = true\n' >.scaffold.toml
seq 1 501 | sed 's/^/# /' >big2.py
git add .scaffold.toml big2.py
assert_passes "override: [rules.size] disabled skips the size cap"

# 54. A disabled forbidden-pattern rule lets its match through.
cat >.scaffold.toml <<'EOF'
[rules."backend/Use structlog (or the project's logger), not print()"]
disabled = true
reason   = "test"
by       = "test"
EOF
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
assert_passes "override: disabled pattern rule lets the match through"

# 55. severity = "warn" reports the match but does NOT fail the build.
cat >.scaffold.toml <<'EOF'
[rules."backend/Use structlog (or the project's logger), not print()"]
severity = "warn"
EOF
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn — .scaffold.toml override)" "$HOOK_OUT"; then
    echo "  ✓ override: severity=warn reports without failing"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: severity=warn passed but emitted no warn notice"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: severity=warn — hook failed, expected pass-with-warning"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 56. Hygiene rule downgrade: case-collision as a warning still passes. Feed the
#     NUL-delimited path list to check-hygiene directly (a real case-variant pair
#     can't coexist on a case-insensitive FS), with the override on disk.
printf '[rules.case-collision]\nseverity = "warn"\n' >.scaffold.toml
if printf '%s\0' 'Collide.txt' 'collide.txt' | .githooks/lib/check-hygiene >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn — .scaffold.toml override)" "$HOOK_OUT"; then
    echo "  ✓ override: case-collision severity=warn passes with a notice"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: case-collision warn passed but emitted no notice"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: case-collision severity=warn — failed, expected pass"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 57. FAIL SAFE: an unparseable .scaffold.toml disables nothing — print() is
#     still rejected (a config can only weaken via a clean, explicit entry).
printf 'this is { not ] valid toml at all\n' >.scaffold.toml
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
assert_rejects "override: malformed config fails safe (rule still enforced)" "structlog"

# 58. SECURITY BOUNDARY: .scaffold.toml cannot disable the secret scanner —
#     check-secrets never consults it, so the AKIA key is still caught.
cat >.scaffold.toml <<'EOF'
[rules."secrets/AWS access key ID (AKIA) or temporary session key (ASIA) — rotate immediately"]
disabled = true
EOF
echo "AKIA""IOSFODNN7EXAMPLE" >creds.txt
git add .scaffold.toml creds.txt
assert_rejects "override: secret scanner is NOT disablable via .scaffold.toml" "AWS access key"

# 59. scaffold-audit (installed by install.sh) lists active overrides. The CI
#     guardrails job runs this so a disabled rule is visible in the build log.
printf '[rules."backend/Use structlog (or the project'\''s logger), not print()"]\ndisabled = true\n' >.scaffold.toml
if .githooks/lib/scaffold-audit >"$HOOK_OUT" 2>&1 \
   && grep -qF "DISABLED" "$HOOK_OUT" && grep -qF "backend/Use structlog" "$HOOK_OUT"; then
  echo "  ✓ scaffold-audit lists active overrides"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-audit — did not list the disabled rule"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 60-62. check-gitleaks — opt-in local gitleaks pass (install.sh --gitleaks-hook).
#     Exercised with a FAKE gitleaks on an isolated PATH so the suite needs no
#     real binary and stays deterministic. The dirs are symlinked with the few
#     externals the script needs (bash to launch it, cat to drain stdin) so a
#     PATH-scoped run can't accidentally find a system gitleaks.
CG="$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template"
mk_glbin() { local d=$1; ln -sf "$(command -v bash)" "$d/bash"; ln -sf "$(command -v cat)" "$d/cat"; }
# (60) gitleaks absent → fail-OPEN: exit 0 with a "not installed" note.
NOGL=$(mktemp -d); mk_glbin "$NOGL"
if PATH="$NOGL" bash "$CG" </dev/null >"$HOOK_OUT" 2>&1 && grep -qF "gitleaks not installed" "$HOOK_OUT"; then
  echo "  ✓ check-gitleaks fails open (exit 0 + note) when the binary is absent"; PASS=$((PASS + 1))
else
  echo "  ✗ check-gitleaks — expected clean skip when gitleaks is absent"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# (61) gitleaks present and reports a leak (exit 1) → check-gitleaks blocks.
GLBIN=$(mktemp -d); mk_glbin "$GLBIN"
printf '#!/bin/sh\nexit 1\n' >"$GLBIN/gitleaks"; chmod +x "$GLBIN/gitleaks"
if PATH="$GLBIN" bash "$CG" </dev/null >"$HOOK_OUT" 2>&1; then
  echo "  ✗ check-gitleaks — allowed a commit when gitleaks reported a leak"; FAIL=$((FAIL + 1))
elif grep -qF "gitleaks flagged a potential secret" "$HOOK_OUT"; then
  echo "  ✓ check-gitleaks blocks when gitleaks reports a leak"; PASS=$((PASS + 1))
else
  echo "  ✗ check-gitleaks — blocked but missing the expected message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# (62) gitleaks present and clean (exit 0) → check-gitleaks allows.
printf '#!/bin/sh\nexit 0\n' >"$GLBIN/gitleaks"
if PATH="$GLBIN" bash "$CG" </dev/null >"$HOOK_OUT" 2>&1; then
  echo "  ✓ check-gitleaks allows a clean staged scan"; PASS=$((PASS + 1))
else
  echo "  ✗ check-gitleaks — blocked a clean scan, expected allow"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$NOGL" "$GLBIN"
reset_repo
