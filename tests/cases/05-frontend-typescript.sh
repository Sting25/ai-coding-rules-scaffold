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
if npx --no-install tsc --version >/dev/null 2>&1; then
  echo '{"compilerOptions":{"strict":true,"noEmit":true}}' >tsconfig.json
  echo 'const n: number = "definitely not a number";' >typeerr.ts
  git add tsconfig.json typeerr.ts
  assert_rejects "tsc --noEmit rejects a type error" "error TS"
else
  echo "  - skipped tsc test (typescript not installed in temp repo)"
fi
