# shellcheck shell=bash
# cases/21-ci-workflow-drift.sh: cp_scaffold_preserve, install-lib.sh's
# drift-preserving policy for the shipped CI workflows. Sourced into the
# driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and helpers are already
# in scope.
#
# What #105 was: lint.yml used cp_scaffold (scaffold-owned, refreshed on a
# plain re-run) even though it is the file a project commonly hand-edits to
# add local CI steps (e.g. setup-node for a local.d check). A re-run silently
# discarded that edit; a real downstream repo measured 23 deletions, 0
# insertions from one upgrade, with no signal beyond a log line and no way
# back except the .scaffold-bak. lint.yml moved to cp_scaffold_preserve:
# drift is kept and notified, same shape as .forbidden-patterns/*.txt via
# cp_pattern; --force still replaces it, backed up first.
#
# What #110 is: the same silent-discard risk applies to tests.yml,
# coverage.yml and gitleaks.yml, not just lint.yml, and there was no
# principled reason to leave those three on the overwrite policy once
# cp_scaffold_preserve existed. tests.yml in particular is a common
# consumer-authored filename that install.sh claims by convention, so a
# pre-existing hand-written version was always at risk, not just a version
# edited after a scaffold install. All four workflows now share the exact
# same drift-preserving mechanism, so this file drives one generic
# assertion set (_wd_case) over all four rather than repeating the same
# three checks per file: the mechanism is identical, only the destination
# path, shipped template, and the install flag needed to bring the file into
# existence differ.

echo "cases/21: CI workflow drift-preserving install policy (lint.yml #105, tests/coverage/gitleaks.yml #110)"

# _wd_fixture EXTRA_FLAG: a throwaway frontend-mode repo with the scaffold
# installed. EXTRA_FLAG is the flag (if any) needed for this run to touch the
# workflow under test: coverage.yml only installs under --coverage-gate,
# gitleaks.yml only installs under --gitleaks-ci (an opt-in workflow install.sh
# only ever writes to when the flag is passed on THAT run, unlike coverage.yml
# which re-detects itself from a prior run's file), lint.yml and tests.yml
# need nothing extra. Branches on EXTRA_FLAG rather than an unquoted expansion
# so an empty flag never turns into a stray empty-string argument.
_wd_fixture() {
  local extra=$1 t
  t=$(mktemp -d)
  if [ -n "$extra" ]; then
    ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
      && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$extra" ) >/dev/null 2>&1
  else
    ( cd "$t" && git init --quiet && echo '{"name":"x"}' >package.json \
      && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >/dev/null 2>&1
  fi
  printf '%s' "$t"
}

# _wd_install DIR EXTRA_FLAG [MORE_FLAGS...]: re-run install.sh in DIR with
# the same EXTRA_FLAG (empty means none) plus whatever else the caller wants
# (e.g. --force), output captured to $HOOK_OUT. Same empty-flag branching as
# _wd_fixture, for the same reason.
_wd_install() {
  local dir=$1 extra=$2; shift 2
  if [ -n "$extra" ]; then
    ( cd "$dir" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$extra" "$@" ) >"$HOOK_OUT" 2>&1
  else
    ( cd "$dir" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$@" ) >"$HOOK_OUT" 2>&1
  fi
}

# _wd_case LABEL REL_PATH TEMPLATE EXTRA_FLAG: the three cp_scaffold_preserve
# guarantees, proven against one workflow file per call.
_wd_case() {
  local label=$1 rel=$2 tpl=$3 extra=$4
  local base T1 T2 T3
  base=$(basename "$rel")

  # (T) a drifted FILE is PRESERVED and the drift note is printed, with no
  #     .scaffold-bak: cp_scaffold_preserve only backs up under --force.
  T1=$(_wd_fixture "$extra")
  printf '\n# local CI customization: setup-node for a local.d check\n' >>"$T1/$rel"
  _wd_install "$T1" "$extra"
  if grep -qF "local CI customization" "$T1/$rel" \
     && grep -q "note (drift):.*$base" "$HOOK_OUT" \
     && ! cmp -s "$tpl" "$T1/$rel" \
     && [ ! -e "$T1/$rel.scaffold-bak" ]; then
    echo "  ✓ [$label] a drifted file is kept, with a drift note and no backup"; PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] drifted file should be kept with a drift note (#110)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$T1"

  # (T) --force on a drifted FILE backs up the user's version, then installs
  #     the shipped one: the documented escape hatch from the drift note.
  T2=$(_wd_fixture "$extra")
  printf '\n# local CI customization: setup-node for a local.d check\n' >>"$T2/$rel"
  _wd_install "$T2" "$extra" --force
  if [ -f "$T2/$rel.scaffold-bak" ] \
     && grep -qF "local CI customization" "$T2/$rel.scaffold-bak" \
     && cmp -s "$tpl" "$T2/$rel"; then
    echo "  ✓ [$label] --force backs up a drifted file then installs the shipped one"; PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] --force should back up then replace a drifted file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$T2"

  # (T) a PRISTINE (unchanged) FILE is a silent no-op on re-run: matches the
  #     shipped version, so no drift note or refresh line fires for it, and
  #     the file is untouched. Checked by MESSAGE KIND rather than "the
  #     filename appears nowhere in the output", since coverage.yml and
  #     gitleaks.yml both print an unconditional explanatory "note:" line on
  #     every run regardless of drift state.
  T3=$(_wd_fixture "$extra")
  _wd_install "$T3" "$extra"
  if cmp -s "$tpl" "$T3/$rel" \
     && ! grep -q "note (drift):.*$base" "$HOOK_OUT" \
     && ! grep -q "updated:.*$base" "$HOOK_OUT" \
     && [ ! -e "$T3/$rel.scaffold-bak" ]; then
    echo "  ✓ [$label] a pristine file is a clean no-op on re-run"; PASS=$((PASS + 1))
  else
    echo "  ✗ [$label] re-run should leave a pristine file alone with no drift/refresh line"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$T3"
}

_wd_case "lint.yml"     ".github/workflows/lint.yml"     "$SCAFFOLD_DIR/.github/workflows/lint.yml.template"     ""
_wd_case "tests.yml"    ".github/workflows/tests.yml"    "$SCAFFOLD_DIR/.github/workflows/tests.yml.template"    ""
_wd_case "coverage.yml" ".github/workflows/coverage.yml" "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template" "--coverage-gate"
_wd_case "gitleaks.yml" ".github/workflows/gitleaks.yml" "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template" "--gitleaks-ci"

reset_repo
