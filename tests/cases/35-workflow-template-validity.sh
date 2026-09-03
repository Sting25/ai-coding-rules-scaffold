# shellcheck shell=bash
# cases/35-workflow-template-validity.sh: EVERY shipped .github/workflows/
# *.yml.template — AND every workflow the scaffold runs on itself — must be a
# valid GitHub Actions workflow. Sourced into the driver's shell, so
# PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are already in scope.
#
# WHY ALL OF THEM. actionlint had exactly three call sites — cases/02 for
# lint.yml, cases/09 for coverage.yml, cases/19 for tests.yml — one workflow
# each, against eight shipped templates. The five with no coverage included
# test-guard.yml, whose two enforcement steps are gated on an `if:` expression:
# a workflow GitHub accepts, reports green, and runs nothing is the worst shape
# a guardrail can take. Discovering the set from a glob (rather than naming
# workflows) is the point — a ninth template is covered the moment it is added.
#
# WHY THE SCAFFOLD'S OWN WORKFLOWS TOO. `*.yml.template` matched none of
# .github/workflows/{shellcheck,test,self-lint,release,zizmor,dependency-review}
# .yml, so the six workflows that actually gate this repo's merges were
# validated by nothing at all. That is not hypothetical: a rewrite of the
# discovery step in shellcheck.yml shipped a `run:` block that aborted under
# `set -e` before it ever invoked the linter, and no check in the tree looked at
# that file. actionlint would not have caught that particular bug either (see
# the honest limits below), but "no test even opens these files" is its own
# hole, and it is the one that let the bug through.
#
# WHAT actionlint ACTUALLY BUYS, measured rather than assumed. It resolves
# context expressions (`github.*`, `steps.*`, `needs.*`) and their types, `if:`
# syntax, `runs-on` labels, workflow/job/step key names, cron and glob syntax,
# and action input/output names for actions it knows. It does NOT know the
# output names of a `run:` step in your own workflow: a step that writes
# `present` to $GITHUB_OUTPUT and is read as `steps.detect.outputs.presnt`
# lints clean — that typo class is confirmed uncovered here, and remains the
# argument for asserting on workflow BEHAVIOUR (cases/19, 21, 27) rather than
# treating a green actionlint as proof a workflow does its job.
#
# zizmor in test.yml does render all eight templates, but it is a SECURITY
# auditor: SHA pins, permissions, persist-credentials. It does not evaluate
# Actions expression or `if:` semantics, so it is not a substitute for this.
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
# Actions semantics, not the shell inside `run:` blocks — the shellcheck.yml
# workflow and the repo's own linters own that.

echo "cases/35: every shipped workflow template — and the scaffold's own workflows — is valid"

_wt_templates=("$SCAFFOLD_DIR"/.github/workflows/*.yml.template)
_wt_own=("$SCAFFOLD_DIR"/.github/workflows/*.yml)
[ -e "${_wt_templates[0]}" ] || _wt_templates=()
[ -e "${_wt_own[0]}" ] || _wt_own=()
_wt_total=$(( ${#_wt_templates[@]} + ${#_wt_own[@]} ))

if [ "${#_wt_templates[@]}" -eq 0 ] || [ "${#_wt_own[@]}" -eq 0 ]; then
  # An unexpanded glob would otherwise make this whole case a silent no-op —
  # the same failure mode the case exists to remove. Both halves are asserted
  # separately so losing one class cannot hide behind the other's count.
  echo "  ✗ workflow discovery is empty (${#_wt_templates[@]} template(s), ${#_wt_own[@]} own workflow(s)) — the scaffold ships none, or a glob broke"
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
  # The scaffold's own workflows are linted where they live: they reference each
  # other and the repo's real paths, so copying them elsewhere would change the
  # check.
  for _wt_tpl in "${_wt_own[@]}"; do
    _wt_name=$(basename "$_wt_tpl")
    if ( cd "$SCAFFOLD_DIR" && actionlint -shellcheck= -pyflakes= ".github/workflows/$_wt_name" ) >"$HOOK_OUT" 2>&1; then
      echo "  ✓ .github/workflows/$_wt_name (the scaffold's own CI) is a valid workflow"
      PASS=$((PASS + 1))
    else
      echo "  ✗ .github/workflows/$_wt_name failed actionlint — the scaffold's own gate is malformed"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
  done
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  # test.yml installs a pinned, checksum-verified actionlint before running
  # this suite, so absent-in-CI means that step broke or moved — go red rather
  # than skip $_wt_total workflow validations behind a green run.
  echo "  ✗ actionlint not installed: $_wt_total workflows (${#_wt_templates[@]} shipped templates + ${#_wt_own[@]} of the scaffold's own) cannot be validated in CI (see the 'Install actionlint' step in test.yml)"
  FAIL=$((FAIL + 1))
else
  echo "  - SKIP: actionlint not installed — $_wt_total workflow(s) were NOT validated (CI installs it; locally, install actionlint to run this guard)"
  SKIP=$((SKIP + _wt_total))
fi
unset _wt_templates _wt_own _wt_total _wt_tpl _wt_name _wt_dir

# The release gate must be the PR gate, not a copy of it. release.yml once
# carried its own bare `./tests/run.sh` with none of test.yml's tool installs;
# it passed while the runner counted only passes and went red on the v0.16.0
# tag the first time floors counted attempted assertions (#161). Runs without
# actionlint: it is a structural check on the file, not a lint.
if grep -Eq '^\s+uses: \./\.github/workflows/test\.yml\s*$' "$SCAFFOLD_DIR/.github/workflows/release.yml" \
   && grep -Eq '^\s+workflow_call:\s*$' "$SCAFFOLD_DIR/.github/workflows/test.yml"; then
  echo "  ✓ release.yml gates the tag on the same test.yml job every PR runs (workflow_call)"
  PASS=$((PASS + 1))
else
  echo "  ✗ release.yml does not call test.yml: the release gate is a private copy of the suite run and will drift from the PR gate again"
  FAIL=$((FAIL + 1))
fi
