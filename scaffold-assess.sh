#!/usr/bin/env bash
# scaffold-assess.sh — measure what the scaffold would flag in THIS project,
# before adopting anything. Read-only: writes nothing into the target tree.
#
# usage: scaffold-assess.sh [--samples N]   (run from anywhere inside the repo)
#   --samples N   show up to N example findings per scanner (default 3)
#
# Exit status: 0 assessment printed, 2 usage error / not a git repository.
# Findings never change the exit status: this is a measurement, not a gate.
#
# WHY. Every guard the scaffold ships is cheap on a fresh repository and
# expensive to discover on an existing one: the first commit after adoption
# is where a project learns that a pattern rule fires on 200 legacy files, or
# that a root tsconfig.json makes the hook type-check the whole tree (#163:
# 12,235 errors). COMPONENTS.md lets a reader pick components; this script
# tells them what each would cost, per component, with nothing copied.
#
# HOW. The shipped scanners are rendered from their *.template sources into a
# temp directory and run from the target's git root over `git ls-files`, the
# same whole-tree list lint.yml scans in CI. check-patterns and check-secrets
# read their pattern files from $SCAFFOLD_PATTERNS_DIR, pointed at the shipped
# templates, so a tree with no .forbidden-patterns/ still gets the real rules.
# The target's own .scaffold.toml overrides, if any, are honored, because they
# would be honored by the hook too.
#
# WHAT IT CANNOT SEE. The scanners read the git INDEX (`git show :0:path`),
# which is what the hook and CI read, so untracked files are not scanned; the
# count of untracked files is printed rather than left silent. A component
# whose language has no tracked files is reported as "not applicable", never
# as "clean": zero findings on zero files proves nothing.
set -euo pipefail

SAMPLES=3
while [ $# -gt 0 ]; do
  case "$1" in
    --samples) shift; SAMPLES=${1:-}; case "$SAMPLES" in ''|*[!0-9]*) echo "scaffold-assess: --samples needs a number" >&2; exit 2 ;; esac ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "scaffold-assess: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "scaffold-assess: not inside a git repository. The scanners read the git index, so there is nothing to measure here." >&2
  exit 2
fi
cd "$ROOT"
if [ "$(pwd -P)" = "$SCAFFOLD_DIR" ]; then
  echo "scaffold-assess: run this from the project you want to assess, not from the scaffold checkout." >&2
  exit 2
fi

# Render the scanners and pattern files somewhere the target tree never sees.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/lib" "$WORK/patterns"
for t in "$SCAFFOLD_DIR"/githooks/lib/check-*.template "$SCAFFOLD_DIR"/githooks/lib/scaffold-config.template; do
  n=$(basename "$t" .template)
  cp "$t" "$WORK/lib/$n" && chmod +x "$WORK/lib/$n"
done
for t in "$SCAFFOLD_DIR"/forbidden-patterns/*.txt.template; do
  cp "$t" "$WORK/patterns/$(basename "$t" .template)"
done
export SCAFFOLD_PATTERNS_DIR="$WORK/patterns"

ALL="$WORK/all.z"
git -c core.quotepath=off ls-files -z >"$ALL"
TRACKED=$(tr -cd '\0' <"$ALL" | wc -c | tr -d ' ')
UNTRACKED=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')

echo "scaffold-assess: $ROOT"
echo "  tracked files scanned: $TRACKED   untracked (not scanned, not in the index): $UNTRACKED"
[ -f .scaffold.toml ] && echo "  note: this repo has a .scaffold.toml; its overrides are applied below, as the hook would apply them."
echo

# run_scanner NAME LISTFILE: run one rendered scanner over a NUL list, capture
# its plain (non --ci) output, and print a one-line verdict plus samples.
# Findings are the "✗ file: desc" and "! file: desc" lines the scanners emit
# per (file, rule); the indented match excerpts under them are not counted.
# Alternation, not a bracket expression: under a C locale `[✗!]` is a byte
# class and never matches the three-byte glyph, which reported every scanner
# clean on a tree with findings (caught by the smoke, then by case 39).
run_scanner() {
  local name=$1 list=$2 out="$WORK/$1.out" n
  "$WORK/lib/$name" <"$list" >"$out" 2>&1 || true
  n=$(grep -cE '^(✗|!) ' "$out" || true)
  if [ "$n" -eq 0 ]; then
    echo "  ✓ $name: clean"
  else
    echo "  ✗ $name: $n finding(s)"
    grep -E '^(✗|!) ' "$out" | head -n "$SAMPLES" | sed 's/^/      /'
    [ "$n" -gt "$SAMPLES" ] && echo "      ... and $((n - SAMPLES)) more"
  fi
  return 0
}

echo "Commit guard core (COMPONENTS.md entry 1), whole tree:"
for s in check-secrets check-filenames check-hygiene check-large-files check-size; do
  run_scanner "$s" "$ALL"
done
echo

# Per-language pattern files: attribute findings to one file at a time via
# CHECK_PATTERNS_INCLUDE, and count the tracked files its header extensions
# match so "no files" is reported as not applicable rather than clean.
echo "Language pattern files (entry 2), one line per file:"
for cfg in "$WORK"/patterns/*.txt; do
  base=$(basename "$cfg")
  case "$base" in secrets.txt) continue ;; esac
  exts=$(grep -m1 -E '^#[[:space:]]*scaffold-extensions:' "$cfg" | sed -E 's/^#[[:space:]]*scaffold-extensions:[[:space:]]*//; s/[[:space:]]+$//')
  if [ -z "$exts" ]; then
    echo "  ! $base: no scaffold-extensions header, skipped"
    continue
  fi
  re='\.('; for e in $exts; do re="$re$e|"; done; re="${re%|})\$"
  matched=$(tr '\0' '\n' <"$ALL" | grep -ciE "$re" || true)
  if [ "$matched" -eq 0 ]; then
    echo "  - $base: not applicable (no tracked files with extension: $exts)"
    continue
  fi
  out="$WORK/$base.out"
  CHECK_PATTERNS_INCLUDE="$base" "$WORK/lib/check-patterns" <"$ALL" >"$out" 2>&1 || true
  n=$(grep -cE '^(✗|!) ' "$out" || true)
  if [ "$n" -eq 0 ]; then
    echo "  ✓ $base: clean across $matched file(s)"
  else
    echo "  ✗ $base: $n finding(s) across $matched file(s) ($(grep -E '^(✗|!) ' "$out" | cut -d: -f1 | sort -u | wc -l | tr -d ' ') files)"
    grep -E '^(✗|!) ' "$out" | head -n "$SAMPLES" | sed 's/^/      /'
    [ "$n" -gt "$SAMPLES" ] && echo "      ... and $((n - SAMPLES)) more"
  fi
done
echo

# Project-wide tool configs (entries 6 to 10): these govern the whole tree, so
# the honest measurement is the tool itself, run with the shipped config and
# nothing copied. Only run when the tool resolves; say so when it does not.
echo "Project-wide configs (entries 6 to 10), measured with the shipped config:"
py_files=$(tr '\0' '\n' <"$ALL" | grep -c '\.py$' || true)
if [ "$py_files" -eq 0 ]; then
  echo "  - ruff.toml: not applicable (no tracked .py files)"
elif command -v ruff >/dev/null 2>&1 || python3 -m ruff --version >/dev/null 2>&1; then
  if command -v ruff >/dev/null 2>&1; then RUFF=ruff; else RUFF="python3 -m ruff"; fi
  n=$($RUFF check --no-cache --config "$SCAFFOLD_DIR/ruff.toml.template" --quiet --exit-zero --output-format concise . 2>/dev/null | grep -c . || true)
  echo "  $([ "$n" -eq 0 ] && echo ✓ || echo ✗) ruff.toml: $n finding(s) across $py_files .py file(s); the hook lints only staged files, so this is the debt, not a blocker"
else
  echo "  ! ruff.toml: $py_files .py file(s), ruff not installed here, not measured"
fi
js_files=$(tr '\0' '\n' <"$ALL" | grep -ciE '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)
if [ "$js_files" -eq 0 ]; then
  echo "  - tsconfig.json: not applicable (no tracked JS/TS files)"
elif [ -f tsconfig.json ]; then
  echo "  - tsconfig.json: this repo already has one; the scaffold's would not be copied over it"
elif grep -q '"workspaces"' package.json 2>/dev/null || [ -f pnpm-workspace.yaml ]; then
  echo "  ! tsconfig.json: workspaces monorepo, do not add a root tsconfig.json (#163); per-package configs already type-check"
elif command -v node >/dev/null 2>&1 && node -e "require.resolve('typescript/package.json')" >/dev/null 2>&1; then
  n=$(npx --no-install tsc --noEmit -p "$SCAFFOLD_DIR/tsconfig.json.template" 2>&1 | grep -c 'error TS' || true)
  echo "  $([ "$n" -eq 0 ] && echo ✓ || echo ✗) tsconfig.json: $n type error(s) across $js_files JS/TS file(s); the hook runs tsc PROJECT-WIDE on every JS/TS commit, so this is a blocker until zero"
else
  echo "  ! tsconfig.json: $js_files JS/TS file(s), typescript not resolvable here, not measured. It is project-wide: measure before adopting."
fi
if [ "$js_files" -gt 0 ]; then
  if command -v node >/dev/null 2>&1 && node -e "require.resolve('eslint/package.json')" >/dev/null 2>&1; then
    echo "  ! eslint.config.js: eslint is installed; measure with: npx eslint -c \"$SCAFFOLD_DIR/eslint.config.js.template\" . (needs typescript-eslint and eslint-plugin-security)"
  else
    echo "  ! eslint.config.js: $js_files JS/TS file(s), eslint not resolvable here, not measured"
  fi
fi
echo

echo "Tools on this machine (what the hook and CI can run):"
tool() { if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  - $1: absent ($3)"; fi; }
tool "ruff (Python lint)"          "command -v ruff || python3 -m ruff --version" "entry 6 does nothing without it"
tool "pytest"                      "command -v pytest || python3 -m pytest --version" "entries 4 and 18 need it"
tool "node"                        "command -v node" "every JS/TS tool below needs it"
tool "eslint (project-local)"      "node -e \"require.resolve('eslint/package.json')\"" "entry 9 skips with a note"
tool "typescript (project-local)"  "node -e \"require.resolve('typescript/package.json')\"" "entry 10 skips with a note"
tool "prettier (project-local)"    "node -e \"require.resolve('prettier/package.json')\"" "entry 11 skips with a note"
tool "shellcheck"                  "command -v shellcheck" "shell.txt rules still run; shellcheck lint does not"
tool "gitleaks"                    "command -v gitleaks" "entry 16's local pass skips, CI gate still runs"
tool "jq"                          "command -v jq" "entry 15's agent guard fails open"
tool "actionlint"                  "command -v actionlint" "workflow validation in COMPONENTS.md verify steps is skipped"
echo
echo "Next: read COMPONENTS.md, adopt the entries you want, run each verify block, then scaffold-doctor.sh."
echo "Nothing was written to $ROOT."
