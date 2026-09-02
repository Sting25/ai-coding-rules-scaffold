#!/usr/bin/env bash
# tests/run.sh — verify the scaffold's pre-commit hook actually rejects bad
# code. Creates a throwaway git repo in a temp dir, installs the scaffold,
# stages known-bad and known-good fixtures, and asserts the hook's verdict.
# Exits non-zero on any failed assertion.
#
# Run locally:  ./tests/run.sh
# Run in CI:    same — see .github/workflows/test.yml
#
# This is a thin driver: it resolves the scaffold root, sources the shared
# library (lib/common.sh — globals, the EXIT trap, the assertion helpers, and
# the bootstrap install), then sources each cases/*.sh test-area file in order.
# Everything runs in THIS shell process, so the globals (PASS/FAIL/WORK/...) and
# helper functions stay visible to every case file. Keep the case files sourced
# (not executed) so they share that state.

set -euo pipefail

# Resolve the scaffold root the SAME way the original single-file harness did
# (run.sh lives in tests/, so the root is its parent). Export it BEFORE sourcing
# common.sh — the bootstrap install block and several cases read $SCAFFOLD_DIR.
SCAFFOLD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SCAFFOLD_DIR

HERE="$(cd "$(dirname "$0")" && pwd)"

# Shared library: globals, EXIT-trap cleanup, helpers, and the bootstrap that
# installs the scaffold into a throwaway repo and cd's into $WORK.
# shellcheck source=lib/common.sh disable=SC1091
. "$HERE/lib/common.sh"

# Bootstrap left us in $WORK; make sure every case file runs from there (some
# cases cd into their own temp dirs and cd back to "$WORK").
cd "$WORK"

# Source each test-area file in order. Order is preserved from the original
# single-file harness — some cases are order-sensitive (shared temp repo state).
for case_file in \
  "$HERE/cases/01-size-patterns.sh" \
  "$HERE/cases/02-scaffold-allow-ruff-edge.sh" \
  "$HERE/cases/03-binary-defense.sh" \
  "$HERE/cases/04-shell-config-rename.sh" \
  "$HERE/cases/05-frontend-typescript.sh" \
  "$HERE/cases/06-hygiene-multilang.sh" \
  "$HERE/cases/07-agent-commit.sh" \
  "$HERE/cases/08-overrides-gitleaks.sh" \
  "$HERE/cases/09-toolchain-clobber.sh" \
  "$HERE/cases/10-ci-diff-scope.sh" \
  "$HERE/cases/11-npm-bundle.sh" \
  "$HERE/cases/12-install-backup-cap.sh" \
  "$HERE/cases/13-devsetup-guards.sh" \
  "$HERE/cases/14-shell-install-mode.sh" \
  "$HERE/cases/15-local-checks.sh" \
  "$HERE/cases/16-coverage-gate.sh" \
  "$HERE/cases/17-whole-tree-configs.sh" \
  "$HERE/cases/18-doctor.sh" \
  "$HERE/cases/19-test-workflow.sh" \
  "$HERE/cases/20-paired-artifacts.sh" \
  "$HERE/cases/21-ci-workflow-drift.sh" \
  "$HERE/cases/22-large-file-guard.sh" \
  "$HERE/cases/23-npm-cooldown.sh" \
  "$HERE/cases/24-claude-skill.sh" \
  "$HERE/cases/25-interactive-install.sh" \
  "$HERE/cases/26-repo-adaptation-warn.sh" \
  "$HERE/cases/27-test-guard.sh" \
  "$HERE/cases/28-check-patterns-scope.sh" \
  "$HERE/cases/29-install-symlink-dirs.sh" \
  "$HERE/cases/30-install-manifest.sh" \
  "$HERE/cases/31-install-verify-offer.sh" \
  "$HERE/cases/32-uninstall-report.sh" \
  "$HERE/cases/33-harness-self-checks.sh"; do
  # shellcheck source=/dev/null
  . "$case_file"
done

# --- assertion floor -------------------------------------------------------
# "0 failed" alone cannot tell a complete run from a truncated one. A case file
# that stops early (a stray `return`, a guard that turns out false, a case
# dropped from the list above) takes its assertions with it and still prints
# "0 failed": prepending `return 0` to cases/07-agent-commit.sh silently loses
# 22 assertions and reports "Result: 372 passed, 0 failed", exit 0, green CI.
# MIN_PASS is the floor that turns a shrinking suite into a red run.
#
# The value is a MEASURED floor, taken with every optional, `command -v`-gated
# tool ABSENT from PATH (ruff, actionlint, jq, php, and a project-local
# typescript), because those legitimately skip assertions on a bare machine. A
# machine that has them reports MORE, never fewer, so this can never fire by
# luck on a complete run.
#
# BUMPING IT: adding assertions is expected to raise this number. Run the suite
# with those tools absent, read the new "Result:" count, and set MIN_PASS to it
# in the same commit that adds the assertions. Never edit it to make a red run
# green: below the floor the right question is which case stopped running.
MIN_PASS=383

echo ""
echo "Result: $PASS passed, $FAIL failed"

if [ "$PASS" -lt "$MIN_PASS" ]; then
  echo "" >&2
  echo "ERROR: only $PASS assertions ran; the floor is $MIN_PASS." >&2
  echo "       A case file stopped early or never ran. A short run reports" >&2
  echo "       '0 failed' without having proved anything, so it fails here." >&2
  exit 1
fi

# `exit "$FAIL"` would wrap: an exit status is taken mod 256, so exactly 256
# failing assertions exits 0 and CI goes green on a fully broken suite (and
# 394 would report 138). The count is already printed above; the status only
# has to answer pass/fail, so clamp it to 1.
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
