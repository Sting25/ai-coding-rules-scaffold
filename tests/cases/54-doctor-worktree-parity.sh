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
#   (e) a .prettierrc.json.template is not a prettier config: no note
#   (f) eslint declared in devDependencies but not installed is a note
#   (g) a pyproject name that is code is never executed (no PWNED file)
#   (h) a venv whose .pth points at another checkout is a note; one pointing here is not
#   (i) a name that is not importable and has no package directory is no note

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
  # WP_IGNORE: note lines to disregard (a pyproject fixture also trips the unrelated ruff note)
  sect=$(grep -v -E "${WP_IGNORE:-^\$}" <<<"$sect" || true)
  if [ -n "${WP_NOFILE:-}" ] && [ -e "$t/$WP_NOFILE" ]; then ok=0; fi
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

# (e) the hook's prettier predicate: a .template file is not a config (no node_modules here).
if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
  wp_prettier_template() { echo '{}' >package.json; echo '{}' >.prettierrc.json.template; }
  wp_case "a .prettierrc.json.template is not a prettier config" "" wp_prettier_template
  # (f) eslint declared, not installed
  wp_eslint_declared() { echo '{"devDependencies":{"eslint":"^9.0.0"}}' >package.json; }
  wp_case "eslint declared but not installed is a note" "eslint is not installed in this worktree" wp_eslint_declared
else
  echo "  - skipped the prettier/eslint cases (node or npx not on PATH)"; SKIP=$((SKIP + 1))
fi

# (g)-(i) the project name is data, never code; need a python3 to act as the venv interpreter.
if command -v python3 >/dev/null 2>&1; then
  wp_fake_venv() { mkdir -p .venv/bin && ln -s "$(command -v python3)" .venv/bin/python; }
  wp_inject() {
    printf '[project]\nname = "os;open('"'"'PWNED'"'"','"'"'w'"'"')#"\n' >pyproject.toml
    wp_fake_venv
  }
  WP_IGNORE='ruff is not|pytest is not' WP_NOFILE=PWNED
  wp_case "a pyproject name that is code is not executed, and no note" "" wp_inject
  WP_NOFILE=""
  wp_namespace() { printf '[project]\nname = "ns-thing" # c\n' >pyproject.toml; wp_fake_venv; }
  wp_case "a non-importable name with no package directory is no note" "" wp_namespace
  # (h) a real (pip-less) venv whose .pth names a checkout
  wp_pth_venv() {
    printf '[project]\nname = "demo"\n' >pyproject.toml
    mkdir -p src/demo && : >src/demo/__init__.py
    python3 -m venv --without-pip .venv >/dev/null 2>&1 || return 0
    printf '%s\n' "$WP_PTH" >"$(echo .venv/lib/python*/site-packages)/demo.pth"
  }
  wp_pth_outside() { WP_PTH=$WP_OTHER/src wp_pth_venv; }
  wp_pth_inside()  { WP_PTH=$PWD/src wp_pth_venv; }
  WP_OTHER=$(mktemp -d); mkdir -p "$WP_OTHER/src/demo"; : >"$WP_OTHER/src/demo/__init__.py"
  wp_case "a venv importing the project from another checkout is a note" "outside this worktree" wp_pth_outside
  wp_case "a venv importing the project from this worktree is no note" "" wp_pth_inside
  rm -rf "$WP_OTHER"
  WP_IGNORE=""
else
  echo "  - skipped the venv import cases (no python3 on PATH)"; SKIP=$((SKIP + 1))
fi
