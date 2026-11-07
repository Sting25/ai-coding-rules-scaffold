# shellcheck shell=bash
# cases/62-worktree-sweep-report.sh: the test-guard gates' worktree lifecycle (#221).
# Sourced into the driver's shell, so PASS/FAIL/SKIP/HOOK_OUT/SCAFFOLD_DIR are in scope.
#
#   (a) worktree-sweep: an old redgreen- temp worktree is removed (directory and
#       registration), a fresh one, a locked one, a differently named one and a
#       redgreen- one outside the temp dir all survive, and it exits 0
#   (b) ownership: another repository's worktree, an unregistered directory, a
#       symlinked wt and a worktree outside the one temp root all survive
#   (c) SIGTERM during a check-red-green run that holds a temp worktree: the
#       worktree is cleaned and the exit code is 143 (Python skips `finally`
#       on SIGTERM unless a handler raises)
#   (d) SIGKILL cannot be trapped: the worktree stays, and the next run's sweep
#       removes it
#   (e) scaffold-worktree-report.sh lists merged, unmerged and missing-directory
#       worktrees, removes nothing, and exits 0
#
# Fixtures live in mktemp directories; TMPDIR is pointed at a private one for
# (a) to (d) so the sweep only ever sees what the case created.

echo "cases/62: worktree sweep and report (#221)"

c62_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
c62_bad() { echo "  ✗ $1"; sed 's/^/      /' "$HOOK_OUT" | head -20; FAIL=$((FAIL + 1)); }
c62_check() { # c62_check <description> <command...>
  local d=$1
  shift
  if "$@"; then c62_ok "$d"; else c62_bad "$d"; fi
}

# c62_repo <var>: a repository with one commit, in a private TMPDIR-like parent.
c62_repo() {
  local r
  r=$(mktemp -d)
  ( cd "$r" && git init --quiet -b main && git config user.email t@test.local && git config user.name T \
    && printf 'x\n' >f && git add f && git commit --quiet -m base --no-verify ) >/dev/null 2>&1  # scaffold-allow: test fixture
  printf -v "$1" '%s' "$r"
}

# c62_old <path>: backdate a directory well past the sweep's age limit.
c62_old() { touch -t 202001010000 "$1"; }

# c62_wt <repo> <tmpdir> <name>: add <tmpdir>/<name>/wt as a detached worktree.
c62_wt() { mkdir -p "$2/$3" && git -C "$1" worktree add --quiet --detach "$2/$3/wt" HEAD >/dev/null 2>&1; }
c62_registered() { git -C "$1" worktree list --porcelain | grep -c "^worktree .*$2" || true; }

SWEEP="$SCAFFOLD_DIR/githooks/lib/worktree-sweep.template"

# --- (a) the sweep's guards ----------------------------------------------------
c62_repo C62_R
C62_T=$(mktemp -d)
C62_TP=$(cd -P "$C62_T" && pwd -P)
c62_wt "$C62_R" "$C62_TP" redgreen-OLD1;  c62_old "$C62_TP/redgreen-OLD1"
c62_wt "$C62_R" "$C62_TP" redgreen-NEW1
c62_wt "$C62_R" "$C62_TP" redgreen-LOCK;  c62_old "$C62_TP/redgreen-LOCK"
git -C "$C62_R" worktree lock "$C62_TP/redgreen-LOCK/wt" >/dev/null 2>&1
c62_wt "$C62_R" "$C62_TP" keepme-OLD;     c62_old "$C62_TP/keepme-OLD"
mkdir -p "$C62_R/redgreen-HERE"
git -C "$C62_R" worktree add --quiet --detach "$C62_R/redgreen-HERE/wt" HEAD >/dev/null 2>&1; c62_old "$C62_R/redgreen-HERE"
C62_PRE=$(c62_registered "$C62_R" "")
C62_RC=0
( cd "$C62_R" && TMPDIR="$C62_TP" bash "$SWEEP" ) >"$HOOK_OUT" 2>&1 || C62_RC=$?
c62_check "sweep: an old redgreen- temp worktree is removed (directory and registration), exit 0 (was $C62_PRE registered)" \
  test "$C62_RC" -eq 0 -a ! -d "$C62_TP/redgreen-OLD1" -a "$(c62_registered "$C62_R" redgreen-OLD1)" -eq 0
c62_check "sweep: a fresh redgreen- worktree survives (a run in progress is not touched)" \
  test -d "$C62_TP/redgreen-NEW1/wt" -a "$(c62_registered "$C62_R" redgreen-NEW1)" -eq 1
c62_check "sweep: a locked worktree survives" test -d "$C62_TP/redgreen-LOCK/wt"
c62_check "sweep: an old worktree with another name survives" test -d "$C62_TP/keepme-OLD/wt"
c62_check "sweep: a redgreen- worktree outside the temp dir survives" test -d "$C62_R/redgreen-HERE/wt"
C62_RC=0
C62_E=$(mktemp -d)
( cd "$C62_E" && git init --quiet && TMPDIR="$C62_TP" bash "$SWEEP" ) >"$HOOK_OUT" 2>&1 || C62_RC=$?
c62_check "sweep: a repository with no worktrees at all exits 0 and prints nothing" test "$C62_RC" -eq 0 -a ! -s "$HOOK_OUT"
C62_RC=0
( cd "$C62_TP" && TMPDIR="$C62_TP" bash "$SWEEP" ) >"$HOOK_OUT" 2>&1 || C62_RC=$?
c62_check "sweep: outside a git repository it exits 0" test "$C62_RC" -eq 0

# --- (b) ownership: only what THIS repository lists is ever touched ---------------
# (1) an old redgreen-ts-/wt that is a worktree of a DIFFERENT repository, with a
#     user file in it; (2) an unregistered old redgreen-ts- directory; (3) an old
#     redgreen-ts-sym/wt that is a SYMLINK to a linked worktree outside the temp dir;
#     (4) an old registered redgreen- worktree under /tmp while TMPDIR is elsewhere.
c62_repo C62_F
mkdir -p "$C62_TP/redgreen-ts-FOR"
git -C "$C62_F" worktree add --quiet --detach "$C62_TP/redgreen-ts-FOR/wt" HEAD >/dev/null 2>&1
printf 'mine\n' >"$C62_TP/redgreen-ts-FOR/wt/user-file"
c62_old "$C62_TP/redgreen-ts-FOR"
mkdir -p "$C62_TP/redgreen-ts-PLAIN/wt"; c62_old "$C62_TP/redgreen-ts-PLAIN"
C62_OUT=$(mktemp -d)
git -C "$C62_R" worktree add --quiet --detach "$C62_OUT/real" HEAD >/dev/null 2>&1
printf 'real\n' >"$C62_OUT/real/user-file"
mkdir -p "$C62_TP/redgreen-ts-sym"; ln -s "$C62_OUT/real" "$C62_TP/redgreen-ts-sym/wt"; c62_old "$C62_TP/redgreen-ts-sym"
C62_SYS=$(mktemp -d /tmp/redgreen-XXXXXX)
git -C "$C62_R" worktree add --quiet --detach "$C62_SYS/wt" HEAD >/dev/null 2>&1; c62_old "$C62_SYS"
( cd "$C62_R" && SCAFFOLD_WORKTREE_SWEEP_MAX_AGE=0 TMPDIR="$C62_TP" bash "$SWEEP" ) >"$HOOK_OUT" 2>&1 || true
c62_check "sweep: another repository's old redgreen-ts-/wt survives with its file" test -f "$C62_TP/redgreen-ts-FOR/wt/user-file"
c62_check "sweep: an unregistered redgreen-ts- directory is never scanned for or deleted" test -d "$C62_TP/redgreen-ts-PLAIN/wt"
c62_check "sweep: a symlinked wt is not followed, the linked worktree outside the temp dir survives" \
  test -f "$C62_OUT/real/user-file" -a -L "$C62_TP/redgreen-ts-sym/wt"
c62_check "sweep: the one temp root is TMPDIR, a /tmp worktree is left alone when TMPDIR is elsewhere" test -d "$C62_SYS/wt"
git -C "$C62_R" worktree remove --force "$C62_SYS/wt" >/dev/null 2>&1
git -C "$C62_R" worktree remove --force "$C62_OUT/real" >/dev/null 2>&1
git -C "$C62_F" worktree remove --force "$C62_TP/redgreen-ts-FOR/wt" >/dev/null 2>&1
rm -rf "$C62_F" "$C62_OUT" "$C62_SYS"
git -C "$C62_R" worktree unlock "$C62_TP/redgreen-LOCK/wt" >/dev/null 2>&1
rm -rf "$C62_R" "$C62_T" "$C62_E"

# --- (c)/(d) signals during a real check-red-green run -----------------------------
# The gate shells out to `python -m pytest`; a stub pytest on PYTHONPATH answers
# the HEAD collection at once and hangs when run inside the redgreen- worktree,
# so the gate is holding its temp worktree when the signal arrives.
RGATE="$SCAFFOLD_DIR/githooks/lib/check-red-green.template"
C62_STUB=$(mktemp -d)
mkdir -p "$C62_STUB/pytest"
: >"$C62_STUB/pytest/__init__.py"  # a regular package, so it wins over an installed pytest on sys.path
cat >"$C62_STUB/pytest/__main__.py" <<'PY'
import os, sys, time
if "redgreen-" in os.getcwd():
    open(os.environ["C62_MARK"], "w").close()
    time.sleep(30)  # bounded: after SIGKILL of the gate this orphan ends itself
else:
    print("tests/test_x.py::test_a")
PY

# c62_start_gate: start the gate on a fresh fixture; sets C62_PID, C62_R, C62_T.
# Returns 1 when the gate never reached its worktree.
c62_start_gate() {
  c62_repo C62_R
  C62_T=$(mktemp -d)
  C62_TP=$(cd -P "$C62_T" && pwd -P)
  C62_MARK="$C62_TP/marker"
  mkdir -p "$C62_R/tests"
  ( cd "$C62_R" && printf 'def test_a():\n    assert True\n' >tests/test_x.py && git add -A \
    && git commit --quiet -m "add a test" --no-verify ) >/dev/null 2>&1  # scaffold-allow: test fixture
  C62_BASE=$(git -C "$C62_R" rev-parse HEAD~1)
  ( cd "$C62_R" && exec env TMPDIR="$C62_TP" PYTHONPATH="$C62_STUB" C62_MARK="$C62_MARK" \
      python3 "$RGATE" --base "$C62_BASE" ) >"$HOOK_OUT" 2>&1 &
  C62_PID=$!
  for _ in $(seq 1 100); do [ -f "$C62_MARK" ] && return 0; sleep 0.2; done
  kill -KILL "$C62_PID" 2>/dev/null
  return 1
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "  - SKIP: python3 not available, the signal assertions did NOT run"
  SKIP=$((SKIP + 4))
else
  if c62_start_gate; then
    C62_HELD=$(find "$C62_TP" -maxdepth 1 -name 'redgreen-*' | wc -l | tr -d ' ')
    kill -TERM "$C62_PID"
    C62_RC=0
    wait "$C62_PID" || C62_RC=$?
    c62_check "SIGTERM mid-run (temp worktree held: $C62_HELD): the gate exits 143" test "$C62_RC" -eq 143
    c62_check "SIGTERM mid-run: the temp directory is gone" test "$C62_HELD" -eq 1 -a -z "$(find "$C62_TP" -maxdepth 1 -name 'redgreen-*')"
    c62_check "SIGTERM mid-run: the worktree registration is gone" test "$(git -C "$C62_R" worktree list --porcelain | grep -c '^worktree ')" -eq 1
  else
    c62_bad "SIGTERM: the gate never reached its temp worktree"
  fi
  rm -rf "$C62_R" "$C62_T"

  if c62_start_gate; then
    kill -KILL "$C62_PID"
    wait "$C62_PID" 2>/dev/null || true
    C62_LEFT=$(find "$C62_TP" -maxdepth 1 -name 'redgreen-*' | wc -l | tr -d ' ')
    ( cd "$C62_R" && TMPDIR="$C62_TP" SCAFFOLD_WORKTREE_SWEEP_MAX_AGE=0 bash "$SWEEP" ) >"$HOOK_OUT" 2>&1 || true
    c62_check "SIGKILL leaves the worktree ($C62_LEFT dir), and the next run's sweep removes it" \
      test "$C62_LEFT" -eq 1 -a -z "$(find "$C62_TP" -maxdepth 1 -name 'redgreen-*')" -a "$(git -C "$C62_R" worktree list --porcelain | grep -c '^worktree ')" -eq 1
  else
    c62_bad "SIGKILL: the gate never reached its temp worktree"
  fi
  rm -rf "$C62_R" "$C62_T"
fi
rm -rf "$C62_STUB"

# --- (e) the report script ----------------------------------------------------------
c62_repo C62_R
C62_W=$(mktemp -d)
(
  cd "$C62_R" || exit 1
  git worktree add --quiet -b "done" "$C62_W/done" HEAD
  git worktree add --quiet -b gone "$C62_W/gone" HEAD
  git worktree add --quiet -b open "$C62_W/open" HEAD
  ( cd "$C62_W/open" && printf 'y\n' >g && git add g && git commit --quiet -m wip --no-verify )  # scaffold-allow: test fixture
  rm -rf "$C62_W/gone"
) >/dev/null 2>&1
C62_BEFORE=$(git -C "$C62_R" worktree list --porcelain | grep -c '^worktree ')
C62_RC=0
( cd "$C62_R" && SCAFFOLD_REPORT_NO_GH=1 bash "$SCAFFOLD_DIR/scaffold-worktree-report.sh" ) >"$HOOK_OUT" 2>&1 || C62_RC=$?
c62_check "report: exits 0 and lists all four registered worktrees" test "$C62_RC" -eq 0 -a "$(grep -c -e ' main  ' -e ' done  ' -e ' gone  ' -e ' open  ' "$HOOK_OUT")" -eq 4
c62_check "report: a branch merged into main reads 'yes'" grep -Eq ' done +[0-9a-z-]+ +yes ' "$HOOK_OUT"
c62_check "report: a branch with its own commit reads 'no'" grep -Eq ' open +[0-9a-z-]+ +no ' "$HOOK_OUT"
c62_check "report: a deleted directory reads MISSING" grep -Eq ' gone .*MISSING' "$HOOK_OUT"
c62_check "report: read-only, the registrations are unchanged" test "$(git -C "$C62_R" worktree list --porcelain | grep -c '^worktree ')" -eq "$C62_BEFORE"
C62_RC=0
( cd "$C62_W" && bash "$SCAFFOLD_DIR/scaffold-worktree-report.sh" ) >"$HOOK_OUT" 2>&1 || C62_RC=$?
c62_check "report: outside a git repository it still exits 0" test "$C62_RC" -eq 0
git -C "$C62_R" worktree prune >/dev/null 2>&1
rm -rf "$C62_R" "$C62_W"
unset C62_R C62_T C62_TP C62_E C62_W C62_STUB C62_PID C62_MARK C62_BASE C62_HELD C62_LEFT C62_PRE C62_BEFORE C62_RC
