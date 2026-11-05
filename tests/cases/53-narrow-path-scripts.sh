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
  if grep -qF "$np_pat" "$SCAFFOLD_DIR/$np_f"; then np_bad="$np_bad $np_f"; fi
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

# (C) install.sh/uninstall.sh beyond --help are NOT run without dirname: the
# sourced install-lib.sh and install-manifest.sh call dirname(1) at run time
# (a separate defect, not this idiom), so those runs would fail for another reason.

# (D) scaffold-assess against a repo with one tracked file.
fixture_repo NPA
printf 'echo hi\n' >"$NPA/a.sh"
git -C "$NPA" add a.sh
np_rc=0
( cd "$NPA" && PATH="$NPNODIR" "$SCAFFOLD_DIR/scaffold-assess.sh" ) >"$HOOK_OUT" 2>&1 || np_rc=$?
if [ "$np_rc" -eq 0 ] && ! grep -qE 'No such file|not found|cannot' "$HOOK_OUT"; then
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

rm -rf "$NPI" "$NPA" "$NPMIN" "$NPNODIR"
