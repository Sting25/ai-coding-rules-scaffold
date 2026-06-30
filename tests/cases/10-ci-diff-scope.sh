# shellcheck shell=bash
# cases/10-ci-diff-scope.sh — verify lib/ci-changed-files scopes CI to the
# PR/push diff, and that lint.yml's guardrails two-scope split behaves: a fresh
# install onto a repo with LEGACY violations must NOT retroactively fail them
# (size/patterns/hygiene are diff-scoped), while NEW violations and any
# committed secret/.env ARE still caught (secrets/filenames stay whole-tree).
# Sourced into the driver's shell, so it shares PASS/FAIL and runs under -euo
# pipefail. This is the regression guard for the diff-scoping behavior — the
# logic lives in a committed lib script precisely so it can be tested here
# (rather than as untestable bash inside the workflow YAML).

# shellcheck disable=SC2164
cd "$WORK"
C10=$(mktemp -d)

# Build a synthetic project: scaffold install, a LEGACY baseline, then a feature
# branch adding NEW violations (legacy left untouched). `yes | head` makes the
# 600-line files without depending on python being present.
(
  cd "$C10"
  git init -q
  git config user.email test@test.local
  git config user.name "Scaffold Test"
  echo '{"name":"x"}' >package.json
  echo 'name = "x"' >pyproject.toml
  "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null
  git add -A && git commit -q -m scaffold --no-verify          # scaffold-allow: test fixture
  printf 'legacy_x = 1\n%.0s' {1..600} >legacy_big.py         # size > 500 (no pipe → pipefail-safe)
  printf 'def legacy():\n    print("legacy debug")\n' >legacy_debug.py   # backend.txt: print(
  # Split the literal in THIS source so self-lint's whole-tree secret scan
  # doesn't flag this test file; the printf reassembles the full key at runtime
  # into legacy_secret.py, which is what the scan under test must catch.
  printf 'AWS = "%s"\n' "AKIA""IOSFODNN7EXAMPLE" >legacy_secret.py   # secrets.txt: AKIA…
  printf 'FOO=bar\n' >.env                                     # check-filenames: .env
  git add -A && git commit -q -m base --no-verify             # scaffold-allow: test fixture
  git checkout -q -b feature
  printf 'new_y = 1\n%.0s' {1..600} >new_big.py               # size > 500 (no pipe → pipefail-safe)
  printf 'def fresh():\n    print("new debug")\n' >new_debug.py  # backend.txt: print(
  printf '# docs only\n' >notes.md                            # .md → ignored
  git add -A && git commit -q -m feat --no-verify            # scaffold-allow: test fixture
) >"$HOOK_OUT" 2>&1

HEAD=$(git -C "$C10" rev-parse feature 2>/dev/null || true)
BASE=$(git -C "$C10" rev-parse feature^ 2>/dev/null || true)   # base = feature's parent
ZERO=0000000000000000000000000000000000000000

# Print the helper's NUL list as a newline list for an EVENT + (a,b) rev pair.
# Both PR_* and PUSH_* are set to (a,b); the helper reads only the pair its
# EVENT selects, so this one shape drives every scenario.
changed_list() {
  ( cd "$C10" \
    && EVENT=$1 PR_BASE_SHA=${2:-} PR_HEAD_SHA=${3:-} PUSH_BEFORE=${2:-} PUSH_AFTER=${3:-} \
       bash .githooks/lib/ci-changed-files ) 2>/dev/null | tr '\0' '\n' || true
}
in_list()  { grep -qxF "$2" <<<"$1"; }   # whole-line literal match (here-string → no SIGPIPE)

echo "cases/10 — CI diff-scoping (lib/ci-changed-files)"

if [ -z "$BASE" ] || [ -z "$HEAD" ]; then
  echo "  ✗ setup failed (no feature history)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
else
  # (1) pull_request → only the new files, legacy excluded
  PR=$(changed_list pull_request "$BASE" "$HEAD")
  if in_list "$PR" new_big.py && in_list "$PR" new_debug.py; then
    echo "  ✓ ci-changed-files(PR) lists new files"; PASS=$((PASS + 1))
  else echo "  ✗ ci-changed-files(PR) missing new files"; printf '%s\n' "$PR" | sed 's/^/      /'; FAIL=$((FAIL + 1)); fi
  if in_list "$PR" legacy_big.py || in_list "$PR" legacy_debug.py; then
    echo "  ✗ ci-changed-files(PR) leaked legacy into diff"; FAIL=$((FAIL + 1))
  else echo "  ✓ ci-changed-files(PR) excludes legacy"; PASS=$((PASS + 1)); fi

  # (2) push (before=base, after=head) → same as PR
  PUSH=$(changed_list push "$BASE" "$HEAD")
  if in_list "$PUSH" new_big.py && ! in_list "$PUSH" legacy_big.py; then
    echo "  ✓ ci-changed-files(push) scopes to the pushed range"; PASS=$((PASS + 1))
  else echo "  ✗ ci-changed-files(push) wrong scope"; printf '%s\n' "$PUSH" | sed 's/^/      /'; FAIL=$((FAIL + 1)); fi

  # (3) fallback: zero before-SHA (brand-new repo) → whole tree
  FB=$(changed_list push "$ZERO" "$HEAD")
  if in_list "$FB" legacy_big.py && in_list "$FB" new_big.py; then
    echo "  ✓ ci-changed-files(fallback) scans whole tree"; PASS=$((PASS + 1))
  else echo "  ✗ ci-changed-files(fallback) did not fall open"; printf '%s\n' "$FB" | sed 's/^/      /'; FAIL=$((FAIL + 1)); fi

  # (4) unrecognized event → fail open to whole tree
  WD=$(changed_list workflow_dispatch "$BASE" "$HEAD")
  if in_list "$WD" legacy_big.py; then
    echo "  ✓ ci-changed-files(unknown event) fails open to whole tree"; PASS=$((PASS + 1))
  else echo "  ✗ ci-changed-files(unknown event) did not fail open"; printf '%s\n' "$WD" | sed 's/^/      /'; FAIL=$((FAIL + 1)); fi

  # (5) INTEGRATION — mirror the guardrails job's two scopes and assert the split.
  (
    cd "$C10"
    export EVENT=pull_request PR_BASE_SHA=$BASE PR_HEAD_SHA=$HEAD PUSH_BEFORE='' PUSH_AFTER=''
    ALL=$(mktemp); git -c core.quotepath=off ls-files -z >"$ALL"
    CH=$(mktemp);  bash .githooks/lib/ci-changed-files >"$CH"
    .githooks/lib/check-size      --ci <"$CH"  || true
    .githooks/lib/check-patterns  --ci <"$CH"  || true
    .githooks/lib/check-secrets   --ci <"$ALL" || true
    .githooks/lib/check-filenames --ci <"$ALL" || true
  ) >"$WORK/c10.int" 2>&1 || true

  if grep -qF new_big.py "$WORK/c10.int" && grep -qF new_debug.py "$WORK/c10.int"; then
    echo "  ✓ guardrails flags NEW size + pattern violations"; PASS=$((PASS + 1))
  else echo "  ✗ guardrails missed new violations"; sed 's/^/      /' "$WORK/c10.int"; FAIL=$((FAIL + 1)); fi
  if grep -qF legacy_big.py "$WORK/c10.int" || grep -qF legacy_debug.py "$WORK/c10.int"; then
    echo "  ✗ guardrails failed legacy code (not grandfathered)"; sed 's/^/      /' "$WORK/c10.int"; FAIL=$((FAIL + 1))
  else echo "  ✓ guardrails grandfathers LEGACY size + pattern violations"; PASS=$((PASS + 1)); fi
  if grep -qF legacy_secret.py "$WORK/c10.int"; then
    echo "  ✓ guardrails catches committed SECRET whole-tree (unchanged legacy)"; PASS=$((PASS + 1))
  else echo "  ✗ guardrails missed the committed secret"; sed 's/^/      /' "$WORK/c10.int"; FAIL=$((FAIL + 1)); fi
  if grep -qF .env "$WORK/c10.int"; then
    echo "  ✓ guardrails catches committed .env whole-tree (filenames)"; PASS=$((PASS + 1))
  else echo "  ✗ guardrails missed the .env"; sed 's/^/      /' "$WORK/c10.int"; FAIL=$((FAIL + 1)); fi
fi

rm -rf "$C10"; rm -f "$WORK/c10.int"
cd "$WORK"
