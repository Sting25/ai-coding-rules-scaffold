# shellcheck shell=bash
# cases/45-tsc-local-warning.sh: the pre-commit `tsc --noEmit` step is a WARNING
# locally by default and a blocking error only when .scaffold.toml says so.
# Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/WORK and reset_repo are
# in scope.
#
# Why: tsc runs project-wide (it ignores tsconfig.json when given file args), so
# a one-file commit used to fail on pre-existing type errors in unrelated files
# and the only way out was `--no-verify`, which AGENTS.md forbids. lint.yml runs
# the same `tsc --noEmit` on the pull request and fails the job, so the gate is
# not lost; the local run is feedback. The rule id is `tsc`:
#   [rules.tsc]  severity = "error"  restores the local block
#                disabled = true     skips the step
#
# A real tsc is not on PATH on the machines the suite runs on (and an installed
# one would make the result depend on the machine), so this case plants a
# project-local node_modules/typescript for the hook's Node-resolution gate and
# puts a FAKE npx first on PATH that prints a compiler-style error and exits 2,
# the same shape cases/05 (42i) uses. The fake answers only `tsc`; anything else
# exits 0 so the other optional steps cannot decide the verdict.

echo ""
echo "pre-commit tsc: warning locally, blocking on request:"
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver
cd "$WORK"
reset_repo

TSW_BIN=$(mktemp -d)
cat >"$TSW_BIN/npx" <<'STUB'
#!/bin/sh
case "$*" in
  *tsc*) echo "legacy/old.ts(3,7): error TS2322: FAKE TSC type error"; exit 2 ;;
  *)     exit 0 ;;
esac
STUB
chmod +x "$TSW_BIN/npx"
# A passing tsc, for the "no warning when there are no errors" check.
TSW_OK=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' >"$TSW_OK/npx"
chmod +x "$TSW_OK/npx"

TSW_LINE='! tsc --noEmit reported errors (warning locally; the lint workflow fails the PR on them)'

# tsw_stage [<no-tsconfig>]: a typed project with an unrelated pre-existing
# error (the fake tsc reports it) and ONE new staged file.
tsw_stage() {
  mkdir -p node_modules/typescript src
  echo '{"name":"typescript","version":"0.0.0-test"}' >node_modules/typescript/package.json
  [ "${1:-}" = notsconfig ] || echo '{"compilerOptions":{"strict":true,"noEmit":true}}' >tsconfig.json
  echo 'export const added = 1;' >src/new.ts
  git add src/new.ts
  [ "${1:-}" = notsconfig ] || git add tsconfig.json
  # The bootstrap install already tracks a .scaffold.toml, and the hook stashes
  # UNSTAGED edits for the run, so a config edit only counts once it is staged.
  [ ! -f .scaffold.toml ] || git add .scaffold.toml
}

# tsw_run <bin-dir>: run the hook with that fake npx first on PATH.
tsw_run() { PATH="$1:$PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1; }

# tsw_ok / tsw_bad <name>: record one passing / failing assertion.
tsw_ok()  { echo "  ✓ $1"; PASS=$((PASS + 1)); }
tsw_bad() { echo "  ✗ $1"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1)); }

# 45a. Default (no .scaffold.toml): type errors elsewhere do NOT block the
#      commit; the compiler output and the one-line warning are printed.
tsw_stage
if tsw_run "$TSW_BIN" && grep -qF 'FAKE TSC type error' "$HOOK_OUT" && grep -qF "$TSW_LINE" "$HOOK_OUT"; then
  tsw_ok "default: tsc errors in another file allow the commit, with the compiler output and the warning line"
else
  tsw_bad "default: expected exit 0 with tsc output and the warning line"
fi
reset_repo; rm -rf node_modules

# 45b. severity = "error" restores the local block; no warning line is printed
#      (the commit is refused, there is nothing to reassure about).
cat >.scaffold.toml <<'TOML'
[rules.tsc]
severity = "error"
TOML
tsw_stage
if tsw_run "$TSW_BIN"; then
  tsw_bad "severity = error: hook accepted despite tsc errors"
elif grep -qF 'FAKE TSC type error' "$HOOK_OUT" && ! grep -qF "$TSW_LINE" "$HOOK_OUT"; then
  tsw_ok "severity = \"error\": tsc errors refuse the commit"
else
  tsw_bad "severity = error: refused, but without the compiler output (or with the warning line)"
fi
reset_repo; rm -rf node_modules

# 45c. severity = "warn" spelled out is the same as the default.
cat >.scaffold.toml <<'TOML'
[rules.tsc]
severity = "warn"
TOML
tsw_stage
if tsw_run "$TSW_BIN" && grep -qF "$TSW_LINE" "$HOOK_OUT"; then
  tsw_ok "severity = \"warn\": commit allowed with the warning line"
else
  tsw_bad "severity = warn: expected exit 0 with the warning line"
fi
reset_repo; rm -rf node_modules

# 45d. disabled = true: tsc is not run at all, so neither its output nor the
#      warning line appears, and the commit is allowed.
cat >.scaffold.toml <<'TOML'
[rules.tsc]
disabled = true
TOML
tsw_stage
if tsw_run "$TSW_BIN" && ! grep -qF 'FAKE TSC' "$HOOK_OUT" && ! grep -qF "$TSW_LINE" "$HOOK_OUT" \
   && ! grep -qF 'skipping the local tsc' "$HOOK_OUT"; then
  tsw_ok "disabled = true: tsc is not run, no output from it"
else
  tsw_bad "disabled = true: tsc output or warning still present"
fi
reset_repo; rm -rf node_modules

# 45e. A clean tsc run prints no warning line (the line means "errors were seen").
rm -f .scaffold.toml
tsw_stage
if tsw_run "$TSW_OK" && ! grep -qF "$TSW_LINE" "$HOOK_OUT"; then
  tsw_ok "tsc exits 0: no warning line"
else
  tsw_bad "tsc exits 0: expected a clean pass with no warning line"
fi
reset_repo; rm -rf node_modules

# 45f. No tsconfig.json: the step is not entered (tsc never runs), unchanged.
tsw_stage notsconfig
if tsw_run "$TSW_BIN" && ! grep -qF 'FAKE TSC' "$HOOK_OUT" && ! grep -qF "$TSW_LINE" "$HOOK_OUT"; then
  tsw_ok "no tsconfig.json: tsc is skipped, commit allowed"
else
  tsw_bad "no tsconfig.json: tsc must not run"
fi
reset_repo; rm -rf node_modules

# 45g. tsconfig.json but TypeScript not resolvable: the existing "skipping" note,
#      unchanged, and tsc is not run.
echo '{"compilerOptions":{"strict":true,"noEmit":true}}' >tsconfig.json
mkdir -p src
echo 'export const added = 1;' >src/new.ts
git add tsconfig.json src/new.ts
if tsw_run "$TSW_BIN" && grep -qF 'TypeScript not installed in this project' "$HOOK_OUT" \
   && grep -qF 'skipping the local tsc type check' "$HOOK_OUT" && ! grep -qF 'FAKE TSC' "$HOOK_OUT"; then
  tsw_ok "typescript not installed: the skipping note is printed and tsc is not run"
else
  tsw_bad "typescript not installed: expected the skipping note"
fi
reset_repo

# 45h. The helper itself: a caller-supplied default applies only when the table
#      sets no severity; an explicit severity, disabled and the plain default
#      for every other rule are unchanged.
rm -f .scaffold.toml
tsw_got="$(.githooks/lib/scaffold-config rule-state tsc warn),$(.githooks/lib/scaffold-config rule-state size)"
printf '[rules.tsc]\nseverity = "error"\n' >.scaffold.toml
tsw_got="$tsw_got,$(.githooks/lib/scaffold-config rule-state tsc warn)"
printf '[rules.tsc]\nreason = "x"\n' >.scaffold.toml
tsw_got="$tsw_got,$(.githooks/lib/scaffold-config rule-state tsc warn),$(.githooks/lib/scaffold-config rule-state tsc)"
if [ "$tsw_got" = "warn,error,error,warn,error" ]; then
  tsw_ok "scaffold-config rule-state <id> <default>: default only when no severity is set"
else
  echo "  ✗ scaffold-config rule-state defaults gave: $tsw_got (want warn,error,error,warn,error)"; FAIL=$((FAIL + 1))
fi
rm -f .scaffold.toml

rm -rf "$TSW_BIN" "$TSW_OK" node_modules
unset TSW_BIN TSW_OK TSW_LINE tsw_got
unset -f tsw_stage tsw_run tsw_ok tsw_bad
reset_repo
