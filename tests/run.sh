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
  "$HERE/cases/11-npm-bundle.sh"; do
  # shellcheck source=/dev/null
  . "$case_file"
done

echo ""
echo "Result: $PASS passed, $FAIL failed"
exit "$FAIL"
