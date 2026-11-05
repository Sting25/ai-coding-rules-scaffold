# shellcheck shell=bash
# cases/54-doctor-worktree-parity.sh: scaffold-doctor's advisory "worktree
# parity" section (#211). Notes only: each case also requires the gap count to
# stay where it was (0, or the one section-1 gap in case b). Sourced into the driver's shell, so
# PASS/FAIL/SKIP/HOOK_OUT/SCAFFOLD_DIR are in scope. Fixtures are scratch repos
# under mktemp -d; no git worktree is created.
#   (a) the plain install prints no parity note
#   (b) a core.hooksPath outside the repo prints the hooksPath note
#   (c) a node_modules/.package-lock.json that differs from the lockfile
#   (d) requires-python above the gate interpreter prints the interpreter note

echo "cases/54: doctor worktree parity (advisory)"

# wp_case <name> <expect-substring or ""> <mutation cmd...>
# An empty expectation means "the parity section must print no note at all".
wp_case() {
  local name=$1 expect=$2 t rc=0 sect
  shift 2
  fixture_repo t
  echo '#!/usr/bin/env bash' >"$t/run.sh"
  fixture_install "$t" --shell --no-verify
  ( cd "$t" && "$@" ) >/dev/null 2>&1 || true
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || rc=$?
  sect=$(sed -n '/^worktree parity/,$p' "$HOOK_OUT")
  local want_gaps=${WP_WANT_GAPS:-0} ok=1
  [ "$rc" -eq "${WP_WANT_RC:-0}" ] || ok=0
  if [ "$want_gaps" -eq 0 ]; then
    grep -q ' 0 gaps' "$HOOK_OUT" || ok=0
  else
    grep -q "^✗ $want_gaps guardrail" "$HOOK_OUT" || ok=0
  fi
  if [ -z "$expect" ]; then
    ! grep -q '^  !' <<<"$sect" || ok=0
  else
    grep -qF -- "$expect" <<<"$sect" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "  ✓ $name"; PASS=$((PASS + 1))
  else
    echo "  ✗ $name (exit $rc, wanted ${WP_WANT_RC:-0} with $want_gaps gap(s), expect: ${expect:-no parity note})"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  rm -rf "$t"
}

wp_hookspath()  { git config core.hooksPath /some/absolute/elsewhere/.githooks; }
wp_stale_nm() {
  mkdir -p node_modules
  printf '{"packages":{"":{"name":"x"},"node_modules/left-pad":{"version":"1.3.0"}}}' >package-lock.json
  printf '{"packages":{"node_modules/left-pad":{"version":"1.2.0"}}}' >node_modules/.package-lock.json
}
wp_requires_py() { printf '[project]\nname = "demo"\nrequires-python = ">=3.99"\n' >pyproject.toml; }

wp_case "a plain install prints no parity note" "" true

# (b) A hooksPath elsewhere is already section 1's gap (1, exactly), so this
# case expects exit 1 with ONE gap: the parity section adds a note, not a second.
WP_WANT_RC=1; WP_WANT_GAPS=1
wp_case "hooksPath outside the worktree adds a note and no extra gap" "outside this worktree" wp_hookspath
WP_WANT_RC=0; WP_WANT_GAPS=0

# (c) needs node or python3 with json to compare; the check itself skips otherwise.
if command -v node >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  wp_case "node_modules that differs from the lockfile is a note" "do not match the lockfile; run npm ci" wp_stale_nm
else
  echo "  - skipped the lockfile case (neither node nor python3 on PATH)"; SKIP=$((SKIP + 1))
fi

# (d) the interpreter is python3 on PATH; skip when there is none.
if command -v python3 >/dev/null 2>&1; then
  wp_case "requires-python above the interpreter is a note" "below pyproject.toml's requires-python >=3.99" wp_requires_py
else
  echo "  - skipped the requires-python case (no python3 on PATH)"; SKIP=$((SKIP + 1))
fi
