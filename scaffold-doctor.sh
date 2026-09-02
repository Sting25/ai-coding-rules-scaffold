#!/usr/bin/env bash
# scaffold-doctor.sh — is this project's scaffold ARMED, or merely installed?
#
# install.sh reports what it WROTE. That is a different question from whether
# the guardrails actually RUN, and the gap between the two is where this
# scaffold's worst bugs have lived: issue #76 was a `grep -r` that silently
# scanned one file instead of a tree, and issue #72 was a check whose call site
# got reset on upgrade while the check script stayed on disk as decoration.
# Both were PRESENT and both were NOT RUNNING, and nothing said so.
#
# So this script never reports "file exists". It reports, for each guardrail,
# whether the thing that makes it execute is in place:
#
#   ✓  armed        — it runs, and it has the data it needs to do work
#   ✗  gap          — installed but inert; a commit that should be blocked isn't
#   !  note         — deliberate off-switch, or optional surface not opted into
#
# Exit status: 0 when there are no gaps, 1 when there are, 2 on usage error.
# Notes never affect the exit status — a project that never opted into gitleaks
# is healthy, and a doctor that cried wolf about it would stop being read.
set -euo pipefail

# CDPATH is inherited from the caller's environment and makes `cd` ECHO the
# directory it landed in, on stdout, where `2>/dev/null` cannot suppress it. The
# wiring check below resolves two paths with `$(cd ... && pwd -P)`; a relative
# `cd .githooks` gets the echo prepended and an absolute one does not, so the
# two resolved paths stop matching and a correctly wired project is reported as
# a hard gap, exit 1. Measured: `CDPATH=. scaffold-doctor.sh --quiet` turned a
# clean "0 gaps" into a false [wiring] gap for both the absolute and the
# `./.githooks` spelling of core.hooksPath.
unset CDPATH

usage() {
  cat <<'USAGE'
usage: scaffold-doctor.sh [--quiet]

Checks that an installed project's scaffold guardrails are armed, not just
present. Run it from anywhere inside the project's git working tree.

  --quiet   print only gaps and the summary line
  -h        this message

Exit: 0 = no gaps, 1 = at least one guardrail installed but not running,
      2 = usage error / not a git repository.
USAGE
}

QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scaffold-doctor: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Captured BEFORE any cd: this is where scaffold-doctor.sh itself lives (the
# npm package root, the Homebrew libexec dir, or a git clone), which is also
# where install-lib.sh ships alongside it in all three distribution paths.
# Used by the "paired artifacts" section below to reuse install.sh's own
# detection logic instead of duplicating it.
SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"

# The shipped checks read their config by BARE RELATIVE PATH
# (".forbidden-patterns/secrets.txt", ".scaffold.toml"), which works because git
# invokes hooks from the top of the working tree. A doctor run from a
# subdirectory has to reproduce that or it would report phantom gaps.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "✗ not a git repository — run scaffold-doctor from inside the project" >&2
  exit 2
fi
cd "$ROOT"

GAPS=0
NOTES=0
OKS=0
SECTION=""

section() { SECTION=$1; [ "$QUIET" -eq 1 ] || printf '\n%s\n' "$1"; }
ok()   { OKS=$((OKS + 1));   [ "$QUIET" -eq 1 ] || echo "  ✓ $1"; }
note() { NOTES=$((NOTES + 1)); [ "$QUIET" -eq 1 ] || echo "  ! $1"; }
# note_always <what-is-half-armed> — a note that --quiet may not swallow.
# --quiet exists so a CI step or a pre-flight script can print gaps and nothing
# else, and most notes are "you never opted into this", which such a caller
# genuinely does not need. A guardrail that IS installed and has been switched
# off or half-wired is the opposite: it is the one state where the summary line
# "armed, N check(s) running, 0 gaps" is actively misleading, and hiding it is
# how a project ends up believing a cap is enforcing something it no longer
# enforces. Counted like any other note, so it still never affects exit status.
note_always() {
  NOTES=$((NOTES + 1))
  if [ "$QUIET" -eq 1 ]; then echo "  ! [$SECTION] $1"; else echo "  ! $1"; fi
}
# gap <what-is-inert> [how-to-fix] — the fix line is not decoration: a report
# that tells you something is broken without telling you the command that arms
# it gets acknowledged and not acted on.
gap() {
  GAPS=$((GAPS + 1))
  if [ "$QUIET" -eq 1 ]; then echo "  ✗ [$SECTION] $1"; else echo "  ✗ $1"; fi
  if [ $# -gt 1 ]; then echo "      fix: $2"; fi
}

[ "$QUIET" -eq 1 ] || echo "scaffold-doctor — $ROOT"

# --- 1. wiring --------------------------------------------------------------
# The single highest-value check in this file. Everything else can be perfect
# and none of it runs if git is not pointed at .githooks. install.sh sets
# core.hooksPath only when it is unset or already .githooks; when a project
# already uses Husky (or anything else) install.sh writes .githooks/ anyway and
# only WARNS, so "installed but never wired" is a state install.sh can leave
# behind by design.
section "wiring"
HOOKS_PATH=$(git config --get core.hooksPath || true)
# Compare RESOLVED directories, not strings. git accepts `.githooks`,
# `./.githooks`, `.githooks/` and an absolute path interchangeably, and runs the
# hook in every one of those spellings — measured. A string equality test calls
# three working configurations broken, and a hard gap on a healthy project is
# worse than a missed note: it teaches the reader to distrust the report.
# `cd` failing (a hooksPath that points nowhere) leaves the value empty, which
# correctly falls through to the gap branch.
HOOKS_ABS=""
GITHOOKS_ABS=$(cd .githooks 2>/dev/null && pwd -P) || true
if [ -n "$HOOKS_PATH" ]; then
  HOOKS_ABS=$(cd "$HOOKS_PATH" 2>/dev/null && pwd -P) || true
fi
if [ -n "$HOOKS_ABS" ] && [ -n "$GITHOOKS_ABS" ] && [ "$HOOKS_ABS" = "$GITHOOKS_ABS" ]; then
  ok "core.hooksPath = $HOOKS_PATH"
elif [ -z "$HOOKS_PATH" ]; then
  gap "core.hooksPath is unset — git runs .git/hooks, so nothing in .githooks/ executes" \
      "git config core.hooksPath .githooks"
else
  gap "core.hooksPath = '$HOOKS_PATH' — .githooks/ is on disk but git never runs it" \
      "git config core.hooksPath .githooks   (or wire the scaffold hook into '$HOOKS_PATH')"
fi

# --- 2. hook entry point ----------------------------------------------------
# git silently ignores a hook file without the executable bit. No error, no
# warning, no commit blocked — the exact failure mode this script exists for.
section "hook entry point"
if [ ! -f .githooks/pre-commit ]; then
  gap ".githooks/pre-commit is missing — the scaffold is not installed here" \
      "run the scaffold's install.sh from this directory"
elif [ ! -x .githooks/pre-commit ]; then
  gap ".githooks/pre-commit is not executable — git skips it silently" \
      "chmod +x .githooks/pre-commit"
else
  ok ".githooks/pre-commit present and executable"
fi
if [ -f .githooks/commit-msg ] && [ ! -x .githooks/commit-msg ]; then
  gap ".githooks/commit-msg is not executable — git skips it silently" \
      "chmod +x .githooks/commit-msg"
fi

# --- 3. the shipped checks --------------------------------------------------
# The orchestrator calls these six unguarded, so a missing or non-executable
# one makes the hook error out and BLOCK the commit — noisy, not silent, but
# still broken, and worth naming precisely rather than leaving to a stack trace.
#
# Present and executable is still not the same as RUNNING, which is the whole
# premise of this script and was the one thing this section did not test. Issue
# #72 is exactly that shape: an upgrade preserved a customized
# .github/workflows/lint.yml whose check-large-files call site was never there,
# the script stayed on disk, and this report said "lib/check-large-files armed
# ... 0 gaps" while an 800 KB file committed clean. So each check is now matched
# against its CALLERS too.
#
# check_called_in NAME FILE... — is NAME invoked in any of those files?
# Comment lines are stripped first: every one of these files discusses the
# checks by name in its own header, and a header is not a call site. The name
# must match as a whole word so one check's name cannot satisfy another's.
check_called_in() {
  local name=$1
  shift
  local re="(^|[^A-Za-z0-9_.-])${name}([^A-Za-z0-9_.-]|\$)" f body
  for f in "$@"; do
    [ -f "$f" ] || continue
    body=$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null || true)
    if grep -qE "$re" <<<"$body"; then
      return 0
    fi
  done
  return 1
}
section "shipped checks"
for chk in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene; do
  if [ ! -f ".githooks/lib/$chk" ]; then
    gap "lib/$chk is missing — the hook calls it unguarded and every commit will error" \
        "re-run install.sh to restore it"
  elif [ ! -x ".githooks/lib/$chk" ]; then
    gap "lib/$chk is not executable — every commit will error on it" "chmod +x .githooks/lib/$chk"
  elif ! check_called_in "$chk" .githooks/pre-commit .githooks/commit-msg \
                         .githooks/local.d/* .github/workflows/*.yml; then
    gap "lib/$chk is installed and executable but nothing calls it — no invocation in .githooks/pre-commit or .github/workflows/, so it is decoration and the commits it should block are not blocked (issue #72)" \
        "re-run install.sh to restore the call sites, then re-apply any customization you had made to the hook or workflow"
  elif [ -f .github/workflows/lint.yml ] && ! check_called_in "$chk" .github/workflows/*.yml; then
    # Half-wired, not inert: the hook still runs it locally, so this is a note
    # rather than a gap. But --no-verify, a push from a machine without the
    # hooks wired, and a web-UI edit all reach main with nobody having run it,
    # which is what makes it worth saying out loud even under --quiet.
    note_always "lib/$chk runs in the pre-commit hook but NO CI call site invokes it — a --no-verify commit or a push from an unwired clone reaches main unchecked (issue #72)"
  else
    ok "lib/$chk armed"
  fi
done
# The opt-in checks arrive only with their flag, so absence is not a gap. Once
# one IS on disk the same rule applies: a check nothing calls is decoration,
# whichever flag installed it.
for chk_path in .githooks/lib/check-*; do
  [ -f "$chk_path" ] || continue
  chk=$(basename "$chk_path")
  case "$chk" in
    check-size|check-large-files|check-patterns|check-filenames|check-secrets|check-hygiene) continue ;;
  esac
  if ! check_called_in "$chk" .githooks/pre-commit .githooks/commit-msg \
                       .githooks/local.d/* .github/workflows/*.yml; then
    gap "lib/$chk is installed but nothing calls it — no invocation in .githooks/ or .github/workflows/, so it never runs" \
        "re-run install.sh with the flag that installed it, to restore its call site"
  fi
done

# --- 4. pattern data --------------------------------------------------------
# check-patterns auto-discovers .forbidden-patterns/*.txt. If the directory is
# gone the glob matches nothing, the loop body never runs, and the scanner exits
# 0 — a full pattern scanner reporting success while scanning nothing.
section "pattern data"
if [ ! -d .forbidden-patterns ]; then
  gap ".forbidden-patterns/ is missing — check-patterns scans nothing and still exits 0" \
      "re-run install.sh to restore the pattern files"
else
  # secrets.txt is the non-disableable boundary. check-secrets exits 0 SILENTLY
  # when it is absent locally (leniency for pre-install checkouts), so absence
  # here is a live hole rather than a loud failure.
  if [ ! -f .forbidden-patterns/secrets.txt ]; then
    gap "secrets.txt is missing — check-secrets exits 0 silently on every local commit" \
        "re-run install.sh to restore .forbidden-patterns/secrets.txt"
  else
    # Count only ACTIVE patterns: blank lines and comments carry no rule. The
    # `(?-i)` case-sensitivity marker (issue #67) sits inside a pattern line, so
    # it does not need stripping to be counted.
    active=$(grep -cvE '^[[:space:]]*(#|$)' .forbidden-patterns/secrets.txt || true)
    if [ "${active:-0}" -eq 0 ]; then
      gap "secrets.txt has no active patterns — the secret scanner is disabled" \
          "restore its patterns, or re-run install.sh"
    else
      ok "secrets.txt armed ($active active patterns)"
    fi
  fi
  # Every other pattern file needs an extension mapping or check-patterns prints
  # a warning to stderr and skips it — and hook stderr scrolls past unread.
  for cfg in .forbidden-patterns/*.txt; do
    [ -e "$cfg" ] || continue
    base=$(basename "$cfg")
    case "$base" in secrets.txt) continue ;; esac
    hdr=$(grep -m1 -E '^#[[:space:]]*scaffold-extensions:' "$cfg" 2>/dev/null || true)
    case "$base" in
      backend.txt|frontend.txt|shell.txt) hdr=${hdr:-builtin} ;;
    esac
    if [ -z "$hdr" ]; then
      gap "$base has no '# scaffold-extensions:' header and no built-in mapping — check-patterns skips it" \
          "add '# scaffold-extensions: <ext> ...' as a comment line in $cfg"
    else
      pat=$(grep -cvE '^[[:space:]]*(#|$)' "$cfg" || true)
      if [ "${pat:-0}" -eq 0 ]; then
        note "$base has no active patterns — it scans its file types and matches nothing"
      else
        ok "$base armed ($pat active patterns)"
      fi
    fi
  done
fi

# --- 5. opt-in surfaces -----------------------------------------------------
# Both fail OPEN when their external tool is absent, but they are NOT equally
# quiet, and the severity follows that difference rather than the symmetry:
#
#   check-gitleaks  prints an actionable note on every single commit and names
#                   the CI gitleaks job as the authoritative gate. The developer
#                   is already being told, so this is a note. Making it a gap
#                   would mean the doctor exits 1 forever on any machine without
#                   the binary — crying wolf about a self-announcing condition.
#   agent-precheck  exits 0 with EMPTY output when jq is missing. Nothing,
#                   anywhere, ever says so. That is a gap — as is losing its
#                   executable bit, since its callers exec the path directly
#                   and read exit 126 as "not blocked" (check-gitleaks differs:
#                   the hook's own -x guard makes that bit a real off switch).
#
# Measured, not assumed: run each with PATH narrowed to /usr/bin:/bin.
section "opt-in surfaces"
if [ -f .githooks/lib/check-gitleaks ]; then
  if [ ! -x .githooks/lib/check-gitleaks ]; then
    note "lib/check-gitleaks is not executable — the hook's -x guard skips it (off switch)"
  elif command -v gitleaks >/dev/null 2>&1; then
    ok "lib/check-gitleaks armed (gitleaks on PATH)"
  else
    note "lib/check-gitleaks is installed but gitleaks is not on PATH — the local scan is a no-op (it says so on every commit; CI is the authoritative gate)"
  fi
else
  note "gitleaks hook not installed (opt in with install.sh --gitleaks-hook)"
fi
if [ -f .githooks/lib/agent-precheck ]; then
  if [ ! -x .githooks/lib/agent-precheck ]; then
    # Unlike check-gitleaks, nothing guards this call with -x. Both
    # claude-settings.json and cursor-hooks.json invoke the path DIRECTLY as a
    # command, so a missing executable bit yields exit 126 — and the agent
    # runtimes block only on exit 2, so 126 is allowed through. Measured: the
    # tool call proceeds and nothing is printed anywhere.
    gap "lib/agent-precheck is not executable — the agent runtime gets exit 126, not the exit 2 that blocks, so the tool call proceeds" \
        "chmod +x .githooks/lib/agent-precheck"
  elif command -v jq >/dev/null 2>&1; then
    ok "lib/agent-precheck armed (jq on PATH)"
  else
    gap "lib/agent-precheck is installed but jq is not on PATH — it exits 0 on every agent edit" \
        "install jq (brew install jq)"
  fi
else
  note "agent guardrails not installed (opt in with install.sh --claude or --cursor)"
fi

# --- 6. project-local checks ------------------------------------------------
# In local.d/ the executable bit IS the on/off switch, so a non-executable entry
# is a deliberate state, not a defect — reported, never counted as a gap.
section "project-local checks"
if [ ! -d .githooks/local.d ]; then
  note "no .githooks/local.d/ — project-local checks not in use"
else
  found=0
  for lc in .githooks/local.d/*; do
    [ -f "$lc" ] || continue
    case "$(basename "$lc")" in README.md) continue ;; esac
    found=$((found + 1))
    if [ -x "$lc" ]; then ok "local.d/$(basename "$lc") armed"
    else note "local.d/$(basename "$lc") present but not executable (that bit is the off switch)"; fi
  done
  [ "$found" -gt 0 ] || note ".githooks/local.d/ is empty — no project-local checks"
fi

# --- 7. per-project overrides -----------------------------------------------
# scaffold-config fails open to empty output when it is missing, and empty
# output means "no override" — so a .scaffold.toml full of intentional
# overrides is silently ignored, in the direction of stricter, which is the
# hardest kind of silence to notice.
section "per-project overrides"
if [ ! -f .scaffold.toml ]; then
  note "no .scaffold.toml — every rule runs at its shipped default"
elif [ ! -x .githooks/lib/scaffold-config ]; then
  gap ".scaffold.toml exists but lib/scaffold-config is missing or not executable — every override in it is silently ignored" \
      "re-run install.sh to restore .githooks/lib/scaffold-config"
else
  ok ".scaffold.toml readable and lib/scaffold-config armed"
  if [ -x .githooks/lib/scaffold-audit ] && [ "$QUIET" -eq 0 ]; then
    .githooks/lib/scaffold-audit 2>/dev/null | sed 's/^/      /' || true
  fi
fi

# --- 8. paired artifacts -----------------------------------------------------
# Some guardrails ship as two halves that only work together: a config file
# plus the CI workflow that reads it, or a local pre-commit pass plus the CI
# gate it defers to. install.sh writes both halves together, but an
# interrupted install, a later re-run without a flag, or a hand-copied file
# can leave only one half on disk (#96), and once that happens, nothing
# checks again. Detection lives in install-lib.sh's check_paired_artifacts so
# install.sh's own end-of-run summary reports the exact same states with the
# exact same wording; sourced here rather than duplicated.
section "paired artifacts"
if [ -f "$SCAFFOLD_DIR/install-lib.sh" ]; then
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, by name, from check_paired_artifacts (SC2317 on older shellcheck, SC2329 on newer, same underlying finding)
  doctor_pair_note() { note "$1"; }
  # shellcheck source=install-lib.sh
  . "$SCAFFOLD_DIR/install-lib.sh"
  check_paired_artifacts gap doctor_pair_note
else
  note "install-lib.sh not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): paired-artifact checks skipped; re-fetch the full scaffold bundle, not just this one file"
fi

# --- 9. protections not enabled ----------------------------------------------
# P-19b: this scaffold's users typically do not read code and often ask their
# agent "run scaffold-doctor and tell me what is off" rather than reading the
# report themselves. Section 5 above already notes two of these (gitleaks
# hook, agent guardrails) mid-report; this promotes ALL of them, every
# opt-in this project could have but does not, into one clearly titled
# section near the end, so that question has one direct answer instead of a
# note to spot among many. Pure presence checks: a hand-copied file counts
# as "enabled" here, same as everywhere else in this script. Notes only,
# same contract as every note() above: this never affects exit status.
section "Protections not enabled"
PNE_ANY=0
_pne() { note "$1"; PNE_ANY=1; }
[ -f .githooks/lib/check-gitleaks ]            || _pne "gitleaks hook (local secret scan, pre-commit): not installed. Enable with install.sh --gitleaks-hook"
[ -f .github/workflows/gitleaks.yml ]          || _pne "gitleaks CI gate (unskippable secret scan): not installed. Enable with install.sh --gitleaks-ci"
[ -f .github/workflows/dependency-review.yml ] || _pne "dependency-review CI gate (blocks a PR that adds a vulnerable/malicious dependency): not installed. Enable with install.sh --dependency-review"
[ -f .github/workflows/zizmor.yml ]            || _pne "zizmor CI gate (audits your own GitHub Actions workflows): not installed. Enable with install.sh --zizmor-ci"
[ -f .github/workflows/socket-security.yml ]   || _pne "Socket Firewall CI gate (blocks a malicious/typosquat package at install time): not installed. Enable with install.sh --socket-ci"
[ -f .github/workflows/test-guard.yml ]        || _pne "test-guard CI gate (red-green: a new test must fail against the PR base before it may pass): not installed. Enable with install.sh --test-guard"
[ -f .claude/settings.json ]                   || _pne "Claude Code agent guardrails: not installed. Enable with install.sh --claude"
[ -f .cursor/hooks.json ]                      || _pne "Cursor agent guardrails: not installed. Enable with install.sh --cursor"
[ -f .githooks/commit-msg ]                    || _pne "commit-msg hook (Conventional Commits): not installed. Enable with install.sh --commit-msg"
[ -f .npmrc ]                                   || _pne "npm install-layer cooldown (.npmrc min-release-age, delays freshly published versions): not installed. Enable with install.sh --npm-cooldown"
[ -f .claude/skills/coding-rules/SKILL.md ]     || _pne "Claude Code Skill (on-demand rules loading): not installed. Enable with install.sh --claude-skill"
[ "$PNE_ANY" -eq 1 ] || ok "every opt-in protection is enabled in this project"

# --- summary ----------------------------------------------------------------
echo ""
if [ "$GAPS" -eq 0 ]; then
  echo "✓ armed: $OKS check(s) running, $NOTES note(s), 0 gaps."
  exit 0
fi
echo "✗ $GAPS guardrail(s) installed but NOT running ($OKS armed, $NOTES note(s))."
exit 1
