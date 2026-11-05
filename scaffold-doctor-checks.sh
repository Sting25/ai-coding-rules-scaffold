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

# lib/py-tool is the Python tool resolver the hook sources for ruff. Missing, the
# hook prints a note and SKIPS the local ruff pass on every commit, so staged
# .py files go unlinted locally and CI is the only gate. Only a hook that
# actually sources it is held to it (an install that predates py-tool has none).
if [ -f .githooks/pre-commit ] && grep -q 'py-tool' .githooks/pre-commit; then
  if [ ! -r .githooks/lib/py-tool ]; then
    gap "lib/py-tool is missing: the hook skips the local ruff pass on every commit (it prints a note and moves on)" \
        "re-run install.sh to restore .githooks/lib/py-tool"
  else
    ok "lib/py-tool present (the hook resolves ruff through it)"
  fi
fi

# --- worktree parity (advisory) ----------------------------------------------
# Issue #211, advisory part only. A linked worktree copies tracked files and
# nothing else, so it can pass its own checks while running against another
# checkout's hooks, a stale node_modules or a venv that imports the wrong copy
# of the project. Five cheap conditions, each reported with `note` and NEVER with
# `gap`: nothing here blocks pre-commit or pre-push or counts toward the exit
# status. Every check is skipped quietly when its inputs are absent (no
# node_modules, no venv, no pyproject.toml); no network, no installs.
# OUT OF SCOPE: comparing installed tool VERSIONS against the lockfile (#211
# stays open for it), and any blocking variant. Called from scaffold-doctor.sh as
# doctor_worktree_parity, after the other sections.
#   1 core.hooksPath resolves outside this worktree
#   2 node_modules/.package-lock.json differs from package-lock.json
#   3 the venv imports the project from outside this worktree
#   4 a gate tool (ruff, pytest, eslint, prettier) is missing from the environment
#     the hook would use (python via lib/py-tool, JS via node's resolver, as
#     pre-commit's js_tool_installed does)
#   5 the gate interpreter is older than pyproject's requires-python minimum
doctor_worktree_parity() {
  local top hp hpdir pyname pyproj=0 interp="" out pyver req
  top=$(pwd -P)
  # 1. core.hooksPath. Unset is section 1's gap, and so is a path elsewhere; this adds the note.
  hp=$(git config --get core.hooksPath 2>/dev/null || true)
  if [ -n "$hp" ]; then
    case $hp in /*) ;; *) hp="$top/$hp" ;; esac
    hpdir=$(cd "$hp" 2>/dev/null && pwd -P) || hpdir=$hp
    case $hpdir/ in "$top"/*) ;; *)
      note "core.hooksPath resolves to $hpdir, outside this worktree ($top): the hooks that run are another checkout's. Fix: git config core.hooksPath .githooks (in this worktree)" ;;
    esac
  fi
  # 2. node_modules vs the lockfile (packages maps; the root and optional entries are not compared)
  if [ -f package-lock.json ] && [ -f node_modules/.package-lock.json ]; then
    local lockcmp='
const [a,b]=process.argv.slice(1).map(f=>JSON.parse(require("fs").readFileSync(f,"utf8")).packages||{});
let bad=0;for(const k of Object.keys(b)){if(!a[k]||a[k].version!==b[k].version)bad=1}
for(const k of Object.keys(a)){if(k!==""&&!a[k].optional&&!a[k].link&&!b[k])bad=1}
process.exit(bad)'
    if command -v node >/dev/null 2>&1; then
      node -e "$lockcmp" package-lock.json node_modules/.package-lock.json >/dev/null 2>&1 ||
        note "installed node_modules do not match the lockfile; run npm ci"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c '
import json,sys
a=json.load(open(sys.argv[1])).get("packages",{});b=json.load(open(sys.argv[2])).get("packages",{})
bad=any(k not in a or a[k].get("version")!=v.get("version") for k,v in b.items())
bad=bad or any(k and not v.get("optional") and not v.get("link") and k not in b for k,v in a.items())
sys.exit(1 if bad else 0)' package-lock.json node_modules/.package-lock.json >/dev/null 2>&1 ||
        note "installed node_modules do not match the lockfile; run npm ci"
    else
      note "lockfile parity check skipped: neither node nor python3 is available to compare package-lock.json with node_modules/.package-lock.json"
    fi
  fi
  # Python: the interpreter the gates would use is the venv's, else python3.
  if [ -f pyproject.toml ]; then
    pyproj=1
    if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then interp=$VIRTUAL_ENV/bin/python
    elif [ -x .venv/bin/python ]; then interp=.venv/bin/python
    elif [ -x venv/bin/python ]; then interp=venv/bin/python
    elif command -v python3 >/dev/null 2>&1; then interp=python3; fi
  fi
  # 3. the venv imports the project from inside this worktree
  pyname=$(awk '/^\[/{p=($0=="[project]")} p&&/^name[[:space:]]*=/{gsub(/^[^=]*=[[:space:]]*["'\'']|["'\''][[:space:]]*(#.*)?$/,"");print;exit}' pyproject.toml 2>/dev/null || true)
  pyname=${pyname//-/_}
  if [ -n "$pyname" ] && [ -x .venv/bin/python ]; then
    if out=$(.venv/bin/python -c "import $pyname; print($pyname.__file__)" 2>/dev/null); then
      out=$(cd "${out%/*}" 2>/dev/null && pwd -P || echo "$out")
      case $out/ in "$top"/*) ;; *) note "the venv imports $pyname from $out, outside this worktree" ;; esac
    else
      note "the venv cannot import $pyname (.venv/bin/python -c 'import $pyname' fails): it is not installed there, or installed from elsewhere"
    fi
  fi
  # 4. gate tools missing from the environment the gates use
  if [ "$pyproj" -eq 1 ] || [ -f ruff.toml ]; then
    if [ -r .githooks/lib/py-tool ]; then
      ( . .githooks/lib/py-tool; py_tool ruff ) >/dev/null 2>&1 ||
        note "ruff is not resolvable by the hook's lib/py-tool (venv, PATH, python3 -m): the local lint pass is skipped here"
      if grep -q pytest pyproject.toml 2>/dev/null; then
        ( . .githooks/lib/py-tool; py_tool pytest ) >/dev/null 2>&1 ||
          note "pytest is not resolvable by lib/py-tool (venv, PATH, python3 -m): tests cannot run here"
      fi
    fi
  fi
  if [ -f package.json ] && command -v node >/dev/null 2>&1; then
    local jt
    for jt in eslint prettier; do
      if [ "$jt" = prettier ]; then
        local pc cfg=0
        for pc in .prettierrc* prettier.config.*; do [ -e "$pc" ] && cfg=1; done
        [ "$cfg" -eq 1 ] || continue
      fi
      node -e "require.resolve('$jt/package.json')" >/dev/null 2>&1 ||
        note "$jt is not installed in this worktree's node_modules: the hook skips the local $jt pass"
    done
  fi
  # 5. interpreter vs requires-python (>=X.Y or >=X.Y,<...; anything else is skipped)
  req=$(sed -n 's/^requires-python[[:space:]]*=[[:space:]]*["'\'']>=[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\)\(\.[0-9]*\)\{0,1\}\(,[^"'\'']*\)\{0,1\}["'\''].*/\1/p' pyproject.toml 2>/dev/null || true)
  req=${req%%$'\n'*}
  if [ -n "$req" ] && [ -n "$interp" ]; then
    pyver=$("$interp" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)
    if [ -n "$pyver" ]; then
      # pure-bash major.minor compare (no sort/head: the doctor runs under a narrowed PATH too)
      if [ "${pyver%%.*}" -lt "${req%%.*}" ] ||
         { [ "${pyver%%.*}" -eq "${req%%.*}" ] && [ "${pyver#*.}" -lt "${req#*.}" ]; }; then
        note "the gate interpreter ($interp) is Python $pyver, below pyproject.toml's requires-python >=$req"
      fi
    fi
  fi
  return 0
}
