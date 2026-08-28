# shellcheck shell=bash
# install-lib.sh — file-write policy helpers for install.sh.
#
# SOURCED (not executed) by install.sh, so these functions run in that script's
# shell under its `set -euo pipefail` and read its globals (FORCE). Extracted here
# so install.sh stays under the scaffold's own 500-line module-size cap — the
# guardrail the scaffold enforces on every project it installs into, itself
# included. Behavior is identical to when these lived inline in install.sh.

# Default the caller-provided global so this file also lints/behaves standalone.
# install.sh always sets FORCE before sourcing, so this is a no-op there; if the
# lib is ever sourced without it, 0 (= not --force) is the safe default.
: "${FORCE:=0}"

# --- file ownership & the install/upgrade model -----------------------------
# Re-running install.sh is the supported UPGRADE path, so each destination is
# copied through the policy its OWNERSHIP demands:
#
#   cp_scaffold  scaffold-owned CODE: scanners, libs, hooks. These carry
#                security fixes, so a plain re-run REFRESHES them whenever they
#                differ from the shipped version (no --force needed); that's
#                how an upgrader who just re-runs install.sh actually receives
#                the fixes. Every overwrite is backed up first (#72), a project
#                may have edited one, and that edit must never vanish silently.
#                No CI workflow file uses this policy any more (as of #110,
#                every shipped workflow goes through cp_scaffold_preserve
#                below instead: a project commonly hand-edits or pre-authors
#                these, and a plain refresh risks silently discarding that).
#   cp_safe      USER-OWNED files — ruff.toml, eslint config, .scaffold.toml,
#                dependabot.yml, the rules docs, etc. A project customizes these,
#                so they're never auto-replaced: skip unless --force (which backs
#                up first). CLAUDE.md / AGENTS.md have their own merge handlers.
#   cp_pattern   .forbidden-patterns/*.txt — the hard case: scaffold-SHIPPED yet
#                user-EXTENDED (teams append their own rows). Auto-overwriting
#                would clobber those rows, so a re-run only NOTIFIES on drift and
#                keeps the user's file; --force backs up + replaces so the user's
#                additions survive in .scaffold-bak for manual merge-back.
#   cp_scaffold_preserve  scaffold-owned CI workflows that a project is expected
#                to hand-edit or that commonly arrive pre-authored: today,
#                .github/workflows/lint.yml, tests.yml, coverage.yml and
#                gitleaks.yml. Same drift-preserving behavior as cp_pattern:
#                a re-run only NOTIFIES on drift and keeps the user's edits;
#                --force backs up + replaces. Added for lint.yml in #105: a
#                plain cp_scaffold refresh there silently discarded a
#                consumer's CI customization (measured on a real downstream
#                repo: 23 deletions, 0 insertions) with no signal beyond a log
#                line and no way back except the .scaffold-bak. #110 extended
#                the same policy to tests.yml, coverage.yml and gitleaks.yml:
#                the same silent-discard risk applies to any hand-edited or
#                pre-existing workflow file, not just lint.yml, and there was
#                no principled reason to keep those three on the overwrite
#                policy once the mechanism existed.
#
# The four policies share one write MECHANISM (_cp_replace) and one backup
# routine (_backup), so the A7 symlink defenses live in exactly one place.

# _mkdir_safe DIR — create DIR as real directories, never following a symlink at
# ANY path component. `rm -f "$dst"` in _cp_replace drops a symlink at the LEAF
# file, but a plain `mkdir -p` follows a symlinked PARENT (e.g. a planted
# `.githooks -> ~/.ssh` or `.github -> $HOME`), which would send every scanner /
# hook / CI workflow — and any overwrite — THROUGH the link, outside the repo,
# while the in-tree path stays a symlink (a silent write-through + fail-open).
# Walk the path top-down, dropping any symlink component before descending, so we
# always land real dirs in the tree. Mirrors scripts/dev-setup.sh's _mkdir_safe
# (B4) but handles arbitrary depth for the shared _cp_replace mechanism.
_mkdir_safe() {
  local dir=$1 path='' comp
  while [ -n "$dir" ]; do
    comp=${dir%%/*}
    case $dir in */*) dir=${dir#*/} ;; *) dir= ;; esac
    [ -z "$comp" ] && continue
    path="${path:+$path/}$comp"
    [ -L "$path" ] && rm -f "$path"
    [ -d "$path" ] || mkdir "$path"
  done
}

# _cp_replace SRC DST — the actual write. `[ -e ]` alone is false for a DANGLING
# symlink and follows a LIVE one, so a pre-existing symlink at a scaffold path
# used to make `cp` follow it and write the scanner to the link's target OUTSIDE
# the repo. We drop any symlink at every parent component (_mkdir_safe) AND at the
# leaf (`rm -f`) first, so we always write a real regular file IN the tree, never
# THROUGH a link.
_cp_replace() {
  local src=$1 dst=$2
  _mkdir_safe "$(dirname "$dst")"
  rm -f "$dst"
  cp "$src" "$dst"
}

# _backup DST — copy an existing file/symlink aside to <dst>.scaffold-bak[.N]
# before it is replaced, so no local edit is ever silently destroyed. `-P` backs
# up a symlink AS the link, never the dereferenced target content. Returns non-zero
# when all >99 slots are taken; callers treat that as "skip this one file, keep
# going" (`|| return 0`) — never abort, and never overwrite without a backup.
_backup() {
  local dst=$1
  local bak="${dst}.scaffold-bak" n=0
  while [ -e "$bak" ] || [ -L "$bak" ]; do
    n=$((n + 1))
    if [ "$n" -gt 99 ]; then
      echo "error: too many .scaffold-bak files for $dst — clean some up." >&2
      echo "       Skipping this one file (left untouched); re-run after cleanup." >&2
      return 1
    fi
    bak="${dst}.scaffold-bak.${n}"
  done
  cp -P "$dst" "$bak"
  echo "backed up:    $dst -> $bak"
}

# cp_safe SRC DST — USER-OWNED file. Install if absent; otherwise leave it alone
# unless --force (which backs up the differing file, then replaces it).
cp_safe() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst — left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        echo "skip (exists): $dst  — left untouched (use --force to replace)"
      fi
      return
    fi
    # --force: back up before overwriting, but only when it actually differs. A
    # symlink is never compared through (`-L` short-circuits) and always replaced.
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# cp_scaffold SRC DST — SCAFFOLD-OWNED code. Refreshes on diff so security fixes
# reach upgraders on a plain re-run. Identical → silent no-op. A symlink planted
# at a scaffold-owned path is always replaced with the real scanner (better than
# leaving a dead link there) and never written through.
#
# ALWAYS backs up before overwriting — not just under --force (issue #72). The
# old policy skipped the routine-refresh backup on the premise that "the prior
# bytes are scaffold code, recoverable from git history and the scaffold repo."
# That premise is TRUE for an untouched destination and FALSE for an edited one,
# and nothing tested which it was. .githooks/pre-commit is the file a project
# MUST edit to wire in a local check (.github/workflows/lint.yml used to be the
# other one, until #105 moved it to cp_scaffold_preserve below: a project
# customizing its CI turned out to be at least as common as one customizing the
# hook, and losing it needed more than a backup, it needed not being
# overwritten at all), so the false case was the likely one, and its symptom
# was silent: the local check script stayed on disk, its call site was reset,
# nothing errored, and the guardrail became decoration. Backing up unconditionally
# makes the loss recoverable AND prints a "backed up:" line, which is the
# signal that was missing. Cost is a .scaffold-bak beside each file that
# actually changed in the upgrade; `.githooks/local.d/` now exists so local
# checks need not live in a scaffold-owned file at all.
#
# If _backup fails (>99 slots), we skip this ONE file rather than overwrite it
# unbacked — same policy as cp_safe/cp_pattern (B12). That defers a scanner
# refresh, so _backup prints why and tells the user to clean up and re-run.
cp_scaffold() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # Already current? Never compare THROUGH a symlink (A7).
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    _backup "$dst" || return 0
    _cp_replace "$src" "$dst"
    echo "updated:      $dst (refreshed to the shipped version)"
    return
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# cp_pattern SRC DST — .forbidden-patterns/*.txt. Install if absent; if it drifts
# from the shipped version, NOTIFY (the user may have added rows; new shipped
# rules may be worth merging) but keep the user's file. --force backs up + writes
# the shipped version, so the user's additions survive in .scaffold-bak.
cp_pattern() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst — left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        echo "note (drift):  $dst differs from the shipped patterns — your customizations are kept. Diff against forbidden-patterns/$(basename "$dst").template for new rules to merge, or re-run with --force to replace (backs yours up to .scaffold-bak)."
      fi
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# cp_scaffold_preserve SRC DST: a scaffold-owned CI workflow (today:
# lint.yml, tests.yml, coverage.yml, gitleaks.yml, see the policy comment
# above). Install if absent; on drift NOTIFY and keep the user's file rather
# than overwriting it, same shape as cp_pattern, because a plain cp_scaffold
# refresh here silently discards a consumer's hand-edit or pre-existing
# version of the file (#105 for lint.yml, extended to the other three CI
# workflows in #110) instead of merely risking it. --force still backs up +
# replaces, matching cp_scaffold/cp_pattern's --force semantics.
cp_scaffold_preserve() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst, left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        echo "note (drift):  $dst differs from the shipped version: your customizations are kept. Diff against $src for upstream changes to merge, or re-run with --force to replace (backs yours up to .scaffold-bak)."
      fi
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst"
  echo "installed:    $dst"
}

# chmod +x only a real regular file. A scaffold path that cp_safe deliberately
# SKIPPED because it's a (possibly dangling) symlink must not abort the install
# via a chmod that follows a broken link and fails under set -e — nor should we
# flip the mode of a skipped, user-owned file.
mkx() { if [ -f "$1" ]; then chmod +x "$1"; fi; }

# install_test_workflow_ci, the test-execution CI workflow (#97): DEFAULT-ON,
# exactly one of two shapes, plus a recorded opt-out. Extracted here (like
# install-verify.sh's run_toolchain_verify) once install.sh neared its own
# 500-line cap; reads the caller's globals (NO_TEST_WORKFLOW, COVERAGE_GATE,
# SCAFFOLD_DIR) and sets TEST_CI_STATE for the caller's end-of-run summary.
#
# A default install used to produce lint-only CI (green checks with zero
# tests ever executing), which is the bug this closes. Three end states,
# decided in this order:
#
#   1. --no-test-workflow -> install NEITHER workflow. The one way a repo ends
#      up with no test execution in CI, and it must say so loudly, per
#      operational-rules.md's "record every skip" (unless a workflow from a
#      prior run is already on disk, CI keeps running it either way).
#   2. --coverage-gate (or coverage.yml already on disk from a prior run) ->
#      install coverage.yml, which already runs the tests AND gates patch
#      coverage. It gates EXECUTION of changed lines, not assertion quality;
#      see RECOMMENDATIONS.md.
#   3. default -> install tests.yml: pytest/vitest run on every PR/push, no
#      coverage threshold.
#
# Never both: coverage.yml already runs the tests, so installing tests.yml
# alongside it would run the suite twice for the same push/PR. If an upgrade
# adds --coverage-gate on top of a prior default install, the now-redundant
# tests.yml (if untouched since install) is retired rather than left to
# double-run.
#
# Both files are written through cp_scaffold_preserve, not cp_scaffold
# (#110): a re-run that finds either file changed from the shipped version
# keeps the drifted file and prints a "note (drift):" line instead of
# refreshing it, same policy as lint.yml since #105.
install_test_workflow_ci() {
  if [ "$NO_TEST_WORKFLOW" -eq 1 ]; then
    if [ "$COVERAGE_GATE" -eq 1 ]; then
      echo "warning: --no-test-workflow overrides --coverage-gate: neither tests.yml nor coverage.yml will be installed."
    fi
    if [ -f ".github/workflows/tests.yml" ] || [ -f ".github/workflows/coverage.yml" ]; then
      echo "note: an existing tests.yml/coverage.yml was left in place. --no-test-workflow only skips a NEW install, it does not remove one."
      echo "note: this repo's CI still runs tests via that existing workflow; --no-test-workflow only affects what THIS run installs."
    else
      echo "SKIPPED: test-execution CI workflow (--no-test-workflow). This repo's CI will NOT run tests."
      echo "         Recorded skip (operational-rules.md, 'no silent failures'): add tests.yml or coverage.yml"
      echo "         by hand, or re-run without --no-test-workflow, before trusting this repo's CI as a real gate."
    fi
  elif [ "$COVERAGE_GATE" -eq 1 ] || { [ -f ".github/workflows/coverage.yml" ] && [ ! -f ".github/workflows/tests.yml" ]; }; then
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/coverage.yml.template" ".github/workflows/coverage.yml"
    echo "note: coverage.yml gates patch coverage (default 100% of changed lines)."
    echo "      It forces changed lines to be RUN by a test, not verified — pair with review."
    if [ -f ".github/workflows/tests.yml" ]; then
      if cmp -s "$SCAFFOLD_DIR/.github/workflows/tests.yml.template" ".github/workflows/tests.yml"; then
        # Only remove the stale file once it's actually backed up (mirrors
        # cp_scaffold's own `_backup "$dst" || return 0` policy): never delete
        # without a recoverable copy, even if that means leaving both
        # workflows in place (with the warning above) on the rare
        # backup-cap exhaustion.
        if _backup ".github/workflows/tests.yml"; then
          rm -f ".github/workflows/tests.yml"
          echo "removed:      .github/workflows/tests.yml (superseded by coverage.yml: running both would run tests twice)"
        fi
      else
        echo "warning: .github/workflows/tests.yml also exists and looks customized, left in place."
        echo "         Remove it by hand so tests don't run twice; coverage.yml already runs them."
      fi
    fi
  else
    # `tests.yml` is a common consumer-authored filename, and this path is
    # cp_scaffold_preserve (scaffold-owned but drift-preserving, #110): a
    # FIRST install that finds a differing, already-existing tests.yml (hand
    # written, or edited since a prior scaffold install) is kept as-is, with
    # cp_scaffold_preserve's own "note (drift): ..." line explaining why and
    # how to replace it. No separate warning is printed here: a second message
    # saying the same thing in different words would just be noise, and (pre
    # #110) it also went stale the moment the underlying policy changed, since
    # this file used to claim the pre-existing version gets backed up and
    # refreshed on every re-run, which is no longer true.
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/tests.yml.template" ".github/workflows/tests.yml"
    echo "note: tests.yml runs pytest/vitest on every PR/push with no coverage threshold."
    echo "      Add --coverage-gate for the patch-coverage strictness layer on top."
  fi

  # Final state for the caller's summary line: read back from disk rather
  # than the flags alone, so an upgrade that already had one file installed
  # (independent of THIS run's flags) is reported accurately. TEST_CI_STATE is
  # a deliberate global: install.sh (which sources this file) reads it after
  # calling this function, but shellcheck lints install-lib.sh on its own and
  # can't see that cross-file use.
  # shellcheck disable=SC2034
  if [ -f ".github/workflows/coverage.yml" ]; then
    TEST_CI_STATE="tests + patch-coverage gate via coverage.yml"
  elif [ -f ".github/workflows/tests.yml" ]; then
    TEST_CI_STATE="tests run in CI via tests.yml"
  elif [ "$NO_TEST_WORKFLOW" -eq 1 ]; then
    TEST_CI_STATE="NO test execution in CI (--no-test-workflow given)"
  else
    TEST_CI_STATE="NO test execution in CI (no workflow installed)"
  fi
}

# install_opt_in_zizmor_ci / install_opt_in_socket_ci — same shape as
# --gitleaks-ci / --dependency-review in install.sh: a dedicated flag installs
# the workflow via cp_scaffold_preserve (drift-preserving, same policy as
# gitleaks.yml / dependency-review.yml since #110 / #113) and prints one
# explanatory note. Extracted here rather than left inline (unlike
# --gitleaks-ci / --dependency-review) for the same reason
# install_test_workflow_ci and install-verify.sh exist: install.sh is pinned
# at its own 500-line module cap (issue #84), and these two opt-ins were the
# lines that pushed it over.
install_opt_in_zizmor_ci() {
  if [ "$ZIZMOR_CI" -eq 1 ]; then
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/zizmor.yml.template" ".github/workflows/zizmor.yml"
    echo "note: zizmor.yml audits YOUR repo's GitHub Actions workflows (unpinned refs, template injection, over-scoped tokens). It may be red on pre-existing workflows the first run; see the template header for the fix."
  fi
}

install_opt_in_socket_ci() {
  if [ "$SOCKET_CI" -eq 1 ]; then
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/socket-security.yml.template" ".github/workflows/socket-security.yml"
    echo "note: socket-security.yml blocks a known-malicious or typosquat/hallucinated package AT INSTALL TIME, before its code runs. No API key needed for the default firewall-free mode."
  fi
}

# check_paired_artifacts GAP_FN NOTE_FN (#96): detect scaffold artifacts that
# are meant to arrive in matched pairs (a config half plus the CI half that
# enforces it, or a local hook half plus the CI half it defers to) where only
# one half is on disk. A real downstream repo had `.coveragerc` at root with
# no `.github/workflows/coverage.yml`: every PR showed green CI (lint.yml
# alone) while zero tests had ever executed, and nothing recorded that the
# gate was incomplete. Shared between scaffold-doctor.sh (GAP_FN=gap, affects
# exit status) and install.sh's own end-of-run summary (a plain warn wrapper
# that never fails the run) so the detection logic and the wording live in
# exactly one place.
#
# GAP_FN is called as `fn "<message>" "<fix command>"`, matching the doctor's
# own gap() signature: a half-install that leaves a guardrail's backstop
# silently missing. NOTE_FN is called as `fn "<message>"`, matching note(): a
# state that is worth naming but, measured against what install.sh actually
# does today, is a normal or deliberate outcome rather than a broken one.
check_paired_artifacts() {
  local gap_fn=$1 note_fn=$2
  local looks_python=0
  { [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && looks_python=1

  # 1. .coveragerc vs coverage.yml. install.sh writes .coveragerc for EVERY
  # Python install regardless of --coverage-gate (a harmless standalone
  # config, same policy as ruff.toml), so its presence alone does not mean
  # anyone ever asked for the gate: that is the common, healthy default
  # today, hence a note, not a gap. The inverse is the real anomaly:
  # coverage.yml only ever lands when --coverage-gate is passed, and a
  # Python install writes .coveragerc in that same run, so a Python project
  # with coverage.yml but no .coveragerc means the config half was deleted
  # or never restored. Gated on "looks like a Python project" so a
  # frontend-only --coverage-gate install (which legitimately has no
  # .coveragerc, vitest coverage does not use it) is not misreported.
  if [ -f .coveragerc ] && [ ! -f .github/workflows/coverage.yml ]; then
    "$note_fn" ".coveragerc is present with no .github/workflows/coverage.yml: it has no effect until the patch-coverage gate is installed too (install.sh --coverage-gate)"
  fi
  if [ -f .github/workflows/coverage.yml ] && [ ! -f .coveragerc ] && [ "$looks_python" -eq 1 ]; then
    "$gap_fn" ".github/workflows/coverage.yml is present but .coveragerc is not, and this looks like a Python project: pytest-cov has no local config to read coverage settings from" \
      "re-run install.sh --python (or --both) to restore .coveragerc"
  fi

  # 2. local gitleaks hook vs gitleaks CI workflow. check-gitleaks tells
  # every commit that CI is the authoritative, unskippable gate (see
  # scaffold-doctor.sh's own "opt-in surfaces" section); if that gate does
  # not exist, the hook is making a promise nothing keeps, and --no-verify
  # (or an unwired hooksPath) lets a secret through with nothing behind it.
  # The inverse is a documented, valid strategy: CI-only enforcement, no
  # local friction.
  if [ -f .githooks/lib/check-gitleaks ] && [ ! -f .github/workflows/gitleaks.yml ]; then
    "$gap_fn" "the local gitleaks pre-commit pass is installed (.githooks/lib/check-gitleaks) but .github/workflows/gitleaks.yml is not: every commit is told CI is the authoritative gate, and there is no CI gate behind it" \
      "re-run install.sh --gitleaks-ci"
  fi
  if [ -f .github/workflows/gitleaks.yml ] && [ ! -f .githooks/lib/check-gitleaks ]; then
    "$note_fn" "the gitleaks CI workflow is installed with no local pre-commit pass: CI remains the unskippable, authoritative gate, so this is a valid CI-only posture; add local feedback with install.sh --gitleaks-hook if you want it before push"
  fi

  # 3. tests.yml vs coverage.yml (#97's default-on test execution): never
  # both (they would run the suite twice), never neither in a repo that has
  # scaffold CI at all (lint.yml is the always-installed signal that this IS
  # a scaffold-CI repo). install_test_workflow_ci already prevents "both" on
  # every normal install/upgrade path, so it only reappears via a hand
  # restore; "neither" is exactly the #97 bug restated for detection, and can
  # persist quietly long after a --no-test-workflow install-time notice has
  # scrolled off a terminal.
  if [ -f .github/workflows/tests.yml ] && [ -f .github/workflows/coverage.yml ]; then
    "$note_fn" "both .github/workflows/tests.yml and coverage.yml are installed: coverage.yml already runs the tests, so this push/PR's suite runs twice; remove tests.yml, coverage.yml supersedes it"
  elif [ -f .github/workflows/lint.yml ] \
       && [ ! -f .github/workflows/tests.yml ] \
       && [ ! -f .github/workflows/coverage.yml ]; then
    "$gap_fn" ".github/workflows/lint.yml is installed but neither tests.yml nor coverage.yml is: CI runs lint checks only, and no test ever executes on a PR or push" \
      "re-run install.sh to install the default tests.yml (or install.sh --coverage-gate for the stricter gate)"
  fi
}
