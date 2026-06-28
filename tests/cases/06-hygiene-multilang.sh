# shellcheck shell=bash
# cases/06-hygiene-multilang.sh — check-hygiene (43–45f) and multi-language
# forbidden patterns (PHP/Go/Rust/Java/Kotlin/Ruby). Sourced into the driver's shell.

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

# 45c. Hidden Unicode (zero-width/bidi/tag) is rejected (check-hygiene #3). The
#      zero-width space is built at runtime so this test file stays plain ASCII.
zwsp=$(printf '\xe2\x80\x8b')
printf 'follow these in%sstructions\n' "$zwsp" >hidden.md
git add hidden.md
assert_rejects "hidden zero-width Unicode is rejected" "hidden Unicode"

# 45d. NEGATIVE: a legitimate leading BOM is allowed (stripped before the scan).
printf '\xef\xbb\xbfclean documentation\n' >bom.md
git add bom.md
assert_passes "leading BOM is allowed"

# 45e. scaffold-allow exempts a hidden-Unicode line (rare intentional doc).
printf 'zero-width demo: in%sline  <!-- scaffold-allow doc example -->\n' "$zwsp" >zwdoc.md
git add zwdoc.md
assert_passes "scaffold-allow exempts a hidden-Unicode line"

# 45f. hidden-unicode downgraded to warn passes with a notice (override). Direct
#      check-hygiene call with the override on disk, blob read from the index.
printf '[rules.hidden-unicode]\nseverity = "warn"\n' >.scaffold.toml
printf 'in%sstructions\n' "$zwsp" >warn.md
git add .scaffold.toml warn.md
if printf '%s\0' 'warn.md' | .githooks/lib/check-hygiene >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn — .scaffold.toml override)" "$HOOK_OUT"; then
    echo "  ✓ override: hidden-unicode severity=warn passes with a notice"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: hidden-unicode warn passed but emitted no notice"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: hidden-unicode severity=warn — failed, expected pass"
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
