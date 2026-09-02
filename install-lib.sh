# shellcheck shell=bash
# install-lib.sh — file-write policy helpers for install.sh.
#
# SOURCED (not executed) by install.sh, so these functions run in that script's
# shell under its `set -euo pipefail` and read its globals (FORCE). Extracted here
# so install.sh stays under the scaffold's own 500-line cap, the guardrail it
# enforces on every project it installs into, itself included.

# Default the caller-provided global so this file also lints/behaves standalone.
# install.sh always sets FORCE before sourcing, so this is a no-op there; if the
# lib is ever sourced without it, 0 (= not --force) is the safe default.
: "${FORCE:=0}"

# --- file ownership & the install/upgrade model -----------------------------
# Re-running install.sh is the supported UPGRADE path, so each destination is
# copied through the policy its OWNERSHIP demands:
#
#   cp_scaffold  scaffold-owned CODE: scanners, libs, hooks. These carry security
#                fixes, so a plain re-run REFRESHES them whenever they differ from
#                the shipped version (no --force needed); every overwrite is
#                backed up first (#72), since a project may have edited one. No CI
#                workflow file uses this policy any more (as of #110, every
#                shipped workflow goes through cp_scaffold_preserve below instead:
#                a project commonly hand-edits or pre-authors these, and a plain
#                refresh risks silently discarding that).
#   cp_safe      USER-OWNED files — ruff.toml, eslint config, .scaffold.toml,
#                dependabot.yml, the rules docs, etc. A project customizes these,
#                so they're never auto-replaced: skip unless --force (which backs
#                up first). CLAUDE.md / AGENTS.md have their own merge handlers.
#   cp_pattern   .forbidden-patterns/*.txt — the hard case: scaffold-SHIPPED yet
#                user-EXTENDED (teams append their own rows). Auto-overwriting
#                would clobber those rows, so a re-run only NOTIFIES on drift and
#                keeps the user's file; --force backs up + replaces so the user's
#                additions survive in .scaffold-bak for manual merge-back.
#   cp_scaffold_preserve  scaffold-owned CI workflows a project is expected to
#                hand-edit or that commonly arrive pre-authored: lint.yml,
#                tests.yml, coverage.yml, gitleaks.yml. Same drift-preserving
#                behavior as cp_pattern: NOTIFIES on drift, keeps the user's
#                edits; --force backs up + replaces. Added for lint.yml in #105
#                (a plain cp_scaffold refresh there discarded a consumer's CI
#                customization with no way back) and extended to the other
#                three in #110; see its own
#                function comment below for the full history.
#
# The four policies share one write MECHANISM (_cp_replace) and one backup
# routine (_backup), so the A7 symlink defenses live in exactly one place.

# SCAFFOLD_SYMLINK_DIRS — the symlinked directories _mkdir_safe has already
# refused this run, so the explanation prints once per path rather than once per
# file underneath it, and so install.sh can fail the run at the end instead of
# exiting 0 over a half-written install. Space separated; scaffold paths never
# contain a space.
SCAFFOLD_SYMLINK_DIRS=""

# _mkdir_safe DIR — create DIR as real directories, never following a symlink at
# ANY path component. `rm -f "$dst"` in _cp_replace drops a symlink at the LEAF
# file, but a plain `mkdir -p` follows a symlinked PARENT (e.g. a planted
# `.githooks -> ~/.ssh` or `.github -> $HOME`), sending every scanner/hook/CI
# workflow, and any overwrite, THROUGH the link and outside the repo, while the
# in-tree path stays a symlink (a silent write-through + fail-open).
#
# This used to `rm -f` the symlink component and carry on. That closed the
# write-through, but it DELETED a directory link the user had put there, with no
# warning, no backup and no summary line: a `.claude -> ../shared-claude` was
# gone after one install and the shared notes it pointed at were orphaned, while
# the only log line was "installed: .claude/settings.json" (audit
# code-install-policy-2). Deleting someone's link is a bigger decision than an
# installer gets to make silently, and every LEAF symlink is already refused
# with "skip (exists, symlink)" rather than removed. So: refuse the write, name
# the link and its target, say what to do, and let the caller skip that file.
_mkdir_safe() {
  local dir=$1 path='' comp target
  while [ -n "$dir" ]; do
    comp=${dir%%/*}
    case $dir in */*) dir=${dir#*/} ;; *) dir= ;; esac
    [ -z "$comp" ] && continue
    path="${path:+$path/}$comp"
    if [ -L "$path" ]; then
      case " $SCAFFOLD_SYMLINK_DIRS " in
        *" $path "*) ;;
        *)
          SCAFFOLD_SYMLINK_DIRS="$SCAFFOLD_SYMLINK_DIRS $path"
          target=$(readlink "$path" 2>/dev/null || true)
          echo "error: $path is a symlink${target:+ -> $target}, not a real directory." >&2
          echo "       Refusing to write scaffold files through it (they would land outside the" >&2
          echo "       repo), and refusing to delete it (it is yours). Nothing under $path was" >&2
          echo "       installed. Decide which you want, then re-run install.sh:" >&2
          echo "         mv $path ${path}.link   # keep the link aside, install into a real dir" >&2
          echo "         rm $path                # drop the link for good" >&2
          ;;
      esac
      return 1
    fi
    [ -d "$path" ] || mkdir "$path" || return 1
  done
  return 0
}

# print_refused_writes_summary — end-of-run report for the refusals above.
# A symlinked scaffold directory makes EVERY write under it a skip, so the
# install is genuinely incomplete and must not exit 0 pretending otherwise
# ("no silent failures"). Returns 1 so the caller can fail the run.
print_refused_writes_summary() {
  local d
  [ -n "$SCAFFOLD_SYMLINK_DIRS" ] || return 0
  echo ""
  echo "INSTALL INCOMPLETE: nothing was written under these symlinked directories:"
  for d in $SCAFFOLD_SYMLINK_DIRS; do echo "  - $d"; done
  echo "Replace each with a real directory (or move the link aside) and re-run install.sh."
  return 1
}

# _cp_replace SRC DST — the actual write. `[ -e ]` alone is false for a DANGLING
# symlink and follows a LIVE one, so a pre-existing symlink at a scaffold path
# used to make `cp` follow it and write the scanner to the link's target OUTSIDE
# the repo. We drop any symlink at every parent component (_mkdir_safe) AND at the
# leaf (`rm -f`) first, so we always write a real regular file IN the tree, never
# THROUGH a link.
_cp_replace() {
  local src=$1 dst=$2
  # _mkdir_safe refuses a symlinked parent rather than deleting it, so this can
  # legitimately fail; propagate that so every cp_* caller skips the one file
  # (and does not print an "installed:"/"updated:" line for a write that never
  # happened) instead of aborting the whole run under errexit.
  _mkdir_safe "$(dirname "$dst")" || return 1
  rm -f "$dst"
  cp "$src" "$dst"
}

# _backup DST — copy an existing file/symlink aside to <dst>.scaffold-bak[.N]
# before it is replaced, so no local edit is ever silently destroyed. `-P` backs
# up a symlink AS the link, never the dereferenced target content. Returns non-zero
# when all >99 slots are taken; callers treat that as "skip this one file, keep
# going" (`|| return 0`) — never abort, and never overwrite without a backup. Every
# cp_* overwrite funnels through here, so this is also the one place that can warn
# on a dropped `# Repo adaptation:` line regardless of which policy triggered it
# (#127): cp_scaffold's unconditional refresh, or --force on cp_safe/cp_pattern/
# cp_scaffold_preserve.
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
  # The copy is LOAD-BEARING, so its exit status is checked (audit
  # shell-03-backup-silent-failure). _backup is always called with errexit
  # disabled (`_backup "$dst" || return 0`, or `if _backup ...`), so an
  # unchecked `cp` failure was swallowed: the run still printed "backed up:"
  # and the caller still overwrote the user's file, with no backup on disk and
  # exit 0. Measured with an unreadable destination: the local edit was gone
  # and no .scaffold-bak existed. Failing here makes every caller skip that one
  # file instead, the same policy as the >99-slot cap below.
  if ! cp -P "$dst" "$bak"; then
    echo "error: could not back up $dst -> $bak (the copy failed: unreadable file, full disk, or a read-only directory)." >&2
    echo "       Skipping this one file (left untouched); nothing is overwritten without a backup." >&2
    return 1
  fi
  echo "backed up:    $dst -> $bak"
  _warn_repo_adaptations "$dst" "$bak"
}

# _warn_repo_adaptations DST BAK — DST is about to be overwritten; BAK is the
# backup _backup just made of its old content. Warn, don't try to re-splice: a
# marked block naming why it diverges from the template is real intent, but
# text-level reinsertion into the freshly-rendered file is fragile (anchors
# drift across versions), so the backup plus a loud pointer is the safer fix.
_warn_repo_adaptations() {
  local dst=$1 bak=$2 n
  n=$(grep -c '# Repo adaptation:' "$bak" 2>/dev/null || true)
  if [ -n "$n" ] && [ "$n" -gt 0 ]; then
    echo "warning: $dst carried $n 'Repo adaptation' line(s), now overwritten:"
    grep -n '# Repo adaptation:' "$bak" | sed 's/^/         /'
    echo "         re-apply by hand from $bak, or whatever it existed for may regress."
  fi
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
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
}

# cp_scaffold SRC DST — SCAFFOLD-OWNED code. Refreshes on diff so security fixes
# reach upgraders on a plain re-run. Identical → silent no-op. A symlink planted
# at a scaffold-owned path is always replaced with the real scanner (better than
# leaving a dead link there) and never written through.
#
# ALWAYS backs up before overwriting, not just under --force (issue #72): the old
# policy skipped the refresh backup on the premise that the prior bytes were
# recoverable scaffold code, true for an untouched destination but false for an
# edited one, and nothing tested which case applied. That mattered most for
# .githooks/pre-commit, the file a project MUST edit to wire in a local check: a
# reset call site failed silently and the guardrail became decoration with no
# signal. Unconditional backup makes the loss recoverable and prints a "backed
# up:" line; `.githooks/local.d/` now exists so local checks need not live in a
# scaffold-owned file at all. If _backup fails (>99 slots), skip this ONE file
# rather than overwrite it unbacked, same policy as cp_safe/cp_pattern (B12).
cp_scaffold() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # Already current? Never compare THROUGH a symlink (A7).
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      return
    fi
    _backup "$dst" || return 0
    _cp_replace "$src" "$dst" || return 0
    echo "updated:      $dst (refreshed to the shipped version)"
    return
  fi
  _cp_replace "$src" "$dst" || return 0
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
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
}

# cp_scaffold_preserve SRC DST: a scaffold-owned CI workflow (today: lint.yml,
# tests.yml, coverage.yml, gitleaks.yml, see the policy comment above). Install
# if absent; on drift NOTIFY and keep the user's file rather than overwriting
# it, same shape as cp_pattern, because a plain cp_scaffold refresh here
# silently discards a consumer's hand-edit or pre-existing version of the file
# (#105 for lint.yml, extended to the other three in #110). --force still
# backs up + replaces, matching cp_scaffold/cp_pattern's --force semantics.
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
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
}

# chmod +x only a real regular file. A scaffold path that cp_safe deliberately
# SKIPPED because it's a (possibly dangling) symlink must not abort the install
# via a chmod that follows a broken link and fails under set -e — nor should we
# flip the mode of a skipped, user-owned file.
mkx() { if [ -f "$1" ]; then chmod +x "$1"; fi; }

# install_opt_in_* flag bodies (zizmor CI, Socket CI, npm cooldown #117,
# Claude Skill #118, test-guard #140) and install_test_workflow_ci (#97) live
# in install-optin.sh, sourced by install.sh alongside this file: first
# extracted from install.sh at its 500-line module cap (issue #84), then out of
# this file each time it reached the same cap. Copy-policy rationale per flag is
# in that file's header.

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

# print_not_enabled_summary (P-19a): this scaffold's users typically do not
# read code, and this installer is typically RUN BY AN AI AGENT on their
# behalf, not by the human at a terminal (the real incident this responds to:
# an agent hand-copied files instead of running the installer, hooks ended up
# unarmed, gitleaks was never enabled, and a secret shipped that the disabled
# layers would have caught). Every opt-in that is NOT enabled in the PROJECT
# gets listed here, by name, with the exact command to turn it on: "silently
# absent" is the failure mode this exists to close.
#
# Opens with a block addressed to the installing AGENT specifically, since
# that is the actual reader roughly half the time, asking it to relay the
# list to its human before treating the install as finished; the same text
# reads fine for a human running this by hand.
#
# Presence checks, not this-run flags: a plain re-run of install.sh with no
# flags passes GITLEAKS_HOOK=0, CLAUDE=0, etc. even when a prior run already
# installed those gates, so checking the flag globals falsely reports an
# already-armed gate as "not enabled". Check what is actually on disk in the
# target project instead, same file-presence signals scaffold-doctor.sh's
# "Protections not enabled" section uses (kept in sync with it by hand; there
# is no shared list to source since this runs before scaffold-doctor.sh
# exists in a fresh install).
print_not_enabled_summary() {
  local any=0
  echo ""
  echo "If you are an AI agent running this install: relay the list below to"
  echo "your user verbatim, and ask which of these opt-in protections to"
  echo "enable, before you consider this install finished."
  echo ""
  echo "Opt-in protections not enabled in this project:"
  [ -f .githooks/lib/check-gitleaks ]            || { echo "  - gitleaks hook (local secret scan, pre-commit): not enabled. Enable with ./install.sh --gitleaks-hook"; any=1; }
  [ -f .github/workflows/gitleaks.yml ]          || { echo "  - gitleaks CI gate (unskippable secret scan): not enabled. Enable with ./install.sh --gitleaks-ci"; any=1; }
  echo "  - GitHub push protection (free, blocks a push containing a known secret pattern; on by default for public repos): not this installer's to enable. Turn it on in Repo Settings > Code security > Push protection."
  [ -f .github/workflows/dependency-review.yml ] || { echo "  - dependency-review CI gate (blocks vulnerable/malicious deps on a PR): not enabled. Enable with ./install.sh --dependency-review"; any=1; }
  [ -f .github/workflows/zizmor.yml ]            || { echo "  - zizmor CI gate (audits your own GitHub Actions workflows): not enabled. Enable with ./install.sh --zizmor-ci"; any=1; }
  [ -f .github/workflows/socket-security.yml ]   || { echo "  - Socket Firewall CI gate (blocks a malicious/typosquat package at install time): not enabled. Enable with ./install.sh --socket-ci"; any=1; }
  [ -f .github/workflows/test-guard.yml ]        || { echo "  - test-guard CI gate (red-green: a new test must fail against the PR base before it may pass): not enabled. Enable with ./install.sh --test-guard"; any=1; }
  [ -f .npmrc ]                                  || { echo "  - npm install-layer cooldown (.npmrc min-release-age, delays freshly published versions): not enabled. Enable with ./install.sh --npm-cooldown"; any=1; }
  [ -f .claude/skills/coding-rules/SKILL.md ]    || { echo "  - Claude Code Skill (on-demand rules loading): not enabled. Enable with ./install.sh --claude-skill"; any=1; }
  [ -f .claude/settings.json ]                   || { echo "  - Claude Code agent guardrails: not enabled. Enable with ./install.sh --claude"; any=1; }
  [ -f .cursor/hooks.json ]                      || { echo "  - Cursor agent guardrails: not enabled. Enable with ./install.sh --cursor"; any=1; }
  [ -f .githooks/commit-msg ]                    || { echo "  - commit-msg hook (Conventional Commits): not enabled. Enable with ./install.sh --commit-msg"; any=1; }
  if [ "$any" -eq 0 ]; then
    echo "  (none: every opt-in protection above is already enabled in this project)"
  fi
  echo ""
  echo "Check what is armed at any time: ./scaffold-doctor.sh, or 'npx ai-coding-rules-scaffold doctor' if you did not clone this repo."
}

# print_history_scan_note (P-05): check-secrets and gitleaks.yml only ever
# look at commits made AFTER this install, so a repo with pre-existing
# history may already carry a secret from before the scaffold existed, and
# nothing in the shipped inventory can see it. Printed only when HEAD
# already resolves (a brand-new `git init` has nothing to scan yet); the
# rotate-first framing and the force-push warning match README.md's "Already
# have commit history?" section, so the two never contradict each other.
print_history_scan_note() {
  if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    echo ""
    echo "This repo already has commit history: run a one-time full-history secret"
    echo "scan before trusting this install for anything committed before today:"
    echo "  gitleaks git .   (or trufflehog's history mode)"
    echo "A hit means rotate or revoke that credential first: that is the actual"
    echo "fix. History rewriting (git-filter-repo or BFG, never git filter-branch)"
    echo "is optional cleanup afterward, not a substitute, and it force-pushes and"
    echo "rewrites every clone, so route it through your human rather than doing"
    echo "it yourself. See README.md's 'Already have commit history?' section."
  fi
}
