# shellcheck shell=bash
# cases/14-shell-install-mode.sh — `install.sh --shell` and the manifest-less
# auto-detect fallback (issue #65 part 2). Sourced into the driver's shell, so
# the globals (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) and helpers are already in scope.
# Its own file rather than appended to cases/09, which is near the 500-line cap.

echo "cases/14 — shell-only install mode (#65)"

# Files every mode installs, and files that belong ONLY to a Python/TS install.
# Shell mode must produce the first set and none of the second: a shell-only
# project has no Python/TS toolchain for those configs to configure.
SHELL_WANT=".githooks/pre-commit .githooks/lib/check-size .githooks/lib/check-patterns
.githooks/lib/check-filenames .githooks/lib/check-secrets .githooks/lib/check-hygiene
.forbidden-patterns/shell.txt .forbidden-patterns/secrets.txt AGENTS.md .scaffold.toml"
SHELL_UNWANT="ruff.toml pytest.ini .coveragerc eslint.config.js tsconfig.json
.prettierrc.json .prettierignore vitest.config.ts
.forbidden-patterns/backend.txt .forbidden-patterns/frontend.txt"

# (T) --shell installs hooks + the shell-relevant/language-agnostic patterns and
#     skips every Python/TS config template.
STMP=$(mktemp -d)
( cd "$STMP" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '#!/usr/bin/env bash' >run.sh \
  && "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >"$HOOK_OUT" 2>&1
SHELL_OK=1; SHELL_WHY=""
for f in $SHELL_WANT; do
  [ -f "$STMP/$f" ] || { SHELL_OK=0; SHELL_WHY="$SHELL_WHY missing:$f"; }
done
for f in $SHELL_UNWANT; do
  [ -f "$STMP/$f" ] && { SHELL_OK=0; SHELL_WHY="$SHELL_WHY leaked:$f"; }
done
if [ "$SHELL_OK" -eq 1 ]; then
  echo "  ✓ --shell installs hooks + shell/secrets patterns, skips Python/TS configs"; PASS=$((PASS + 1))
else
  echo "  ✗ --shell — unexpected file set:$SHELL_WHY"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$STMP"

# (T) Auto-detect fallback: no manifest but a TRACKED *.sh selects shell mode
#     without the flag — the same git-ls-files fallback the shipped
#     lint.yml.template php job uses when there's no composer.json.
#     `core.hooksPath` is pointed at a nonexistent dir rather than passing the
#     commit `--no-verify`: shell.txt forbids that flag and this harness is a
#     .sh file the scaffold scans itself. It also defends against a global
#     hooksPath leaking into the fixture repo, which the flag would not.
ATMP=$(mktemp -d)
( cd "$ATMP" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '#!/usr/bin/env bash' >deploy.sh && git add deploy.sh \
  && git -c core.hooksPath=/nonexistent -c user.email=t@t.local -c user.name=t \
       commit --quiet -m fixture \
  && "$SCAFFOLD_DIR/install.sh" --no-verify ) >"$HOOK_OUT" 2>&1
if grep -qF "Done (mode: shell)." "$HOOK_OUT" && [ -f "$ATMP/.forbidden-patterns/shell.txt" ] \
   && [ ! -f "$ATMP/ruff.toml" ] && [ ! -f "$ATMP/eslint.config.js" ]; then
  echo "  ✓ auto-detect selects shell mode for a manifest-less repo with a tracked *.sh"; PASS=$((PASS + 1))
else
  echo "  ✗ auto-detect did not select shell mode for a tracked shell-only repo"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$ATMP"

# (T) Auto-detect fallback, UNTRACKED: install.sh is routinely run on a fresh
#     project before anything is committed, where `git ls-files` returns nothing.
#     A working-tree probe backs it up, so the flagless install still works.
UTMP=$(mktemp -d)
( cd "$UTMP" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '#!/usr/bin/env bash' >deploy.sh \
  && "$SCAFFOLD_DIR/install.sh" --no-verify ) >"$HOOK_OUT" 2>&1
if grep -qF "Done (mode: shell)." "$HOOK_OUT" && [ -f "$UTMP/.forbidden-patterns/shell.txt" ]; then
  echo "  ✓ auto-detect selects shell mode with an UNCOMMITTED *.sh (fresh repo)"; PASS=$((PASS + 1))
else
  echo "  ✗ auto-detect missed an uncommitted shell script (git ls-files is empty here)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$UTMP"

# (T) PRECEDENCE: the shell fallback must fire ONLY when there is no manifest.
#     A package.json repo that also ships shell scripts is still a frontend
#     project — otherwise adding a build script would silently downgrade the
#     install and drop the eslint/tsconfig the CI frontend job needs.
PTMP=$(mktemp -d)
( cd "$PTMP" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
  && echo '#!/usr/bin/env bash' >build.sh \
  && "$SCAFFOLD_DIR/install.sh" --no-verify ) >"$HOOK_OUT" 2>&1
if grep -qF "Done (mode: frontend)." "$HOOK_OUT" && [ -f "$PTMP/eslint.config.js" ]; then
  echo "  ✓ a manifest still wins over the shell fallback (package.json + *.sh ⇒ frontend)"; PASS=$((PASS + 1))
else
  echo "  ✗ shell fallback overrode an explicit manifest"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$PTMP"

# (T) NEGATIVE: no manifest AND no shell script still errors — no silent, wrong
#     stack guess, and the message names --shell among the options.
NTMP=$(mktemp -d)
NOSTACK_RC=0
( cd "$NTMP" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo "hello" >README.md \
  && "$SCAFFOLD_DIR/install.sh" --no-verify ) >"$HOOK_OUT" 2>&1 || NOSTACK_RC=$?
if [ "$NOSTACK_RC" -ne 0 ] && grep -qF "Specify the stack explicitly" "$HOOK_OUT" \
   && grep -qF -- "--shell" "$HOOK_OUT"; then
  echo "  ✓ auto-detect still errors with no manifest and no shell scripts"; PASS=$((PASS + 1))
else
  echo "  ✗ auto-detect — expected an error naming --shell for a repo with no stack signal"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$NTMP"

reset_repo
