# shellcheck shell=bash
# cases/57-refusal-log.sh: the durable refusal log (issue #218). Every shipped
# gate that refuses appends exactly one line to <git common dir>/
# scaffold-blocks.log, via .githooks/lib/refusal-log, and never records content.
# Sourced into the driver's shell; cwd is "$WORK". Gates are invoked directly
# with a NUL-delimited file list on stdin so the line count is per gate.

echo "Refusal log test cases (#218):"

rl_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
rl_bad() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# rl_logpath DIR: the log path for the repo at DIR (common dir, so a linked
# worktree maps to the main checkout's .git).
rl_logpath() {
  local c
  c=$(cd "$1" && git rev-parse --git-common-dir)
  case $c in /*) ;; *) c="$1/$c" ;; esac
  printf '%s/scaffold-blocks.log' "$c"
}
rl_count() {
  if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi
}
rl_field() { printf '%s' "$1" | cut -f"$2"; }
# rl_slug TEXT: the helper's documented slug rule, restated independently.
rl_slug() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9' '-' \
    | sed 's/^-*//; s/-*$//' | cut -c1-48 | sed 's/-*$//'
}
# rl_run SCRIPT FILE: run one gate on a one-entry NUL list; exit code in RL_RC.
rl_run() {
  RL_RC=0
  printf '%s\0' "$2" | env -u CLAUDE_SESSION_ID "$1" >"$HOOK_OUT" 2>&1 || RL_RC=$?
}
# rl_expect LABEL LOG BEFORE GATE RULE [RC]: exactly one new line, the right
# gate and rule, the right exit code in both the process and the line.
rl_expect() {
  local label=$1 log=$2 before=$3 gate=$4 rule=$5 want=${6:-1} after last
  after=$(rl_count "$log")
  last=$(tail -n 1 "$log" 2>/dev/null || true)
  if [ "$RL_RC" -eq "$want" ] && [ $((after - before)) -eq 1 ] \
     && [ "$(rl_field "$last" 2)" = "$gate" ] && [ "$(rl_field "$last" 3)" = "$rule" ] \
     && [ "$(rl_field "$last" 5)" = "$want" ]; then
    rl_ok "$label: one line, gate $gate, rule $rule"
  else
    rl_bad "$label: expected rc $want and +1 line ($gate $rule), got rc $RL_RC, +$((after - before)), last: $last"
    sed 's/^/      /' "$HOOK_OUT"
  fi
}

RLLOG=$(rl_logpath "$WORK")
rm -f "$RLLOG" "$RLLOG.1"
RLT=$(mktemp -d)
mkdir -p "$RLT/lib"
cp .githooks/lib/refusal-log "$RLT/lib/refusal-log"
chmod +x "$RLT/lib/refusal-log"
akia="AKIA""IOSFODNN7EXAMPLE"   # split so this file carries no real-looking key
bigpy() { seq 1 501 | sed 's/^/x = /' >"$1"; }

# a1. check-size
bigpy big.py
git add big.py
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-size big.py
rl_expect "check-size" "$RLLOG" "$rl_before" check-size size
reset_repo

# a2. check-large-files (600 KB, as cases/22)
dd if=/dev/zero bs=1000 count=600 2>/dev/null | tr '\0' x >large.txt
git add large.txt
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-large-files large.txt
rl_expect "check-large-files" "$RLLOG" "$rl_before" check-large-files large-files
reset_repo

# a3. check-patterns: the rule is the slug of the matched rule's DESCRIPTION
rl_desc=$(awk -F'\t' '/print\[\[:space:\]\]\*\\\(/ { print $2; exit }' .forbidden-patterns/backend.txt)
printf 'print("debug")\n' >app.py
git add app.py
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-patterns app.py
rl_expect "check-patterns" "$RLLOG" "$rl_before" check-patterns "$(rl_slug "$rl_desc")"
reset_repo

# a4. check-filenames
printf 'A=1\n' >.env
git add -f .env
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-filenames .env
rl_expect "check-filenames" "$RLLOG" "$rl_before" check-filenames env-file
reset_repo

# a5. check-secrets: rule is the slug of the secret rule's description
rl_desc=$(awk -F'\t' '/AKIA\|ASIA/ { print $2; exit }' .forbidden-patterns/secrets.txt)
printf 'AWS=%s\n' "$akia" >cfg.txt
git add cfg.txt
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-secrets cfg.txt
rl_expect "check-secrets" "$RLLOG" "$rl_before" check-secrets "$(rl_slug "$rl_desc")"
reset_repo

# c1. secret-shaped: the key staged for check-secrets is nowhere in the log
if [ -s "$RLLOG" ] && ! grep -qF "$akia" "$RLLOG"; then
  rl_ok "the staged secret value is not in the log after a check-secrets refusal"
else
  rl_bad "the log is missing or contains the staged secret value after a check-secrets refusal"
fi

# a6. check-hygiene: conflict marker (assembled so this file has none)
{ printf '%s HEAD\n' '<<<<<<<'; printf 'x\n=======\ny\n'; printf '%s b\n' '>>>>>>>'; } >conf.py
git add conf.py
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-hygiene conf.py
rl_expect "check-hygiene" "$RLLOG" "$rl_before" check-hygiene conflict-marker
reset_repo

# a7. check-gitleaks (opt-in, so run a copy beside the helper; needs gitleaks)
if command -v gitleaks >/dev/null 2>&1; then
  cp "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" "$RLT/lib/check-gitleaks"
  chmod +x "$RLT/lib/check-gitleaks"
  printf 'token = "%s"\n' "gh""p_aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5" >tok.txt
  git add tok.txt
  rl_before=$(rl_count "$RLLOG")
  rl_run "$RLT/lib/check-gitleaks" tok.txt
  rl_expect "check-gitleaks" "$RLLOG" "$rl_before" check-gitleaks gitleaks
  reset_repo
else
  echo "  - SKIP: gitleaks not installed, check-gitleaks's refusal-log assertion did NOT run"
  SKIP=$((SKIP + 1))
fi

# a8. commit-msg (opt-in hook, so run a copy with the helper in its lib/)
cp "$SCAFFOLD_DIR/githooks/commit-msg.template" "$RLT/commit-msg"
chmod +x "$RLT/commit-msg"
printf 'bad subject\n' >"$RLT/msg"
rl_before=$(rl_count "$RLLOG")
RL_RC=0
env -u CLAUDE_SESSION_ID "$RLT/commit-msg" "$RLT/msg" >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_expect "commit-msg" "$RLLOG" "$rl_before" commit-msg not-conventional

# a9. pre-commit's own refusal: deleting a pattern config. One line only.
git rm -q .forbidden-patterns/backend.txt
rl_before=$(rl_count "$RLLOG")
RL_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_expect "pre-commit own refusal" "$RLLOG" "$rl_before" pre-commit config-deleted
reset_repo

# a10. agent-precheck (Claude Code hook; needs jq). Run a copy beside the helper.
if command -v jq >/dev/null 2>&1; then
  cp "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" "$RLT/lib/agent-precheck"
  chmod +x "$RLT/lib/agent-precheck"
  pc=$(printf '{"session_id":"sess-z","tool_name":"Write","tool_input":{"file_path":"x.py","content":"AWS=%s"}}' "$akia")
  rl_before=$(rl_count "$RLLOG")
  RL_RC=0
  printf '%s' "$pc" | env -u CLAUDE_SESSION_ID CLAUDE_PROJECT_DIR="$PWD" bash "$RLT/lib/agent-precheck" >"$HOOK_OUT" 2>&1 || RL_RC=$?
  last=$(tail -n 1 "$RLLOG" 2>/dev/null || true)
  if [ "$RL_RC" -eq 2 ] && [ $(($(rl_count "$RLLOG") - rl_before)) -eq 1 ] \
     && [ "$(rl_field "$last" 2)" = agent-precheck ] && [ "$(rl_field "$last" 3)" = secrets ] \
     && [ "$(rl_field "$last" 4)" = x.py ] && [ "$(rl_field "$last" 5)" = 2 ] \
     && [ "$(rl_field "$last" 6)" = sess-z ] && [ "$(rl_field "$last" 7)" = - ]; then
    rl_ok "agent-precheck Write: exit 2, one line, rule secrets, file x.py, session from payload, no hash"
  else
    rl_bad "agent-precheck Write: rc $RL_RC, last line: $last"
    sed 's/^/      /' "$HOOK_OUT"
  fi
  pc=$(jq -nc --arg c "export AWS=$akia" '{tool_name:"Bash",tool_input:{command:$c}}')
  rl_before=$(rl_count "$RLLOG")
  RL_RC=0
  printf '%s' "$pc" | env -u CLAUDE_SESSION_ID CLAUDE_PROJECT_DIR="$PWD" bash "$RLT/lib/agent-precheck" >"$HOOK_OUT" 2>&1 || RL_RC=$?
  last=$(tail -n 1 "$RLLOG" 2>/dev/null || true)
  rl_hex='^[0-9a-f]{12}$'
  rl_h=$(rl_field "$last" 7)
  if [ "$RL_RC" -eq 2 ] && [ $(($(rl_count "$RLLOG") - rl_before)) -eq 1 ] \
     && [[ $rl_h =~ $rl_hex ]] && [ "$(rl_field "$last" 4)" = - ]; then
    rl_ok "agent-precheck Bash: exit 2, one line, 12-hex command hash, no file"
  else
    rl_bad "agent-precheck Bash: rc $RL_RC, last line: $last"
    sed 's/^/      /' "$HOOK_OUT"
  fi
  # c2. the key sat inside the Bash command; the log must not carry it
  if grep -qF "$akia" "$RLLOG"; then
    rl_bad "the log contains the secret from a refused Bash command"
  else
    rl_ok "the secret inside a refused Bash command is not in the log"
  fi
else
  echo "  - SKIP: jq not installed, agent-precheck's 3 refusal-log assertions did NOT run"
  SKIP=$((SKIP + 3))
fi

# a11. check-red-green and check-mutation-diff (python3; copies beside the helper)
if command -v python3 >/dev/null 2>&1; then
  fixture_repo RLPY
  mkdir "$RLPY/tests"
  for rl_py in check-red-green check-mutation-diff; do
    cp "$SCAFFOLD_DIR/githooks/lib/$rl_py.template" "$RLT/lib/$rl_py"
    chmod +x "$RLT/lib/$rl_py"
    rl_pylog=$(rl_logpath "$RLPY")
    rl_before=$(rl_count "$rl_pylog")
    RL_RC=0
    ( cd "$RLPY" && env -u CLAUDE_SESSION_ID python3 "$RLT/lib/$rl_py" --base no-such-ref ) >"$HOOK_OUT" 2>&1 || RL_RC=$?
    rl_expect "$rl_py" "$rl_pylog" "$rl_before" "$rl_py" setup-error 2
  done
  # A directory at the helper path is skipped, a non-executable helper still
  # logs (the gate runs it through bash); neither may raise or change the exit.
  rl_py=check-red-green
  mv "$RLT/lib/refusal-log" "$RLT/refusal-log.away"
  mkdir "$RLT/lib/refusal-log"
  rl_before=$(rl_count "$rl_pylog")
  RL_RC=0
  ( cd "$RLPY" && env -u CLAUDE_SESSION_ID python3 "$RLT/lib/$rl_py" --base no-such-ref ) >"$HOOK_OUT" 2>&1 || RL_RC=$?
  rl_tb=$(grep -c Traceback "$HOOK_OUT" || true)
  if [ "$RL_RC" -eq 2 ] && [ "$rl_tb" -eq 0 ] && [ "$(rl_count "$rl_pylog")" -eq "$rl_before" ]; then
    rl_ok "$rl_py with a directory at the helper path: exit 2, no traceback, nothing logged"
  else
    rl_bad "$rl_py with a directory at the helper path: rc $RL_RC, tracebacks $rl_tb, +$(($(rl_count "$rl_pylog") - rl_before)) line(s)"
    sed 's/^/      /' "$HOOK_OUT"
  fi
  rmdir "$RLT/lib/refusal-log"
  mv "$RLT/refusal-log.away" "$RLT/lib/refusal-log"
  chmod -x "$RLT/lib/refusal-log"
  rl_before=$(rl_count "$rl_pylog")
  RL_RC=0
  ( cd "$RLPY" && env -u CLAUDE_SESSION_ID python3 "$RLT/lib/$rl_py" --base no-such-ref ) >"$HOOK_OUT" 2>&1 || RL_RC=$?
  rl_expect "$rl_py with a non-executable helper" "$rl_pylog" "$rl_before" "$rl_py" setup-error 2
  chmod +x "$RLT/lib/refusal-log"
  rm -rf "$RLPY"
else
  echo "  - SKIP: python3 not installed, check-red-green and check-mutation-diff's 4 refusal-log assertions did NOT run"
  SKIP=$((SKIP + 4))
fi

# b. A whole pre-commit run refused only by check-patterns: one line, from the
#    check, none from pre-commit itself.
printf 'print("debug")\n' >app.py
git add app.py
rl_before=$(rl_count "$RLLOG")
RL_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_expect "full pre-commit run refused only by check-patterns" "$RLLOG" "$rl_before" check-patterns "$(rl_slug "$(awk -F'\t' '/print\[\[:space:\]\]\*\\\(/ { print $2; exit }' .forbidden-patterns/backend.txt)")"
reset_repo

# d. Line format: 7 tab-separated fields on every line, ISO-8601 UTC time.
rl_badlines=$(awk -F'\t' 'NF != 7 { n++ } END { print n + 0 }' "$RLLOG")
rl_ts=$(head -n 1 "$RLLOG" | cut -f1)
rl_tsre='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [ "$rl_badlines" -eq 0 ] && [[ $rl_ts =~ $rl_tsre ]]; then
  rl_ok "every log line has 7 tab-separated fields and an ISO-8601 UTC time ($rl_ts)"
else
  rl_bad "log line format wrong: $rl_badlines line(s) not 7 fields, first time '$rl_ts'"
fi
rl_codes=$(cut -f5 "$RLLOG" | sort -u | tr '\n' ' ')
# Exit 2 lines come only from the jq-gated agent-precheck assertions.
if command -v jq >/dev/null 2>&1; then rl_want="1 2 "; else rl_want="1 "; fi
if [ "$rl_codes" = "$rl_want" ]; then
  rl_ok "the exit-code field carries the gate's exit code (set '$rl_want', exit 2 only with jq)"
else
  rl_bad "exit-code field values were '$rl_codes', expected '$rl_want' (exit 2 only with jq)"
fi

# e. Durability: session field, a second environment, a linked worktree.
bigpy big.py
git add big.py
rl_before=$(rl_count "$RLLOG")
printf 'big.py\0' | CLAUDE_SESSION_ID=sess-a .githooks/lib/check-size >/dev/null 2>&1 || true
printf 'big.py\0' | env -u CLAUDE_SESSION_ID .githooks/lib/check-size >/dev/null 2>&1 || true
rl_l1=$(sed -n "$((rl_before + 1))p" "$RLLOG")
rl_l2=$(sed -n "$((rl_before + 2))p" "$RLLOG")
if [ "$(rl_count "$RLLOG")" -eq $((rl_before + 2)) ] && [ "$(rl_field "$rl_l1" 6)" = sess-a ] \
   && [ "$(rl_field "$rl_l2" 6)" = - ]; then
  rl_ok "the sess-a line survives a later refusal in a fresh environment (session field - there)"
else
  rl_bad "durability/session fields wrong: '$rl_l1' / '$rl_l2'"
fi
rl_wt="$RLT/wt"
git worktree add -q "$rl_wt" -b wt-218
bigpy "$rl_wt/big.py"
( cd "$rl_wt" && git add big.py && printf 'big.py\0' | env -u CLAUDE_SESSION_ID "$WORK/.githooks/lib/check-size" >/dev/null 2>&1 ) || true
if [ "$(rl_count "$RLLOG")" -eq $((rl_before + 3)) ]; then
  rl_ok "a refusal inside a linked worktree lands in the main checkout's log"
else
  rl_bad "worktree refusal did not land in $RLLOG (count $(rl_count "$RLLOG"), expected $((rl_before + 3)))"
fi
git worktree remove --force "$rl_wt"
git branch -D wt-218 >/dev/null 2>&1
if [ "$(rl_count "$RLLOG")" -eq $((rl_before + 3)) ] && [ "$(sed -n "$((rl_before + 1))p" "$RLLOG")" = "$rl_l1" ]; then
  rl_ok "the log lines survive removing the worktree and deleting its branch"
else
  rl_bad "log lost lines after worktree removal"
fi
reset_repo

# g. Fail open: with the helper gone the gate refuses identically, logs nothing.
bigpy big.py
git add big.py
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-size big.py
rl_rc_with=$RL_RC
cp "$HOOK_OUT" "$RLT/with.out"
mv .githooks/lib/refusal-log "$RLT/refusal-log.away"
rl_run .githooks/lib/check-size big.py
rl_rc_without=$RL_RC
mv "$RLT/refusal-log.away" .githooks/lib/refusal-log
if [ "$rl_rc_with" -eq 1 ] && [ "$rl_rc_without" -eq 1 ] && cmp -s "$RLT/with.out" "$HOOK_OUT" \
   && [ "$(rl_count "$RLLOG")" -eq $((rl_before + 1)) ]; then
  rl_ok "without the helper check-size still refuses (exit 1), output identical, nothing logged"
else
  rl_bad "fail-open: rc with=$rl_rc_with without=$rl_rc_without, lines +$(($(rl_count "$RLLOG") - rl_before)) (expected +1 from the with-helper run only)"
fi
reset_repo

# g2. A helper that is present but not executable: the gate still refuses
#     identically and writes no line (the bash gates run it only when +x).
bigpy big.py
git add big.py
rl_before=$(rl_count "$RLLOG")
chmod -x .githooks/lib/refusal-log
rl_run .githooks/lib/check-size big.py
chmod +x .githooks/lib/refusal-log
if [ "$RL_RC" -eq 1 ] && cmp -s "$RLT/with.out" "$HOOK_OUT" && [ "$(rl_count "$RLLOG")" -eq "$rl_before" ]; then
  rl_ok "with a non-executable helper check-size still refuses (exit 1), output identical, nothing logged"
else
  rl_bad "non-executable helper: rc $RL_RC, +$(($(rl_count "$RLLOG") - rl_before)) line(s)"
fi
reset_repo

# g3. CDPATH=. must not stop the log line (cd would echo and corrupt SELF_DIR).
printf 'AWS=%s\n' "$akia" >cfg.txt
git add cfg.txt
rl_before=$(rl_count "$RLLOG")
RL_RC=0
printf 'cfg.txt\0' | env -u CLAUDE_SESSION_ID CDPATH=. .githooks/lib/check-secrets >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_expect "check-secrets with CDPATH=." "$RLLOG" "$rl_before" check-secrets "$(rl_slug "$(awk -F'\t' '/AKIA\|ASIA/ { print $2; exit }' .forbidden-patterns/secrets.txt)")"
reset_repo

# g4. A failing local.d check: pre-commit logs it under the script's name.
mkdir -p .githooks/local.d
printf '#!/usr/bin/env bash\nexit 1\n' >.githooks/local.d/zz-fail
chmod +x .githooks/local.d/zz-fail
printf 'ok\n' >ok.txt
git add ok.txt
rl_before=$(rl_count "$RLLOG")
RL_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_expect "a failing local.d check" "$RLLOG" "$rl_before" pre-commit local-check-zz-fail
rm -f .githooks/local.d/zz-fail
rmdir .githooks/local.d 2>/dev/null || true
reset_repo

# h. A warn-state finding is not a refusal: exit 0, nothing logged.
printf '[rules.size]\nseverity = "warn"\n' >.scaffold.toml
bigpy big.py
git add .scaffold.toml big.py
rl_before=$(rl_count "$RLLOG")
rl_run .githooks/lib/check-size big.py
if [ "$RL_RC" -eq 0 ] && [ "$(rl_count "$RLLOG")" -eq "$rl_before" ]; then
  rl_ok "a severity = warn override exits 0 and adds no line"
else
  rl_bad "warn state: rc $RL_RC, +$(($(rl_count "$RLLOG") - rl_before)) line(s)"
fi
reset_repo

# f. Rotation: a log over 1 MiB moves to .log.1 and a fresh log starts.
rm -f "$RLLOG" "$RLLOG.1"
dd if=/dev/zero bs=1100 count=1000 2>/dev/null | tr '\0' j >"$RLLOG"
bigpy big.py
git add big.py
rl_run .githooks/lib/check-size big.py
if [ -f "$RLLOG.1" ] && [ "$(rl_count "$RLLOG")" -eq 1 ] && [ "$(wc -c <"$RLLOG.1" | tr -d ' ')" -ge 1048576 ]; then
  rl_ok "a log over 1 MiB rotates to .log.1 and the new log has exactly 1 line"
else
  rl_bad "rotation: .log.1 present=$([ -f "$RLLOG.1" ] && echo yes || echo no), .log lines=$(rl_count "$RLLOG")"
fi
reset_repo

# i. scaffold-blocks.sh: per-gate count, longest retry run, and the empty case.
rm -f "$RLLOG" "$RLLOG.1"
printf 'A=1\n' >.env
git add -f .env
rl_run .githooks/lib/check-filenames .env
reset_repo
bigpy big.py
git add big.py
rl_run .githooks/lib/check-size big.py
rl_run .githooks/lib/check-size big.py
rl_run .githooks/lib/check-size big.py
reset_repo
RL_RC=0
"$SCAFFOLD_DIR/scaffold-blocks.sh" >"$HOOK_OUT" 2>&1 || RL_RC=$?
rl_n=$(awk -F'\t' '$2 == "check-size"' "$RLLOG" | wc -l | tr -d ' ')
if [ "$RL_RC" -eq 0 ] && grep -qE "^  $rl_n  check-size$" "$HOOK_OUT" \
   && grep -qE "^longest retry run: 3 consecutive refusal\(s\) of check-size size big.py" "$HOOK_OUT"; then
  rl_ok "scaffold-blocks.sh prints the check-size count ($rl_n) and a retry run of 3"
else
  rl_bad "scaffold-blocks.sh output unexpected (rc $RL_RC, check-size lines $rl_n)"
  sed 's/^/      /' "$HOOK_OUT"
fi
fixture_repo RLEMPTY
RL_RC=0
( cd "$RLEMPTY" && "$SCAFFOLD_DIR/scaffold-blocks.sh" ) >"$HOOK_OUT" 2>&1 || RL_RC=$?
if [ "$RL_RC" -eq 0 ] && grep -qF "no refusals recorded" "$HOOK_OUT"; then
  rl_ok "scaffold-blocks.sh on a repo with no log says so and exits 0"
else
  rl_bad "scaffold-blocks.sh on an empty repo: rc $RL_RC"
  sed 's/^/      /' "$HOOK_OUT"
fi
rm -rf "$RLEMPTY"

# j. Source-level pins.
rl_missing=""
for rl_t in "$SCAFFOLD_DIR"/githooks/lib/check-*.template "$SCAFFOLD_DIR/githooks/pre-commit.template" \
            "$SCAFFOLD_DIR/githooks/commit-msg.template" "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template"; do
  grep -qF refusal-log "$rl_t" || rl_missing="$rl_missing ${rl_t##*/}"
done
if [ -z "$rl_missing" ]; then
  rl_ok "every check-*, pre-commit, commit-msg and agent-precheck template calls refusal-log"
else
  rl_bad "templates without a refusal-log call:$rl_missing"
fi
rl_mut=$(wc -l <"$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" | tr -d ' ')
if [ "$rl_mut" -eq 500 ]; then
  rl_ok "check-mutation-diff.template is exactly 500 lines (the cap, no headroom)"
else
  rl_bad "check-mutation-diff.template is $rl_mut lines, expected exactly 500"
fi
if grep -Eq '(^|[^[:alnum:]_-])set -[a-zA-Z]*e' "$SCAFFOLD_DIR/githooks/lib/refusal-log.template"; then
  rl_bad "refusal-log.template uses set -e: logging must never fail a gate"
else
  rl_ok "refusal-log.template has no set -e"
fi

rm -rf "$RLT"
