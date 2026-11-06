# shellcheck shell=bash
# cases/61-refusal-class-helper.sh: the refusal-log --say helper itself, the
# Python and TypeScript gates' class trailers, and the source pins (issue #259).
# Companion of cases/60-refusal-class.sh, which runs the per-gate trailers. Self-
# sufficient: it defines what it needs, so it also runs alone. Sourced into the
# driver's shell; cwd is "$WORK".

echo "Refusal class helper and pin test cases (#259):"

rc_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
rc_bad() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); sed 's/^/      /' "$HOOK_OUT"; }

rc_a="refusal class (a): this check failed on your own change. Fix the file, never the gate."
rc_b="refusal class (b): this gate is itself wrong or broken. Stop and report this message to the user verbatim."

rc_logpath() {
  local c
  c=$(cd "$1" && git rev-parse --git-common-dir)
  case $c in /*) ;; *) c="$1/$c" ;; esac
  printf '%s/scaffold-blocks.log' "$c"
}
rc_count() { if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }

RCLOG=$(rc_logpath "$WORK")
RCT=$(mktemp -d)
mkdir -p "$RCT/lib"
cp .githooks/lib/refusal-log "$RCT/lib/refusal-log"
chmod +x "$RCT/lib/refusal-log"

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

# The Python gates: setup error is class (b). The gate's own error text must come
# before the trailer in the same output (proves the flush ordering).
if command -v python3 >/dev/null 2>&1; then
  fixture_repo RCPY
  mkdir "$RCPY/tests"
  for rc_py in check-red-green check-mutation-diff; do
    cp "$SCAFFOLD_DIR/githooks/lib/$rc_py.template" "$RCT/lib/$rc_py"
    chmod +x "$RCT/lib/$rc_py"
    RC_RC=0
    ( cd "$RCPY" && env -u CLAUDE_SESSION_ID python3 "$RCT/lib/$rc_py" --ci --base no-such-ref ) >"$HOOK_OUT" 2>&1 || RC_RC=$?
    rc_expect "$rc_py setup error" "$rc_b" 2
    rc_el=$(grep -n '^::error::' "$HOOK_OUT" | head -n 1 | cut -d: -f1)
    rc_tl=$(grep -nxF "$rc_b" "$HOOK_OUT" | head -n 1 | cut -d: -f1)
    if [ -n "$rc_el" ] && [ -n "$rc_tl" ] && [ "$rc_el" -lt "$rc_tl" ]; then
      rc_ok "$rc_py: the gate's ::error:: line precedes the trailer"
    else
      rc_bad "$rc_py: ::error:: line ${rc_el:-none}, trailer line ${rc_tl:-none}"
    fi
  done
  rm -rf "$RCPY"
else
  echo "  - SKIP: python3 not installed, the Python gates' class trailer assertions did NOT run"
  SKIP=$((SKIP + 4))
fi


# The TypeScript twins (node): setup error is class (b), after the gate's ::error::.
if command -v node >/dev/null 2>&1; then
  fixture_repo RCTS
  (
    cd "$RCTS" || exit 1
    mkdir -p .githooks/lib node_modules/@stryker-mutator/core node_modules/@stryker-mutator/vitest-runner
    printf '{"name":"x","type":"module","devDependencies":{"vitest":"^3.0.0"}}\n' >package.json
    printf '{"version":"10.1.1"}\n' >node_modules/@stryker-mutator/core/package.json
    printf '{"version":"10.1.1"}\n' >node_modules/@stryker-mutator/vitest-runner/package.json
    printf 'node_modules/\n' >.gitignore
    git add -A && git -c commit.gpgsign=false commit -q -m base
  ) >/dev/null 2>&1
  cp "$SCAFFOLD_DIR/githooks/lib/refusal-log.template" "$RCTS/.githooks/lib/refusal-log"
  chmod +x "$RCTS/.githooks/lib/refusal-log"
  for rc_ts in check-red-green-ts check-mutation-diff-ts; do
    cp "$SCAFFOLD_DIR/githooks/lib/$rc_ts.template" "$RCTS/.githooks/lib/$rc_ts"
    RC_RC=0
    ( cd "$RCTS" && env -u CLAUDE_SESSION_ID node ".githooks/lib/$rc_ts" --ci --base no-such-ref ) >"$HOOK_OUT" 2>&1 || RC_RC=$?
    rc_expect "$rc_ts setup error" "$rc_b" 2
    rc_el=$(grep -n '^::error' "$HOOK_OUT" | head -n 1 | cut -d: -f1)
    rc_tl=$(grep -nxF "$rc_b" "$HOOK_OUT" | head -n 1 | cut -d: -f1)
    if [ -n "$rc_el" ] && [ -n "$rc_tl" ] && [ "$rc_el" -lt "$rc_tl" ]; then
      rc_ok "$rc_ts: the gate's ::error line precedes the trailer"
    else
      rc_bad "$rc_ts: ::error line ${rc_el:-none}, trailer line ${rc_tl:-none}"
    fi
  done
  rm -rf "$RCTS"
else
  echo "  - SKIP: node not on PATH, the TypeScript twins' class trailer assertions did NOT run"
  SKIP=$((SKIP + 4))
fi


# --- the helper itself ---------------------------------------------------------
rc_before=$(rc_count "$RCLOG")
rc_out=$(.githooks/lib/refusal-log --say a 2>"$RCT/err" ) && rc_hrc=0 || rc_hrc=$?
if [ "$rc_hrc" -eq 0 ] && [ -z "$rc_out" ] && [ "$(cat "$RCT/err")" = "$rc_a" ] \
   && [ "$(rc_count "$RCLOG")" -eq "$rc_before" ]; then
  rc_ok "refusal-log --say a: trailer on stderr only, exit 0, no log line"
else
  rc_bad "refusal-log --say a: exit $rc_hrc, stdout [$rc_out], stderr [$(cat "$RCT/err")]"
fi
.githooks/lib/refusal-log --say zzz >"$RCT/out" 2>"$RCT/err" || true
if [ ! -s "$RCT/out" ] && [ ! -s "$RCT/err" ]; then
  rc_ok "refusal-log --say zzz prints nothing"
else
  rc_bad "refusal-log --say zzz printed output"
fi
rc_nogit=$(mktemp -d)
( cd "$rc_nogit" && GIT_CEILING_DIRECTORIES=$(dirname "$rc_nogit") "$WORK/.githooks/lib/refusal-log" --say b ) >"$RCT/out" 2>"$RCT/err" || true
if [ ! -s "$RCT/out" ] && [ "$(cat "$RCT/err")" = "$rc_b" ]; then
  rc_ok "refusal-log --say b prints the trailer outside a git repository"
else
  rc_bad "refusal-log --say b outside a repo: stderr [$(cat "$RCT/err")]"
fi
( cd "$rc_nogit" && GIT_CEILING_DIRECTORIES=$(dirname "$rc_nogit") "$WORK/.githooks/lib/refusal-log" check-size size f 1 --say a ) >"$RCT/out" 2>"$RCT/err" && rc_hrc=0 || rc_hrc=$?
if [ "$rc_hrc" -eq 0 ] && [ ! -s "$RCT/out" ] && [ "$(cat "$RCT/err")" = "$rc_a" ]; then
  rc_ok "refusal-log with four positionals and --say a prints the trailer outside a git repository"
else
  rc_bad "refusal-log four positionals outside a repo: exit $rc_hrc, stderr [$(cat "$RCT/err")]"
fi
rm -rf "$rc_nogit"
rc_before=$(rc_count "$RCLOG")
.githooks/lib/refusal-log check-size size big.py 1 --say a >"$RCT/out" 2>"$RCT/err" || true
if [ "$(rc_count "$RCLOG")" -eq $((rc_before + 1)) ] && [ "$(cat "$RCT/err")" = "$rc_a" ] && [ ! -s "$RCT/out" ]; then
  rc_ok "refusal-log with positionals and --say appends one line and prints the trailer"
else
  rc_bad "refusal-log positionals plus --say: +$(($(rc_count "$RCLOG") - rc_before)) line(s), stderr [$(cat "$RCT/err")]"
fi

# --- source pins ---------------------------------------------------------------
rc_hits=$(grep -rlF 'refusal class (' "$SCAFFOLD_DIR/githooks" | sed "s|^$SCAFFOLD_DIR/githooks/||")
if [ "$rc_hits" = "lib/refusal-log.template" ]; then
  rc_ok "the trailer text lives only in lib/refusal-log.template"
else
  rc_bad "trailer text found outside the helper: $rc_hits"
fi
rc_missing=$(find "$SCAFFOLD_DIR/githooks" -type f -name '*.template' ! -name 'refusal-log.template' -exec awk '
  /^[[:space:]]*#/ { next }
  { l = $0; gsub(/-x "[^"]*refusal-log"/, "", l); gsub(/is_file\(\)/, "", l) }
  l ~ /"\$SELF_DIR\/refusal-log" / || l ~ /"\$LIB\/refusal-log" / || l ~ /"\$HOOK_DIR\/lib\/refusal-log" / || l ~ /str\(_RL\)/ || l ~ /spawnSync\("bash", \[rl/ || l ~ /\[rl,/ {
    if (l !~ /--say/) print FILENAME ":" FNR }
' {} + )
if [ -z "$rc_missing" ]; then
  rc_ok "every refusal-log invocation in the templates carries --say"
else
  rc_bad "refusal-log invoked without --say: $rc_missing"
fi
# Python gates: exit 1 is class (a), anything else (b); both flush before the helper runs.
rc_pin=ok
for rc_py in check-red-green check-mutation-diff; do
  rc_f="$SCAFFOLD_DIR/githooks/lib/$rc_py.template"
  grep -qF '{1: "a"}.get(rc, "b")' "$rc_f" || rc_pin="$rc_py lacks the exit-1 class mapping"
  [ "$(grep -F 'subprocess.run(' "$rc_f" | grep -cF 'sys.stdout.flush(); ')" -eq 2 ] || rc_pin="$rc_py: both helper calls must follow sys.stdout.flush()"
  grep -F '"timeout"' "$rc_f" | grep -qF 'sys.stdout.flush(); ' || rc_pin="$rc_py timeout line lacks the flush"
done
for rc_py in check-red-green check-mutation-diff; do
  grep -qF '"timeout", "", "2", "--say", "b"' "$SCAFFOLD_DIR/githooks/lib/$rc_py.template" || rc_pin="$rc_py timeout line lacks --say b"
done
for rc_ts in check-red-green-ts check-mutation-diff-ts; do
  grep -qF 'process.exitCode === 1 ? "a" : "b"' "$SCAFFOLD_DIR/githooks/lib/$rc_ts.template" || rc_pin="$rc_ts lacks the exit-1 class mapping"
done
if [ "$rc_pin" = ok ]; then
  rc_ok "the Python and TypeScript gates map exit 1 to (a), the rest to (b), and flush before the helper"
else
  rc_bad "class mapping pin: $rc_pin"
fi
if ! grep -rqF 'refusal class (c)' "$SCAFFOLD_DIR/githooks"; then
  rc_ok "no template prints a class (c) line (a harness denial never runs a gate)"
else
  rc_bad "a template prints refusal class (c)"
fi

rm -rf "$RCT"
