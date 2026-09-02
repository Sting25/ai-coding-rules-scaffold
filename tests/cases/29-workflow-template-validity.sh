# shellcheck shell=bash
# cases/29-workflow-template-validity.sh: EVERY shipped .github/workflows/
# *.yml.template must be a valid GitHub Actions workflow. Sourced into the
# driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are already in scope.
#
# WHY ALL OF THEM. actionlint had exactly three call sites — cases/02 for
# lint.yml, cases/09 for coverage.yml, cases/19 for tests.yml — one workflow
# each, against eight shipped templates. The five with no coverage included
# test-guard.yml, whose two enforcement steps are gated on
# `if: steps.detect.outputs.present == 'true'`: precisely the expression/`if:`
# class of error that makes GitHub accept the file, report the job green, and
# run nothing. A required status check that passes while executing no steps is
# the worst shape a guardrail can take, and nothing in this repo would have
# noticed. Discovering the set from the glob (rather than naming workflows) is
# the point — a ninth template is covered the moment it is added.
#
# zizmor in test.yml does render all eight, but it is a SECURITY auditor: SHA
# pins, permissions, persist-credentials. It does not evaluate Actions
# expression or `if:` semantics, so it is not a substitute for this.
#
# WHY THE SKIP IS LOUD. The three original sites each ended in a bare
# `echo "  - skipped ... (actionlint not installed)"`, one line among hundreds
# of ✓. If the actionlint install step in test.yml is ever renamed, reordered or
# put behind a condition, that arm makes the entire guard evaporate with the
# suite still printing all-green. So: absent locally is a SKIP that is COUNTED
# and shows up in the driver's final Result line; absent under $GITHUB_ACTIONS
# is a hard FAIL, the same #85 rule tests/lib/eslint-syntax-check.sh:40 applies
# to a missing node.
#
# `-shellcheck= -pyflakes=` matches the existing call sites: this guard is about
# Actions semantics, not the shell inside `run:` blocks (shellcheck.yml and the
# repo's own linters own that).

echo "cases/29: every shipped workflow template is a valid GitHub Actions workflow"

_wt_templates=("$SCAFFOLD_DIR"/.github/workflows/*.yml.template)
if [ ! -e "${_wt_templates[0]}" ]; then
  # An unexpanded glob would otherwise make this whole case a silent no-op —
  # the same failure mode the case exists to remove.
  echo "  ✗ no .github/workflows/*.yml.template found — the scaffold ships none, or the glob broke"
  FAIL=$((FAIL + 1))
elif command -v actionlint >/dev/null 2>&1; then
  # Render every template into ONE workspace first: actionlint resolves
  # workflow-level references against the directory it is given, so linting a
  # file in isolation is not the same check the consumer's repo gets.
  _wt_dir=$(mktemp -d)
  mkdir -p "$_wt_dir/.github/workflows"
  for _wt_tpl in "${_wt_templates[@]}"; do
    cp "$_wt_tpl" "$_wt_dir/.github/workflows/$(basename "$_wt_tpl" .template)"
  done
  for _wt_tpl in "${_wt_templates[@]}"; do
    _wt_name=$(basename "$_wt_tpl" .template)
    if ( cd "$_wt_dir" && actionlint -shellcheck= -pyflakes= ".github/workflows/$_wt_name" ) >"$HOOK_OUT" 2>&1; then
      echo "  ✓ $_wt_name.template is a valid GitHub Actions workflow"
      PASS=$((PASS + 1))
    else
      echo "  ✗ $_wt_name.template failed actionlint — GitHub would accept it and run less than it claims"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
  done
  rm -rf "$_wt_dir"
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  # test.yml installs a pinned, checksum-verified actionlint before running
  # this suite, so absent-in-CI means that step broke or moved — go red rather
  # than skip ${#_wt_templates[@]} workflow validations behind a green run.
  echo "  ✗ actionlint not installed: ${#_wt_templates[@]} shipped workflow templates cannot be validated in CI (see the 'Install actionlint' step in test.yml)"
  FAIL=$((FAIL + 1))
else
  echo "  - SKIP: actionlint not installed — ${#_wt_templates[@]} shipped workflow template(s) were NOT validated (CI installs it; locally, install actionlint to run this guard)"
  SKIP=$((SKIP + ${#_wt_templates[@]}))
fi
unset _wt_templates _wt_tpl _wt_name _wt_dir
