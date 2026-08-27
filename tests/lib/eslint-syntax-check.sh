#!/usr/bin/env bash
# tests/lib/eslint-syntax-check.sh: syntax check for eslint.config.js.template,
# extracted from cases/17-whole-tree-configs.sh (#111 / #85) so it can be
# mutation-tested as a subprocess, the same way check-gitleaks is tested in
# cases/08: run it under a curated PATH with node removed and assert on its
# exit code and output, instead of trying to mutate an inline block that is
# sourced into the whole test driver's shell.
#
# The template is ESM with imports, so it is syntax-checked as .mjs; a syntax
# error here means every consumer's eslint fails to load. This is the only
# syntax check on the shipped template, and test.yml has no setup-node step,
# so it currently relies on the runner image happening to ship node. A missing
# node LOCALLY is a silent skip, but a missing node in CI (GITHUB_ACTIONS set)
# is a hard FAILURE (#85) rather than a silent skip: if the runner ever stops
# shipping node, this must go red instead of quietly stop running.
#
# Usage: eslint-syntax-check.sh <path-to-eslint.config.js.template>
# Exit: 0 = valid syntax, or a clean skip (node absent, not CI).
#       1 = a syntax error, or node absent under GITHUB_ACTIONS (#85).

set -euo pipefail

TPL=${1:?usage: eslint-syntax-check.sh <path-to-eslint.config.js.template>}

if command -v node >/dev/null 2>&1; then
  DIR=$(mktemp -d)
  ESM="$DIR/eslint.config.mjs"
  OUT=$(mktemp)
  cp "$TPL" "$ESM"
  if node --check "$ESM" >"$OUT" 2>&1; then
    echo "  ✓ eslint.config.js.template is syntactically valid ESM"
    rm -rf "$DIR" "$OUT"
    exit 0
  else
    echo "  ✗ eslint.config.js.template has a syntax error"
    sed 's/^/      /' "$OUT"
    rm -rf "$DIR" "$OUT"
    exit 1
  fi
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "  ✗ node not installed: eslint config syntax check cannot run in CI (#85)"
  exit 1
else
  echo "  - skipped eslint config syntax check (node not installed)"
  exit 0
fi
