# shellcheck shell=bash
# scaffold-doctor-checks.sh — section 3 of scaffold-doctor.sh: the shipped
# checks (present, executable, and CALLED), and the opt-in checks' call
# sites. SOURCED by scaffold-doctor.sh at the point section 3 used to be
# inline, so it runs with the doctor's counters, helpers and `set -euo
# pipefail`; extracted for the same reason scaffold-doctor-gates.sh was, the
# doctor's own 500-line cap, when the discovery-loop and manifest-aware
# absence logic (COMPONENTS.md entries 1a to 1f) pushed it over. Not a
# standalone script: it has no shebang on purpose.

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
    # The hook and lint.yml run every present lib/check-* through a discovery
    # loop rather than naming each scanner (COMPONENTS.md entries 1a to 1f),
    # so a `check-*` glob over lib/ is a call site for every check-* name.
    case "$name" in check-*)
      if grep -q -e "\$LIB\"/check-\*" -e "\$LIB/check-\*" -e ".githooks/lib/check-\*" <<<"$body"; then
        return 0
      fi ;;
    esac
  done
  return 1
}
section "shipped checks"
for chk in check-size check-large-files check-patterns check-filenames check-secrets check-hygiene; do
  if [ ! -f ".githooks/lib/$chk" ]; then
    # Absent is two different things. The hook runs whatever is present, so a
    # scanner that was never adopted is a note (COMPONENTS.md lets a project
    # take a subset). One the installer RECORDED in its manifest and that is
    # now gone was removed, and the hook went quiet about it: that is a gap.
    if [ -f .githooks/.scaffold-manifest ] && grep -qE "[[:space:]]\.githooks/lib/$chk\$" .githooks/.scaffold-manifest; then
      gap "lib/$chk was installed (recorded in .githooks/.scaffold-manifest) and is now missing — the hook silently skips it" \
          "re-run install.sh to restore it, or remove its manifest line if dropping it was deliberate"
    else
      note "lib/$chk not adopted (COMPONENTS.md entry 1) — the hook runs only the scanners present"
    fi
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

