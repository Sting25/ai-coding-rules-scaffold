# shellcheck shell=bash
# cases/63-branch-gate.sh: lib/check-branch, called from pre-commit, refuses a
# commit on the repository's default branch (#220). Sourced into the driver's
# shell (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and fixture_* in scope); self-
# sufficient, so it also runs alone. The suite's own fixtures commit on a work
# branch (tests/lib/common.sh), so every other case stays unaffected.

echo "cases/63: check-branch refuses the default branch, allows a work branch and the first commit (#220)"

br_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
br_bad() { echo "  ✗ $1"; sed 's/^/      /' "$HOOK_OUT" | head -20; FAIL=$((FAIL + 1)); }

# br_hook <dir> [env args...]: run the INSTALLED pre-commit in <dir>. Sets BR_RC;
# stdout+stderr land in $HOOK_OUT.
br_hook() {
  local dir=$1 rc=0
  shift
  ( cd "$dir" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_GATE_STRICT -u SCAFFOLD_ALLOW_DEFAULT_BRANCH "$@" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || rc=$?
  BR_RC=$rc
}
# br_expect <description> <want-rc> <fixed-string>...
br_expect() {
  local desc=$1 want=$2 s
  shift 2
  for s in "$@"; do
    grep -qF -- "$s" "$HOOK_OUT" || { br_bad "$desc (output lacks: $s)"; return; }
  done
  if [ "$BR_RC" -eq "$want" ]; then br_ok "$desc"; else br_bad "$desc (want exit $want, got $BR_RC)"; fi
}

fixture_repo BR
if [ "$(git -C "$BR" symbolic-ref --short HEAD)" = work ]; then br_ok "the suite's fixture starts on a work branch, not the default branch"
else : >"$HOOK_OUT"; br_bad "fixture_repo must check out a work branch"; fi
fixture_install "$BR" --python --no-verify

# Unborn branch: the first commit of a new repository is allowed.
git -C "$BR" checkout --quiet -b main
printf 'first\n' >"$BR/first.txt"
git -C "$BR" add first.txt
br_hook "$BR"
br_expect "the first commit of a new repository is allowed even on main" 0
git -C "$BR" add -A
git -C "$BR" commit --quiet -m "base"

# Refuse on the default branch.
printf 'second\n' >"$BR/second.txt"
git -C "$BR" add second.txt
br_hook "$BR"
br_expect "a commit on main is refused, naming the escape variable" 1 "refusing to commit on the default branch 'main'" "SCAFFOLD_ALLOW_DEFAULT_BRANCH=1" "git switch -c"
if tail -n 1 "$HOOK_OUT" | grep -qF 'refusal class (a)'; then br_ok "the refusal carries the class trailer"
else br_bad "the refusal must end with the class (a) trailer"; fi
( cd "$BR" && env -u SCAFFOLD_GATE_LOG -u SCAFFOLD_ALLOW_DEFAULT_BRANCH .githooks/lib/check-branch ) >"$HOOK_OUT" 2>&1 && BR_RC=0 || BR_RC=$?
br_expect "check-branch alone: exit 1, gate line ran 1, class trailer last" 1 "gate=branch status=ran checked=1" "refusal class (a)"
git -C "$BR" config core.hooksPath .githooks
if git -C "$BR" commit --quiet -m "direct commit on main" >"$HOOK_OUT" 2>&1; then br_bad "git commit on main must be refused by the wired hook"
else br_ok "git commit on main is refused through the wired hook"; fi
git -C "$BR" config --unset core.hooksPath

# The escape variable lets one deliberate commit through, and says so.
br_hook "$BR" SCAFFOLD_ALLOW_DEFAULT_BRANCH=1
br_expect "SCAFFOLD_ALLOW_DEFAULT_BRANCH=1 allows the commit" 0
( cd "$BR" && env -u SCAFFOLD_GATE_LOG SCAFFOLD_ALLOW_DEFAULT_BRANCH=1 .githooks/lib/check-branch ) >"$HOOK_OUT" 2>&1 && BR_RC=0 || BR_RC=$?
br_expect "the escape is announced and recorded in the gate line" 0 "SCAFFOLD_ALLOW_DEFAULT_BRANCH=1 is set" "escape SCAFFOLD_ALLOW_DEFAULT_BRANCH=1 used"

# An empty commit (nothing staged) on the default branch is refused too.
git -C "$BR" reset --quiet
br_hook "$BR"
br_expect "nothing staged on main is still refused (--allow-empty)" 1 "refusing to commit on the default branch"

# master is protected when no setting names another default.
git -C "$BR" checkout --quiet -b master
printf 'x\n' >"$BR/m.txt"
git -C "$BR" add m.txt
br_hook "$BR"
br_expect "a commit on master is refused" 1 "default branch 'master'"

# Work branches pass, and so does a branch merely named like the default.
for br_b in work feature/main main-fix; do
  git -C "$BR" checkout --quiet -B "$br_b"
  br_hook "$BR"
  br_expect "a commit on '$br_b' is allowed" 0
done

# Detached HEAD (rebase, bisect) has no branch to refuse.
git -C "$BR" checkout --quiet --detach
br_hook "$BR"
br_expect "a detached HEAD is allowed" 0
git -C "$BR" checkout --quiet work

# The default is read from origin/HEAD first, then init.defaultBranch.
git -C "$BR" update-ref refs/remotes/origin/trunk HEAD
git -C "$BR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
git -C "$BR" checkout --quiet -B trunk
br_hook "$BR"
br_expect "origin/HEAD names the default: a commit on trunk is refused" 1 "default branch 'trunk'"
git -C "$BR" checkout --quiet -B main
br_hook "$BR"
br_expect "origin/HEAD = trunk: main is then an ordinary branch" 0
git -C "$BR" symbolic-ref --delete refs/remotes/origin/HEAD
git -C "$BR" config init.defaultBranch develop
git -C "$BR" checkout --quiet -B develop
br_hook "$BR"
br_expect "init.defaultBranch names the default when origin/HEAD is unset" 1 "default branch 'develop'"
git -C "$BR" config --unset init.defaultBranch
git -C "$BR" checkout --quiet work

# Per-project settings: disabled is a recorded skip (passes under strict), warn passes.
git -C "$BR" checkout --quiet -B main
printf '[rules.branch]\ndisabled = true\n' >"$BR/.scaffold.toml"
git -C "$BR" add .scaffold.toml
br_hook "$BR" SCAFFOLD_GATE_STRICT=1
br_expect "[rules.branch] disabled = true allows main, even under strict" 0
( cd "$BR" && env -u SCAFFOLD_GATE_LOG SCAFFOLD_GATE_STRICT=1 .githooks/lib/check-branch ) >"$HOOK_OUT" 2>&1 && BR_RC=0 || BR_RC=$?
br_expect "disabled is a recorded skip: gate line status=skipped, reason disabled:" 0 "gate=branch status=skipped" "disabled:"
printf '[rules.branch]\nseverity = "warn"\n' >"$BR/.scaffold.toml"
git -C "$BR" add .scaffold.toml
br_hook "$BR"
br_expect "severity = warn lets the commit through and says so" 0 "warn"

# Wiring.
if grep -qF 'check-branch' "$SCAFFOLD_DIR/githooks/pre-commit.template" && grep -qF 'check-branch' "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"; then
  br_ok "pre-commit calls check-branch and lint.yml skips it (CI always runs on the default branch)"
else : >"$HOOK_OUT"; br_bad "pre-commit.template must call check-branch and lint.yml.template must skip it"; fi
if [ -x "$BR/.githooks/lib/check-branch" ]; then br_ok "install.sh delivers check-branch executable"
else : >"$HOOK_OUT"; br_bad "install.sh must install an executable lib/check-branch"; fi
rm -rf "$BR"
