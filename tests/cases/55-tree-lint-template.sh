# shellcheck shell=bash
# cases/55-tree-lint-template.sh: the opt-in whole-tree lint workflow (#217).
# Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and the
# fixture_* helpers are in scope.
#
# The template is advisory by design, so its shape is the contract: it runs on a
# schedule and on push, never on pull_request; only the report job may write
# issues; the file list comes from `git ls-files` (never a directory walk, so
# gitignored content stays out, #76); the tracking issue is found by label. A
# plain install must not create it, and --tree-lint must.

echo "cases/55: opt-in whole-tree lint workflow (advisory, one tracking issue)"

TL_TPL="$SCAFFOLD_DIR/.github/workflows/lint-tree.yml.template"

# Non-comment lines only, so the header prose cannot satisfy or trip a check.
TL_CODE=$(grep -v '^[[:space:]]*#' "$TL_TPL")

tl_ok() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
tl_bad() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# (a) triggers: schedule and push, never pull_request
if printf '%s\n' "$TL_CODE" | grep -q '^  schedule:' \
   && printf '%s\n' "$TL_CODE" | grep -q '^  push:' \
   && ! printf '%s\n' "$TL_CODE" | grep -q 'pull_request'; then
  tl_ok "lint-tree.yml.template triggers on schedule and push, with no pull_request"
else
  tl_bad "lint-tree.yml.template must have schedule: and push: triggers and no pull_request"
fi

# (b) issues: write only on the report job (workflow level stays contents: read)
tl_report_perms=$(printf '%s\n' "$TL_CODE" | awk '/^  report:/ { inb = 1 } inb')
tl_before_report=$(printf '%s\n' "$TL_CODE" | awk '/^  report:/ { exit } { print }')
if [ "$(printf '%s\n' "$TL_CODE" | grep -c 'issues: write')" -eq 1 ] \
   && printf '%s\n' "$tl_report_perms" | grep -q 'issues: write' \
   && ! printf '%s\n' "$tl_before_report" | grep -q 'issues: write'; then
  tl_ok "issues: write appears once, on the report job only"
else
  tl_bad "issues: write must appear exactly once, inside the report job"
fi

# (c) whole-tree file list from git ls-files; label-based issue lookup
if printf '%s\n' "$TL_CODE" | grep -q 'git -c core.quotepath=off ls-files -z' \
   && printf '%s\n' "$TL_CODE" | grep -q 'lint-baseline'; then
  tl_ok "the file list comes from git ls-files and the tracking issue is found by the lint-baseline label"
else
  tl_bad "expected 'git -c core.quotepath=off ls-files -z' and the lint-baseline label in the template"
fi

# (d) no github.event.* interpolation in the template body (template injection)
if ! printf '%s\n' "$TL_CODE" | grep -q 'github\.event\.'; then
  tl_ok "no github.event.* expression is interpolated anywhere"
else
  tl_bad "lint-tree.yml.template must not reference github.event.*"
fi

# (e) a plain install does not create it; --tree-lint does
fixture_repo TL_A
echo '{"name":"x"}' >"$TL_A/package.json"
fixture_install "$TL_A" --frontend --no-verify
fixture_repo TL_B
echo '{"name":"x"}' >"$TL_B/package.json"
fixture_install "$TL_B" --frontend --no-verify --tree-lint
if [ ! -e "$TL_A/.github/workflows/lint-tree.yml" ] \
   && cmp -s "$TL_TPL" "$TL_B/.github/workflows/lint-tree.yml"; then
  tl_ok "a plain install does not create lint-tree.yml; --tree-lint installs the shipped template"
else
  tl_bad "lint-tree.yml must be absent on a plain install and identical to the template under --tree-lint"
fi
rm -rf "$TL_A" "$TL_B"
