# shellcheck shell=bash
# install-interactive.sh — the --interactive/-i wizard: prompts for the
# stack and each opt-in feature toggle, then sets the exact same globals the
# flag-parsing loop in install.sh would set. Extracted to its own file
# because install.sh and install-lib.sh are both already at the scaffold's
# own 500-line cap. SOURCED (not exec'd) so it runs in install.sh's shell,
# after MODE has been auto-detected and after install-lib.sh is loaded, but
# before any file is actually written.
#
# Reads come from a dedicated fd (3), not stdin: the installer is commonly
# invoked as `curl ... | bash` or via `npx`, where stdin is already the
# script body, not a keyboard. SCAFFOLD_TTY (default /dev/tty) names the
# source; tests override it to a plain file of canned answers, one per line,
# in prompt order, so the wizard is exercised without a real terminal.
#
# --force / --no-verify / --no-install are deliberately NOT asked here: they
# govern re-run/edge-case behavior (overwrite drifted files, skip the smoke
# test, never auto-run a package manager), not "which feature do I want"
# (the actual thing this wizard replaces). Pass them as flags alongside
# --interactive if needed.
#
# Every CLAUDE/CURSOR/... assignment below is read only after install.sh
# sources this file, so shellcheck (which lints this file on its own) can't
# see the use and flags each one SC2034; same cross-file pattern already
# documented and suppressed once in install-lib.sh's TEST_CI_STATE.
# shellcheck disable=SC2034

SCAFFOLD_TTY="${SCAFFOLD_TTY:-/dev/tty}"

# _ask QUESTION DEFAULT(Y|N): prompts on stderr (so `install.sh -i >log`
# still shows the questions), reads one line from fd 3, and leaves 0/1 in
# $_ASK_ANS. An empty answer (bare Enter, or EOF) takes DEFAULT.
_ask() {
  local question=$1 default=$2 ans="" hint="y/N"
  [ "$default" = "Y" ] && hint="Y/n"
  printf '%s [%s] ' "$question" "$hint" >&2
  IFS= read -r ans <&3 || true
  [ -z "$ans" ] && ans=$default
  case "$ans" in
    [Yy]*) _ASK_ANS=1 ;;
    *)     _ASK_ANS=0 ;;
  esac
}

run_interactive() {
  if [ ! -r "$SCAFFOLD_TTY" ]; then
    echo "error: --interactive needs a terminal (no readable $SCAFFOLD_TTY)." >&2
    echo "       Pass flags explicitly instead of -i in a non-interactive shell." >&2
    exit 1
  fi
  exec 3<"$SCAFFOLD_TTY"

  echo "ai-coding-rules-scaffold: interactive install (Enter accepts [default])" >&2
  echo >&2

  _ask "Detected stack: $MODE. Use it?" Y
  if [ "$_ASK_ANS" -eq 0 ]; then
    printf 'Pick a stack (python / frontend / both / shell): ' >&2
    local pick=""
    IFS= read -r pick <&3 || true
    case "$pick" in
      python|frontend|both|shell) MODE="$pick" ;;
      *) echo "error: unrecognized stack '$pick' (want python/frontend/both/shell)" >&2; exit 1 ;;
    esac
  fi

  _ask "Install Claude Code agent guardrails (--claude)?" N;      CLAUDE=$_ASK_ANS
  _ask "Install Cursor agent guardrails (--cursor)?" N;           CURSOR=$_ASK_ANS
  _ask "Install the Conventional-Commits commit-msg hook (--commit-msg)?" N
  COMMIT_MSG=$_ASK_ANS
  _ask "Install the local gitleaks pre-commit pass (--gitleaks-hook)?" N
  GITLEAKS_HOOK=$_ASK_ANS
  _ask "Install the unskippable gitleaks CI gate (--gitleaks-ci)?" N
  GITLEAKS_CI=$_ASK_ANS
  _ask "Install the dependency-review CI gate (--dependency-review; needs GitHub Advanced Security on a private repo, or it errors)?" N
  DEPENDENCY_REVIEW=$_ASK_ANS
  _ask "Install the zizmor GitHub Actions audit gate (--zizmor-ci)?" N
  ZIZMOR_CI=$_ASK_ANS
  _ask "Install the Socket Firewall supply-chain gate (--socket-ci)?" N
  SOCKET_CI=$_ASK_ANS
  _ask "Install the red-green test-integrity gate (--test-guard; a new test must fail on the PR base before it may pass)?" N
  TEST_GUARD=$_ASK_ANS
  _ask "Install npm's min-release-age cooldown (--npm-cooldown; needs npm >=11.10)?" N
  NPM_COOLDOWN=$_ASK_ANS
  _ask "Install the on-demand Claude Code Skill (--claude-skill)?" N
  CLAUDE_SKILL=$_ASK_ANS
  _ask "Install every language's forbidden-pattern file, not just $MODE's (--all-langs)?" N
  ALL_LANGS=$_ASK_ANS

  _ask "Install a test-execution CI workflow?" Y
  if [ "$_ASK_ANS" -eq 1 ]; then
    _ask "Add a patch-coverage gate on top (--coverage-gate)?" N
    COVERAGE_GATE=$_ASK_ANS
    NO_TEST_WORKFLOW=0
  else
    COVERAGE_GATE=0
    NO_TEST_WORKFLOW=1
  fi

  exec 3<&-
  echo >&2
}
