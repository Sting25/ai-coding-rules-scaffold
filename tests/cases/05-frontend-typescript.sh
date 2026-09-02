# shellcheck shell=bash
# cases/05-frontend-typescript.sh — frontend forbidden-pattern rules (36–41)
# and the tsc type-check integration (42). Sourced into the driver's shell.

# 36. Focused test (.only) is rejected — a green CI that ran almost nothing is
#     the single most dangerous frontend commit.
echo 'it.only("smoke", () => {});' >focused.test.ts
git add focused.test.ts
assert_rejects "focused test (.only) is rejected" "Focused test"

# 37. NEGATIVE: an ordinary test (no .only) must pass — the .only regex must not
#     fire on a plain it(...)/test(...) call.
echo 'it("does a thing", () => { expect(1).toBe(1); });' >ok.test.ts
git add ok.test.ts
assert_passes "ordinary it(...) test is not flagged as .only"

# 38. @ts-ignore is rejected — use @ts-expect-error with a justification.
{
  echo '// @ts-ignore'
  echo 'const x: number = "nope";'
} >tsignore.ts
git add tsignore.ts
assert_rejects "@ts-ignore is rejected" "@ts-expect-error"

# 39. dangerouslySetInnerHTML is rejected as an XSS vector.
echo 'const el = <div dangerouslySetInnerHTML={{ __html: userInput }} />;' >xss.tsx
git add xss.tsx
assert_rejects "dangerouslySetInnerHTML is rejected" "XSS vector"

# 39b. Raw innerHTML assignment is an XSS sink (frontend.txt) — same bug class as
#      dangerouslySetInnerHTML but the vanilla-DOM form. frontend.txt scopes to
#      ts/tsx/js/jsx/vue, so this .ts content on a .sh harness line is not scanned.
echo 'el.innerHTML = userInput;' >innerhtml.ts
git add innerhtml.ts
assert_rejects "innerHTML assignment is rejected" "XSS sink"

# 39c. NEGATIVE: an innerHTML COMPARISON (===) is not an assignment — the regex
#      requires a non-`=` after the single `=`, so `=== ""` must pass.
echo 'if (el.innerHTML === "") { doThing(); }' >innerhtml-cmp.ts
git add innerhtml-cmp.ts
assert_passes "innerHTML comparison (===) is not flagged"

# 40. hardcoded localhost URL is rejected — config/env instead.
echo 'const api = "http://localhost:8080/v1";' >localhost.ts
git add localhost.ts
assert_rejects "hardcoded localhost URL is rejected" "hardcoded localhost"

# 40b. Disabling TLS verification is rejected (frontend.txt Security). Both the
#      env-var form and the rejectUnauthorized:false option form.
echo 'const agent = new https.Agent({ rejectUnauthorized: false });' >tls.ts
git add tls.ts
assert_rejects "rejectUnauthorized: false is rejected" "TLS validation"

echo 'process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";' >tls2.ts
git add tls2.ts
assert_rejects "NODE_TLS_REJECT_UNAUTHORIZED is rejected" "TLS certificate validation"

# 40c. NEGATIVE: rejectUnauthorized: true (the safe value) must NOT be flagged.
echo 'const agent = new https.Agent({ rejectUnauthorized: true });' >tlsok.ts
git add tlsok.ts
assert_passes "rejectUnauthorized: true is not flagged"

# 40d. Svelte {@html} is rejected — same XSS bug class as dangerouslySetInnerHTML
#      (React) / v-html (Vue). Also proves .svelte is now in the extensions header:
#      if it weren't scanned, this would not reject.
echo '<p>{@html post.body}</p>' >Card.svelte
git add Card.svelte
assert_rejects "Svelte {@html} is rejected" "XSS vector"

# 40e. NEGATIVE: ordinary Svelte interpolation ({expr}, not {@html}) must pass —
#      the required space after @html keeps the rule off normal markup and prose.
echo '<h1>{post.title}</h1>' >Ok.svelte
git add Ok.svelte
assert_passes "ordinary Svelte {expr} interpolation is not flagged"

# 41. NEGATIVE: console.warn / console.error are allowed (only console.log is
#     banned) and a clean .ts file with no tsconfig.json passes — proving the
#     new tsc block silently skips when TypeScript isn't configured.
{
  echo 'console.warn("heads up");'
  echo 'export const value = 42;'
} >clean.ts
git add clean.ts
assert_passes "console.warn allowed; clean .ts with no tsconfig passes"

# 42. tsc type-error rejection — only runs where TypeScript is resolvable in the
#     temp repo (it isn't, by default: no node_modules), so this is normally a
#     skip. Documents intent and exercises the path on machines that have a
#     project-local tsc. The hook runs `tsc --noEmit` project-wide when a
#     tsconfig.json exists.
#     The predicate is the hook's own gate (Node resolution from node_modules),
#     not `npx --no-install`, which also answers from the global npx cache.
if node -e "require.resolve('typescript/package.json')" >/dev/null 2>&1; then
  echo '{"compilerOptions":{"strict":true,"noEmit":true}}' >tsconfig.json
  echo 'const n: number = "definitely not a number";' >typeerr.ts
  git add tsconfig.json typeerr.ts
  assert_rejects "tsc --noEmit rejects a type error" "error TS"
else
  echo "  - skipped tsc test (typescript not installed in temp repo)"
fi

# 42b. eslint block rejection. The JS-linter integration in the pre-commit
#      orchestrator had no rejection test — eslint isn't resolvable in the temp
#      repo, so it silently skips, meaning a regression that stops eslint
#      findings from setting FAILED would ship green. Plant a project-local
#      node_modules/eslint so the hook's Node-resolution gate passes, and stub
#      `npx` on an isolated PATH so the lint run fails, proving the block
#      propagates a non-zero exit into the hook's failure.
ESB=$(mktemp -d)
cat >"$ESB/npx" <<'STUB'
#!/bin/sh
# `eslint -- <files>` → fail (lint); anything else → ok.
case "$*" in
  *eslint*) echo "eslint: problems found"; exit 1 ;;
  *)        exit 0 ;;
esac
STUB
chmod +x "$ESB/npx"
mkdir -p node_modules/eslint
echo '{"name":"eslint","version":"0.0.0-test"}' >node_modules/eslint/package.json
echo 'const x = 1' >lintme.js
git add lintme.js
if PATH="$ESB:$PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ eslint block: hook accepted despite an eslint failure"; FAIL=$((FAIL + 1))
elif grep -qF "Pre-commit failed" "$HOOK_OUT"; then
  echo "  ✓ eslint findings fail the pre-commit hook (project-local install)"; PASS=$((PASS + 1))
else
  echo "  ✗ eslint block: rejected but not via the linter path"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf node_modules
reset_repo

# 42b2. REGRESSION: a tool that npx can resolve (global _npx cache) but that is
#       NOT in this project's node_modules must be treated as not installed:
#       skip notice, exit 0. Same stub as 42b (npx "runs" eslint and fails),
#       no node_modules planted. Before the Node-resolution gate this was the
#       cached-eslint crash that failed 5 cases on any machine with a stale
#       ~/.npm/_npx eslint entry, so this case is deterministic on purpose.
echo 'const z = 1' >cachedonly.js
git add cachedonly.js
if PATH="$ESB:$PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1 \
   && grep -qF "note: eslint not installed" "$HOOK_OUT"; then
  echo "  ✓ npx-resolvable but not project-local eslint is skipped, not run"; PASS=$((PASS + 1))
else
  echo "  ✗ npx-resolvable but not project-local eslint: expected skip notice and exit 0"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$ESB"
reset_repo

# 42c. skip notice: when npx can't resolve eslint (a matching .js file is
#      staged and eslint.config.js ships from the scaffold install), the hook
#      must print a one-line notice to stderr and still exit 0. No node_modules
#      exists in the temp repo, so the Node-resolution gate fails; the failing
#      `npx` stub proves the hook never even launches the tool.
NPXFAIL=$(mktemp -d)
cat >"$NPXFAIL/npx" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$NPXFAIL/npx"
echo 'const y = 1' >noeslint.js
git add noeslint.js
if PATH="$NPXFAIL:$PATH" .githooks/pre-commit >"$HOOK_OUT" 2>&1 \
   && grep -qF "note: eslint not installed" "$HOOK_OUT"; then
  echo "  ✓ eslint-unresolvable skip prints a notice and still exits 0"
  PASS=$((PASS + 1))
else
  echo "  ✗ eslint-unresolvable skip: expected a note on stderr and exit 0"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$NPXFAIL"
reset_repo

# 42d. NEGATIVE: a repo with no staged .py/.js/.php files must print NO
#      lint-skip notices at all, even though none of ruff/eslint/prettier/tsc/
#      php/phpcs are proven present here. The notices are scoped to "there was
#      matching staged work this check could not run", not "the tool merely
#      happens to be absent".
echo '# just docs' >readme-notes.md
git add readme-notes.md
.githooks/pre-commit >"$HOOK_OUT" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qE "note: (ruff|eslint|prettier|TypeScript|php|phpcs)" "$HOOK_OUT"; then
  echo "  ✓ no matching staged files produces no lint-skip notices"
  PASS=$((PASS + 1))
else
  echo "  ✗ unexpected notice (or failure, rc=$rc) with no matching staged files"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

# 42e. CI MIRROR of 42b2. The pre-commit hook and lint.yml must agree on what
#      "eslint is installed" means. The hook gates on Node resolution from the
#      project's node_modules (42b2); lint.yml's ESLint step used to gate only
#      the CONFIG-LOAD check that way and left `npx --no-install eslint --
#      <files>` unguarded, so any repo with a package.json but no
#      eslint.config.js (every `install.sh --python` onto a repo that carries
#      tailwind/esbuild/husky) ran eslint from npm's global _npx cache on a
#      warm runner, or died with "npx canceled due to missing packages" on a
#      cold one. Both outcomes fail a required check for a linter the project
#      never configured.
#
#      Run the step's REAL shell body, lifted out of the shipped YAML, the same
#      way cases/16 does for the coverage gate: asserting on the text would pass
#      against any rewrite that reintroduced the hole by another route.
LINT_TPL="$SCAFFOLD_DIR/.github/workflows/lint.yml.template"

_lint_run_block() {
  awk -v step="      - name: $1" '
    $0 == step { found = 1 }
    found && /run: \|/ { inrun = 1; next }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 !~ /^          /) exit
      sub(/^          /, "")
      print
    }
  ' "$LINT_TPL"
}

ESCI=$(mktemp -d)
_lint_run_block "ESLint (changed files only)" >"$ESCI/step.sh"
# A project shaped like the reported one: package.json (so the detect step turns
# the job on), a changed .js file, NO eslint.config.js and NO node_modules. The
# npx stub stands in for the warm _npx cache: it "runs" eslint and reports
# findings, so if the step reaches it at all the body exits non-zero.
cat >"$ESCI/npx" <<'STUB'
#!/bin/sh
case "$*" in
  *eslint*) echo "eslint: cached copy ran"; exit 1 ;;
  *)        exit 0 ;;
esac
STUB
chmod +x "$ESCI/npx"
mkdir -p "$ESCI/proj"
echo '{"name":"x"}' >"$ESCI/proj/package.json"
printf 'app.js\0' >"$ESCI/proj/changed.nul"

esci_rc=0
( cd "$ESCI/proj" && PATH="$ESCI:$PATH" bash -e "$ESCI/step.sh" ) >"$HOOK_OUT" 2>&1 || esci_rc=$?
if [ "$esci_rc" -eq 0 ] && grep -qF "skipping eslint" "$HOOK_OUT" \
   && ! grep -qF "cached copy ran" "$HOOK_OUT"; then
  echo "  ✓ lint.yml skips eslint (exit 0, logged reason) with no project-local eslint"
  PASS=$((PASS + 1))
else
  echo "  ✗ lint.yml ESLint step: expected exit 0 + a skip reason, got rc=$esci_rc"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# 42f. POSITIVE control for 42e: the gate must not have turned the step into a
#      no-op. With eslint resolvable from the project's own node_modules the
#      step MUST reach `npx --no-install eslint` and propagate its non-zero
#      exit, so real lint findings still fail the job.
mkdir -p "$ESCI/proj/node_modules/eslint"
echo '{"name":"eslint","version":"0.0.0-test"}' >"$ESCI/proj/node_modules/eslint/package.json"
esci_rc=0
( cd "$ESCI/proj" && PATH="$ESCI:$PATH" bash -e "$ESCI/step.sh" ) >"$HOOK_OUT" 2>&1 || esci_rc=$?
if [ "$esci_rc" -ne 0 ] && grep -qF "cached copy ran" "$HOOK_OUT"; then
  echo "  ✓ lint.yml still runs eslint and fails the job when it is project-local"
  PASS=$((PASS + 1))
else
  echo "  ✗ lint.yml ESLint step: expected a lint failure to propagate, got rc=$esci_rc"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# 42g. The eslint.config.js branch keeps its ACTIONABLE hard error: a shipped
#      config with no eslint installed is a broken setup, not a skip.
rm -rf "$ESCI/proj/node_modules"
echo 'export default [];' >"$ESCI/proj/eslint.config.js"
esci_rc=0
( cd "$ESCI/proj" && PATH="$ESCI:$PATH" bash -e "$ESCI/step.sh" ) >"$HOOK_OUT" 2>&1 || esci_rc=$?
if [ "$esci_rc" -ne 0 ] && grep -qF "::error file=eslint.config.js::eslint is not installed" "$HOOK_OUT"; then
  echo "  ✓ lint.yml still hard-errors when eslint.config.js ships without eslint"
  PASS=$((PASS + 1))
else
  echo "  ✗ lint.yml ESLint step: expected the actionable install error, got rc=$esci_rc"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$ESCI"
reset_repo
