# shellcheck shell=bash
# cases/17-whole-tree-configs.sh — installed configs must not silently degrade to
# whole-tree scope (issue #76). Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) are already in scope.
#
# What #76 was: AGENTS.md prescribes whole-tree local checks (`npx eslint .`,
# `pytest`), but the configs installed beside them enumerate their exclusions
# instead of deriving them, and neither honours .gitignore. Anything on disk but
# not in git — a vendored toolchain, an agent worktree, an extra checkout — is
# inside the blast radius. CI never sees it (fresh checkout + diff-scoped), so it
# only ever bites locally, and the documented gate and the real gate disagree.
#
# Both halves share one signature: a config that LOOKS scoped and BEHAVES
# whole-tree, without announcing the fallback.
#   pytest: `testpaths = tests` matching nothing falls back to rootdir collection.
#   eslint: an `ignores` list that misses a directory descends into it.

echo "cases/17 — configs that silently go whole-tree (#76)"

# (T) A pytest config in a SUBDIRECTORY must stop the root pytest.ini install.
#     This is the monorepo case and the sharpest part of the bug: the old guard
#     was `grep -rqs … pyproject.toml tox.ini setup.cfg`, and `-r` does not
#     recurse for a FILE argument — only a directory — so it could only ever see
#     a ROOT config. A root pytest.ini then shadows the real one (pytest reads
#     exactly one ini-file and rootdir wins, losing e.g. asyncio_mode) AND its
#     `testpaths = tests` matches nothing, so collection walks the whole tree.
#     Inert and shadowing at once — the worst of the three outcomes.
MONO=$(mktemp -d)
mkdir -p "$MONO/backend"
( cd "$MONO" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && git config core.hooksPath .nohooks \
  && printf '[project]\nname = "x"\n' >pyproject.toml \
  && printf '[tool.pytest.ini_options]\nasyncio_mode = "auto"\n' >backend/pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python ) >"$HOOK_OUT" 2>&1
if [ ! -f "$MONO/pytest.ini" ] && grep -qF "pytest config in backend" "$HOOK_OUT"; then
  echo "  ✓ a pytest config in a subdirectory blocks the root pytest.ini install"; PASS=$((PASS + 1))
else
  echo "  ✗ root pytest.ini installed over a subdirectory's pytest config (#76)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$MONO"

# (T) A pytest config under node_modules is a dependency's, not the repo's, so
#     it must NOT count as a subdirectory config. The probe prunes node_modules,
#     but `find -mindepth 2` never evaluates the prune on a depth-1 directory,
#     so the prune was inert and a vendored pyproject.toml suppressed the root
#     pytest.ini with a "pytest config in node_modules/x" skip (found while
#     fixing the same construct for tsconfig.json, #163).
VEND=$(mktemp -d)
mkdir -p "$VEND/node_modules/x"
( cd "$VEND" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && git config core.hooksPath .nohooks \
  && printf '[project]\nname = "x"\n' >pyproject.toml \
  && printf '[tool.pytest.ini_options]\n' >node_modules/x/pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python ) >"$HOOK_OUT" 2>&1
if [ -f "$VEND/pytest.ini" ] && ! grep -q "pytest config in node_modules" "$HOOK_OUT"; then
  echo "  ✓ a pytest config under node_modules is pruned; the root pytest.ini is still installed"; PASS=$((PASS + 1))
else
  echo "  ✗ a vendored pyproject.toml under node_modules must not suppress the root pytest.ini"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$VEND"

# (T) With no pytest config anywhere, the file still installs — the detection
#     must not be so eager that the feature stops working. Without this, deleting
#     the install line entirely would pass the assertion above.
PLAIN=$(mktemp -d)
( cd "$PLAIN" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && git config core.hooksPath .nohooks \
  && printf '[project]\nname = "x"\n' >pyproject.toml && mkdir tests \
  && "$SCAFFOLD_DIR/install.sh" --python ) >"$HOOK_OUT" 2>&1
if [ -f "$PLAIN/pytest.ini" ]; then
  echo "  ✓ pytest.ini still installs when nothing else configures pytest"; PASS=$((PASS + 1))
else
  echo "  ✗ pytest.ini no longer installs at all — detection is too eager"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$PLAIN"

# (T) Installing with no ./tests must SAY so. `testpaths = tests` that matches
#     nothing is not an error to pytest — it collects from rootdir instead — so
#     the config reads as scoped while behaving as whole-tree. Silence here is
#     how a consumer discovers it later via a collection error from a vendored
#     package, which is the failure the issue actually reported.
NOTESTS=$(mktemp -d)
( cd "$NOTESTS" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && git config core.hooksPath .nohooks \
  && printf '[project]\nname = "x"\n' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --python ) >"$HOOK_OUT" 2>&1
if [ -f "$NOTESTS/pytest.ini" ] && grep -qF "matches nothing" "$HOOK_OUT"; then
  echo "  ✓ installing pytest.ini without ./tests warns that collection goes whole-tree"; PASS=$((PASS + 1))
else
  echo "  ✗ no warning that testpaths matches nothing (silent whole-tree collection)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$NOTESTS"

# (T) norecursedirs must re-list pytest's DEFAULTS. Setting the key REPLACES the
#     default list rather than extending it, so shipping only the additions would
#     silently START collecting build/, dist/ and node_modules again — a
#     regression that looks like a harmless config line.
PYINI="$SCAFFOLD_DIR/pytest.ini.template"
NRD=$(grep -E '^norecursedirs' "$PYINI" || true)
NRD_MISSING=""
for d in '\*\.egg' '\.\*' '_darcs' 'build' 'CVS' 'dist' 'node_modules' 'venv' '{arch}'; do
  printf '%s' "$NRD" | grep -qE "(^|[[:space:]])${d}([[:space:]]|$)" || NRD_MISSING="$NRD_MISSING $d"
done
if [ -n "$NRD" ] && [ -z "$NRD_MISSING" ]; then
  echo "  ✓ norecursedirs re-lists pytest's defaults (setting it replaces, not extends)"; PASS=$((PASS + 1))
else
  echo "  ✗ norecursedirs drops pytest defaults:$NRD_MISSING — build/dist/node_modules would be collected again"; FAIL=$((FAIL + 1))
fi

# (T) The eslint config must derive its ignores from .gitignore. A hardcoded list
#     only covers the names someone thought of; the reported failure was an agent
#     worktree holding its own eslint.config.js and no node_modules, where eslint
#     died with ERR_MODULE_NOT_FOUND and linted NOTHING (exit 2) rather than
#     merely reporting noise.
ESLINT_TPL="$SCAFFOLD_DIR/eslint.config.js.template"
if grep -qF 'includeIgnoreFile' "$ESLINT_TPL" \
   && grep -qF "'@eslint/compat'" "$ESLINT_TPL" \
   && grep -qF '.gitignore' "$ESLINT_TPL"; then
  echo "  ✓ eslint.config.js derives ignores from .gitignore (@eslint/compat)"; PASS=$((PASS + 1))
else
  echo "  ✗ eslint.config.js still enumerates ignores instead of deriving them (#76)"; FAIL=$((FAIL + 1))
fi

# (T) ...guarded on the file existing. includeIgnoreFile THROWS on a missing
#     .gitignore, and a config that throws does not lint leniently — it does not
#     lint at all. A repo without a .gitignore must still load its config.
if grep -qE 'existsSync' "$ESLINT_TPL"; then
  echo "  ✓ .gitignore lookup is existence-guarded (no .gitignore ⇒ config still loads)"; PASS=$((PASS + 1))
else
  echo "  ✗ includeIgnoreFile is unguarded — a repo with no .gitignore fails to load eslint config"; FAIL=$((FAIL + 1))
fi

# (T) The new peer dependency must be in the documented install line. The config
#     imports @eslint/compat at module scope, so a consumer who follows the
#     header's `npm i -D` and misses it gets ERR_MODULE_NOT_FOUND on every run —
#     trading the bug for the same symptom.
if grep -qF '@eslint/compat' "$ESLINT_TPL" \
   && grep -E '^//   npm i -D' "$ESLINT_TPL" | grep -qF '@eslint/compat'; then
  echo "  ✓ @eslint/compat is listed in the documented peer install"; PASS=$((PASS + 1))
else
  echo "  ✗ @eslint/compat imported but missing from the 'npm i -D' line — consumers get ERR_MODULE_NOT_FOUND"; FAIL=$((FAIL + 1))
fi

# (T) The shipped config must PARSE. It is ESM with imports, so it is checked as
#     .mjs; a syntax error here means every consumer's eslint fails to load.
#     Skipped when node is absent locally, but a missing node in CI (#85) is a
#     FAILURE rather than a silent skip: this is the only syntax check on the
#     shipped template, and test.yml has no setup-node step, so it relies on
#     the runner image happening to ship node. If that ever stops being true,
#     the check must go red instead of quietly stop running.
#
#     Extracted to tests/lib/eslint-syntax-check.sh (#111): it is invoked here
#     as a subprocess so the node-absent branches below can be mutation-tested
#     under a curated PATH, the same way check-gitleaks is tested in cases/08:
#     an inline block sourced into this whole file's shell could not be
#     exercised that cheaply. The PASS/FAIL tally still lives here, driven by
#     the subprocess's exit code; the status line itself is the script's output.
ESC="$SCAFFOLD_DIR/tests/lib/eslint-syntax-check.sh"
if bash "$ESC" "$ESLINT_TPL" >"$HOOK_OUT" 2>&1; then
  cat "$HOOK_OUT"; PASS=$((PASS + 1))
else
  cat "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi

# (T) node-absent branches of eslint-syntax-check.sh, proven under a curated
#     PATH with no node on it (mirrors mk_glbin in cases/08's check-gitleaks
#     coverage). GITHUB_ACTIONS is explicitly overridden (not just set/unset)
#     on each invocation so this stays correct whether or not the suite itself
#     is currently running inside real CI.
NONODE=$(mktemp -d); ln -sf "$(command -v bash)" "$NONODE/bash"
# node absent + GITHUB_ACTIONS set must be a hard FAILURE (#85), not a skip.
if PATH="$NONODE" GITHUB_ACTIONS=true bash "$ESC" "$ESLINT_TPL" >"$HOOK_OUT" 2>&1; then
  echo "  ✗ eslint-syntax-check: allowed a missing node to pass under GITHUB_ACTIONS (#85)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "cannot run in CI (#85)" "$HOOK_OUT"; then
  echo "  ✓ eslint-syntax-check fails when node is absent under GITHUB_ACTIONS (#85)"; PASS=$((PASS + 1))
else
  echo "  ✗ eslint-syntax-check: failed without the expected CI message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
# node absent, not CI, must be a clean skip (exit 0), not a failure.
if PATH="$NONODE" GITHUB_ACTIONS="" bash "$ESC" "$ESLINT_TPL" >"$HOOK_OUT" 2>&1 \
   && grep -qF "skipped eslint config syntax check" "$HOOK_OUT"; then
  echo "  ✓ eslint-syntax-check skips cleanly when node is absent locally"; PASS=$((PASS + 1))
else
  echo "  ✗ eslint-syntax-check: expected a clean local skip when node is absent"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$NONODE"

reset_repo
