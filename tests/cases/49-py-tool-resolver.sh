# shellcheck shell=bash
# cases/49-py-tool-resolver.sh: the shared Python tool resolver, lib/py-tool
# (#192, #194). Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/
# SCAFFOLD_DIR and the fixture_* helpers are in scope. Helpers are prefixed pt_.
#
# The hook, scaffold-assess.sh and install-verify.sh each did a PATH-only tool
# lookup. A tool living only in the project's .venv was "absent" to some of them
# (assess measured the system ruff, verify offered `pip install`), and a linked
# git worktree, which never has the gitignored .venv, skipped the lint pass.
# Every tool here is a stub that names itself, so no real ruff is needed and the
# winner of each lookup is visible in the output.

echo "cases/49: shared py-tool resolver: venv beats PATH, linked worktree borrows, assess and verify use it (#192, #194)"

# pt_stub FILE NAME VERSION LABEL: an executable that prints "NAME VERSION" for
# --version and "LABEL RAN" for anything else, then exits 1, so a run that
# reaches it is rejected with the label in the output.
pt_stub() {
  mkdir -p "$(dirname "$1")"
  # shellcheck disable=SC2016  # $1 is for the stub's own shell, not this one
  printf '#!/bin/sh\ncase "$1" in --version) echo "%s %s"; exit 0 ;; esac\necho "%s RAN"\nexit 1\n' "$2" "$3" "$4" >"$1"
  chmod +x "$1"
}

PT=$(mktemp -d)

# --- (A) hook: a tool in ./.venv wins over the same tool on PATH ---------------
fixture_repo PT_A
fixture_install "$PT_A" --python --no-verify
printf '.venv/\n' >>"$PT_A/.gitignore"
printf 'ok = True\n' >"$PT_A/a.py"
pt_stub "$PT_A/.venv/bin/ruff" ruff 1.0.0 "VENV RUFF"
pt_stub "$PT/pathbin/ruff" ruff 2.0.0 "PATH RUFF"
( cd "$PT_A" && git add a.py && PATH="$PT/pathbin:$PATH" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "VENV RUFF RAN" "$HOOK_OUT" && ! grep -qF "PATH RUFF" "$HOOK_OUT"; then
  echo "  ✓ ruff in ./.venv is used even though another ruff is first on PATH"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the ./.venv ruff to win over PATH"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# --- (A2) Windows layout: <venv>/Scripts/<tool>.exe is probed too -------------
rm -rf "$PT_A/.venv"
pt_stub "$PT_A/.venv/Scripts/ruff.exe" ruff 1.0.0 "SCRIPTS RUFF"
( cd "$PT_A" && PATH="$PT/pathbin:$PATH" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "SCRIPTS RUFF RAN" "$HOOK_OUT"; then
  echo "  ✓ a venv laid out as Scripts/ruff.exe (Windows Git Bash) is found"; PASS=$((PASS + 1))
else
  echo "  ✗ expected .venv/Scripts/ruff.exe to be found"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$PT_A/.venv"

# --- (B) hook: a linked worktree borrows the main worktree's .venv -------------
git -C "$PT_A" add -A
git -C "$PT_A" commit -q --no-verify -m "scaffold"  # scaffold-allow: test fixture
pt_stub "$PT_A/.venv/bin/ruff" ruff 1.0.0 "MAIN RUFF"
PT_WT="$PT/linked-wt"
git -C "$PT_A" worktree add -q "$PT_WT" -b pt-linked
printf 'ok = True\n' >"$PT_WT/b.py"
( cd "$PT_WT" && git add b.py && PATH="$PT/pathbin:$PATH" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || true
if [ ! -e "$PT_WT/.venv" ] && grep -qF "MAIN RUFF RAN" "$HOOK_OUT" \
   && [ "$(grep -c 'BORROWED FROM MAIN WORKTREE' "$HOOK_OUT")" -eq 1 ] && ! grep -qF "PATH RUFF" "$HOOK_OUT"; then
  echo "  ✓ a linked worktree with no .venv runs the main worktree's ruff and prints one BORROWED note"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the main worktree's ruff, one BORROWED note, and not the PATH ruff"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# The main checkout itself is not "borrowing" from itself.
printf 'ok = 2\n' >"$PT_A/a.py"
( cd "$PT_A" && git add a.py && PATH="$PT/pathbin:$PATH" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "MAIN RUFF RAN" "$HOOK_OUT" && ! grep -qF "BORROWED" "$HOOK_OUT"; then
  echo "  ✓ the main worktree uses its own .venv with no BORROWED note"; PASS=$((PASS + 1))
else
  echo "  ✗ the main worktree printed a BORROWED note"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# The worktree's own .venv, once it has one, wins over the main one.
pt_stub "$PT_WT/.venv/bin/ruff" ruff 1.0.0 "OWN RUFF"
( cd "$PT_WT" && PATH="$PT/pathbin:$PATH" .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "OWN RUFF RAN" "$HOOK_OUT" && ! grep -qF "BORROWED" "$HOOK_OUT"; then
  echo "  ✓ a linked worktree's own .venv beats the borrowed one"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the worktree's own .venv to win"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# --- (C) scaffold-assess.sh prints the binary and version it measured ----------
fixture_repo PT_C
printf 'import os\n' >"$PT_C/m.py"
git -C "$PT_C" add m.py
git -C "$PT_C" commit -q --no-verify -m init  # scaffold-allow: test fixture
pt_stub "$PT_C/.venv/bin/ruff" ruff 9.9.9 "ASSESS VENV RUFF"
pt_stub "$PT/assessbin/ruff" ruff 1.1.1 "ASSESS PATH RUFF"
( cd "$PT_C" && PATH="$PT/assessbin:$PATH" bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "ruff measured with .venv/bin/ruff (ruff 9.9.9)" "$HOOK_OUT"; then
  echo "  ✓ assess measures with the project's .venv ruff and prints its path and version"; PASS=$((PASS + 1))
else
  echo "  ✗ expected 'ruff measured with .venv/bin/ruff (ruff 9.9.9)'"; grep -n "ruff" "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi
rm -rf "$PT_C/.venv"
( cd "$PT_C" && PATH="$PT/assessbin:$PATH" bash "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || true
if grep -qF "ruff measured with $PT/assessbin/ruff (ruff 1.1.1)" "$HOOK_OUT"; then
  echo "  ✓ assess names the PATH binary and version when there is no venv"; PASS=$((PASS + 1))
else
  echo "  ✗ expected the PATH ruff to be named"; grep -n "ruff" "$HOOK_OUT" | sed 's/^/      /'; FAIL=$((FAIL + 1))
fi

# --- (D) install-verify.sh does not offer pip install for a tool in .venv -------
# PATH holds only the utilities the module needs, so ruff and pytest are absent
# from PATH by construction; whatever the host has installed cannot leak in.
PT_SAFE="$PT/safe"
mkdir -p "$PT_SAFE"
for pt_t in env bash sh git grep sed awk tr head dirname cat uname; do
  pt_p=$(command -v "$pt_t" 2>/dev/null || true)
  [ -n "$pt_p" ] && ln -s "$pt_p" "$PT_SAFE/$pt_t"
done
fixture_repo PT_D
printf '[project]\nname = "x"\n' >"$PT_D/pyproject.toml"
pt_verify() {
  ( cd "$PT_D" && MODE=python VERIFY=1 NO_INSTALL=1 SCAFFOLD_DIR="$SCAFFOLD_DIR" PATH="$PT_SAFE" \
      bash -c '. "$SCAFFOLD_DIR/install-verify.sh"; run_toolchain_verify' ) >"$HOOK_OUT" 2>&1 || true
}
pt_verify
if grep -qF "! ruff not installed, run: pip install ruff" "$HOOK_OUT" \
   && grep -qF "! pytest + coverage not installed, run: pip install pytest pytest-cov" "$HOOK_OUT"; then
  echo "  ✓ control: with no ruff or pytest anywhere, install-verify still offers pip install"; PASS=$((PASS + 1))
else
  echo "  ✗ control run did not offer the install"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
pt_stub "$PT_D/.venv/bin/ruff" ruff 3.3.3 "VERIFY RUFF"
pt_stub "$PT_D/.venv/bin/pytest" pytest 4.4.4 "VERIFY PYTEST"
pt_verify
if grep -qF "✓ ruff installed" "$HOOK_OUT" && grep -qF "✓ pytest + coverage installed" "$HOOK_OUT" \
   && ! grep -qF "pip install" "$HOOK_OUT"; then
  echo "  ✓ ruff and pytest present only in .venv are reported installed, no pip install offered"; PASS=$((PASS + 1))
else
  echo "  ✗ expected both tools reported installed from .venv and no pip install line"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

rm -rf "$PT"
git -C "$PT_A" worktree prune
rm -rf "$PT_A" "$PT_C" "$PT_D"
unset PT PT_A PT_C PT_D PT_WT PT_SAFE pt_t pt_p
unset -f pt_stub pt_verify
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver
cd "$WORK"
reset_repo
