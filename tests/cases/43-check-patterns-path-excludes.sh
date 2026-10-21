# shellcheck shell=bash
# cases/43-check-patterns-path-excludes.sh: per-rule path excludes in
# check-patterns (shipped `exclude=` defaults on the print-style rules, plus the
# `exclude = [...]` key in .scaffold.toml). Sourced into the driver's shell, so
# PASS/FAIL/HOOK_OUT/WORK and reset_repo are in scope. Split out of cases/28 (at
# the 500-line module cap) rather than weakening the cap.

# --- per-rule path excludes ----------------------------------------------------
# A rule can skip paths: shipped defaults ride on the rule line (third TAB field,
# `exclude=<globs>`) and a project adds more with `exclude = [...]` in the rule's
# .scaffold.toml table. The assertions pin three things: the shipped CLI/script/
# test defaults let print-style code through with NO config, the rule still fires
# everywhere else, and the exclude is per RULE (a rule with no default, or a
# different rule on the same excluded path, still fires). Invokes check-patterns
# directly like the cases above, on STAGED fixtures.
echo ""
echo "check-patterns per-rule path excludes:"
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver
cd "$WORK"
reset_repo

# px_case <name> <allowed|refused> <file> <content> [<needle>]
# `allowed` = exit 0 and no finding printed. `refused` = exit 1, the file is
# named, the needle (the rule's description text) is in the output, and the
# shipped `exclude=` field never leaked into that description.
px_case() {
  local name=$1 want=$2 file=$3 content=$4 needle=${5:-} rc=0
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >"$file"
  git add "$file"
  printf '%s\0' "$file" | .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$want" = allowed ]; then
    if [ "$rc" -eq 0 ] && ! grep -qE '✗|::error' "$HOOK_OUT"; then
      echo "  ✓ $name"; PASS=$((PASS + 1))
    else
      echo "  ✗ $name: expected allowed, got exit $rc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  else
    if [ "$rc" -eq 1 ] && grep -qF "$file" "$HOOK_OUT" && grep -qF "$needle" "$HOOK_OUT" \
       && ! grep -qF 'exclude=' "$HOOK_OUT"; then
      echo "  ✓ $name"; PASS=$((PASS + 1))
    else
      echo "  ✗ $name: expected refused with '$needle', got exit $rc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  fi
}

PX_PRINT='print("x")'
PX_PY_RULE="backend/Use structlog (or the project's logger), not print()"

# 28i. Shipped defaults, NO .scaffold.toml: CLI, script and test code passes.
rm -f .scaffold.toml
px_case "default: tests/test_cli.py may print()" allowed tests/test_cli.py "$PX_PRINT"
px_case "default: scripts/migrate.py may print()" allowed scripts/migrate.py "$PX_PRINT"
px_case "default: cmd/root.go may fmt.Println()" allowed cmd/root.go 'fmt.Println("x")'
px_case "default: src/main.rs may println!()" allowed src/main.rs 'println!("x");'
px_case "default: a Go *_test.go file may fmt.Println() at any depth" allowed pkg/deep/foo_test.go 'fmt.Println("x")'

# 28j. Everywhere else the same rules still fire.
px_case "default: app/service.py still refused for print()" refused app/service.py "$PX_PRINT" "Use structlog"
px_case "default: pkg/foo.go still refused for fmt.Println()" refused pkg/foo.go 'fmt.Println("x")' "Remove fmt.Print"
px_case "default: src/lib.rs still refused for println!()" refused src/lib.rs 'println!("x");' "not println!()"

# 28k. Per RULE, not per path: tests/ is excluded for print() only. breakpoint()
#      has no default exclude, so it still fires inside tests/.
px_case "default exclude is per rule: breakpoint() still refused in tests/" refused tests/test_dbg.py 'breakpoint()' "Remove breakpoint()"
reset_repo

# 28l. Config layer: `exclude` in the rule's table.
cat >.scaffold.toml <<'TOML'
[rules."backend/Use structlog (or the project's logger), not print()"]
exclude = ["app/cli/*"]
TOML
git add .scaffold.toml
px_case "config exclude: app/cli/main.py may print()" allowed app/cli/main.py "$PX_PRINT"
px_case "config exclude: app/service.py still refused" refused app/service.py "$PX_PRINT" "Use structlog"
px_case "config exclude adds to the defaults: tests/ still allowed" allowed tests/test_cli.py "$PX_PRINT"
px_case "config exclude is per rule: breakpoint() refused in app/cli/" refused app/cli/dbg.py 'breakpoint()' "Remove breakpoint()"

# 28m. A config exclude keyed to a rule id that does not exist exempts nothing,
#      and the id is the CLEAN description (the shipped exclude= field is not
#      part of it).
cat >.scaffold.toml <<'TOML'
[rules."backend/not a real rule"]
exclude = ["app/*"]
TOML
git add .scaffold.toml
px_case "config exclude for another rule id exempts nothing" refused app/other.py "$PX_PRINT" "Use structlog"

# 28n. Several globs in one array all apply; a malformed (unterminated) array is
#      ignored whole, which fails safe to full scanning.
cat >.scaffold.toml <<'TOML'
[rules."backend/Use structlog (or the project's logger), not print()"]
exclude = [ "tools/*", "jobs/*" ]
TOML
git add .scaffold.toml
px_case "config exclude with two globs: the second applies" allowed jobs/nightly.py "$PX_PRINT"
cat >.scaffold.toml <<'TOML'
[rules."backend/Use structlog (or the project's logger), not print()"]
exclude = ["tools/*",
TOML
git add .scaffold.toml
px_case "unterminated exclude array is ignored, fails safe" refused tools/run.py "$PX_PRINT" "Use structlog"

# 28o. The helper's own answer, and the audit view of it.
cat >.scaffold.toml <<'TOML'
[rules."backend/Use structlog (or the project's logger), not print()"]
exclude = ["app/cli/*", "*/mgmt/*"]
TOML
px_got=$(.githooks/lib/scaffold-config rule-excludes "$PX_PY_RULE" 2>&1 || true)
if [ "$px_got" = "$(printf 'app/cli/*\n*/mgmt/*')" ]; then
  echo "  ✓ scaffold-config rule-excludes prints one glob per line"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-config rule-excludes printed: $px_got"; FAIL=$((FAIL + 1))
fi
if .githooks/lib/scaffold-audit >"$HOOK_OUT" 2>&1 && grep -qF 'exclude: ["app/cli/*", "*/mgmt/*"]' "$HOOK_OUT"; then
  echo "  ✓ scaffold-audit lists a rule's path excludes"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-audit did not list the exclude"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
unset px_got PX_PRINT PX_PY_RULE
unset -f px_case
reset_repo
