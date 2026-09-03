# shellcheck shell=bash
# scaffold-doctor-gates.sh: the guardrails that live OUTSIDE .githooks/ — the
# CI backstop and the two measurement gates that can be widened until they
# grade nothing — plus the inventory of the ones this project never turned on.
#
# SOURCED (not exec'd) by scaffold-doctor.sh at the point where these sections
# used to sit inline, so they run in that shell with its counters (GAPS/OKS/
# NOTES), its helpers (section/ok/gap/note), its QUIET flag, its SCAFFOLD_DIR
# and its `set -euo pipefail`. Nothing here is a function on purpose: this is
# straight-line report code whose ORDER IS ITS OUTPUT, and sourcing it in place
# keeps that order and every counter update exactly as it was.
#
# Extracted when scaffold-doctor.sh reached the scaffold's own 500-line module
# cap (coding-rules.md rule 1), the same reason install.sh sources
# install-lib.sh / install-wiring.sh and uninstall.sh sources
# uninstall-drop-lang.sh. The scaffold enforces that cap on its users, so it
# takes the extraction rather than raising the number.
#
# WHY THESE SECTIONS AND NOT OTHERS. Sections 1-7 stay in scaffold-doctor.sh
# because they answer one question — does the pre-commit hook run, and does it
# have the data it needs — off .githooks/ and the files it consumes. Section 8
# stays with them because its "install-wiring.sh not found" note is what a
# scaffold-doctor.sh copied out of the bundle on its own reports, and moving it
# into a second module would take that report out with it. Everything here
# starts where the hook stops — `git commit --no-verify` skips every
# client-side hook, so:
#
#   9.  is the CI job that re-runs those same checks still there and still
#       calling them (the ONLY backstop behind --no-verify)?
#   10. does the patch-coverage gate still measure the changed lines, or has
#       the threshold / .coveragerc omit / vitest coverage.exclude been widened
#       until a green check means nothing?
#   11. does ESLint still see the source, or has one .gitignore line turned
#       every rule off for a tree that is still tracked, committed and shipped?
#   12. which of these gates does this project not have at all?
#
# All four are self-contained: each opens with its own section() and reads only
# the project files it names, so they can move as a block without any of the
# ordering or state coupling that sections 1-8 have with each other.

# --- 9. server-side backstop -------------------------------------------------
# Every hook in this scaffold is client-side and `git commit --no-verify`
# skips all of them — pre-commit.template says so out loud. .github/workflows/
# lint.yml re-running the same lib/check-* scripts IS the answer to that, and
# it is the only one. Nothing guarded its removal: the pre-commit deletion
# guard matches `^\.forbidden-patterns/.+\.txt$` only, workflows run from the
# PR head so the deleting PR's own checks no longer include the job, and this
# script used to grade such a repo "armed, 0 gaps".
section "server-side backstop"
if [ ! -d .githooks/lib ]; then
  note "no .githooks/lib/ — no local checks installed, so there is nothing for CI to mirror"
elif [ ! -f .github/workflows/lint.yml ]; then
  gap ".github/workflows/lint.yml is missing — the lib/check-* scripts run client-side only, and 'git commit --no-verify' bypasses every one of them with nothing behind it" \
      "re-run install.sh to restore .github/workflows/lint.yml"
# Anchored past any leading '#': lint.yml is YAML, and a job hollowed out to a
# comment that still NAMES the scripts it no longer runs would otherwise read
# as armed — the exact "present but not running" shape this script exists for.
elif grep -qE '^[[:space:]]*[^#[:space:]].*check-secrets' .github/workflows/lint.yml &&
     grep -qE '^[[:space:]]*[^#[:space:]].*check-patterns' .github/workflows/lint.yml; then
  ok "lint.yml re-runs the guardrail checks server-side"
else
  gap ".github/workflows/lint.yml exists but its guardrails job no longer invokes lib/check-secrets and lib/check-patterns — CI is not mirroring the hook" \
      "re-run install.sh --force to restore the guardrails job"
fi

# --- 10. patch-coverage gate -------------------------------------------------
# The opt-in gate has a CONTINUOUS off switch nothing else watches. Editing
# DIFF_COVER_FAIL_UNDER from "100" to "0" leaves the workflow installed, the
# job green and the check name unchanged in branch protection; install.sh
# preserves the drift by policy (cp_scaffold_preserve, #105/#110) and prints
# at most a "note (drift):" on a re-run nobody performs. Widening .coveragerc's
# `omit` — or vitest's `coverage.exclude`, the same switch on the JS side — is
# the same move one layer down: an excluded path never reaches coverage.xml /
# cobertura-coverage.xml, and diff-cover scores a changed line it has no data
# for as COVERED. All three are reported against the SHIPPED templates, so this
# tracks the scaffold's own default rather than a number hardcoded here.
section "patch-coverage gate"
COV_TPL="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"
COVRC_TPL="$SCAFFOLD_DIR/.coveragerc.template"
VITEST_TPL="$SCAFFOLD_DIR/vitest.config.ts.template"
# Every check in this section compares against a template that ships BESIDE
# this script, and a doctor copied out of the bundle on its own would skip all
# three in total silence — the failure mode this whole script exists to name.
# Said once, here, in the same shape as the paired-artifacts note above.
if [ ! -f "$COV_TPL" ] || [ ! -f "$COVRC_TPL" ] || [ ! -f "$VITEST_TPL" ]; then
  note "coverage templates not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): the .coveragerc omit and vitest coverage.exclude drift checks are skipped, and the threshold below is compared against a hardcoded 100 instead of the shipped default; re-fetch the full scaffold bundle, not just this one file"
fi
# awk, not `grep -o | head`: same narrowed-PATH reason as the drift check above.
# ANCHORED ON THE KEY at the start of a line, and the value taken from after the
# colon: an unanchored match reads `# DIFF_COVER_FAIL_UNDER: 100 is the default`
# sitting above a real `DIFF_COVER_FAIL_UNDER: "0"` as the value and prints
# "✓ patch coverage: 100%" over a dead gate — one comment line restoring the
# exact false green this section exists to kill. The first digit run before any
# inline `#` is the value, so "100", '80' and 100 (all valid YAML) read alike.
_fail_under() {
  awk '
    /^[[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:/ {
      rest = $0
      sub(/^[[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:/, "", rest)
      h = index(rest, "#")
      if (h > 0) rest = substr(rest, 1, h - 1)
      if (match(rest, /[0-9]+/)) { print substr(rest, RSTART, RLENGTH); exit }
    }' "$1" 2>/dev/null || true
}
if [ ! -f .github/workflows/coverage.yml ]; then
  note "no .github/workflows/coverage.yml — no patch-coverage gate (opt in with install.sh --coverage-gate)"
else
  thr=$(_fail_under .github/workflows/coverage.yml)
  shipped=100
  if [ -f "$COV_TPL" ]; then
    shipped=$(_fail_under "$COV_TPL")
  fi
  shipped=${shipped:-100}
  # A gap, not a note, at ANY value below the shipped default: the doctor's own
  # definition of a gap is "installed but inert; a commit that should be blocked
  # isn't", and at 80 a PR whose changed lines are 85% covered merges where the
  # shipped policy would have stopped it. Adopting an existing codebase at a
  # lower number and ratcheting up is a legitimate choice — the doctor will
  # keep naming it until you get back to the default, which is the point.
  if [ -z "$thr" ]; then
    gap "coverage.yml has no DIFF_COVER_FAIL_UNDER — diff-cover falls back to its own default instead of this project's threshold" \
        "restore 'DIFF_COVER_FAIL_UNDER: \"$shipped\"' in the workflow's env: block"
  elif [ "$thr" -eq 0 ]; then
    gap "DIFF_COVER_FAIL_UNDER is 0 — the patch-coverage gate is installed, runs, and CANNOT FAIL; the green check it produces is indistinguishable from a real one" \
        "raise it back to $shipped, or delete coverage.yml so the repo stops advertising a gate it does not have"
  elif [ "$thr" -lt "$shipped" ]; then
    gap "patch coverage is ${thr}% of changed lines, below the shipped ${shipped}% — changed lines between ${thr}% and ${shipped}% coverage now merge green" \
        "raise DIFF_COVER_FAIL_UNDER back to $shipped; if ${thr} is a deliberate adoption ratchet, say so in the PR that set it and expect this line until it is back up"
  else
    ok "patch coverage: ${thr}% of changed lines"
  fi
fi
# .coveragerc `omit` drift. Only ADDED entries matter: a shorter list is
# stricter. Read on the raw entry text so a reordered list is not drift.
#
# The continuation rules below are configparser's, not "indented lines until
# anything else". A full-line comment or a blank line INSIDE the block does NOT
# end the value — configparser strips the comment, keeps the option open and
# reads on — so an awk that stopped at either would print
# "✓ omit list matches the shipped template" over an added `*/payments/*` the
# moment someone wrote `# legacy, see #99` above it. That is the LIKELY shape,
# not a corner case: .coveragerc.template's own comment tells the reader to say
# out loud why an entry is there, and house style is to comment the why. The
# value ends only at a line starting in column 0 (the next key or section).
# Entries are comma-separable too (coverage.py splits on commas AND newlines),
# so `omit = a, b` is two entries, not one path named "a, b".
_omit_entries() {
  awk '
    function emit(s,   n, i, a) {
      n = split(s, a, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        if (a[i] != "") print a[i]
      }
    }
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*omit[[:space:]]*=/ { inomit = 1; v = $0; sub(/^[^=]*=/, "", v); emit(v); next }
    inomit && /^[[:space:]]*$/ { next }
    inomit && /^[[:space:]]/ { emit($0); next }
    { inomit = 0 }
  ' "$1" 2>/dev/null || true
}
if [ -f .coveragerc ] && [ -f "$COVRC_TPL" ]; then
  # -Fxq, not a regex match: omit entries are globs (`*/tests/*`), and comparing
  # them as patterns would call `*/test_*.py` a match for anything.
  shipped_omit=$(_omit_entries "$COVRC_TPL")
  added=""
  while IFS= read -r _e; do
    if [ -n "$_e" ] && ! printf '%s\n' "$shipped_omit" | grep -Fxq -- "$_e"; then
      added="${added}${_e}
"
    fi
  done <<EOF
$(_omit_entries .coveragerc)
EOF
  if [ -n "$added" ]; then
    nadd=$(printf '%s' "$added" | grep -c '' || true)
    gap ".coveragerc omits $nadd path(s) the shipped template does not — every changed line under them drops out of coverage.xml and diff-cover scores it as COVERED, so the gate passes on untested code there" \
        "remove the added omit entries, or keep them and say in the PR which code is no longer gated"
    [ "$QUIET" -eq 1 ] || printf '%s' "$added" | sed 's/^/        - /'
  else
    ok ".coveragerc omit list matches the shipped template (nothing extra hidden from the gate)"
  fi
fi
# vitest `coverage.exclude` drift — the JS half of the same off switch, and the
# half nothing else in this scaffold looks at. An excluded path emits no entry
# in cobertura-coverage.xml at all, which diff-cover reads as COVERED.
#
# Entries are pulled by scanning for QUOTED strings rather than splitting on
# commas: `'**/.{git,cache}/**'` is one glob containing commas, and a comma
# split would report three phantom paths. Only the first exclude array AFTER a
# `coverage:` key is read, so a `test.exclude` (which selects TEST files, not
# measured files) is not mistaken for this one.
_vitest_cov_excludes() {
  awk '
    /coverage[[:space:]]*:/ { incov = 1 }
    incov && !inx && /exclude[[:space:]]*:[[:space:]]*\[/ {
      inx = 1; sub(/^.*exclude[[:space:]]*:[[:space:]]*\[/, "")
    }
    inx {
      line = $0
      sub(/\/\/.*$/, "", line)
      while (match(line, "[\"\047\140][^\"\047\140]*[\"\047\140]")) {
        pre = substr(line, 1, RSTART - 1)
        # The array closed before this string: it belongs to whatever follows
        # on the same line (an `include:` list, say), not to the excludes.
        if (index(pre, "]") > 0) { line = pre; break }
        e = substr(line, RSTART + 1, RLENGTH - 2)
        if (e != "") print e
        line = substr(line, RSTART + RLENGTH)
      }
      if (index(line, "]") > 0) exit
    }
  ' "$1" 2>/dev/null || true
}
# Excluding tests, build output, type stubs and tool config is what an exclude
# list is FOR — every hand-written vitest config has some of it, and the
# shipped template reached today's list by a different route (it now spreads
# vitest's own `coverageConfigDefaults.exclude` instead of respelling them), so
# a bare "not in the template" test would fire on every correctly-installed
# repo one release behind. Reported entries are therefore only those that name
# neither a test/build/tooling path nor a non-source file type — i.e. the move
# F34 is actually about: taking a directory of YOUR OWN SOURCE out of the gate.
# Directory words are matched with a non-word boundary on both sides so that
# `app/routes/**` is not read as "contains out" and quietly excused.
_BENIGN_EXCLUDE='(^|[^a-zA-Z0-9_])(node_modules|dist|build|out|coverage|target|vendor|bower_components|tests?|specs?|__tests__|__mocks__|__snapshots__|fixtures|mocks|stubs|cypress|playwright|e2e|storybook|stories|bench|benchmark|examples?|docs?|scripts?|generated|__generated__)([^a-zA-Z0-9_]|$)|\.d\.ts|\.config\.|\.setup\.|(eslint|prettier|babel|mocha|stylelint|npm)rc|/\.|^\.|virtual:|__x00__'
# install.sh writes vitest.config.ts, but a project that renamed it (or that
# keeps its vitest block in vite.config.ts, which is equally valid) would
# otherwise have this check skip without a word. First one that exists wins.
VITEST_CFG=""
for _c in vitest.config.ts vitest.config.mts vitest.config.js vite.config.ts vite.config.js; do
  if [ -f "$_c" ]; then VITEST_CFG=$_c; break; fi
done
if [ -n "$VITEST_CFG" ] && [ -f "$VITEST_TPL" ]; then
  shipped_x=$(_vitest_cov_excludes "$VITEST_TPL")
  xadded=""
  while IFS= read -r _e; do
    if [ -n "$_e" ] &&
       ! printf '%s\n' "$shipped_x" | grep -Fxq -- "$_e" &&
       ! printf '%s\n' "$_e" | grep -qEi -- "$_BENIGN_EXCLUDE"; then
      xadded="${xadded}${_e}
"
    fi
  done <<EOF
$(_vitest_cov_excludes "$VITEST_CFG")
EOF
  if [ -n "$xadded" ]; then
    nx=$(printf '%s' "$xadded" | grep -c '' || true)
    gap "$VITEST_CFG excludes $nx source path(s) from coverage that the shipped template does not — vitest emits no data for them, and diff-cover scores a changed line it has no data for as COVERED, so the gate passes on untested code there" \
        "remove the added coverage.exclude entries, or keep them and say in the PR which code is no longer gated"
    [ "$QUIET" -eq 1 ] || printf '%s' "$xadded" | sed 's/^/        - /'
  else
    ok "$VITEST_CFG: coverage.exclude hides no source path the shipped template measures"
  fi
fi

# --- 11. lint ignore derivation ----------------------------------------------
# eslint.config.js.template calls `includeIgnoreFile(.gitignore)`, so ESLint's
# ignore list IS .gitignore. That derivation is deliberate and stays (#76: a
# hardcoded ignore list only covers the names someone thought of, and `npx
# eslint .` walking a vendored toolchain or an agent worktree either drowns in
# other people's code or dies with ERR_MODULE_NOT_FOUND). What was unguarded is
# its cost, which the template states out loud and nothing enforced: appending
# one line to .gitignore turns every rule off for a whole tree, in a diff nobody
# reads as a lint change. It fails OPEN and it fails SILENTLY at BOTH gates —
# .githooks/pre-commit and .github/workflows/lint.yml hand eslint explicit
# staged/changed paths, so an ignored-but-modified file yields only the
# non-fatal "File ignored because of a matching ignore pattern" warning and exit
# 0 — and gitignore does not untrack anything, so that code keeps being
# committed and shipped with no-floating-promises, no-explicit-any and the rest
# silently off.
#
# WHAT IS REPORTED, and why it is exactly this narrow. A doctor that fired on a
# normal node_modules/ dist/ coverage/ *.min.js .gitignore would be switched off
# within a day, and then the hole above is open again with a green report over
# it — so the bar here is silence on a correct project, not coverage:
#
#   * TRACKED files only (git's own index). Being ignored does not untrack
#     anything, so a tracked-and-ignored source file is code that still ships
#     unlinted — the whole hole, in one condition. Untracked-and-ignored is
#     node_modules/ and dist/ BY CONSTRUCTION: thousands of files, every one of
#     them correctly ignored, and none of them committable by accident anyway.
#   * matched by GIT, not by a .gitignore parser written here. Negation lines,
#     directory rules, `**`, anchoring and last-match-wins precedence are git's
#     semantics; half an implementation of them is exactly how this check would
#     start crying wolf. `--no-index` because the default check-ignore reports
#     nothing for tracked paths, which is the only kind we care about, and `-v`
#     so the report can name the rule to delete.
#   * the ROOT .gitignore only. includeIgnoreFile reads that one file, so a
#     match from .git/info/exclude, a global core.excludesFile or a nested
#     subdirectory .gitignore is NOT an ESLint ignore and reporting it would be
#     a false positive by construction. `-v` prints the source file, so this is
#     a filter on fact rather than an assumption.
#   * minus build output, vendored code and generated files, which legitimately
#     contain .js and are SUPPOSED to be ignored. A committed dist/bundle.js, a
#     vendored jquery.js, a checked-in .pnp.cjs and a *.d.ts stub are all real,
#     all ignored, and none of them is a lint hole.
#
# Only when the project actually uses the derivation: no eslint.config.* naming
# includeIgnoreFile, or no .gitignore, means nothing derives anything and this
# section does not exist for that project.
ESLINT_CFG=""
for _c in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts; do
  if [ -f "$_c" ] && grep -q 'includeIgnoreFile' "$_c" 2>/dev/null; then ESLINT_CFG=$_c; break; fi
done
# Path COMPONENTS, not word boundaries: `app/routes/` must not read as "contains
# out", and `distributed/` is not `dist/`. Kept to output/vendor/generated only —
# test and config paths are lintable source and their absence from the linter is
# a real hole, unlike their absence from a coverage number (section 10).
_LINT_IGNORE_BENIGN='(^|/)(node_modules|bower_components|jspm_packages|dist|build|out|output|public|target|coverage|vendor|vendored|third_party|thirdparty|external|generated|__generated__|gen|\.nyc_output|\.next|\.nuxt|\.svelte-kit|\.astro|\.docusaurus|\.turbo|\.vercel|\.netlify|\.serverless|\.cache|\.output|\.yarn|\.pnpm|\.parcel-cache|storybook-static)(/|$)|\.(min|bundle|chunk|generated|gen|pb)\.[cm]?[jt]sx?$|\.d\.[cm]?ts$|\.scaffold-bak(\.[0-9]+)?$|(^|/)\.pnp\.[cm]?js$'
if [ -n "$ESLINT_CFG" ] && [ -f .gitignore ]; then
  section "lint ignore derivation"
  # One pipeline, and only tools case 18's narrowed-PATH runs provide (git,
  # grep, awk): a doctor that dies on a missing coreutil would be its own bug.
  # `-v` output is `<source>:<line>:<pattern>\t<pathname>`; the pattern may
  # itself contain colons, so it is taken as "everything after the second one".
  # A NEGATION line is printed by check-ignore even though the path it names is
  # NOT ignored (measured: `!src/ok.ts` appears in the output), so `!` patterns
  # are dropped or every un-ignored exception would be reported as a hole.
  ign_hits=$(git ls-files 2>/dev/null \
    | grep -E '\.[cm]?[jt]sx?$' \
    | git check-ignore --no-index -v --stdin 2>/dev/null \
    | awk -F'\t' '
        NF < 2 { next }
        {
          i = index($1, ":"); if (i == 0) next
          if (substr($1, 1, i - 1) != ".gitignore") next
          rest = substr($1, i + 1)
          j = index(rest, ":"); if (j == 0) next
          pat = substr(rest, j + 1)
          if (substr(pat, 1, 1) == "!") next
          print $2 "\t" pat
        }' || true)
  ign_bad=""
  while IFS=$'\t' read -r _p _pat; do
    [ -n "$_p" ] || continue
    if printf '%s\n' "$_p" | grep -qE "$_LINT_IGNORE_BENIGN"; then continue; fi
    ign_bad="${ign_bad}${_p}  (.gitignore: ${_pat})
"
  done <<IGN
$ign_hits
IGN
  if [ -n "$ign_bad" ]; then
    nign=$(printf '%s' "$ign_bad" | grep -c '' || true)
    gap ".gitignore hides $nign tracked source file(s) from ESLint: $ESLINT_CFG derives its ignore list from .gitignore (includeIgnoreFile), so every lint rule is OFF for that code at pre-commit AND in CI, while the files stay tracked, committed and shipped" \
        "delete the .gitignore rule named beside each file below, or if that code really is not yours to lint, keep the rule and say in the PR which files stopped being linted"
    if [ "$QUIET" -eq 0 ]; then
      printf '%s' "$ign_bad" | sed -n '1,8{s/^/        - /;p;}'
      [ "${nign:-0}" -le 8 ] || echo "        - ... and $((nign - 8)) more"
    fi
  else
    ok "$ESLINT_CFG derives ESLint's ignores from .gitignore, and .gitignore hides no tracked source from it"
  fi
fi

# --- 12. protections not enabled ---------------------------------------------
# P-19b: this scaffold's users typically do not read code and often ask their
# agent "run scaffold-doctor and tell me what is off" rather than reading the
# report themselves. Section 5 above already notes two of these (gitleaks
# hook, agent guardrails) mid-report; this promotes ALL of them, every
# opt-in this project could have but does not, into one clearly titled
# section near the end, so that question has one direct answer instead of a
# note to spot among many. Pure presence checks: a hand-copied file counts
# as "enabled" here, same as everywhere else in this script. Notes only,
# same contract as every note() above: this never affects exit status.
section "Protections not enabled"
PNE_ANY=0
_pne() { note "$1"; PNE_ANY=1; }
[ -f .githooks/lib/check-gitleaks ]            || _pne "gitleaks hook (local secret scan, pre-commit): not installed. Enable with install.sh --gitleaks-hook"
[ -f .github/workflows/gitleaks.yml ]          || _pne "gitleaks CI gate (unskippable secret scan): not installed. Enable with install.sh --gitleaks-ci"
[ -f .github/workflows/dependency-review.yml ] || _pne "dependency-review CI gate (blocks a PR that adds a vulnerable/malicious dependency): not installed. Enable with install.sh --dependency-review"
[ -f .github/workflows/zizmor.yml ]            || _pne "zizmor CI gate (audits your own GitHub Actions workflows): not installed. Enable with install.sh --zizmor-ci"
[ -f .github/workflows/socket-security.yml ]   || _pne "Socket Firewall CI gate (blocks a malicious/typosquat package at install time): not installed. Enable with install.sh --socket-ci"
[ -f .github/workflows/test-guard.yml ]        || _pne "test-guard CI gate (red-green: a new test must fail against the PR base before it may pass): not installed. Enable with install.sh --test-guard"
[ -f .claude/settings.json ]                   || _pne "Claude Code agent guardrails: not installed. Enable with install.sh --claude"
[ -f .cursor/hooks.json ]                      || _pne "Cursor agent guardrails: not installed. Enable with install.sh --cursor"
[ -f .githooks/commit-msg ]                    || _pne "commit-msg hook (Conventional Commits): not installed. Enable with install.sh --commit-msg"
[ -f .npmrc ]                                   || _pne "npm install-layer cooldown (.npmrc min-release-age, delays freshly published versions): not installed. Enable with install.sh --npm-cooldown"
[ -f .claude/skills/coding-rules/SKILL.md ]     || _pne "Claude Code Skill (on-demand rules loading): not installed. Enable with install.sh --claude-skill"
[ "$PNE_ANY" -eq 1 ] || ok "every opt-in protection is enabled in this project"

# --- 13. required status checks on the default branch -----------------------
# Every check above is enforced locally by the hook and server-side by CI, but
# CI only gates a merge if the branch requires it. Measured on this scaffold's
# own repo (issue #172): a protection object existed and required zero checks,
# so three release PRs merged on an agent's read of the check list, not on the
# repo's say-so. This needs the network and the gh CLI, so it is a gap only
# when it can be measured and is absent; everything else is a note that says
# what was NOT checked, never silence.
section "required status checks on the default branch"
_rsc_remote=$(git config --get remote.origin.url 2>/dev/null || true)
_rsc_repo=""
case "$_rsc_remote" in
  *github.com[:/]*) _rsc_repo=$(printf '%s' "$_rsc_remote" | sed -E 's#.*github\.com[:/]##; s#\.git$##') ;;
esac
if [ -z "$_rsc_repo" ]; then
  note "required status checks: not checked (remote.origin is not a github.com URL)"
elif ! command -v gh >/dev/null 2>&1; then
  note "required status checks: not checked (gh CLI not installed; install it and re-run, or verify in Settings > Branches)"
elif ! gh auth status >/dev/null 2>&1; then
  note "required status checks: not checked (gh is not logged in: run 'gh auth login' and re-run)"
else
  _rsc_default=$(gh api "repos/$_rsc_repo" --jq .default_branch 2>/dev/null || true)
  _rsc_ctx=$(gh api "repos/$_rsc_repo/branches/${_rsc_default:-main}/protection" --jq '.required_status_checks.contexts | length' 2>/dev/null || echo "")
  _rsc_rules=$(gh api "repos/$_rsc_repo/rules/branches/${_rsc_default:-main}" --jq '[.[] | select(.type=="required_status_checks")] | length' 2>/dev/null || echo "0")
  if [ -z "$_rsc_default" ]; then
    note "required status checks: not checked (gh could not read $_rsc_repo; permissions or network)"
  elif [ "${_rsc_ctx:-0}" -gt 0 ] 2>/dev/null || [ "${_rsc_rules:-0}" -gt 0 ] 2>/dev/null; then
    ok "$_rsc_default requires status checks before merge (${_rsc_ctx:-0} via branch protection, ${_rsc_rules:-0} ruleset rule(s))"
  else
    gap "$_rsc_repo: '$_rsc_default' requires NO status checks, so a red or unfinished CI run does not block a merge; every gate above is advisory at merge time" \
        "import .github/rulesets/main-protection.json (COMPONENTS.md entry 20), or Settings > Branches > require the guardrails check"
  fi
fi
unset _rsc_remote _rsc_repo _rsc_default _rsc_ctx _rsc_rules
