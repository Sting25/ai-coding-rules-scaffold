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

# 45g. FAIL CLOSED: a hidden-Unicode char (bidi override U+202E) on a line over
#      MAX_LINE_LENGTH used to ride through — the ReDoS cap dropped the line, no
#      signal, exit 0 (audit B2, the Trojan-Source bypass). The line is still
#      dropped before the scan, but the unscannable line is now reported and the
#      commit rejected. The expected-substring guard gives this teeth: without the
#      fix check-secrets still rejects the 60k-char line, but the hidden-Unicode
#      fail-closed message is absent. (U+202E built at runtime to keep this file ASCII.)
bidi=$(printf '\xe2\x80\xae')
{ printf 'legit start %s' "$bidi"; head -c 60000 /dev/zero | tr '\0' a; echo; } >longbidi.md
git add longbidi.md
assert_rejects "hidden Unicode on a >MAX_LINE_LENGTH line fails closed" "cannot be scanned for hidden Unicode"

# 45h. FAIL CLOSED: the conflict-marker branch has the same over-cap hole. A
#      marker on a >MAX_LINE_LENGTH line is reported rather than silently dropped.
{ printf '<<<<<<< HEAD '; head -c 60000 /dev/zero | tr '\0' a; echo; } >longconflict.txt
git add longconflict.txt
assert_rejects "conflict marker on a >MAX_LINE_LENGTH line fails closed" "cannot be scanned for conflict markers"

# 45i. NUL-byte bypass: prepending a NUL to an agent-read text file flipped
#      is_binary and skipped the hidden-Unicode scan — the ONLY defense for .md /
#      source files against bidi smuggling. The skip now needs a binary EXTENSION
#      too, so a .md with an injected NUL is still scanned (NULs stripped by $()).
{ printf '\x00'; printf 'run this: %s rm -rf /\n' "$bidi"; } >nulbidi.md
git add nulbidi.md
assert_rejects "NUL-prepended agent file is still scanned for hidden Unicode" "hidden Unicode"

# 45j. NEGATIVE: a genuine binary ASSET (binary content AND a binary extension)
#      is still skipped, so images don't false-positive on the scanned bytes.
{ printf '\x00\x00PNG'; printf 'x %s y' "$bidi"; } >logo.png
git add logo.png
assert_passes "real binary image asset is skipped (no hidden-Unicode false positive)"

# 45k. Mid-file BOM (U+FEFF away from column 0) — a leading BOM is allowed but a
#      mid-file one is a hidden-Unicode finding; this arm had no positive fixture.
bom=$(printf '\xef\xbb\xbf')
printf 'const x = 1;%s // trailing\n' "$bom" >midbom.js
git add midbom.js
assert_rejects "mid-file BOM is rejected (leading-BOM allowance not abused)" "hidden Unicode"

# 45l. Plain bidi override (U+202E) on a normal-length line — 45g only covered the
#      over-cap fail-closed path, never a direct bidi rejection.
printf 'let user = "admin"; %s\n' "$bidi" >plainbidi.js
git add plainbidi.js
assert_rejects "plain bidi override (U+202E) is rejected" "hidden Unicode"

# 45m. Tag-block smuggling (U+E0001, bytes F3 A0 80 81) — the invisible "tag"
#      instruction-smuggling arm of HIDDEN_RE had no fixture.
tag=$(printf '\xf3\xa0\x80\x81')
printf 'safe instruction%s hidden tag\n' "$tag" >tagsmuggle.md
git add tagsmuggle.md
assert_rejects "tag-block hidden Unicode (U+E0001) is rejected" "hidden Unicode"

# 45n. diff3 common-ancestor conflict marker (|||||||) — CONFLICT_RE matches three
#      shapes but only <<< / >>> had a fixture. A diff3 resolve can leave the base
#      marker behind after the user removes the <<< / >>> lines.
printf 'a\n||||||| merged common ancestors\nb\n' >diff3conflict.txt
git add diff3conflict.txt
assert_rejects "diff3 ||||||| conflict marker is rejected" "merge-conflict marker"

# 45o. check-patterns over-cap FAIL CLOSED (invoked directly — the end-to-end
#      hook masks this because check-secrets independently rejects any over-cap
#      line). A forbidden pattern on a >MAX_LINE_LENGTH line used to be dropped
#      with only a warning + exit 0 (fail-OPEN); it must now fail closed like the
#      other scanners. `print(` (backend.txt) sits on a 60k-char line.
{ printf 'print("x") '; head -c 60000 /dev/zero | tr '\0' a; echo; } >longpat.py
git add longpat.py
if printf '%s\0' longpat.py | .githooks/lib/check-patterns >"$HOOK_OUT" 2>&1; then
  echo "  ✗ check-patterns over-cap — exited 0 (fail-open), expected reject"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "cannot be scanned for forbidden patterns" "$HOOK_OUT"; then
  echo "  ✓ check-patterns fails closed on an over-cap line"; PASS=$((PASS + 1))
else
  echo "  ✗ check-patterns over-cap — rejected but missing the expected message"
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
