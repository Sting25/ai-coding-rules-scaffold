# shellcheck shell=bash
# install-optin.sh — the install_opt_in_* flag bodies, SOURCED by install.sh
# (like install-lib.sh / install-verify.sh, so they run with FORCE and the
# flag globals in scope).
#
# Why a third module: install.sh is pinned at the scaffold's own 500-line
# module cap (issue #84), which is why these bodies first moved into
# install-lib.sh; install-lib.sh then reached the same cap, and the fix for a
# file at the cap is extraction, not a size exemption ("fix the file, not the
# guardrail"). Every future install_opt_in_* body lands here.
#
# install_test_workflow_ci (#97) landed here the same way and for the same
# reason: it is a per-flag install body, not one of install-lib.sh's file-write
# policy helpers, and install-lib.sh hit the cap again when the install manifest
# was added. Nothing but install.sh ever called it, so the move is a pure
# relocation. print_not_enabled_summary followed it for the same reason and
# fits even better: it is the end-of-run report of which OPT-IN protections
# this project does not have, so it belongs beside the flag bodies that turn
# them on.
#
# Copy policy per function (see install-lib.sh's header for the helpers):
# zizmor / socket / test-guard workflows use cp_scaffold_preserve (CI
# workflows, drift-preserving, #110/#113 policy); npm-cooldown (#117) and
# claude-skill (#118) use cp_safe instead: .npmrc and SKILL.md are USER-OWNED
# (a project may hand-edit either), not scaffold-owned CI, the same policy as
# ruff.toml / .scaffold.toml. test-guard's check-red-green is scaffold-owned
# hook code (cp_scaffold + mkx, refreshed on upgrade like every other
# .githooks/lib scanner).

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

install_opt_in_npm_cooldown() {
  if [ "$NPM_COOLDOWN" -eq 1 ]; then
    cp_safe "$SCAFFOLD_DIR/.npmrc.template" ".npmrc"
    # A pre-existing .npmrc is skipped by cp_safe, and the note below would then
    # state a setting that is not in the file (audit code-install-policy-1).
    warn_unwired_optin ".npmrc" min-release-age "$SCAFFOLD_DIR/.npmrc.template"
    if ! _optin_wired .npmrc min-release-age; then
      return 0
    fi
    echo "note: .npmrc sets min-release-age=7 (npm >=11.10.0 only; an older npm just warns and ignores the key, install still proceeds). See the template header for the 7-day choice and the 'before' interaction."
  fi
}

install_opt_in_claude_skill() {
  if [ "$CLAUDE_SKILL" -eq 1 ]; then
    cp_safe "$SCAFFOLD_DIR/claude-skill/coding-rules/SKILL.md.template" ".claude/skills/coding-rules/SKILL.md"
    echo "note: SKILL.md gives Claude Code on-demand loading of coding-rules.md / operational-rules.md, a complement to the always-loaded AGENTS.md summary (--claude installs runtime hooks instead, a different mechanism)."
  fi
}

# --test-guard (#140 item 2, red-green, plus the advisory mutation layer
# from #145): every NEW test must be shown failing against the PR base
# before it may pass, and the lines a PR changed must kill at least one
# mutant. Four artifacts:
#   .githooks/lib/check-red-green       the red-green check (scaffold-owned,
#                                        refreshed)
#   .githooks/lib/check-mutation-diff   the mutation check (scaffold-owned,
#                                        refreshed; needs no local tooling,
#                                        CI installs mutmut==3.7.0 itself)
#   .github/workflows/test-guard.yml    the PR gate running both
#                                        (drift-preserving)
#   a rules section appended once to coding-rules.md (user-owned, so
#   append-if-marker-absent, same pattern as install-claude.sh's CLAUDE.md
#   merge; a plain re-run never appends twice, and uninstall leaves it, like
#   every other edit to a user-owned file)
# The characterization marker must reach pytest.ini by hand: pytest.ini is
# cp_safe (user-owned), so the installer prints the snippet instead of
# editing the file.
install_opt_in_test_guard() {
  if [ "$TEST_GUARD" -eq 1 ]; then
    cp_scaffold "$SCAFFOLD_DIR/githooks/lib/check-red-green.template" ".githooks/lib/check-red-green"
    mkx ".githooks/lib/check-red-green"
    cp_scaffold "$SCAFFOLD_DIR/githooks/lib/check-mutation-diff.template" ".githooks/lib/check-mutation-diff"
    mkx ".githooks/lib/check-mutation-diff"
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template" ".github/workflows/test-guard.yml"
    if [ -f "coding-rules.md" ] && ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "coding-rules.md" 2>/dev/null; then
      cat "$SCAFFOLD_DIR/coding-rules-test-guard.md" >>"coding-rules.md"
      echo "merged:       appended the test-guard (red-green) section to coding-rules.md (your content kept)"
    fi
    echo "note: test-guard.yml runs check-red-green on every PR: each NEW test is run against the base commit and must FAIL there. Register the exemption marker in pytest.ini under [pytest]:"
    echo "          markers ="
    echo "              characterization: passes against the base branch by design; give a reason"
    echo "      It also runs check-mutation-diff, an advisory mutation-testing layer scoped to the PR's changed lines: surviving mutants print a warning but never fail the job (advisory-first, issue #145). CI installs mutmut==3.7.0 itself, nothing to add locally."
    echo "      and make test-guard a REQUIRED status check on the default branch: an advisory check on a repo where the agent can also merge is a check the agent can route around."
  fi
}

# install_test_workflow_ci, the test-execution CI workflow (#97): DEFAULT-ON,
# exactly one of two shapes, plus a recorded opt-out. Extracted here (like
# install-verify.sh's run_toolchain_verify) once install.sh neared its own
# 500-line cap; reads the caller's globals (NO_TEST_WORKFLOW, COVERAGE_GATE,
# SCAFFOLD_DIR) and sets TEST_CI_STATE for the caller's end-of-run summary.
# A default install used to produce lint-only CI (green checks, zero tests
# ever executing), the bug this closes. Three end states, decided in order:
# (1) --no-test-workflow installs NEITHER workflow, the one way a repo ends
# up with no test execution in CI, and it must say so loudly per
# operational-rules.md's "record every skip" (unless a workflow from a prior
# run is already on disk, which keeps running either way); (2) --coverage-gate
# (or coverage.yml already on disk) installs coverage.yml, which already runs
# the tests AND gates patch coverage of changed lines, not assertion quality,
# see RECOMMENDATIONS.md; (3) default installs tests.yml: pytest/vitest run on
# every PR/push, no coverage threshold. Never both: coverage.yml already runs
# the tests, so tests.yml alongside it would double-run the suite; an upgrade
# that adds --coverage-gate on top of a prior default retires an untouched
# tests.yml rather than leaving it to double-run. Both files go through
# cp_scaffold_preserve, not cp_scaffold (#110): a re-run finding either file
# changed from the shipped version keeps it and prints "note (drift):"
# instead of refreshing, same policy as lint.yml since #105.
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
# _pne_wired FILE NEEDLE LABEL ENABLE_CMD FIX — one summary line for an opt-in
# whose config file can exist WITHOUT the protection wired into it. THREE
# states, not two: absent (install it), present but not wired (merge it), wired
# (say nothing). The two-state presence check reported a stub .claude/
# settings.json, .cursor/hooks.json or .npmrc as an enabled protection and left
# all three off this list entirely, so the one reader this summary exists for,
# an agent relaying it to its user, was told everything was on (audit
# code-install-policy-1). Returns 0 when it printed a line, so the caller can
# set `any`.
_pne_wired() {
  local file=$1 needle=$2 label=$3 cmd=$4 fix=$5
  if _optin_wired "$file" "$needle"; then
    return 1
  fi
  if [ -e "$file" ]; then
    echo "  - $label: PRESENT BUT NOT ARMED. $file exists and does not mention '$needle', so nothing runs. Fix: $fix"
  else
    echo "  - $label: not enabled. Enable with $cmd"
  fi
  return 0
}

# warn_unwired_optin FILE NEEDLE TEMPLATE — printed right after the cp_safe that
# may have SKIPPED a pre-existing config. "skip (exists)" is accurate but
# incomplete: the flag the user just passed did nothing, and the protection they
# asked for is not armed. Say which, and how to fix it, at the moment it happens.
warn_unwired_optin() {
  local file=$1 needle=$2 tpl=$3
  if [ -e "$file" ] && ! _optin_wired "$file" "$needle"; then
    echo "warning: $file exists but does not mention '$needle', so this protection is NOT armed."
    echo "         Merge the relevant keys from $tpl into it by hand. --force would replace your file instead."
  fi
}

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
  _pne_wired .npmrc min-release-age \
    "npm install-layer cooldown (.npmrc min-release-age, delays freshly published versions)" \
    "./install.sh --npm-cooldown" \
    "add the min-release-age line from .npmrc.template to it" && any=1
  [ -f .claude/skills/coding-rules/SKILL.md ]    || { echo "  - Claude Code Skill (on-demand rules loading): not enabled. Enable with ./install.sh --claude-skill"; any=1; }
  _pne_wired .claude/settings.json agent-precheck \
    "Claude Code agent guardrails" "./install.sh --claude" \
    "merge the hooks block from claude-settings.json.template into it" && any=1
  _pne_wired .cursor/hooks.json agent-precheck \
    "Cursor agent guardrails" "./install.sh --cursor" \
    "merge the hooks block from cursor-hooks.json.template into it" && any=1
  [ -f .githooks/commit-msg ]                    || { echo "  - commit-msg hook (Conventional Commits): not enabled. Enable with ./install.sh --commit-msg"; any=1; }
  if [ "$any" -eq 0 ]; then
    echo "  (none: every opt-in protection above is already enabled in this project)"
  fi
  echo ""
  echo "Check what is armed at any time: ./scaffold-doctor.sh, or 'npx ai-coding-rules-scaffold doctor' if you did not clone this repo."
}
