# shellcheck shell=bash
# cases/60-refusal-class.sh: every shipped refusal ends with one fixed class
# trailer (issue #259), printed by .githooks/lib/refusal-log --say. Class (a): a
# check failed on the agent's own change. Class (b): the gate itself is wrong or
# broken. Class (c), a harness denial, is never printed by a gate.
# Sourced into the driver's shell; cwd is "$WORK". Gates are invoked directly
# with a NUL-delimited file list on stdin, as in cases/57.

echo "Refusal class test cases (#259):"

rc_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
rc_bad() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); sed 's/^/      /' "$HOOK_OUT"; }

rc_a="refusal class (a): this check failed on your own change. Fix the file, never the gate."
rc_b="refusal class (b): this gate is itself wrong or broken. Stop and report this message to the user verbatim."

# rc_logpath DIR / rc_count LOG / rc_field LINE N: as in cases/57.
rc_logpath() {
  local c
  c=$(cd "$1" && git rev-parse --git-common-dir)
  case $c in /*) ;; *) c="$1/$c" ;; esac
  printf '%s/scaffold-blocks.log' "$c"
}
rc_count() { if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }
rc_field() { printf '%s' "$1" | cut -f"$2"; }

RCLOG=$(rc_logpath "$WORK")
rm -f "$RCLOG" "$RCLOG.1"
RCT=$(mktemp -d)
mkdir -p "$RCT/lib"
cp .githooks/lib/refusal-log "$RCT/lib/refusal-log"
chmod +x "$RCT/lib/refusal-log"
akia="AKIA""IOSFODNN7EXAMPLE"   # split so this file carries no real-looking key
bigpy() { seq 1 501 | sed 's/^/x = /' >"$1"; }

# rc_run SCRIPT FILE [ENV...]: run one gate on a one-entry NUL list; rc in RC_RC.
rc_run() {
  local script=$1 file=$2
  shift 2
  RC_RC=0
  printf '%s\0' "$file" | env -u CLAUDE_SESSION_ID "$@" "$script" >"$HOOK_OUT" 2>&1 || RC_RC=$?
}
# rc_expect LABEL TRAILER WANT_RC: last line of the combined output is exactly
# TRAILER and the exit code is WANT_RC.
rc_expect() {
  local label=$1 want=$2 wantrc=$3 last
  last=$(tail -n 1 "$HOOK_OUT")
  if [ "$RC_RC" -eq "$wantrc" ] && [ "$last" = "$want" ]; then
    rc_ok "$label: exit $wantrc, output ends with the class trailer"
  else
    rc_bad "$label: expected exit $wantrc and the trailer last, got exit $RC_RC, last line: $last"
  fi
}
# rc_logged LABEL LOG BEFORE GATE RULE: exactly one new line, gate, rule, exit 2.
rc_logged() {
  local label=$1 log=$2 before=$3 gate=$4 rule=$5 after last
  after=$(rc_count "$log")
  last=$(tail -n 1 "$log" 2>/dev/null || true)
  if [ $((after - before)) -eq 1 ] && [ "$(rc_field "$last" 2)" = "$gate" ] \
     && [ "$(rc_field "$last" 3)" = "$rule" ] && [ "$(rc_field "$last" 5)" = "$RC_RC" ]; then
    rc_ok "$label: logged once as $gate $rule, exit $RC_RC"
  else
    rc_bad "$label: expected +1 line ($gate $rule $RC_RC), got +$((after - before)), last: $last"
  fi
}

# rc_rule_is LABEL RULE: the last log line (exactly one new line) names RULE.
rc_rule_is() {
  local label=$1 rule=$2 last
  last=$(tail -n 1 "$RCLOG" 2>/dev/null || true)
  if [ "$(rc_field "$last" 3)" = "$rule" ] && [ "$(rc_count "$RCLOG")" -eq $((rl_before + 1)) ]; then
    rc_ok "$label: logged once as rule $rule"
  else
    rc_bad "$label: expected one new line with rule $rule, last: $last"
  fi
}
# --- class (a) ---------------------------------------------------------------
bigpy big.py
git add big.py
rc_run .githooks/lib/check-size big.py
rc_expect "check-size" "$rc_a" 1
reset_repo

dd if=/dev/zero bs=1000 count=600 2>/dev/null | tr '\0' x >large.txt
git add large.txt
rc_run .githooks/lib/check-large-files large.txt
rc_expect "check-large-files" "$rc_a" 1
reset_repo

printf 'print("debug")\n' >app.py
git add app.py
rc_run .githooks/lib/check-patterns app.py
rc_expect "check-patterns finding" "$rc_a" 1
reset_repo

printf 'A=1\n' >.env
git add -f .env
rc_run .githooks/lib/check-filenames .env
rc_expect "check-filenames" "$rc_a" 1
reset_repo

printf 'AWS=%s\n' "$akia" >cfg.txt
git add cfg.txt
rc_run .githooks/lib/check-secrets cfg.txt
rc_expect "check-secrets finding" "$rc_a" 1
reset_repo

{ printf '%s HEAD\n' '<<<<<<<'; printf 'x\n=======\ny\n'; printf '%s b\n' '>>>>>>>'; } >conf.py
git add conf.py
rc_run .githooks/lib/check-hygiene conf.py
rc_expect "check-hygiene" "$rc_a" 1
reset_repo

if command -v gitleaks >/dev/null 2>&1; then
  cp "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" "$RCT/lib/check-gitleaks"
  chmod +x "$RCT/lib/check-gitleaks"
  printf 'token = "%s"\n' "gh""p_aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5" >tok.txt
  git add tok.txt
  rc_run "$RCT/lib/check-gitleaks" tok.txt
  rc_expect "check-gitleaks" "$rc_a" 1
  reset_repo
else
  echo "  - SKIP: gitleaks not installed, check-gitleaks's class trailer assertion did NOT run"
  SKIP=$((SKIP + 1))
fi

cp "$SCAFFOLD_DIR/githooks/commit-msg.template" "$RCT/commit-msg"
chmod +x "$RCT/commit-msg"
printf 'bad subject\n' >"$RCT/msg"
RC_RC=0
env -u CLAUDE_SESSION_ID "$RCT/commit-msg" "$RCT/msg" >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "commit-msg" "$rc_a" 1

# A conventional subject over 100 characters is a finding on the agent's own message.
printf 'feat: %s\n' "$(printf 'x%.0s' $(seq 1 100))" >"$RCT/msg"
RC_RC=0
env -u CLAUDE_SESSION_ID "$RCT/commit-msg" "$RCT/msg" >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "commit-msg subject over 100 characters" "$rc_a" 1

git rm -q .forbidden-patterns/backend.txt
RC_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "pre-commit config-deleted guard" "$rc_a" 1
reset_repo

if command -v jq >/dev/null 2>&1; then
  cp "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" "$RCT/lib/agent-precheck"
  chmod +x "$RCT/lib/agent-precheck"
  pc=$(printf '{"session_id":"sess-z","tool_name":"Write","tool_input":{"file_path":"x.py","content":"AWS=%s"}}' "$akia")
  RC_RC=0
  printf '%s' "$pc" | env -u CLAUDE_SESSION_ID CLAUDE_PROJECT_DIR="$PWD" bash "$RCT/lib/agent-precheck" >"$HOOK_OUT" 2>&1 || RC_RC=$?
  rc_expect "agent-precheck Write with a secret" "$rc_a" 2
else
  echo "  - SKIP: jq not installed, agent-precheck's class trailer assertion did NOT run"
  SKIP=$((SKIP + 1))
fi

# A full pre-commit run refused only by check-patterns: exactly one trailer, and
# the "Pre-commit failed" banner comes after it.
printf 'print("debug")\n' >app.py
git add app.py
RC_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_n=$(grep -cxF "$rc_a" "$HOOK_OUT" || true)
rc_tl=$(grep -nxF "$rc_a" "$HOOK_OUT" | head -n 1 | cut -d: -f1)
rc_bl=$(grep -n '^Pre-commit failed' "$HOOK_OUT" | head -n 1 | cut -d: -f1)
if [ "$RC_RC" -eq 1 ] && [ "$rc_n" -eq 1 ] && [ -n "$rc_tl" ] && [ -n "$rc_bl" ] && [ "$rc_bl" -gt "$rc_tl" ]; then
  rc_ok "full pre-commit run: one class (a) trailer, then the Pre-commit failed banner"
else
  rc_bad "full pre-commit run: exit $RC_RC, $rc_n trailer(s), trailer line ${rc_tl:-none}, banner line ${rc_bl:-none}"
fi
reset_repo

# --- class (b): a gate's own configuration error, logged with exit 2 ---------
printf 'x = 1\n' >ok.py
git add ok.py
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-size ok.py MAX_LINES=abc
rc_expect "check-size MAX_LINES=abc" "$rc_b" 2
rc_logged "check-size MAX_LINES=abc" "$RCLOG" "$rl_before" check-size invalid-max-lines
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-size ok.py MAX_LINES=0
rc_expect "check-size MAX_LINES=0" "$rc_b" 2
rc_logged "check-size MAX_LINES=0" "$RCLOG" "$rl_before" check-size invalid-max-lines
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-large-files ok.py MAX_BYTES=x
rc_expect "check-large-files MAX_BYTES=x" "$rc_b" 2
rc_logged "check-large-files MAX_BYTES=x" "$RCLOG" "$rl_before" check-large-files invalid-max-bytes
for rc_g in check-patterns check-secrets check-hygiene; do
  rl_before=$(rc_count "$RCLOG")
  rc_run ".githooks/lib/$rc_g" ok.py MAX_LINE_LENGTH=x
  rc_expect "$rc_g MAX_LINE_LENGTH=x" "$rc_b" 2
  rc_logged "$rc_g MAX_LINE_LENGTH=x" "$RCLOG" "$rl_before" "$rc_g" invalid-max-line-length
done
reset_repo

# Empty secrets config with a staged file: the pattern config is broken.
cp .forbidden-patterns/secrets.txt "$RCT/secrets.keep"
: >.forbidden-patterns/secrets.txt
printf 'x = 1\n' >ok.py
git add ok.py
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-secrets ok.py
rc_expect "check-secrets empty config" "$rc_b" 1
rc_logged "check-secrets empty config" "$RCLOG" "$rl_before" check-secrets empty-config
cp "$RCT/secrets.keep" .forbidden-patterns/secrets.txt
reset_repo

# An unscannable over-long line is the gate's limit, not the agent's mistake.
printf 'x = "0123456789012345678901234567890123456789"\n' >app.py
git add app.py
for rc_g in check-patterns check-secrets; do
  rl_before=$(rc_count "$RCLOG")
  rc_run ".githooks/lib/$rc_g" app.py MAX_LINE_LENGTH=10
  rc_expect "$rc_g line-too-long" "$rc_b" 1
  rc_logged "$rc_g line-too-long" "$RCLOG" "$rl_before" "$rc_g" line-too-long
done
reset_repo

# RL_CLASS in the environment must not leak into a finding's class (a).
printf 'print("debug")\n' >app.py
git add app.py
rc_run .githooks/lib/check-patterns app.py RL_CLASS=b
rc_expect "check-patterns finding with RL_CLASS=b in the environment" "$rc_a" 1
reset_repo

# First wins: a secret finding, then an over-long line in a later file, stays (a)
# and the log names the secret rule.
printf 'AWS=%s\n' "$akia" >a.txt
printf 'x = "0123456789012345678901234567890123456789"\n' >b.txt
git add a.txt b.txt
rl_before=$(rc_count "$RCLOG")
RC_RC=0
printf 'a.txt\0b.txt\0' | env -u CLAUDE_SESSION_ID MAX_LINE_LENGTH=30 .githooks/lib/check-secrets >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "check-secrets secret then over-long line" "$rc_a" 1
rc_desc=$(awk -F'\t' '/AKIA\|ASIA/ { print $2; exit }' .forbidden-patterns/secrets.txt)
rc_last=$(tail -n 1 "$RCLOG")
rc_want=$(printf '%s' "$rc_desc" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48 | sed 's/-*$//')
if [ "$(rc_field "$rc_last" 3)" = "$rc_want" ] && [ "$(rc_count "$RCLOG")" -eq $((rl_before + 1)) ]; then
  rc_ok "check-secrets first-wins: the log line carries the secret rule"
else
  rc_bad "check-secrets first-wins: last log line: $rc_last"
fi
reset_repo

# check-hygiene: an unscannable over-long line is class (b).
printf 'x = "0123456789012345678901234567890123456789"\n' >app.py
git add app.py
rc_run .githooks/lib/check-hygiene app.py MAX_LINE_LENGTH=10
rc_expect "check-hygiene line-too-long" "$rc_b" 1
reset_repo

# check-patterns with an empty pattern config, check-secrets with an invalid regex.
cp .forbidden-patterns/backend.txt "$RCT/backend.keep"
: >.forbidden-patterns/backend.txt
printf 'x = 1\n' >ok.py
git add ok.py
rc_run .githooks/lib/check-patterns ok.py
rc_expect "check-patterns empty config" "$rc_b" 1
cp "$RCT/backend.keep" .forbidden-patterns/backend.txt
cp .forbidden-patterns/secrets.txt "$RCT/secrets.keep"
printf '[unclosed\tbad rule\n' >.forbidden-patterns/secrets.txt
rc_run .githooks/lib/check-secrets ok.py
rc_expect "check-secrets invalid regex" "$rc_b" 1
cp "$RCT/secrets.keep" .forbidden-patterns/secrets.txt
reset_repo

# check-patterns whose only rule is an invalid regex: class (b), rule invalid-config.
cp .forbidden-patterns/backend.txt "$RCT/backend.keep"
printf '# scaffold-extensions: py\n[unclosed\tbad rule\n' >.forbidden-patterns/backend.txt
printf 'x = 1\n' >ok.py
git add ok.py
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-patterns ok.py
rc_expect "check-patterns invalid-config" "$rc_b" 1
rc_rule_is "check-patterns invalid-config" invalid-config
cp "$RCT/backend.keep" .forbidden-patterns/backend.txt
reset_repo

# check-patterns first-wins: a pattern finding, then an over-long line in a later file, stays (a).
printf 'print("debug")\n' >a.py
printf 'x = "0123456789012345678901234567890123456789"\n' >b.py
git add a.py b.py
rl_before=$(rc_count "$RCLOG")
RC_RC=0
printf 'a.py\0b.py\0' | env -u CLAUDE_SESSION_ID MAX_LINE_LENGTH=30 .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "check-patterns pattern then over-long line" "$rc_a" 1
rc_desc=$(awk -F'\t' '/print\[\[:space:\]\]\*\\\(/ { print $2; exit }' .forbidden-patterns/backend.txt)
rc_want=$(printf '%s' "$rc_desc" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48 | sed 's/-*$//')
rc_rule_is "check-patterns first-wins" "$rc_want"
reset_repo

# A full pre-commit run refused by a failing local.d check: one (a) trailer, then the banner.
mkdir -p .githooks/local.d
printf '#!/usr/bin/env bash\nexit 1\n' >.githooks/local.d/zz-fail
chmod +x .githooks/local.d/zz-fail
printf 'ok\n' >ok.txt
git add ok.txt
RC_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_n=$(grep -cxF "$rc_a" "$HOOK_OUT" || true)
rc_tl=$(grep -nxF "$rc_a" "$HOOK_OUT" | head -n 1 | cut -d: -f1)
rc_bl=$(grep -n '^Pre-commit failed' "$HOOK_OUT" | head -n 1 | cut -d: -f1)
if [ "$RC_RC" -eq 1 ] && [ "$rc_n" -eq 1 ] && [ -n "$rc_tl" ] && [ -n "$rc_bl" ] && [ "$rc_bl" -gt "$rc_tl" ]; then
  rc_ok "failing local.d check: one class (a) trailer, then the Pre-commit failed banner"
else
  rc_bad "failing local.d check: exit $RC_RC, $rc_n trailer(s), trailer line ${rc_tl:-none}, banner line ${rc_bl:-none}"
fi
rm -f .githooks/local.d/zz-fail
rmdir .githooks/local.d 2>/dev/null || true
reset_repo

# --- mutant killers: config-state refusals and RL_CLASS first-wins ------------
printf 'x = 1\n' >ok.py
git add ok.py

cp .forbidden-patterns/secrets.txt "$RCT/secrets.keep"
rm -f .forbidden-patterns/secrets.txt
rl_before=$(rc_count "$RCLOG")
RC_RC=0
printf '%s\0' ok.py | env -u CLAUDE_SESSION_ID .githooks/lib/check-secrets --ci >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "check-secrets --ci with secrets.txt missing" "$rc_b" 1
rc_rule_is "check-secrets --ci with secrets.txt missing" config-missing
cp "$RCT/secrets.keep" .forbidden-patterns/secrets.txt

rm -f .forbidden-patterns/secrets.txt
mkdir .forbidden-patterns/secrets.txt
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-secrets ok.py
rc_expect "check-secrets with secrets.txt a directory" "$rc_b" 1
rc_rule_is "check-secrets with secrets.txt a directory" config-unreadable
rmdir .forbidden-patterns/secrets.txt
cp "$RCT/secrets.keep" .forbidden-patterns/secrets.txt

chmod 000 .forbidden-patterns/backend.txt
rl_before=$(rc_count "$RCLOG")
rc_run .githooks/lib/check-patterns ok.py
chmod 644 .forbidden-patterns/backend.txt
rc_expect "check-patterns with an unreadable backend.txt" "$rc_b" 1
rc_rule_is "check-patterns with an unreadable backend.txt" config-unreadable

cp .forbidden-patterns/backend.txt "$RCT/backend.keep"
rm -f .forbidden-patterns/backend.txt
rl_before=$(rc_count "$RCLOG")
RC_RC=0
printf '%s\0' ok.py | env -u CLAUDE_SESSION_ID .githooks/lib/check-patterns --ci >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "check-patterns with a manifest-recorded backend.txt removed" "$rc_b" 1
rc_rule_is "check-patterns with a manifest-recorded backend.txt removed" config-removed
cp "$RCT/backend.keep" .forbidden-patterns/backend.txt
reset_repo

# pre-commit: an untracked but present strict config is class (a).
git rm -q --cached .forbidden-patterns/backend.txt
rl_before=$(rc_count "$RCLOG")
RC_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RC_RC=$?
rc_expect "pre-commit config-untracked guard" "$rc_a" 1
rc_rule_is "pre-commit config-untracked guard" config-untracked
reset_repo

# RL_CLASS=b in the environment must not turn other gates' findings into (b).
printf 'AWS=%s\n' "$akia" >cfg.txt
git add cfg.txt
rc_run .githooks/lib/check-secrets cfg.txt RL_CLASS=b
rc_expect "check-secrets finding with RL_CLASS=b in the environment" "$rc_a" 1
reset_repo
{ printf '%s HEAD\n' '<<<<<<<'; printf 'x\n=======\ny\n'; printf '%s b\n' '>>>>>>>'; } >conf.py
git add conf.py
rc_run .githooks/lib/check-hygiene conf.py RL_CLASS=b
rc_expect "check-hygiene finding with RL_CLASS=b in the environment" "$rc_a" 1
reset_repo

# pre-commit stash failure is class (b): an unstaged change plus a read-only refs dir.
printf 'y = 2\n' >st.py
git add st.py
git -c commit.gpgsign=false commit -q -m st
printf 'y = 3\n' >st.py
printf 'z = 1\n' >st2.py
git add st2.py
chmod a-w "$(git rev-parse --git-dir)/refs"
rl_before=$(rc_count "$RCLOG")
RC_RC=0
env -u CLAUDE_SESSION_ID .githooks/pre-commit >"$HOOK_OUT" 2>&1 || RC_RC=$?
chmod u+w "$(git rev-parse --git-dir)/refs"
rc_expect "pre-commit stash failure" "$rc_b" 1
rc_rule_is "pre-commit stash failure" stash-failed
git reset -q --hard HEAD~1
reset_repo

rm -rf "$RCT"
