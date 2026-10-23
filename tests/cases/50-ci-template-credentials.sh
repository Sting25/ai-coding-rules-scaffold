# shellcheck shell=bash
# cases/50-ci-template-credentials.sh: the token each shipped CI template hands
# to the step that needs it (#195, #196). Sourced into the driver's shell, so
# PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR are in scope. Helpers are prefixed ct_.
#
# Both defects only show on a PRIVATE repo, so the scaffold's own (public) CI
# never saw them and actionlint cannot: the YAML is valid, the credentials are
# just missing.
#   #195  gitleaks-action lists the PR's commits through the API on a
#         pull_request event; with `contents: read` alone that is a 403.
#   #196  coverage.yml's diff-cover step ran `git fetch` after a checkout with
#         persist-credentials: false, so on a private repo it died with exit 128.
#         The checkout already fetched full history, so the fetch is now skipped
#         when origin/$GITHUB_BASE_REF exists and otherwise carries its own
#         one-command token.

echo "cases/50: CI templates carry the credentials their steps need (gitleaks pull-requests: read #195, coverage base-ref fetch #196)"

CT_GL="$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template"
CT_COV="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"

# --- (A) gitleaks: job-level pull-requests: read, workflow level stays minimal ---
# Indent tells the two apart: the workflow-level block is 2 spaces deep, the
# job-level one 6.
for ct_f in "$CT_GL" "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml"; do
  if grep -qx '      pull-requests: read' "$ct_f" && ! grep -q '^  pull-requests:' "$ct_f" \
     && [ "$(grep -c 'pull-requests:' "$ct_f")" -eq 1 ]; then
    echo "  ✓ ${ct_f#"$SCAFFOLD_DIR"/}: pull-requests: read is granted at job level only"; PASS=$((PASS + 1))
  else
    echo "  ✗ ${ct_f#"$SCAFFOLD_DIR"/}: expected exactly one 'pull-requests: read', at job level (gitleaks-action 403s on a private repo without it)"; FAIL=$((FAIL + 1))
  fi
done
