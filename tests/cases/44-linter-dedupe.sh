# shellcheck shell=bash
# cases/44-linter-dedupe.sh: a forbidden-pattern rule that carries
# `linter=eslint:<token>` or `linter=ruff:<token>` is skipped by check-patterns
# exactly when pre-commit would run that linter on the file (config present AND
# binary present) AND a token is in the linter's config file, and enforced
# otherwise. Under --ci the binary test is lint.yml's instead (config present).
# Sourced into the driver's shell, so PASS/FAIL/HOOK_OUT/WORK and reset_repo are
# in scope. Modelled on cases/43.
#
# The detection lives in `scaffold-config linter-runs` and MIRRORS the two tests
# in pre-commit.template (config-file presence, then binary presence), so every
# fixture below builds the same evidence pre-commit looks for. node and npx are
# FAKES on a throwaway PATH, deterministic on a machine with or without them:
# the fake `node` answers pre-commit's `require.resolve('eslint/package.json')`
# probe by testing for node_modules/eslint/package.json. Cases that need a
# linter ABSENT run with a PATH holding only the tools the hook itself needs, so
# a real ruff or node on the developer's machine cannot leak in.
echo ""
echo "check-patterns linter-dedupe (linter=eslint:<token> / linter=ruff:<token>):"
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver
cd "$WORK"
reset_repo
rm -f .scaffold.toml

LD_TMP=$(mktemp -d)
LD_SAFE="$LD_TMP/safe"    # only what check-patterns itself needs
LD_NODE="$LD_TMP/node"    # fake node + npx
LD_RUFF="$LD_TMP/ruff"    # fake ruff
mkdir -p "$LD_SAFE" "$LD_NODE" "$LD_RUFF"
for _ld_t in env bash sh git grep sed awk tr head tail dirname basename cat mktemp rm mkdir sort wc cut uname ls readlink; do
  _ld_p=$(command -v "$_ld_t" 2>/dev/null || true)
  [ -n "$_ld_p" ] && ln -s "$_ld_p" "$LD_SAFE/$_ld_t"
done
printf '#!/bin/sh\n[ -f node_modules/eslint/package.json ]\n' >"$LD_NODE/node"
printf '#!/bin/sh\nexit 0\n' >"$LD_NODE/npx"
printf '#!/bin/sh\nexit 0\n' >"$LD_RUFF/ruff"
chmod +x "$LD_NODE/node" "$LD_NODE/npx" "$LD_RUFF/ruff"

# ld_env <none|eslint|eslint-nobin|eslint-notoken|ruff|ruff-nobin|ruff-notoken|both>:
# lay out the repo and set LD_PATH. Builds on the safe PATH only. The configs
# carry the tokens the shipped linter= fields name, as the shipped templates do;
# the -notoken variants are a config file whose linter runs on its defaults.
LD_ESLINT_CFG="export default [js.configs.recommended, ...tseslint.configs.strictTypeChecked, { rules: { 'no-console': 'error' } }];"
LD_RUFF_CFG='[lint]
select = ["E", "F", "PTH", "PGH"]'
ld_env() {
  rm -rf eslint.config.js eslint.config.mjs ruff.toml package.json pyproject.toml node_modules
  LD_PATH="$LD_SAFE"
  case "$1" in
    eslint|both|eslint-nobin|eslint-nonode)
      printf '%s\n' "$LD_ESLINT_CFG" >eslint.config.js ;;
    eslint-notoken) printf 'export default [];\n' >eslint.config.js ;;
  esac
  case "$1" in
    ruff|both|ruff-nobin) printf '%s\n' "$LD_RUFF_CFG" >ruff.toml ;;
    ruff-notoken) printf 'line-length = 100\n' >ruff.toml ;;
  esac
  case "$1" in
    eslint|both|eslint-notoken)
      mkdir -p node_modules/eslint
      printf '{"name":"eslint","version":"0.0.0"}\n' >node_modules/eslint/package.json
      LD_PATH="$LD_NODE:$LD_PATH" ;;
    eslint-nobin) LD_PATH="$LD_NODE:$LD_PATH" ;;   # node there, eslint not installed
  esac
  case "$1" in
    ruff|both|ruff-notoken) LD_PATH="$LD_RUFF:$LD_PATH" ;;
  esac
}

# ld_case <name> <allowed|refused> <file> <content> <needle>
# `refused` = exit 1 and the rule's description (needle) is in the output.
# `allowed` = exit 0 and the needle is absent. Runs check-patterns directly on a
# STAGED fixture, with PATH narrowed to $LD_PATH and no active virtualenv.
ld_case() {
  local name=$1 want=$2 file=$3 content=$4 needle=$5 rc=0
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >"$file"
  git add "$file"
  # shellcheck disable=SC2086  # LD_ARGS is empty or the single word --ci
  printf '%s\0' "$file" | env -u VIRTUAL_ENV PATH="$LD_PATH" .githooks/lib/check-patterns $LD_ARGS >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$want" = allowed ]; then
    if [ "$rc" -eq 0 ] && ! grep -qF "$needle" "$HOOK_OUT"; then
      echo "  ✓ $name"; PASS=$((PASS + 1))
    else
      echo "  ✗ $name: expected allowed (no '$needle'), got exit $rc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  else
    if [ "$rc" -eq 1 ] && grep -qF "$file" "$HOOK_OUT" && grep -qF "$needle" "$HOOK_OUT" \
       && ! grep -qF 'linter=' "$HOOK_OUT"; then
      echo "  ✓ $name"; PASS=$((PASS + 1))
    else
      echo "  ✗ $name: expected refused with '$needle', got exit $rc"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
    fi
  fi
}

LD_ARGS=""
LD_CONSOLE='Use the project logger, not console.log'
LD_DEBUGGER='Remove debugger statement'
LD_TSIGNORE='not @ts-ignore'
LD_TSNOCHECK='@ts-nocheck'
LD_JOIN='Use pathlib.Path(), not os.path.join'
# shellcheck disable=SC2016  # the backticks are literal text in the rule description
LD_TYPEIGN='Bare `# type: ignore`'

# 44a. Neither linter configured: today's behaviour, the regex rules fire.
ld_env none
ld_case "no linter: console.log refused in .ts" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_case "no linter: os.path.join refused in .py" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"

# 44b. eslint config AND the binary resolvable: the regex steps aside.
ld_env eslint
ld_case "eslint runs: console.log not refused in .ts" allowed src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_case "eslint runs: debugger not refused in .ts" allowed src/b.ts 'debugger;' "$LD_DEBUGGER"
ld_case "eslint runs: @ts-ignore not refused in .ts" allowed src/c.ts '// @ts-ignore' "$LD_TSIGNORE"
ld_case "eslint runs: @ts-nocheck not refused in .ts" allowed src/d.ts '// @ts-nocheck' "$LD_TSNOCHECK"
ld_case "eslint runs: console.log not refused in .js" allowed src/e.js 'console.log("x");' "$LD_CONSOLE"

# 44c. eslint config but the linter would be SKIPPED: the regex stays.
ld_env eslint-nobin
ld_case "eslint config, eslint not installed: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_case "eslint config, eslint not installed: debugger refused" refused src/b.ts 'debugger;' "$LD_DEBUGGER"
ld_env eslint-nonode
ld_case "eslint config, no node on PATH: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_env none
mkdir -p node_modules/eslint
printf '{"name":"eslint"}\n' >node_modules/eslint/package.json
LD_PATH="$LD_NODE:$LD_SAFE"
ld_case "eslint installed but no eslint config or package.json: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
# pre-commit's config test is `eslint.config.js` OR `package.json`, but a bare
# package.json runs eslint on its defaults (no no-console), so it dedupes nothing.
printf '{}\n' >package.json
ld_case "package.json alone, eslint on its defaults: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
printf '%s\n' "$LD_ESLINT_CFG" >eslint.config.mjs
ld_case "package.json plus eslint.config.mjs naming no-console: not refused" allowed src/a.ts 'console.log("x");' "$LD_CONSOLE"
rm -rf package.json eslint.config.mjs node_modules
# 44c2. The config is present and eslint installed, but no token: the regex stays.
ld_env eslint-notoken
ld_case "eslint runs without no-console in its config: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_case "eslint runs without recommended or no-debugger: debugger refused" refused src/b.ts 'debugger;' "$LD_DEBUGGER"

# 44d. Coverage: only files pre-commit hands to the linter lose the regex.
ld_env eslint
ld_case "eslint runs but does not lint .vue: console.log still refused" refused src/f.vue 'console.log("x");' "$LD_CONSOLE"
ld_case "eslint runs but does not lint .mts: console.log still refused" refused src/g.mts 'console.log("x");' "$LD_CONSOLE"

# 44e. ruff config AND a ruff binary.
ld_env ruff
ld_case "ruff runs: os.path.join not refused" allowed app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
ld_case "ruff runs: bare type: ignore not refused" allowed app/q.py 'x = f()  # type: ignore' "$LD_TYPEIGN"
ld_case "ruff runs: print() still refused (no linter= on that rule)" refused app/service.py 'print("x")' "Use structlog"
ld_case "ruff runs: os.path.join still refused in a .PY file ruff is never given" refused app/PATHS.PY 'p = os.path.join(a, b)' "$LD_JOIN"

# 44f. ruff config but no binary: the regex stays.
ld_env ruff-nobin
ld_case "ruff config, ruff absent: os.path.join refused" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
ld_case "ruff config, ruff absent: bare type: ignore refused" refused app/q.py 'x = f()  # type: ignore' "$LD_TYPEIGN"
ld_env none
LD_PATH="$LD_RUFF:$LD_SAFE"
ld_case "ruff present but no ruff.toml or pyproject.toml: os.path.join refused" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
printf '[project]\n' >pyproject.toml
ld_case "pyproject.toml without PTH, ruff on its defaults: os.path.join refused" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
printf '[project]\n[tool.ruff.lint]\nselect = ["PTH"]\n' >pyproject.toml
ld_case "pyproject.toml selecting PTH: os.path.join not refused" allowed app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
rm -f pyproject.toml
ld_env ruff-notoken
ld_case "ruff runs without PTH in ruff.toml: os.path.join refused" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
# A project venv is a route pre-commit's py_tool takes before PATH.
ld_env ruff-nobin
mkdir -p .venv/bin
cp "$LD_RUFF/ruff" .venv/bin/ruff
ld_case "ruff in the project .venv counts, as in pre-commit: not refused" allowed app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
rm -rf .venv

# 44g. .scaffold.toml forces the regex back on, per rule.
ld_env both
cat >.scaffold.toml <<'TOML'
[rules."frontend/Use the project logger, not console.log"]
linter-dedupe = false
[rules."backend/Use pathlib.Path(), not os.path.join"]
linter-dedupe = false
TOML
git add .scaffold.toml
ld_case "linter-dedupe = false: console.log refused although eslint runs" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_case "linter-dedupe = false: os.path.join refused although ruff runs" refused app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
ld_case "linter-dedupe is per rule: debugger still skipped" allowed src/b.ts 'debugger;' "$LD_DEBUGGER"
ld_case "linter-dedupe is per rule: bare type: ignore still skipped" allowed app/q.py 'x = f()  # type: ignore' "$LD_TYPEIGN"
rm -f .scaffold.toml
git rm -q --cached .scaffold.toml 2>/dev/null || true

# 44h. A rule without linter= is untouched by either linter.
ld_env both
ld_case "both linters run: print() in app/service.py still refused" refused app/service.py 'print("x")' "Use structlog"
ld_case "both linters run: alert() in .ts still refused" refused src/h.ts 'alert("x");' "alert()"
ld_case "both linters run: breakpoint() still refused" refused app/dbg.py 'breakpoint()' "Remove breakpoint()"

# 44i. The field is parsed in either order beside exclude=, and the description
#      (the rule id) never carries it.
reset_repo
ld_env both
mkdir -p "$LD_TMP/pf"
cp .forbidden-patterns/frontend.txt "$LD_TMP/pf/frontend.keep"
printf '# scaffold-extensions: ts\nzzprobe\tProbe A\tlinter=eslint:no-console\texclude=gen/*\nyyprobe\tProbe B\texclude=gen/*\tlinter=eslint:nope|no-console\nxxprobe\tProbe C\tlinter=pylint:x\nwwprobe\tProbe D\tlinter=eslint\n' >.forbidden-patterns/frontend.txt
ld_case "linter= then exclude=: skipped, description clean" allowed src/i.ts 'zzprobe' 'Probe A'
ld_case "exclude= then linter=, second token alternative matches: skipped" allowed src/j.ts 'yyprobe' 'Probe B'
ld_case "an unknown linter name never skips the rule" refused src/k.ts 'xxprobe' 'Probe C'
ld_case "a linter= field with no token never skips the rule" refused src/m.ts 'wwprobe' 'Probe D'
ld_case "the exclude= beside linter= still applies" allowed gen/l.ts 'zzprobe' 'Probe A'
cp "$LD_TMP/pf/frontend.keep" .forbidden-patterns/frontend.txt

# 44j. The duplicated predicates have not drifted from pre-commit.template. The
#      two files are separate scripts, so this pins the shared lines verbatim.
ld_pin() {
  local what=$1 text=$2
  if grep -qF -- "$text" "$SCAFFOLD_DIR/githooks/pre-commit.template" \
     && grep -qF -- "$text" "$SCAFFOLD_DIR/githooks/lib/scaffold-config.template"; then
    echo "  ✓ pre-commit and scaffold-config agree on $what"; PASS=$((PASS + 1))
  else
    echo "  ✗ $what differs between pre-commit.template and scaffold-config.template"; FAIL=$((FAIL + 1))
  fi
}
ld_pin "the ruff config test" '[ -f ruff.toml ] || [ -f pyproject.toml ]'
ld_pin "the eslint config test" '[ -f eslint.config.js ] || [ -f package.json ]'
ld_pin "the node and npx presence test" 'command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1'
ld_pin "the node resolve probe" "node -e \"require.resolve('"
# shellcheck disable=SC2016  # the expansion text is matched literally
ld_pin "the active-virtualenv route" '[ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/'
ld_pin "the project venv route" 'for cand in .venv venv; do'
ld_pin "the python -m route" 'command -v python3 >/dev/null 2>&1 && python3 -m'

# 44l. --ci: the binary lives in another job, so lint.yml's own test decides
#      (config present). PATH here holds neither node nor ruff.
LD_ARGS=--ci
ld_env eslint-nobin; LD_PATH="$LD_SAFE"
ld_case "--ci, eslint.config.js naming no-console, no eslint here: not refused" allowed src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_env ruff-nobin
ld_case "--ci, ruff.toml selecting PTH, no ruff here: not refused" allowed app/p.py 'p = os.path.join(a, b)' "$LD_JOIN"
ld_env none; printf 'export default [];\n' >eslint.config.js
ld_case "--ci, eslint.config.js without the token: console.log refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
ld_env none; printf '{}\n' >package.json; printf '%s\n' "$LD_ESLINT_CFG" >eslint.config.mjs
ld_case "--ci, package.json not naming eslint (lint.yml skips eslint): refused" refused src/a.ts 'console.log("x");' "$LD_CONSOLE"
printf '{"devDependencies":{"eslint":"9.0.0"}}\n' >package.json
ld_case "--ci, package.json naming eslint plus eslint.config.mjs: not refused" allowed src/a.ts 'console.log("x");' "$LD_CONSOLE"
LD_ARGS=""
ld_env none

# 44k. The audit view names the override.
cat >.scaffold.toml <<'TOML'
[rules."frontend/Use the project logger, not console.log"]
linter-dedupe = false
TOML
if .githooks/lib/scaffold-audit >"$HOOK_OUT" 2>&1 && grep -qF 'linter-dedupe' "$HOOK_OUT"; then
  echo "  ✓ scaffold-audit lists a linter-dedupe override"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-audit did not list the linter-dedupe override"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

rm -rf "$LD_TMP"
unset LD_TMP LD_SAFE LD_NODE LD_RUFF LD_PATH LD_ARGS LD_ESLINT_CFG LD_RUFF_CFG LD_CONSOLE LD_DEBUGGER LD_TSIGNORE LD_TSNOCHECK LD_JOIN LD_TYPEIGN _ld_t _ld_p
unset -f ld_env ld_case ld_pin
reset_repo
