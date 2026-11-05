# shellcheck shell=bash
# cases/53-narrow-path-scripts.sh — the shipped scripts resolve their own
# directory without dirname(1). Sourced into the driver's shell, so PASS/FAIL/
# HOOK_OUT/SCAFFOLD_DIR and the fixture_* helpers are in scope.
#
# Why: bash 5.3 (ubuntu-26.04) made `cd ""` fatal. `$(cd "$(dirname "$0")" &&
# pwd)` is exactly that when dirname is not on PATH, and dies under set -e
# before the script does anything. scaffold-doctor.sh carried the fix (case 42);
# this case covers the other eight scripts. Older bash treats `cd ""` as a
# no-op, so the live checks below only go red on bash >= 5.3 or, for the
# install/uninstall/assess runs, when the wrongly-resolved directory (the
# caller's cwd) holds no bundle. The static check is what catches the idiom
# itself on every bash.

echo "cases/53 — scripts resolve their own directory without dirname(1)"

np_fail() { # np_fail MESSAGE  (shows $HOOK_OUT)
  echo "  ✗ $1"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
}
np_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }

# np_bin NAME [only]: a bin dir of symlinks. With "only", just the tools the
# shipped checks need (the case-42 set). Without, every executable on PATH
# EXCEPT dirname, for scripts that legitimately need cp/mkdir/mktemp.
np_bin() {
  local d tool src p f
  d=$(mktemp -d)
  if [ "${1:-}" = only ]; then
    for tool in bash git grep sed awk basename; do
      src=$(command -v "$tool" 2>/dev/null) || continue
      ln -s "$src" "$d/$tool"
    done
  else
    local IFS=:
    for p in $PATH; do
      [ -d "$p" ] || continue
      for f in "$p"/*; do
        tool=${f##*/}
        [ "$tool" = dirname ] && continue
        [ -x "$f" ] && [ ! -d "$f" ] && [ ! -e "$d/$tool" ] && ln -s "$f" "$d/$tool"
      done
    done
  fi
  printf '%s' "$d"
}

NPMIN=$(np_bin only)
NPNODIR=$(np_bin)
if [ -e "$NPNODIR/dirname" ] || [ -e "$NPMIN/dirname" ]; then
  np_fail "fixture error: dirname leaked onto the narrowed PATH"
fi

# (A) Static: no fixed script still builds its own directory from dirname.
np_bad=""
np_pat="cd \"\$(dirname"
for np_f in install.sh uninstall.sh scaffold-assess.sh githooks/pre-commit.template \
  githooks/lib/check-hygiene.template githooks/lib/check-patterns.template \
  githooks/lib/check-size.template githooks/lib/check-large-files.template; do
  # shellcheck disable=SC2016  # literal patterns, not expansions
  if grep -qF -e "$np_pat" -e 'dirname "$0"' -e 'dirname "${BASH_SOURCE' "$SCAFFOLD_DIR/$np_f"; then
    np_bad="$np_bad $np_f"
  fi
done
if [ -z "$np_bad" ]; then
  np_ok "no shipped script resolves its own directory via cd \"\$(dirname ...)\""
else
  echo "$np_bad" >"$HOOK_OUT"
  np_fail "still on the dirname idiom (fatal as cd \"\" on bash 5.3):"
fi

# (B) --help works with only the check tools on PATH (SCAFFOLD_DIR is resolved
# before the argument loop, so a death there never reaches --help's output).
for np_s in install.sh uninstall.sh; do
  np_rc=0
  ( cd "$WORK" && PATH="$NPMIN" "$SCAFFOLD_DIR/$np_s" --help ) >"$HOOK_OUT" 2>&1 || np_rc=$?
  if [ "$np_rc" -eq 0 ] && [ -s "$HOOK_OUT" ]; then
    np_ok "$np_s --help runs with no dirname on PATH"
  else
    np_fail "$np_s --help died without dirname (exit $np_rc)"
  fi
done

# (C) install.sh beyond --help runs for real in (G) below. The two sources of
# run-time dirname calls it once had (install-lib.sh _cp_replace, which turned
# _mkdir_safe "$(dirname ...)" into _mkdir_safe "" and skipped the symlink-parent
# guard, and install-manifest.sh manifest_flush) now use parameter expansion.

# (G) install.sh for real, on the no-dirname PATH, into a fresh git repo, versus
# the same install on the full PATH. Excluded from the diff: .git (hook samples,
# index and config differ by timestamps and object ids). Nothing else.
fixture_repo NPG1
fixture_repo NPG2
printf '#!/usr/bin/env bash\n' >"$NPG1/run.sh"
printf '#!/usr/bin/env bash\n' >"$NPG2/run.sh"
np_rc=0
( cd "$NPG1" && "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >"$HOOK_OUT.full" 2>&1 || true
( cd "$NPG2" && PATH="$NPNODIR" "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >"$HOOK_OUT" 2>&1 || np_rc=$?
if [ "$np_rc" -eq 0 ] && ! grep -q 'command not found' "$HOOK_OUT" \
   && diff -r --exclude=.git "$NPG1" "$NPG2" >/dev/null; then
  np_ok "install.sh runs for real with no dirname on PATH, tree matches full-PATH install"
else
  { diff -r --exclude=.git "$NPG1" "$NPG2" || true; } >>"$HOOK_OUT" 2>&1
  np_fail "install.sh without dirname failed or diverged (exit $np_rc)"
fi
rm -rf "$NPG1" "$NPG2" "$HOOK_OUT.full"

# (D) scaffold-assess against a repo with one tracked file.
fixture_repo NPA
printf 'echo hi\n' >"$NPA/a.sh"
git -C "$NPA" add a.sh
np_rc=0
( cd "$NPA" && PATH="$NPNODIR" "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || np_rc=$?
if [ "$np_rc" -eq 0 ] && ! grep -qE 'line [0-9]*: .*: (No such file|command not found)' "$HOOK_OUT"; then
  np_ok "scaffold-assess.sh runs with no dirname on PATH"
else
  np_fail "scaffold-assess.sh failed without dirname (exit $np_rc)"
fi

doc_project NPI
# (E) The installed pre-commit hook on a narrowed PATH, then each check on its
# own, invoked by absolute path from the repo root with an empty file list.
# Exit 0 and no shell error text means SELF_DIR/HOOK_DIR resolved.
git -C "$NPI" config user.email t@t.local
git -C "$NPI" config user.name t
printf 'echo hi\n' >"$NPI/ok.sh"
git -C "$NPI" add ok.sh
np_rc=0
( cd "$NPI" && PATH="$NPNODIR" bash .githooks/pre-commit ) >"$HOOK_OUT" 2>&1 || np_rc=$?
if [ "$np_rc" -eq 0 ] && ! grep -qE 'No such file|command not found|cd:' "$HOOK_OUT"; then
  np_ok "pre-commit runs with no dirname on PATH"
else
  np_fail "pre-commit failed without dirname (exit $np_rc)"
fi
# (F) uninstall.sh for real: a dry run against the installed project must print
# the same thing on the narrowed PATH as on the full one. On a pre-5.3 bash the
# old idiom does not die, it resolves SCAFFOLD_DIR to the caller's cwd, so the
# sourced uninstall-drop-lang.sh is missing and the two outputs diverge.
np_full=$(mktemp)
( cd "$NPI" && "$SCAFFOLD_DIR/uninstall.sh" --dry-run ) >"$np_full" 2>&1 || true
np_rc=0
( cd "$NPI" && PATH="$NPNODIR" "$SCAFFOLD_DIR/uninstall.sh" --dry-run ) >"$HOOK_OUT" 2>&1 || np_rc=$?
if [ "$np_rc" -eq 0 ] && [ -s "$HOOK_OUT" ] && diff "$HOOK_OUT" "$np_full" >/dev/null; then
  np_ok "uninstall.sh --dry-run output matches with and without dirname on PATH"
else
  echo "  ✗ uninstall.sh --dry-run diverges without dirname (exit $np_rc)"
  { diff "$HOOK_OUT" "$np_full" || true; } | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi
rm -f "$np_full"
for np_c in check-hygiene check-patterns check-size check-large-files; do
  cp "$SCAFFOLD_DIR/githooks/lib/$np_c.template" "$NPI/.githooks/lib/$np_c"
  chmod +x "$NPI/.githooks/lib/$np_c"
  printf 'ok.sh\0' >"$NPI/np.z"
  np_rc=0
  ( cd "$NPI" && PATH="$NPNODIR" "$NPI/.githooks/lib/$np_c" <np.z ) >"$HOOK_OUT" 2>&1 || np_rc=$?
  if [ "$np_rc" -eq 0 ] && ! grep -qE 'No such file|command not found|cd:' "$HOOK_OUT"; then
    np_ok "$np_c runs with no dirname on PATH"
  else
    np_fail "$np_c failed without dirname (exit $np_rc)"
  fi
done

# (H) The hook's ruff decision on the no-dirname PATH. check-patterns asks
# `scaffold-config linter-runs`, which finds py-tool beside itself; its stderr
# is discarded by the caller, so a missing dirname shows only as a different
# DECISION. Compared against a run on the same PATH plus dirname.
#   H1: ruff NOT installed. The os.path.join regex must stay on (refused), and
#       the output must equal the full run, with no dirname error text.
#   H2: a stub ruff on PATH. ruff "runs", so the regex defers to it (allowed).
#       Without dirname the probe used to fail open to "no", wrongly refusing.
np_nr() { # np_nr [withdir]: NPNODIR minus ruff/python/uv, optionally plus dirname
  local d f tool
  d=$(mktemp -d)
  for f in "$NPNODIR"/*; do
    tool=${f##*/}
    case $tool in ruff|python|python3*|uv|pipx) continue ;; esac
    ln -s "$(readlink "$f")" "$d/$tool"
  done
  if [ "${1:-}" = withdir ]; then ln -s "$(command -v dirname)" "$d/dirname"; fi
  printf '%s' "$d"
}
NPRFULL=$(np_nr withdir)
NPRNODIR=$(np_nr)
NPRSTUB=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' >"$NPRSTUB/ruff"
chmod +x "$NPRSTUB/ruff"
fixture_repo NPH
fixture_install "$NPH" --python --no-verify
printf '[lint]\nselect = ["PTH"]\n' >"$NPH/ruff.toml"
printf 'import os\np = os.path.join("a", "b")\n' >"$NPH/a.py"
git -C "$NPH" add ruff.toml a.py
np_h() { # np_h OUTFILE PATH: run the hook, keep combined output and exit code
  local rc=0
  ( cd "$NPH" && PATH="$2" bash .githooks/pre-commit ) >"$1" 2>&1 || rc=$?
  echo "exit=$rc" >>"$1"
}
np_h "$HOOK_OUT.full" "$NPRFULL"
np_h "$HOOK_OUT" "$NPRNODIR"
if ! grep -q 'dirname: command not found' "$HOOK_OUT" \
   && grep -q 'os.path.join' "$HOOK_OUT.full" \
   && diff "$HOOK_OUT" "$HOOK_OUT.full" >/dev/null; then
  np_ok "pre-commit, ruff not installed: same decision with and without dirname"
else
  { echo "--- full PATH:"; cat "$HOOK_OUT.full"; echo "--- no dirname:"; cat "$HOOK_OUT"; } >"$HOOK_OUT.cmp"
  mv "$HOOK_OUT.cmp" "$HOOK_OUT"
  np_fail "ruff-not-installed decision differs without dirname"
fi
np_h "$HOOK_OUT.full" "$NPRSTUB:$NPRFULL"
np_h "$HOOK_OUT" "$NPRSTUB:$NPRNODIR"
if ! grep -q 'dirname: command not found' "$HOOK_OUT" \
   && ! grep -q 'os.path.join' "$HOOK_OUT.full" \
   && diff "$HOOK_OUT" "$HOOK_OUT.full" >/dev/null; then
  np_ok "pre-commit, ruff present: same decision with and without dirname"
else
  { echo "--- full PATH:"; cat "$HOOK_OUT.full"; echo "--- no dirname:"; cat "$HOOK_OUT"; } >"$HOOK_OUT.cmp"
  mv "$HOOK_OUT.cmp" "$HOOK_OUT"
  np_fail "ruff-present decision differs without dirname"
fi
rm -rf "$NPH" "$NPRFULL" "$NPRNODIR" "$NPRSTUB" "$HOOK_OUT.full"

rm -rf "$NPI" "$NPA" "$NPMIN" "$NPNODIR"
