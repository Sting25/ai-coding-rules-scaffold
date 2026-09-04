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

# install-manifest.sh defines the provenance helpers and install.sh sources it
# BEFORE this file, so these stubs are dead there. scaffold-doctor.sh sources
# install-lib.sh on its own (for check_paired_artifacts) and never copies a
# file, so it gets inert no-ops rather than an undefined-function error if a
# future doctor path ever reaches a cp_* helper.
if ! declare -f manifest_record >/dev/null 2>&1; then
  manifest_record() { :; }
  manifest_says_ours() { return 1; }
  _manifest_hash() { return 1; }
  print_manifest_failure_summary() { return 0; }
  print_gitignore_failure_summary() { return 0; }
fi

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

# SCAFFOLD_SYMLINK_DIRS: the symlinked directories _mkdir_safe has already
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

# print_refused_writes_summary: the end-of-run report for everything that left
# this run incomplete: a symlinked scaffold directory (EVERY write under it is
# skipped) and a failed manifest write (files installed but unrecorded, so the
# next upgrade stops refreshing them). Returns 1, so the caller fails the run.
print_refused_writes_summary() {
  local d rc=0
  print_manifest_failure_summary || rc=1   # install-manifest.sh, same contract
  print_gitignore_failure_summary || rc=1  # install-manifest.sh, same contract
  if [ -n "$SCAFFOLD_SYMLINK_DIRS" ]; then
    echo ""
    echo "INSTALL INCOMPLETE: nothing was written under these symlinked directories:"
    for d in $SCAFFOLD_SYMLINK_DIRS; do echo "  - $d"; done
    echo "Replace each with a real directory (or move the link aside) and re-run install.sh."
    rc=1
  fi
  return "$rc"
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
# on a dropped `Repo adaptation:` marker regardless of which policy triggered it
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
  # A backup is an inert copy, never something git or a hook should execute.
  # These land as SIBLINGS of the file they back up, so .githooks/pre-commit
  # produced .githooks/pre-commit.scaffold-bak at mode 100755, untracked and
  # un-ignored: a routine `git add -A` committed it as if it were a hook (audit
  # upgrade-path-2). Strip the execute bits, never through a symlink backup
  # (`cp -P` keeps it a link, and chmod would follow it to the target).
  if [ -f "$bak" ] && [ ! -L "$bak" ]; then
    chmod a-x "$bak" 2>/dev/null || true
  fi
  echo "backed up:    $dst -> $bak"
  _warn_repo_adaptations "$dst" "$bak"
}

# _warn_repo_adaptations DST BAK — DST is about to be overwritten; BAK is the
# backup _backup just made of its old content. Warn, don't try to re-splice: a
# marked block naming why it diverges from the template is real intent, but
# text-level reinsertion into the freshly-rendered file is fragile (anchors
# drift across versions), so the backup plus a loud pointer is the safer fix.
#
# The marker is matched after ANY comment lead-in, not just `#`. It used to be
# the literal string `# Repo adaptation:`, so the warning could not fire for a
# single file the scaffold installs that is not #-commented: measured (audit
# code-install-policy-4), a `// Repo adaptation:` line in eslint.config.js was
# backed up and overwritten by `install.sh --frontend --force` in total silence
# while the `#` line in lint.yml warned by name. JSON templates (tsconfig.json,
# .prettierrc.json, claude-settings.json, cursor-hooks.json) cannot carry a `#`
# comment at all, so for those the convention is a `//`-prefixed KEY, which is
# valid JSON and matches here:
#
#     "// Repo adaptation: pinned to ES2021 for the vendored runtime": true
#
# `*` covers a jsdoc/CSS block-comment continuation line and `--` SQL/Lua. The
# `(^|[^A-Za-z])` prefix keeps `//` from matching inside a URL or a path.
_warn_repo_adaptations() {
  local dst=$1 bak=$2 n
  local pat='(^|[^A-Za-z])(#|//|\*|--)[[:space:]]*Repo adaptation:'
  n=$(grep -cE "$pat" "$bak" 2>/dev/null || true)
  if [ -n "$n" ] && [ "$n" -gt 0 ]; then
    echo "warning: $dst carried $n 'Repo adaptation' line(s), now overwritten:"
    grep -nE "$pat" "$bak" | sed 's/^/         /'
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
  manifest_record "$dst"
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
      manifest_record "$dst"
      return
    fi
    _backup "$dst" || return 0
    _cp_replace "$src" "$dst" || return 0
    echo "updated:      $dst (refreshed to the shipped version)"
    manifest_record "$dst"
    return
  fi
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
  manifest_record "$dst"
}

# _drift_note DST HINT: the "we are keeping your file" message, worded by what
# the manifest actually knows. A file WITH a manifest entry whose hash no longer
# matches really is a hand-edit, and saying so is accurate. A file with NO entry
# predates the manifest (or the user created it), and the old wording asserted
# "your customizations are kept" to people who had customized nothing: that
# false claim is how an untouched older release stayed stuck for versions while
# its owner was told the installer was protecting their work (audit hist-03,
# upgrade-path-3). A drifted file is deliberately NEVER recorded, since
# recording it would make the next run believe the scaffold wrote those bytes
# and refresh over the user's edit, so this stays the message until --force
# resolves it.
_drift_note() {
  local dst=$1 hint=$2
  if _manifest_hash "$dst" >/dev/null 2>&1; then
    echo "note (drift):  $dst differs from the shipped version and from what the scaffold last wrote there, so your edits are kept. $hint"
  else
    echo "note (drift):  $dst differs from the shipped version. This install predates the install manifest, so nothing on disk records whether that is your edit or simply an older shipped version; it is kept as-is either way. $hint"
  fi
}

# cp_pattern SRC DST — .forbidden-patterns/*.txt. Install if absent; if it drifts
# from the shipped version, NOTIFY (the user may have added rows; new shipped
# rules may be worth merging) but keep the user's file. --force backs up + writes
# the shipped version, so the user's additions survive in .scaffold-bak.
cp_pattern() {
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
      manifest_record "$dst"
      return
    fi
    # Differs from what we ship TODAY, which is not the same as "the user
    # edited it": an untouched install of an older version differs too, and used
    # to be kept forever under a "your customizations are kept" note nobody had
    # earned (audit hist-03 / upgrade-path-1: 26 of 37 secret patterns, and a
    # SendGrid key committing clean). The manifest settles which one it is.
    # Backed up like every other overwrite: the manifest is unsigned plaintext
    # in the tree, so a regenerated or mis-merged one can call a real edit
    # "ours", and with no copy this path would delete it for good (verify-2).
    if [ ! -L "$dst" ] && manifest_says_ours "$dst"; then
      _backup "$dst" || return 0
      _cp_replace "$src" "$dst" || return 0
      echo "updated:      $dst (refreshed to the shipped patterns; unchanged since the scaffold last wrote it)"
      manifest_record "$dst"
      return
    fi
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst — left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        _drift_note "$dst" "Diff against forbidden-patterns/$(basename "$dst").template for new rules to merge, or re-run with --force to replace (backs yours up to .scaffold-bak)."
      fi
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
  manifest_record "$dst"
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
      manifest_record "$dst"
      return
    fi
    # Same manifest check as cp_pattern, for the same reason: an unmodified
    # workflow from an older release is not a hand-edit. Keeping it as one is
    # how a v0.12.0 install ended up with a lint.yml that never calls
    # check-large-files and pins action SHAs a major version back, while the run
    # told its owner their customizations were being preserved (audit hist-01 /
    # upgrade-path-3).
    # Backed up first, for the reason spelled out in cp_pattern above.
    if [ ! -L "$dst" ] && manifest_says_ours "$dst"; then
      _backup "$dst" || return 0
      _cp_replace "$src" "$dst" || return 0
      echo "updated:      $dst (refreshed to the shipped version; unchanged since the scaffold last wrote it)"
      manifest_record "$dst"
      return
    fi
    if [ "$FORCE" -eq 0 ]; then
      if [ -L "$dst" ]; then
        echo "skip (exists, symlink): $dst, left untouched; a scaffold path that is a symlink is suspicious. Replace it with --force."
      else
        _drift_note "$dst" "Diff against $src for upstream changes to merge, or re-run with --force to replace (backs yours up to .scaffold-bak)."
      fi
      return
    fi
    _backup "$dst" || return 0
  fi
  _cp_replace "$src" "$dst" || return 0
  echo "installed:    $dst"
  manifest_record "$dst"
}

# chmod +x only a real regular file. A scaffold path that cp_safe deliberately
# SKIPPED because it's a (possibly dangling) symlink must not abort the install
# via a chmod that follows a broken link and fails under set -e — nor should we
# flip the mode of a skipped, user-owned file.
mkx() { if [ -f "$1" ]; then chmod +x "$1"; fi; }

# --- tsconfig.json placement (#163) -----------------------------------------
# A root tsconfig.json is not just a config file: the pre-commit hook and
# lint.yml run `tsc --noEmit` over the WHOLE tree whenever one exists. In a
# workspaces monorepo that checks every workspace with compiler options written
# for none of them and blocks every JS/TS commit (12,235 errors measured in
# #163, and the natural reaction, --no-verify, switches off every other
# guardrail too). So the file is placed by policy, mirroring COMPONENTS.md's
# adopt=tsconfig block: an existing root file goes through cp_safe unchanged;
# a workspaces repo or one with per-directory tsconfig files gets a skip that
# names the reason; a plain repo gets the file plus a note saying what the hook
# will now do and how to undo it, so the placement is never silent.
cp_tsconfig_root() {
  local src=$1 nested
  if [ -e tsconfig.json ] || [ -L tsconfig.json ]; then
    cp_safe "$src" "tsconfig.json"
    return
  fi
  if grep -qs '"workspaces"' package.json || [ -f pnpm-workspace.yaml ]; then
    echo "skip (workspaces monorepo): tsconfig.json  (not writing a root tsconfig.json: with one present the pre-commit hook and lint.yml run 'tsc --noEmit' over the whole tree with its options and ignore each workspace's own config (#163). Type-check per workspace; to layer the strictness on, merge tsconfig.json.template's compilerOptions into each workspace's tsconfig.)"
    return
  fi
  # No -mindepth: with it, find never evaluates the expression for depth-1
  # entries, so the prune would not fire on ./node_modules and a dependency's
  # tsconfig.json would count as the repo's. The root file cannot match here:
  # its existence was handled above.
  nested=$(find . -maxdepth 3 \
      \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name vendor \
         -o -name dist -o -name build -o -name .claude \) -prune -o \
      -type f -name tsconfig.json -print 2>/dev/null \
    | sed -e 's#^\./##' -e 's#/tsconfig\.json$##' | sort | tr '\n' ' ' || true)
  nested=${nested% }
  if [ -n "$nested" ]; then
    echo "skip (tsconfig.json in $nested): tsconfig.json  (not writing a root tsconfig.json: this repo type-checks per directory, and a root file would make the pre-commit hook and lint.yml run 'tsc --noEmit' over the whole tree instead, #163. Merge tsconfig.json.template's compilerOptions into those configs if you want the strictness.)"
    return
  fi
  cp_safe "$src" "tsconfig.json"
  echo "note:         tsconfig.json installed at the repo root. The pre-commit hook and lint.yml now run 'tsc --noEmit' over every tracked .ts/.tsx on JS/TS commits, with the strict options in that file. If that is not what this repo wants, delete tsconfig.json (or merge its compilerOptions into your own build config) and the type-check step goes back to skipping."
}

# install_opt_in_* flag bodies (zizmor CI, Socket CI, npm cooldown #117,
# Claude Skill #118, test-guard #140) and install_test_workflow_ci (#97) live
# in install-optin.sh, sourced by install.sh alongside this file: first
# extracted from install.sh at its 500-line module cap (issue #84), then out of
# this file each time it reached the same cap. Copy-policy rationale per flag is
# in that file's header.
