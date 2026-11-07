# shellcheck shell=bash
# cases/62-doctor-false-gaps.sh: scaffold-doctor must not report a check as
# "nothing calls it" when something does, and must not demand a GitHub
# workflow from a repo that is not on GitHub (#244). Each case builds the
# false-gap shape on an installed project and requires the false message gone.
#   (a) a wrapper lib file that the hook invokes and that invokes the check
#   (b) a pre-push hook that invokes the check
#   (c) an installer backup (check-x.scaffold-bak) is not a check
#   (d) a non-GitHub remote with no lint.yml is a note, not a gap
#   (e) control: no caller anywhere is still a gap (the fixes did not blind it)
# Sourced into the driver's shell: PASS/FAIL/SKIP/HOOK_OUT/SCAFFOLD_DIR in scope.

echo "cases/62: doctor false gaps (#244)"

fg_project() {
  local __fg_var=$1 __fg_dir
  fixture_repo __fg_dir
  echo '#!/usr/bin/env bash' >"$__fg_dir/run.sh"
  fixture_install "$__fg_dir" --shell --no-verify
  printf -v "$__fg_var" '%s' "$__fg_dir"
}

# The scanner loop is the call site the stock hook and lint.yml share; drop it
# from both so that only what a case adds can call check-large-files.
fg_drop_callsites() {
  grep -v 'lib/check-\*' .github/workflows/lint.yml >lint.tmp && mv lint.tmp .github/workflows/lint.yml
  grep -v -F "\"\$LIB\"/check-*" .githooks/pre-commit >pc.tmp && mv pc.tmp .githooks/pre-commit
  chmod +x .githooks/pre-commit
}
fg_wrapper() {
  fg_drop_callsites
  printf '#!/usr/bin/env bash\n.githooks/lib/check-large-files "$@"\n' >.githooks/lib/run-checks
  chmod +x .githooks/lib/run-checks
  printf '\n.githooks/lib/run-checks\n' >>.githooks/pre-commit
}
fg_prepush() {
  fg_drop_callsites
  printf '#!/usr/bin/env bash\n.githooks/lib/check-large-files "$@"\n' >.githooks/pre-push
  chmod +x .githooks/pre-push
}
fg_backup() {
  fg_drop_callsites
  cp .githooks/lib/check-size .githooks/lib/check-size.scaffold-bak
  chmod +x .githooks/lib/check-size.scaffold-bak
}
fg_gitlab() {
  git remote add origin https://gitlab.example.com/group/proj.git
  rm -f .github/workflows/lint.yml
}

# A mention is not a call: these must all stay gaps (the wrapper never runs it).
fg_wrapper_file() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" >.githooks/lib/run-checks
  chmod +x .githooks/lib/run-checks
}
fg_echo_hook() {
  fg_drop_callsites
  fg_wrapper_file '.githooks/lib/check-large-files "$@"'
  printf '\necho "see run-checks"\n' >>.githooks/pre-commit
}
fg_trail_hook() {
  fg_drop_callsites
  fg_wrapper_file '.githooks/lib/check-large-files "$@"'
  printf '\ntrue # run-checks removed\n' >>.githooks/pre-commit
}
fg_echo_wrapper() {
  fg_drop_callsites
  fg_wrapper_file 'echo "check-large-files is not run here"'
  printf '\n.githooks/lib/run-checks\n' >>.githooks/pre-commit
}
fg_hook_line() {
  fg_drop_callsites
  fg_wrapper_file '.githooks/lib/check-large-files "$@"'
  printf '\n%s\n' "$1" >>.githooks/pre-commit
}
fg_herestring() { fg_hook_line 'cat <<<"run-checks" >/dev/null'; }
fg_heredoc() { fg_hook_line 'cat <<EOF >/dev/null
run-checks
EOF'; }
fg_assign() { fg_hook_line 'W=run-checks'; }
fg_cmdsub() { fg_hook_line 'out=$(.githooks/lib/run-checks)'; }
fg_ghe() {
  git remote add origin git@github.mycorp.com:g/p.git
  rm -f .github/workflows/lint.yml
}

# fg_case <name> <present|absent> <substring> <mutation...>
fg_case() {
  local name=$1 mode=$2 expect=$3 t found=1
  shift 3
  fg_project t
  ( cd "$t" && "$@" ) >/dev/null 2>&1 || true
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || true
  grep -qF -- "$expect" "$HOOK_OUT" || found=0
  if { [ "$mode" = present ] && [ "$found" -eq 1 ]; } || { [ "$mode" = absent ] && [ "$found" -eq 0 ]; }; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name (wanted '$expect' $mode)"
    sed 's/^/      /' "$HOOK_OUT" | head -20
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$t"
}

fg_case "a check invoked through a wrapper lib file is not reported uncalled" absent \
  "lib/check-large-files is installed and executable but nothing calls it" fg_wrapper
fg_case "a check invoked from pre-push is not reported uncalled" absent \
  "lib/check-large-files is installed and executable but nothing calls it" fg_prepush
fg_case "an installer backup of a check is not reported as an uncalled check" absent \
  "check-size.scaffold-bak is installed but nothing calls it" fg_backup
fg_case "a non-GitHub remote without lint.yml is not a missing-workflow gap" absent \
  ".github/workflows/lint.yml is missing" fg_gitlab
fg_case "a non-GitHub remote without lint.yml says CI cannot be checked" present \
  "cannot check CI for this host" fg_gitlab
fg_case "control: with no caller anywhere the check is still a gap" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_drop_callsites
fg_case "a hook that only echoes the wrapper's name does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_echo_hook
fg_case "a hook that only mentions the wrapper in a trailing comment does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_trail_hook
fg_case "a wrapper that only echoes the check's name does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_echo_wrapper
fg_case "a here-string naming the wrapper does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_herestring
fg_case "a here-doc body naming the wrapper does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_heredoc
fg_case "a bare assignment naming the wrapper does not call it" present \
  "lib/check-large-files is installed and executable but nothing calls it" fg_assign
fg_case "a command substitution that runs the wrapper counts as a call" absent \
  "lib/check-large-files is installed and executable but nothing calls it" fg_cmdsub
fg_case "a GitHub Enterprise remote without lint.yml is still a gap" present \
  ".github/workflows/lint.yml is missing" fg_ghe
