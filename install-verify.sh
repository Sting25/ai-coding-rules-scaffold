# shellcheck shell=bash
# install-verify.sh — the post-install toolchain check.
#
# The scaffold ships CONFIGS and ENFORCEMENT; the actual tools
# (ruff/eslint/tsc/prettier/test runner/shellcheck) are project dependencies.
# This module detects what is missing and OFFERS to install it.
#
# SOURCED (not exec'd) by install.sh, exactly like install-lib.sh, so it runs in
# that shell with its globals (MODE, VERIFY, NO_INSTALL) and its `set -euo
# pipefail`. It was extracted from install.sh because that file had reached 497
# of the scaffold's own 500-line module-size cap (issue #84) — the cap is
# dogfooded, so the installer has to obey it like every other module.
#
# Defaults mirror install-lib.sh's `: "${FORCE:=0}"` so this file still behaves
# if it is ever sourced without install.sh having set the globals first.
: "${MODE:=both}"
: "${VERIFY:=1}"
: "${NO_INSTALL:=0}"

# Set by run_toolchain_verify, read by offer. Deliberately a global, not a
# local: offer is a sibling function, so dynamic scope is what carries it.
CAN_AUTORUN=0

# Detect the project's package manager from lockfiles / available binaries.
js_install_cmd() {
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then echo "pnpm add -D"
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then echo "yarn add -D"
  else echo "npm i -D"; fi
}
py_install_cmd() {
  if { [ -f uv.lock ] || grep -qs '\[tool.uv\]' pyproject.toml 2>/dev/null; } && command -v uv >/dev/null 2>&1; then
    echo "uv add --dev"
  else echo "pip install"; fi
}

# offer <label> <presence-test-command> <install-base> <packages>
# Prints ✓ when present; otherwise offers to install (auto-run only if safe).
offer() {
  local label=$1 testcmd=$2 base=$3 pkgs=$4 reply
  if eval "$testcmd" >/dev/null 2>&1; then
    echo "  ✓ $label installed"
    return
  fi
  if [ "$CAN_AUTORUN" -eq 1 ]; then
    printf "  ? %s not installed — install now with '%s %s'? [y/N] " "$label" "$base" "$pkgs"
    read -r reply || reply=""
    case "$reply" in
      [yY]|[yY][eE][sS])
        # shellcheck disable=SC2086  # word-split the package list deliberately
        if $base $pkgs; then echo "  ✓ $label installed"; else echo "  ✗ $label install failed — run: $base $pkgs"; fi ;;
      *) echo "  - skipped — run: $base $pkgs" ;;
    esac
  else
    echo "  ! $label not installed — run: $base $pkgs"
  fi
}

# run_toolchain_verify — the whole post-install check, called once by install.sh
# after the "Done" line. Auto-running a package manager only happens when SAFE:
# interactive TTY, not --no-verify, not in CI, and --no-install not set.
# Otherwise it just prints the command (the scaffold's prior, non-mutating
# behavior) so CI and piped/scripted runs never install.
run_toolchain_verify() {
  CAN_AUTORUN=0
  if [ "$VERIFY" -eq 1 ] && [ "$NO_INSTALL" -eq 0 ] && [ -t 0 ] && [ -z "${CI:-}" ]; then
    CAN_AUTORUN=1
  fi

  if [ "$VERIFY" -eq 1 ]; then
    echo ""
    echo "Checking toolchain (the scaffold configures these; you supply the binaries):"
    case "$MODE" in
      python|both)
        PYI=$(py_install_cmd)
        offer "ruff" "command -v ruff" "$PYI" "ruff"
        # ruff present: also confirm the config actually loads (2+ = config error).
        if command -v ruff >/dev/null 2>&1; then
          ruff_exit=0; ruff check --quiet . >/dev/null 2>&1 || ruff_exit=$?
          [ "$ruff_exit" -ge 2 ] && echo "  ✗ ruff config errored (exit $ruff_exit) — check ruff.toml"
        fi
        offer "pytest + coverage" "command -v pytest" "$PYI" "pytest pytest-cov"
        ;;
    esac
    case "$MODE" in
      frontend|both)
        JSI=$(js_install_cmd)
        offer "eslint" "npx --no-install eslint --version" "$JSI" "eslint @eslint/js @eslint/compat typescript-eslint eslint-plugin-import-x eslint-plugin-unused-imports"
        offer "typescript (tsc)" "npx --no-install tsc --version" "$JSI" "typescript"
        offer "prettier" "npx --no-install prettier --version" "$JSI" "prettier"
        offer "vitest" "npx --no-install vitest --version" "$JSI" "vitest @vitest/coverage-v8"
        # The 'frontend' CI job loads eslint.config.js (and its plugins) from the
        # lockfile. If you skip the eslint prompt above, that job fails with an
        # actionable error until you install the deps AND commit the lockfile.
        echo "  → commit package-lock.json after installing eslint deps, or CI's frontend job will fail."
        ;;
    esac
    case "$MODE" in
      shell)
        # Print-only, never an auto-install offer. `offer` runs a package manager,
        # and shellcheck has no single canonical one across platforms
        # (brew/apt/dnf/cargo/pkg all differ) — unlike ruff (pip) and eslint (npm),
        # where the manifest we just detected names the installer unambiguously.
        if command -v shellcheck >/dev/null 2>&1; then
          echo "  ✓ shellcheck installed"
        else
          echo "  ! shellcheck not installed — see https://www.shellcheck.net (brew install shellcheck / apt install shellcheck)"
        fi
        ;;
    esac
  fi
}
