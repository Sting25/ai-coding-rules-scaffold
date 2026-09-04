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
# where install-wiring.sh and scaffold-doctor-gates.sh ship alongside it in all
# three distribution paths: the first lets the "paired artifacts" section reuse
# install.sh's own detection logic, the second carries sections 9-12.
SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
# If dirname(1) is NOT on PATH (the narrowed PATH tests/cases/18-doctor.sh runs
# this script under), the substitution is empty, `cd ""` is a no-op, and this
# lands on the PROJECT directory instead. Every template comparison below then
# finds no template; the notes in sections 8 and 10 say so out loud rather than
# skipping in silence, which is the part that matters.
# Sections 9-12 are SOURCED from beside this script, and losing THEM is not that
# same degrading: inline they still RAN. So the module lookup — only the module
# lookup — falls back to $0's own directory, through one symlink hop (a doctor
# linked onto PATH), computed here: a relative $0 is relative to the caller's cwd.
DOCTOR_DIR="$SCAFFOLD_DIR"; _d0=$0
[ ! -L "$_d0" ] || { _t=$(readlink "$_d0"); case $_t in /*) _d0=$_t ;; *) _d0=${_d0%/*}/$_t ;; esac; }
{ [ -f "$DOCTOR_DIR/scaffold-doctor-gates.sh" ] && [ -f "$DOCTOR_DIR/scaffold-doctor-checks.sh" ]; } || [ "${_d0%/*}" = "$_d0" ] ||
  DOCTOR_DIR="$(cd "${_d0%/*}" 2>/dev/null && pwd)" || DOCTOR_DIR="$SCAFFOLD_DIR"

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

# core.hooksPath governs whether a COMMIT is checked; whether an AGENT ever
# reads the rules is a separate wiring question with its own silent-gap shape.
# AGENTS.md only LINKS coding-rules.md (a markdown link, kept deliberately
# cross-tool), and a link is not loaded into context at session start — only
# an `@coding-rules.md` import line in CLAUDE.md does that. install_claude_md
# has appended that line since v0.17; installs from before then carry the gap
# with nothing on disk to say so. Nothing to check when this project never had
# coding-rules.md installed. `CLAUDE.md` may be a symlink to `CLAUDE.md.pointer`
# in some setups — `[ -f ]` and `grep` both follow it, which is correct here.
if [ -f coding-rules.md ]; then
  if [ ! -f CLAUDE.md ]; then
    gap "coding-rules.md exists but there is no CLAUDE.md to import it"
  # Anchored, not a substring match: an unanchored '@coding-rules.md' also
  # matches prose like "we removed the @coding-rules.md import", which would
  # report the exact opposite of the truth.
  elif grep -q '^@coding-rules\.md$' CLAUDE.md 2>/dev/null; then
    ok "CLAUDE.md imports coding-rules.md"
  else
    gap "coding-rules.md exists but is not imported by CLAUDE.md (add a line reading @coding-rules.md; AGENTS.md only links the file, so the rules are never loaded)"
  fi
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
# Lives in scaffold-doctor-checks.sh (its header says why), SOURCED here so it
# runs in this shell, in this position, with these counters. Missing, it is a
# note rather than a hard error, for the same reason the gates module is.
if [ -f "$DOCTOR_DIR/scaffold-doctor-checks.sh" ]; then
  # shellcheck source=scaffold-doctor-checks.sh
  . "$DOCTOR_DIR/scaffold-doctor-checks.sh"
else
  note "scaffold-doctor-checks.sh not found next to scaffold-doctor.sh ($DOCTOR_DIR): the shipped-checks section (present, executable, called) is skipped; re-fetch the full scaffold bundle, not just this one file"
fi

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

# --- 9-12. the gates beyond the hook -----------------------------------------
# The CI backstop, the patch-coverage gate, the lint ignore derivation and the
# not-enabled inventory live in scaffold-doctor-gates.sh (its header says which
# and why), SOURCED so they run in this shell with these counters, these helpers
# and this `set -euo pipefail` — install.sh's arrangement with install-lib.sh,
# extracted for the same reason: this file's own 500-line cap. Missing, it is
# section 8's note and not uninstall.sh's hard error, because a doctor copied
# out of the bundle alone must still report what it can.
if [ -f "$DOCTOR_DIR/scaffold-doctor-gates.sh" ]; then
  # shellcheck source=scaffold-doctor-gates.sh
  . "$DOCTOR_DIR/scaffold-doctor-gates.sh"
else
  note "scaffold-doctor-gates.sh not found next to scaffold-doctor.sh ($DOCTOR_DIR): the server-side backstop, patch-coverage, lint-ignore and protections-not-enabled checks are skipped; re-fetch the full scaffold bundle, not just this one file"
fi

# --- 9. template drift (AGENTS.md, coding-rules.md) --------------------------
# AGENTS.md is never rewritten once it exists, and coding-rules.md is replaced
# wholesale only under --force — correct, since both are user-owned once
# installed. The flip side is silent: a scaffold release that adds a section
# to either shipped file leaves an install behind with nothing on disk saying
# so (#133). Neither file carries a version marker, so section HEADINGS
# (every `## `/`### ` line) are the inventory, reported as a NOTE never a gap
# since a project may have deliberately trimmed one.
section "template drift"
# doctor_heading_drift <installed> <shipped> <label> <policy-note>. One awk
# pass mirrors section 4's forbidden-patterns-vs-template comparison: only
# headings that were SHIPPED and are now absent are reported (an extra local
# section is healthy, not drift). The regex skips a `{{...}}`/`<TOKEN>`
# placeholder install.sh would substitute; neither shipped file has one today
# (checked), so this guards a future heading rather than a live case.
doctor_heading_drift() {
  local td_inst=$1 td_shipped=$2 td_label=$3 td_policy=$4 td_quoted
  [ -f "$td_inst" ] || return 0
  if [ ! -f "$td_shipped" ]; then
    note "$(basename "$td_shipped") not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): $td_label drift cannot be checked; re-fetch the full scaffold bundle, not just this one file"
    return 0
  fi
  td_quoted=$(awk '
    FNR == NR { have[$0] = 1; next }
    !/^(## |### )/ { next }
    /\{\{/ || /<[A-Za-z_-]+>/ { next }
    !($0 in have) { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }
  ' "$td_inst" "$td_shipped" 2>/dev/null || true)
  if [ -z "$td_quoted" ]; then
    ok "$td_label carries every section of the shipped template"
    return 0
  fi
  note "$(basename "$td_inst") predates the shipped template: missing $td_quoted. diff it against $td_shipped and adopt what applies; $td_policy"
}
doctor_heading_drift "AGENTS.md" "$SCAFFOLD_DIR/AGENTS.md.template" "AGENTS.md" \
  "install.sh never rewrites this file"
doctor_heading_drift "coding-rules.md" "$SCAFFOLD_DIR/coding-rules.md" "coding-rules.md" \
  "install.sh --force replaces it wholesale (backup in .scaffold-bak); merging by hand keeps local edits"

# --- summary ----------------------------------------------------------------
echo ""
if [ "$GAPS" -eq 0 ]; then
  echo "✓ armed: $OKS check(s) running, $NOTES note(s), 0 gaps."
  exit 0
fi
echo "✗ $GAPS guardrail(s) installed but NOT running ($OKS armed, $NOTES note(s))."
exit 1
