# shellcheck shell=bash
# cases/64-clean-tree-gate.sh: lib/check-clean-tree, the CI step that fails when
# the test suite leaves untracked or modified files behind (#219). Sourced into
# the driver's shell (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and fixture_* in scope);
# self-sufficient, so it also runs alone. Gates run from the INSTALLED copy.

echo "cases/64: check-clean-tree fails a dirty tree and passes a clean one (#219)"

ct_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
ct_bad() { echo "  ✗ $1"; sed 's/^/      /' "$HOOK_OUT" | head -20; FAIL=$((FAIL + 1)); }

# ct_run <dir> <env/args...>: run the installed gate in <dir>; sets CT_RC and
# leaves stdout+stderr in $HOOK_OUT.
ct_run() {
  local dir=$1 rc=0
  shift
  ( cd "$dir" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT "$@" .githooks/lib/check-clean-tree ) >"$HOOK_OUT" 2>&1 || rc=$?
  CT_RC=$rc
}
# ct_expect <description> <want-rc> <fixed-string>...: exit code and output both match.
ct_expect() {
  local desc=$1 want=$2 s
  shift 2
  for s in "$@"; do
    grep -qF -- "$s" "$HOOK_OUT" || { ct_bad "$desc (output lacks: $s)"; return; }
  done
  if [ "$CT_RC" -eq "$want" ]; then ct_ok "$desc"; else ct_bad "$desc (want exit $want, got $CT_RC)"; fi
}

fixture_repo CT
fixture_install "$CT" --python --no-verify
printf 'tracked\n' >"$CT/tracked.txt"
git -C "$CT" add -A
git -C "$CT" commit --quiet -m "base"

ct_run "$CT"
ct_expect "a clean tree passes and reports ran N, not ran 0" 0 "gate=clean-tree status=ran checked="
if grep -qF 'checked=0' "$HOOK_OUT"; then ct_bad "a clean tree must not report checked=0"; else ct_ok "a clean tree's checked count is the tracked file count"; fi

printf 'leaked\n' >"$CT/leak.txt"
ct_run "$CT"
ct_expect "an untracked file fails and is named" 1 "leak.txt" "untracked" "gate=clean-tree status=ran"
if grep -qF 'refusal class (a)' "$HOOK_OUT"; then ct_ok "a refusal ends with the class trailer"; else ct_bad "refusal class trailer missing"; fi
rm -f "$CT/leak.txt"
mkdir -p "$CT/out/deep"
printf 'x\n' >"$CT/out/deep/a.txt"
ct_run "$CT"
ct_expect "a file inside a new untracked directory is listed individually" 1 "out/deep/a.txt"
rm -rf "$CT/out"

printf 'changed\n' >>"$CT/tracked.txt"
ct_run "$CT"
ct_expect "a modified tracked file fails" 1 "tracked.txt" "modified"
git -C "$CT" checkout --quiet -- tracked.txt

printf 'leaked\n' >"$CT/ci-leak.txt"
( cd "$CT" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT .githooks/lib/check-clean-tree --ci ) >"$HOOK_OUT" 2>&1 && CT_RC=0 || CT_RC=$?
ct_expect "--ci annotates the file as a workflow error" 1 "::error file=ci-leak.txt::"
rm -f "$CT/ci-leak.txt"

mkdir -p "$CT/pkg/__pycache__"
printf 'x\n' >"$CT/pkg/__pycache__/m.cpython-312.pyc"
printf 'x\n' >"$CT/coverage.xml"
printf 'x\n' >"$CT/.coverage"
ct_run "$CT"
ct_expect "the shipped workflows' own output (__pycache__, coverage.xml) is not counted" 0 "gate=clean-tree status=ran"
rm -rf "$CT/pkg" "$CT/coverage.xml" "$CT/.coverage"

printf 'ignored.log\n' >>"$CT/.git/info/exclude"
printf 'x\n' >"$CT/ignored.log"
ct_run "$CT"
ct_expect "a git-ignored file passes" 0 "gate=clean-tree status=ran"
rm -f "$CT/ignored.log"

# Defaults match at any depth; a nested stray file is flagged; the verdict is the
# whole repository even when run from a subdirectory.
mkdir -p "$CT/sub/frontend" "$CT/pkg/.pytest_cache"
printf 'x\n' >"$CT/sub/frontend/package-lock.json"
printf 'x\n' >"$CT/pkg/.pytest_cache/v"
printf 'x\n' >"$CT/sub/.coverage"
mkdir -p "$CT/sub/node_modules/m" "$CT/sub/.venv"
printf 'x\n' >"$CT/sub/node_modules/m/i.js"
printf 'x\n' >"$CT/sub/.venv/p"
ct_run "$CT"
ct_expect "nested package-lock.json, .pytest_cache, .coverage, node_modules, .venv are ignored" 0 "gate=clean-tree status=ran"
printf 'x\n' >"$CT/sub/frontend/stray.txt"
ct_run "$CT"
ct_expect "a nested stray file is flagged" 1 "sub/frontend/stray.txt"
mkdir -p "$CT/elsewhere"
printf 'x\n' >"$CT/elsewhere/other.txt"
( cd "$CT/sub" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT ../.githooks/lib/check-clean-tree ) >"$HOOK_OUT" 2>&1 && CT_RC=0 || CT_RC=$?
ct_expect "run from a subdirectory it still sees the whole repository" 1 "elsewhere/other.txt" "sub/frontend/stray.txt"
( cd / && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT "$CT/.githooks/lib/check-clean-tree" ) >"$HOOK_OUT" 2>&1 && CT_RC=0 || CT_RC=$?
ct_expect "outside a repository it fails closed" 1 "not inside a git repository"
rm -rf "$CT/sub" "$CT/pkg" "$CT/elsewhere"

# The built-in excludes cover UNTRACKED files only: a tracked file the suite
# modified is always reported, except a tracked package-lock.json.
mkdir -p "$CT/d/.venv" "$CT/app/coverage" "$CT/web"
printf 'a\n' >"$CT/d/.venv/tracked.txt"
printf 'a\n' >"$CT/app/coverage/keep.txt"
printf 'a\n' >"$CT/web/package-lock.json"
git -C "$CT" add d app web
git -C "$CT" commit --quiet -m "tracked files under excluded-looking paths"
printf 'b\n' >>"$CT/d/.venv/tracked.txt"
ct_run "$CT"
ct_expect "a modified tracked file under .venv/ is flagged" 1 "d/.venv/tracked.txt"
git -C "$CT" checkout --quiet -- d
printf 'b\n' >>"$CT/app/coverage/keep.txt"
ct_run "$CT"
ct_expect "a modified tracked file under coverage/ is flagged" 1 "app/coverage/keep.txt"
git -C "$CT" checkout --quiet -- app
mkdir -p "$CT/n/node_modules/m"
printf 'x\n' >"$CT/n/node_modules/m/i.js"
printf 'b\n' >>"$CT/web/package-lock.json"
ct_run "$CT"
ct_expect "an untracked node_modules file and a modified tracked package-lock.json are ignored" 0 "gate=clean-tree status=ran"
git -C "$CT" checkout --quiet -- web
rm -rf "$CT/n"

# Per-project settings: exclude, warn, disabled (recorded, passes under strict).
printf '[rules.clean-tree]\nexclude = ["build/*"]\n' >"$CT/.scaffold.toml"
git -C "$CT" add .scaffold.toml
git -C "$CT" commit --quiet -m "config: exclude"
mkdir -p "$CT/build"
printf 'x\n' >"$CT/build/report.xml"
ct_run "$CT"
ct_expect "[rules.clean-tree] exclude skips the listed path" 0 "gate=clean-tree status=ran"
printf 'x\n' >"$CT/other.txt"
ct_run "$CT"
ct_expect "a path outside the exclude list still fails" 1 "other.txt"
rm -rf "$CT/build" "$CT/other.txt"

printf '[rules.clean-tree]\nseverity = "warn"\n' >"$CT/.scaffold.toml"
printf 'x\n' >"$CT/warned.txt"
ct_run "$CT"
ct_expect "severity = warn reports the file but exits 0" 0 "warned.txt" "warn"
printf '[rules.clean-tree]\ndisabled = true\n' >"$CT/.scaffold.toml"
ct_run "$CT" SCAFFOLD_GATE_STRICT=1
ct_expect "disabled = true is a recorded skip, passing even under strict" 0 "gate=clean-tree status=skipped" "disabled:"
rm -f "$CT/warned.txt"
git -C "$CT" checkout --quiet -- .scaffold.toml

# Wiring: the CI steps call it, pre-commit and lint.yml skip it by name, and the
# installer delivers it executable.
WF62="$SCAFFOLD_DIR/.github/workflows"
for ct_w in tests coverage; do
  if grep -qF 'check-clean-tree --ci' "$WF62/$ct_w.yml.template"; then ct_ok "$ct_w.yml.template runs check-clean-tree after the test step"
  else : >"$HOOK_OUT"; ct_bad "$ct_w.yml.template must run check-clean-tree"; fi
done
if grep -qF 'check-clean-tree' "$SCAFFOLD_DIR/githooks/pre-commit.template" && grep -qF 'check-clean-tree' "$WF62/lint.yml.template"; then
  ct_ok "pre-commit and lint.yml skip check-clean-tree in their scanner loops"
else : >"$HOOK_OUT"; ct_bad "pre-commit.template and lint.yml.template must skip check-clean-tree"; fi
if [ -x "$CT/.githooks/lib/check-clean-tree" ]; then ct_ok "install.sh delivers check-clean-tree executable"
else : >"$HOOK_OUT"; ct_bad "install.sh must install an executable lib/check-clean-tree"; fi
rm -rf "$CT"
