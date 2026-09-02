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
# If dirname(1) is NOT on PATH (the narrowed PATH tests/cases/18-doctor.sh runs
# this script under), the substitution is empty, `cd ""` is a no-op, and this
# lands on the PROJECT directory instead. Every template comparison below then
# finds no template; the notes in sections 8 and 10 say so out loud rather than
# skipping in silence, which is the part that matters.

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
# note_always <what-is-half-armed>: a note that --quiet may not swallow.
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
# check_called_in NAME FILE... (is NAME invoked in any of those files?)
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
    gap "lib/$chk is installed and executable but nothing calls it: no invocation in .githooks/pre-commit or .github/workflows/, so it is decoration and the commits it should block are not blocked (issue #72)" \
        "re-run install.sh to restore the call sites, then re-apply any customization you had made to the hook or workflow"
  elif [ -f .github/workflows/lint.yml ] && ! check_called_in "$chk" .github/workflows/*.yml; then
    # Half-wired, not inert: the hook still runs it locally, so this is a note
    # rather than a gap. But --no-verify, a push from a machine without the
    # hooks wired, and a web-UI edit all reach main with nobody having run it,
    # which is what makes it worth saying out loud even under --quiet.
    note_always "lib/$chk runs in the pre-commit hook but NO CI call site invokes it: a --no-verify commit or a push from an unwired clone reaches main unchecked (issue #72)"
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
    gap "lib/$chk is installed but nothing calls it: no invocation in .githooks/ or .github/workflows/, so it never runs" \
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
  # Baseline drift. Counting active patterns (above) only catches the file
  # gutted to ZERO — the one state no realistic hand-edit produces. Deleting
  # all but one of secrets.txt's rules leaves "armed (1 active patterns)" on
  # screen while the AWS-key, JWT, PEM and hardcoded-credential rules are gone,
  # and every other layer agrees: check-secrets fails closed only at zero, and
  # pre-commit's DELETED_CONFIG guard only fires on whole-file deletion. These
  # files are cp_pattern — scaffold-shipped but user-EXTENDED — so extra local
  # rules are expected and healthy; only rules that were SHIPPED and are now
  # absent are reported. Compared on the pattern column (tab-separated field 1)
  # so a reworded description is not drift. A scaffold UPGRADE that adds new
  # shipped rules lands here too, and correctly so: from this project's side
  # "rules the scaffold ships that this repo does not run" is one state with
  # one fix, whether it was reached by deleting them or by never merging them.
  # A doctor copied out of the bundle on its own has nothing to compare against
  # and would skip every file below in total silence — the same failure the
  # paired-artifacts section already names out loud, and one this check must not
  # inherit quietly: "no drift reported" would then mean "not looked at".
  if [ -d .forbidden-patterns ] && [ ! -d "$SCAFFOLD_DIR/forbidden-patterns" ]; then
    note "forbidden-patterns/ templates not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): shipped-rule drift cannot be checked; re-fetch the full scaffold bundle, not just this one file"
  fi
  for cfg in .forbidden-patterns/*.txt; do
    [ -e "$cfg" ] || continue
    base=$(basename "$cfg")
    tmpl="$SCAFFOLD_DIR/forbidden-patterns/$base.template"
    # No template = a project-local pattern file (or a doctor copied without
    # the bundle): nothing to compare against, and not a defect.
    [ -f "$tmpl" ] || continue
    # One awk pass, and only tools case 18's narrowed-PATH runs provide (awk,
    # grep, sed): a doctor that dies on a missing coreutil would be its own bug.
    missing=$(awk -F'\t' '
      FNR == NR { if ($0 !~ /^[[:space:]]*(#|$)/) have[$1] = 1; next }
      $0 ~ /^[[:space:]]*(#|$)/ { next }
      !($1 in have) { print $1 }
    ' "$cfg" "$tmpl" 2>/dev/null || true)
    [ -n "$missing" ] || continue
    nmiss=$(printf '%s\n' "$missing" | grep -c '' || true)
    gap "$base is missing $nmiss shipped rule(s) — those patterns are not enforced by the hook or by CI (both read this one file)" \
        "diff $cfg against forbidden-patterns/$base.template and merge the missing rules back, or re-run install.sh --force (yours is backed up to .scaffold-bak). If nothing was deleted here, this project is simply behind the scaffold release you just ran the doctor from — same line, same fix, and it clears on upgrade"
    if [ "$QUIET" -eq 0 ]; then
      printf '%s\n' "$missing" | sed -n '1,8{s/^/        - /;p;}'
      [ "${nmiss:-0}" -le 8 ] || echo "        - ... and $((nmiss - 8)) more"
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
  if [ -x .githooks/lib/scaffold-audit ]; then
    # The audit block was printed verbatim and never counted, so a project that
    # had switched the 500 KB cap and the whole size rule off still summarised
    # as "armed: N check(s) running, 0 gaps", and under --quiet, which is the
    # mode a CI step or an agent asked "what is off here?" actually reads, the
    # overrides did not appear at all. Measured: --quiet output was byte-identical
    # with and without a .scaffold.toml disabling three rules.
    #
    # This script's own header defines `!` as "deliberate off-switch", which is
    # exactly what these are: notes, never gaps (the project asked for them), but
    # notes that --quiet may not swallow, hence note_always.
    AUDIT_OUT=$(.githooks/lib/scaffold-audit 2>/dev/null || true)
    [ "$QUIET" -eq 1 ] || printf '%s\n' "$AUDIT_OUT" | sed 's/^/      /'
    audit_cap=""
    while IFS= read -r audit_line; do
      # Trim the audit's own indentation without a subprocess per line.
      audit_trim=${audit_line#"${audit_line%%[! ]*}"}
      case "$audit_line" in
        *'[size] caps:')        audit_cap="size" ;;
        *'[large-files] caps:') audit_cap="large-files" ;;
        *'rule "'*' DISABLED')
          audit_cap=""
          audit_rule=${audit_line#*rule \"}
          audit_rule=${audit_rule%%\"*}
          note_always "rule \"$audit_rule\" is DISABLED in .scaffold.toml: it is installed and it blocks nothing"
          ;;
        *'rule "'*severity=*)
          audit_cap=""
          audit_rule=${audit_line#*rule \"}
          audit_rule=${audit_rule%%\"*}
          note_always "rule \"$audit_rule\" is downgraded to severity=${audit_line##*severity=} in .scaffold.toml: it reports and no longer blocks"
          ;;
        *' = '*)
          if [ -n "$audit_cap" ]; then
            note_always "[$audit_cap] cap overridden in .scaffold.toml: $audit_trim"
          fi
          ;;
      esac
    done <<AUDIT
$AUDIT_OUT
AUDIT
  fi
fi

# --- 8. paired artifacts -----------------------------------------------------
# Some guardrails ship as two halves that only work together: a config file
# plus the CI workflow that reads it, or a local pre-commit pass plus the CI
# gate it defers to. install.sh writes both halves together, but an
# interrupted install, a later re-run without a flag, or a hand-copied file
# can leave only one half on disk (#96), and once that happens, nothing
# checks again. Detection lives in install-wiring.sh's check_paired_artifacts so
# install.sh's own end-of-run summary reports the exact same states with the
# exact same wording; sourced here rather than duplicated.
section "paired artifacts"
if [ -f "$SCAFFOLD_DIR/install-wiring.sh" ]; then
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, by name, from check_paired_artifacts (SC2317/2329 cannot see that)
  doctor_pair_note() { note "$1"; }
  # shellcheck source=install-wiring.sh
  . "$SCAFFOLD_DIR/install-wiring.sh"
  check_paired_artifacts gap doctor_pair_note
else
  note "install-wiring.sh not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): paired-artifact checks skipped"
fi

# --- 9. server-side backstop -------------------------------------------------
# Every hook in this scaffold is client-side and `git commit --no-verify`
# skips all of them — pre-commit.template says so out loud. .github/workflows/
# lint.yml re-running the same lib/check-* scripts IS the answer to that, and
# it is the only one. Nothing guarded its removal: the pre-commit deletion
# guard matches `^\.forbidden-patterns/.+\.txt$` only, workflows run from the
# PR head so the deleting PR's own checks no longer include the job, and this
# script used to grade such a repo "armed, 0 gaps".
section "server-side backstop"
if [ ! -d .githooks/lib ]; then
  note "no .githooks/lib/ — no local checks installed, so there is nothing for CI to mirror"
elif [ ! -f .github/workflows/lint.yml ]; then
  gap ".github/workflows/lint.yml is missing — the lib/check-* scripts run client-side only, and 'git commit --no-verify' bypasses every one of them with nothing behind it" \
      "re-run install.sh to restore .github/workflows/lint.yml"
# Anchored past any leading '#': lint.yml is YAML, and a job hollowed out to a
# comment that still NAMES the scripts it no longer runs would otherwise read
# as armed — the exact "present but not running" shape this script exists for.
elif grep -qE '^[[:space:]]*[^#[:space:]].*check-secrets' .github/workflows/lint.yml &&
     grep -qE '^[[:space:]]*[^#[:space:]].*check-patterns' .github/workflows/lint.yml; then
  ok "lint.yml re-runs the guardrail checks server-side"
else
  gap ".github/workflows/lint.yml exists but its guardrails job no longer invokes lib/check-secrets and lib/check-patterns — CI is not mirroring the hook" \
      "re-run install.sh --force to restore the guardrails job"
fi

# --- 10. patch-coverage gate -------------------------------------------------
# The opt-in gate has a CONTINUOUS off switch nothing else watches. Editing
# DIFF_COVER_FAIL_UNDER from "100" to "0" leaves the workflow installed, the
# job green and the check name unchanged in branch protection; install.sh
# preserves the drift by policy (cp_scaffold_preserve, #105/#110) and prints
# at most a "note (drift):" on a re-run nobody performs. Widening .coveragerc's
# `omit` — or vitest's `coverage.exclude`, the same switch on the JS side — is
# the same move one layer down: an excluded path never reaches coverage.xml /
# cobertura-coverage.xml, and diff-cover scores a changed line it has no data
# for as COVERED. All three are reported against the SHIPPED templates, so this
# tracks the scaffold's own default rather than a number hardcoded here.
section "patch-coverage gate"
COV_TPL="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"
COVRC_TPL="$SCAFFOLD_DIR/.coveragerc.template"
VITEST_TPL="$SCAFFOLD_DIR/vitest.config.ts.template"
# Every check in this section compares against a template that ships BESIDE
# this script, and a doctor copied out of the bundle on its own would skip all
# three in total silence — the failure mode this whole script exists to name.
# Said once, here, in the same shape as the paired-artifacts note above.
if [ ! -f "$COV_TPL" ] || [ ! -f "$COVRC_TPL" ] || [ ! -f "$VITEST_TPL" ]; then
  note "coverage templates not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): the .coveragerc omit and vitest coverage.exclude drift checks are skipped, and the threshold below is compared against a hardcoded 100 instead of the shipped default; re-fetch the full scaffold bundle, not just this one file"
fi
# awk, not `grep -o | head`: same narrowed-PATH reason as the drift check above.
# ANCHORED ON THE KEY at the start of a line, and the value taken from after the
# colon: an unanchored match reads `# DIFF_COVER_FAIL_UNDER: 100 is the default`
# sitting above a real `DIFF_COVER_FAIL_UNDER: "0"` as the value and prints
# "✓ patch coverage: 100%" over a dead gate — one comment line restoring the
# exact false green this section exists to kill. The first digit run before any
# inline `#` is the value, so "100", '80' and 100 (all valid YAML) read alike.
_fail_under() {
  awk '
    /^[[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:/ {
      rest = $0
      sub(/^[[:space:]]*DIFF_COVER_FAIL_UNDER[[:space:]]*:/, "", rest)
      h = index(rest, "#")
      if (h > 0) rest = substr(rest, 1, h - 1)
      if (match(rest, /[0-9]+/)) { print substr(rest, RSTART, RLENGTH); exit }
    }' "$1" 2>/dev/null || true
}
if [ ! -f .github/workflows/coverage.yml ]; then
  note "no .github/workflows/coverage.yml — no patch-coverage gate (opt in with install.sh --coverage-gate)"
else
  thr=$(_fail_under .github/workflows/coverage.yml)
  shipped=100
  if [ -f "$COV_TPL" ]; then
    shipped=$(_fail_under "$COV_TPL")
  fi
  shipped=${shipped:-100}
  # A gap, not a note, at ANY value below the shipped default: the doctor's own
  # definition of a gap is "installed but inert; a commit that should be blocked
  # isn't", and at 80 a PR whose changed lines are 85% covered merges where the
  # shipped policy would have stopped it. Adopting an existing codebase at a
  # lower number and ratcheting up is a legitimate choice — the doctor will
  # keep naming it until you get back to the default, which is the point.
  if [ -z "$thr" ]; then
    gap "coverage.yml has no DIFF_COVER_FAIL_UNDER — diff-cover falls back to its own default instead of this project's threshold" \
        "restore 'DIFF_COVER_FAIL_UNDER: \"$shipped\"' in the workflow's env: block"
  elif [ "$thr" -eq 0 ]; then
    gap "DIFF_COVER_FAIL_UNDER is 0 — the patch-coverage gate is installed, runs, and CANNOT FAIL; the green check it produces is indistinguishable from a real one" \
        "raise it back to $shipped, or delete coverage.yml so the repo stops advertising a gate it does not have"
  elif [ "$thr" -lt "$shipped" ]; then
    gap "patch coverage is ${thr}% of changed lines, below the shipped ${shipped}% — changed lines between ${thr}% and ${shipped}% coverage now merge green" \
        "raise DIFF_COVER_FAIL_UNDER back to $shipped; if ${thr} is a deliberate adoption ratchet, say so in the PR that set it and expect this line until it is back up"
  else
    ok "patch coverage: ${thr}% of changed lines"
  fi
fi
# .coveragerc `omit` drift. Only ADDED entries matter: a shorter list is
# stricter. Read on the raw entry text so a reordered list is not drift.
#
# The continuation rules below are configparser's, not "indented lines until
# anything else". A full-line comment or a blank line INSIDE the block does NOT
# end the value — configparser strips the comment, keeps the option open and
# reads on — so an awk that stopped at either would print
# "✓ omit list matches the shipped template" over an added `*/payments/*` the
# moment someone wrote `# legacy, see #99` above it. That is the LIKELY shape,
# not a corner case: .coveragerc.template's own comment tells the reader to say
# out loud why an entry is there, and house style is to comment the why. The
# value ends only at a line starting in column 0 (the next key or section).
# Entries are comma-separable too (coverage.py splits on commas AND newlines),
# so `omit = a, b` is two entries, not one path named "a, b".
_omit_entries() {
  awk '
    function emit(s,   n, i, a) {
      n = split(s, a, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        if (a[i] != "") print a[i]
      }
    }
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*omit[[:space:]]*=/ { inomit = 1; v = $0; sub(/^[^=]*=/, "", v); emit(v); next }
    inomit && /^[[:space:]]*$/ { next }
    inomit && /^[[:space:]]/ { emit($0); next }
    { inomit = 0 }
  ' "$1" 2>/dev/null || true
}
if [ -f .coveragerc ] && [ -f "$COVRC_TPL" ]; then
  # -Fxq, not a regex match: omit entries are globs (`*/tests/*`), and comparing
  # them as patterns would call `*/test_*.py` a match for anything.
  shipped_omit=$(_omit_entries "$COVRC_TPL")
  added=""
  while IFS= read -r _e; do
    if [ -n "$_e" ] && ! printf '%s\n' "$shipped_omit" | grep -Fxq -- "$_e"; then
      added="${added}${_e}
"
    fi
  done <<EOF
$(_omit_entries .coveragerc)
EOF
  if [ -n "$added" ]; then
    nadd=$(printf '%s' "$added" | grep -c '' || true)
    gap ".coveragerc omits $nadd path(s) the shipped template does not — every changed line under them drops out of coverage.xml and diff-cover scores it as COVERED, so the gate passes on untested code there" \
        "remove the added omit entries, or keep them and say in the PR which code is no longer gated"
    [ "$QUIET" -eq 1 ] || printf '%s' "$added" | sed 's/^/        - /'
  else
    ok ".coveragerc omit list matches the shipped template (nothing extra hidden from the gate)"
  fi
fi
# vitest `coverage.exclude` drift — the JS half of the same off switch, and the
# half nothing else in this scaffold looks at. An excluded path emits no entry
# in cobertura-coverage.xml at all, which diff-cover reads as COVERED.
#
# Entries are pulled by scanning for QUOTED strings rather than splitting on
# commas: `'**/.{git,cache}/**'` is one glob containing commas, and a comma
# split would report three phantom paths. Only the first exclude array AFTER a
# `coverage:` key is read, so a `test.exclude` (which selects TEST files, not
# measured files) is not mistaken for this one.
_vitest_cov_excludes() {
  awk '
    /coverage[[:space:]]*:/ { incov = 1 }
    incov && !inx && /exclude[[:space:]]*:[[:space:]]*\[/ {
      inx = 1; sub(/^.*exclude[[:space:]]*:[[:space:]]*\[/, "")
    }
    inx {
      line = $0
      sub(/\/\/.*$/, "", line)
      while (match(line, "[\"\047\140][^\"\047\140]*[\"\047\140]")) {
        pre = substr(line, 1, RSTART - 1)
        # The array closed before this string: it belongs to whatever follows
        # on the same line (an `include:` list, say), not to the excludes.
        if (index(pre, "]") > 0) { line = pre; break }
        e = substr(line, RSTART + 1, RLENGTH - 2)
        if (e != "") print e
        line = substr(line, RSTART + RLENGTH)
      }
      if (index(line, "]") > 0) exit
    }
  ' "$1" 2>/dev/null || true
}
# Excluding tests, build output, type stubs and tool config is what an exclude
# list is FOR — every hand-written vitest config has some of it, and the
# shipped template reached today's list by a different route (it now spreads
# vitest's own `coverageConfigDefaults.exclude` instead of respelling them), so
# a bare "not in the template" test would fire on every correctly-installed
# repo one release behind. Reported entries are therefore only those that name
# neither a test/build/tooling path nor a non-source file type — i.e. the move
# F34 is actually about: taking a directory of YOUR OWN SOURCE out of the gate.
# Directory words are matched with a non-word boundary on both sides so that
# `app/routes/**` is not read as "contains out" and quietly excused.
_BENIGN_EXCLUDE='(^|[^a-zA-Z0-9_])(node_modules|dist|build|out|coverage|target|vendor|bower_components|tests?|specs?|__tests__|__mocks__|__snapshots__|fixtures|mocks|stubs|cypress|playwright|e2e|storybook|stories|bench|benchmark|examples?|docs?|scripts?|generated|__generated__)([^a-zA-Z0-9_]|$)|\.d\.ts|\.config\.|\.setup\.|(eslint|prettier|babel|mocha|stylelint|npm)rc|/\.|^\.|virtual:|__x00__'
# install.sh writes vitest.config.ts, but a project that renamed it (or that
# keeps its vitest block in vite.config.ts, which is equally valid) would
# otherwise have this check skip without a word. First one that exists wins.
VITEST_CFG=""
for _c in vitest.config.ts vitest.config.mts vitest.config.js vite.config.ts vite.config.js; do
  if [ -f "$_c" ]; then VITEST_CFG=$_c; break; fi
done
if [ -n "$VITEST_CFG" ] && [ -f "$VITEST_TPL" ]; then
  shipped_x=$(_vitest_cov_excludes "$VITEST_TPL")
  xadded=""
  while IFS= read -r _e; do
    if [ -n "$_e" ] &&
       ! printf '%s\n' "$shipped_x" | grep -Fxq -- "$_e" &&
       ! printf '%s\n' "$_e" | grep -qEi -- "$_BENIGN_EXCLUDE"; then
      xadded="${xadded}${_e}
"
    fi
  done <<EOF
$(_vitest_cov_excludes "$VITEST_CFG")
EOF
  if [ -n "$xadded" ]; then
    nx=$(printf '%s' "$xadded" | grep -c '' || true)
    gap "$VITEST_CFG excludes $nx source path(s) from coverage that the shipped template does not — vitest emits no data for them, and diff-cover scores a changed line it has no data for as COVERED, so the gate passes on untested code there" \
        "remove the added coverage.exclude entries, or keep them and say in the PR which code is no longer gated"
    [ "$QUIET" -eq 1 ] || printf '%s' "$xadded" | sed 's/^/        - /'
  else
    ok "$VITEST_CFG: coverage.exclude hides no source path the shipped template measures"
  fi
fi

# --- 11. protections not enabled ---------------------------------------------
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
