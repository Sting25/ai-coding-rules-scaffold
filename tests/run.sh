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

# A third outcome alongside PASS/FAIL, for an assertion that could not run
# because an OPTIONAL external tool is absent (actionlint, pytest). Those arms
# used to print a lone "- skipped ..." line that vanished into 500 lines of ✓,
# leaving a run where a whole guard never executed indistinguishable from a run
# where it passed. Counting them surfaces the fact in the one line everyone
# reads. Cases that never skip anything simply leave it at 0.
SKIP=0

# Bootstrap left us in $WORK; make sure every case file runs from there (some
# cases cd into their own temp dirs and cd back to "$WORK").
cd "$WORK"

# The test-area files, in order. Order is preserved from the original
# single-file harness — some cases are order-sensitive (shared temp repo state)
# — so this stays an explicit ordered list rather than a `cases/*.sh` glob.
CASE_FILES=(
  01-size-patterns.sh
  02-scaffold-allow-ruff-edge.sh
  03-binary-defense.sh
  04-shell-config-rename.sh
  05-frontend-typescript.sh
  06-hygiene-multilang.sh
  07-agent-commit.sh
  08-overrides-gitleaks.sh
  09-toolchain-clobber.sh
  10-ci-diff-scope.sh
  11-npm-bundle.sh
  12-install-backup-cap.sh
  13-devsetup-guards.sh
  14-shell-install-mode.sh
  15-local-checks.sh
  16-coverage-gate.sh
  17-whole-tree-configs.sh
  18-doctor.sh
  19-test-workflow.sh
  20-paired-artifacts.sh
  21-ci-workflow-drift.sh
  22-large-file-guard.sh
  23-npm-cooldown.sh
  24-claude-skill.sh
  25-interactive-install.sh
  26-repo-adaptation-warn.sh
  27-test-guard.sh
  28-shipped-pattern-files.sh
  29-workflow-template-validity.sh
  30-red-green-verdict.sh
)

# REGISTRATION GUARD. The list above is hand-ordered, and nothing used to
# reconcile it with the directory — so a new cases/28-*.sh was a SILENT no-op:
# the shellcheck workflow lints `tests/cases/*.sh` by GLOB, so a new file went
# green as valid bash and looked wired up while not one of its assertions ever
# ran. The same silence hides a line lost from this list in a merge conflict: a
# whole case file dropping out only lowers PASS while FAIL stays 0, which is
# indistinguishable from a clean run. Reconcile in BOTH directions and abort
# before any case executes.
registered=$(printf '%s\n' "${CASE_FILES[@]}" | sort)
ondisk=$(cd "$HERE/cases" && printf '%s\n' *.sh | sort)
if [ "$registered" != "$ondisk" ]; then
  echo "tests/run.sh: cases/ and CASE_FILES disagree — every tests/cases/*.sh must be registered above." >&2
  comm -23 <(printf '%s\n' "$ondisk") <(printf '%s\n' "$registered") \
    | sed 's|^|  on disk but NOT registered, so it never runs: cases/|' >&2
  comm -13 <(printf '%s\n' "$ondisk") <(printf '%s\n' "$registered") \
    | sed 's|^|  registered but missing from cases/: |' >&2
  exit 1
fi

for case_file in "${CASE_FILES[@]}"; do
  # shellcheck source=/dev/null
  . "$HERE/cases/$case_file"
done

echo ""
echo "Result: $PASS passed, $FAIL failed, $SKIP skipped"
exit "$FAIL"
