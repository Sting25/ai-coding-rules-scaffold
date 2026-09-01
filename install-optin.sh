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
    echo "note: .npmrc sets min-release-age=7 (npm >=11.10.0 only; an older npm just warns and ignores the key, install still proceeds). See the template header for the 7-day choice and the 'before' interaction."
  fi
}

install_opt_in_claude_skill() {
  if [ "$CLAUDE_SKILL" -eq 1 ]; then
    cp_safe "$SCAFFOLD_DIR/claude-skill/coding-rules/SKILL.md.template" ".claude/skills/coding-rules/SKILL.md"
    echo "note: SKILL.md gives Claude Code on-demand loading of coding-rules.md / operational-rules.md, a complement to the always-loaded AGENTS.md summary (--claude installs runtime hooks instead, a different mechanism)."
  fi
}

# --test-guard (#140 item 2, red-green only): every NEW test must be shown
# failing against the PR base before it may pass. Three artifacts:
#   .githooks/lib/check-red-green   the check (scaffold-owned, refreshed)
#   .github/workflows/test-guard.yml  the PR gate (drift-preserving)
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
    cp_scaffold_preserve "$SCAFFOLD_DIR/.github/workflows/test-guard.yml.template" ".github/workflows/test-guard.yml"
    if [ -f "coding-rules.md" ] && ! grep -q 'ai-coding-rules-scaffold:test-guard:begin' "coding-rules.md" 2>/dev/null; then
      cat "$SCAFFOLD_DIR/coding-rules-test-guard.md" >>"coding-rules.md"
      echo "merged:       appended the test-guard (red-green) section to coding-rules.md (your content kept)"
    fi
    echo "note: test-guard.yml runs check-red-green on every PR: each NEW test is run against the base commit and must FAIL there. Register the exemption marker in pytest.ini under [pytest]:"
    echo "          markers ="
    echo "              characterization: passes against the base branch by design; give a reason"
    echo "      and make test-guard a REQUIRED status check on the default branch: an advisory check on a repo where the agent can also merge is a check the agent can route around."
  fi
}
