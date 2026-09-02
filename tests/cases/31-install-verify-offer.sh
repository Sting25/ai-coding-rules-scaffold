# shellcheck shell=bash
# cases/31-install-verify-offer.sh: install-verify.sh's `offer` prompt and its
# auto-install branch. Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/
# SCAFFOLD_DIR and reset_repo are already in scope.
#
# Why this file exists (audit ctg-05). run_toolchain_verify sets CAN_AUTORUN=1
# only when `[ -t 0 ]` and CI is unset, and nothing in tests/ ever supplied a
# TTY: no script/expect/pty anywhere, and every wizard case passes --no-verify.
# So `offer` never prompted, never ran a package manager, and never took its
# failure branch in the whole suite. Replacing the function body with
# `offer(){ return 0; }` was undetected. The only covered path was the
# print-only one.
#
# install-verify.sh now has the same kind of seam the wizard has, under its own
# name (SCAFFOLD_VERIFY_TTY, empty by default: the wizard's SCAFFOLD_TTY
# defaults to /dev/tty and is sourced into the same shell first, so sharing that
# name would inherit a terminal here). Set explicitly, it makes all three answer
# paths reachable with a stub package manager on PATH, so nothing real is ever
# installed; unset, a piped run keeps its non-prompting, non-mutating behavior.
#
# CI is unset for each run (env -u CI): the auto-install branch is deliberately
# disabled under CI, and this suite normally runs there.

echo "cases/31: install-verify's offer prompt and auto-install branch (audit ctg-05)"

# _off_env DIR EXIT: a throwaway frontend project plus a stub `npm` on PATH that
# logs its arguments and exits EXIT. Sets OFF_DIR / OFF_BIN / OFF_LOG / OFF_ANS.
_off_env() {
  local exitcode=$1
  OFF_DIR=$(mktemp -d)
  OFF_BIN="$OFF_DIR/bin"
  OFF_LOG="$OFF_DIR/npm.log"
  OFF_ANS="$OFF_DIR/answers"
  mkdir -p "$OFF_BIN"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"\$*\" >>\"$OFF_LOG\""
    echo "exit $exitcode"
  } >"$OFF_BIN/npm"
  chmod +x "$OFF_BIN/npm"
  ( cd "$OFF_DIR" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json )
}

# _off_run: install.sh WITHOUT --no-verify (so run_toolchain_verify runs), with
# the stub first on PATH and the canned answers as the prompt source.
_off_run() {
  ( cd "$OFF_DIR" \
    && env -u CI PATH="$OFF_BIN:$PATH" SCAFFOLD_VERIFY_TTY="$OFF_ANS" \
       "$SCAFFOLD_DIR/install.sh" --frontend ) >"$HOOK_OUT" 2>&1 </dev/null
}

# (T) DECLINE: the prompt is printed, "n" is honored, and no package manager
#     runs. Asserts the prompt actually fired (the positive artifact), the skip
#     hint carries the exact command, and the stub was never invoked.
_off_env 0
printf 'n\nn\nn\nn\n' >"$OFF_ANS"
_off_run
if grep -q "? eslint not installed, install now with 'npm i -D eslint" "$HOOK_OUT" \
   && grep -q -- "- skipped, run: npm i -D eslint" "$HOOK_OUT" \
   && grep -q -- "- skipped, run: npm i -D typescript" "$HOOK_OUT" \
   && [ ! -e "$OFF_LOG" ]; then
  echo "  ✓ offer prompts and a declined answer runs nothing, printing the command instead"; PASS=$((PASS + 1))
else
  echo "  ✗ offer should prompt, honor 'n', and run no package manager"
  echo "      npm log: $(cat "$OFF_LOG" 2>/dev/null || echo '(none)')"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFF_DIR"

# (T) ACCEPT: "y" actually runs the printed command. Asserts the package manager
#     was invoked with the exact arguments offer advertised, for every tool in
#     the frontend set, and that the success line follows.
_off_env 0
printf 'y\ny\ny\ny\n' >"$OFF_ANS"
_off_run
if [ -f "$OFF_LOG" ] \
   && grep -q '^i -D eslint @eslint/js @eslint/compat typescript-eslint eslint-plugin-import-x eslint-plugin-unused-imports$' "$OFF_LOG" \
   && grep -q '^i -D typescript$' "$OFF_LOG" \
   && grep -q '^i -D prettier$' "$OFF_LOG" \
   && grep -q '^i -D vitest @vitest/coverage-v8$' "$OFF_LOG" \
   && grep -q '✓ eslint installed' "$HOOK_OUT" \
   && grep -q '✓ vitest installed' "$HOOK_OUT"; then
  echo "  ✓ an accepted offer runs the package manager with the command it advertised"; PASS=$((PASS + 1))
else
  echo "  ✗ an accepted offer should run the advertised package-manager command"
  echo "      npm log: $(cat "$OFF_LOG" 2>/dev/null || echo '(none)')"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFF_DIR"

# (T) FAILED INSTALL: the package manager exits non-zero. The run must say so
#     per tool and still finish (a failed optional install is not a failed
#     install), rather than reporting the tool as installed.
_off_env 1
printf 'y\ny\ny\ny\n' >"$OFF_ANS"
OFF_RC=0
_off_run || OFF_RC=$?
if [ "$OFF_RC" -eq 0 ] \
   && grep -q '✗ eslint install failed, run: npm i -D eslint' "$HOOK_OUT" \
   && grep -q '✗ vitest install failed, run: npm i -D vitest' "$HOOK_OUT" \
   && ! grep -q '✓ eslint installed' "$HOOK_OUT" \
   && grep -q 'Done (mode: frontend)' "$HOOK_OUT"; then
  echo "  ✓ a failing package-manager run is reported per tool and does not fail the install"; PASS=$((PASS + 1))
else
  echo "  ✗ a failing install should print the failure line per tool and still complete (exit $OFF_RC)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFF_DIR"

# (T) the seam must not change the DEFAULT: with the seam unset and stdin
#     not a terminal, the run stays print-only and non-mutating. This is the
#     guard that makes the seam safe to ship, so it asserts the stub was never
#     invoked, not merely that no prompt string appeared.
_off_env 0
( cd "$OFF_DIR" \
  && env -u CI PATH="$OFF_BIN:$PATH" "$SCAFFOLD_DIR/install.sh" --frontend ) >"$HOOK_OUT" 2>&1 </dev/null
if grep -q '! eslint not installed, run: npm i -D eslint' "$HOOK_OUT" \
   && ! grep -q 'install now with' "$HOOK_OUT" \
   && [ ! -e "$OFF_LOG" ]; then
  echo "  ✓ without the seam and without a TTY the check stays print-only and non-mutating"; PASS=$((PASS + 1))
else
  echo "  ✗ with no TTY and no seam, offer must print only and run nothing"
  echo "      npm log: $(cat "$OFF_LOG" 2>/dev/null || echo '(none)')"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFF_DIR"

# (T) --no-install still wins over the seam: an explicit "never run a package
#     manager" must not be overridden by pointing at an answer source.
_off_env 0
printf 'y\ny\ny\ny\n' >"$OFF_ANS"
( cd "$OFF_DIR" \
  && env -u CI PATH="$OFF_BIN:$PATH" SCAFFOLD_VERIFY_TTY="$OFF_ANS" \
     "$SCAFFOLD_DIR/install.sh" --frontend --no-install ) >"$HOOK_OUT" 2>&1 </dev/null
if grep -q '! eslint not installed, run: npm i -D eslint' "$HOOK_OUT" \
   && ! grep -q 'install now with' "$HOOK_OUT" \
   && [ ! -e "$OFF_LOG" ]; then
  echo "  ✓ --no-install still suppresses the prompt even with an answer source set"; PASS=$((PASS + 1))
else
  echo "  ✗ --no-install must suppress the prompt and run nothing, seam or no seam"
  echo "      npm log: $(cat "$OFF_LOG" 2>/dev/null || echo '(none)')"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$OFF_DIR"

reset_repo
