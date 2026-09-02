# shellcheck shell=bash
# cases/03-binary-defense.sh — binary/blob-scanning bypass defenses (cases
# 19–22e): NUL bytes, symlinks, newline filenames, modern key prefixes.
# Sourced into the driver's shell.

# 19. NUL byte must not flip the secret scan into "binary file" mode. A single
#     NUL anywhere in a text file used to make grep treat the whole file as
#     binary and silently skip it, bypassing the secret scan in the hook AND in
#     CI. Scanning the staged blob with -a/--text (and $()'s NUL-stripping)
#     closes this. AKIA literal split so this file doesn't itself trip the scan.
printf 'AKIA''IOSFODNN7EXAMPLE\000trailing\n' >nul.txt
git add nul.txt
assert_rejects "NUL byte does not hide a secret" "AWS access key"

# 19b. Secret placed AFTER a NUL byte. Case 19 kept the secret BEFORE the NUL, so
#      a C-string awk (macOS/BSD) that truncates the record at the NUL still saw
#      it. A secret AFTER the NUL was silently lost by the awk length-cap stage —
#      a real fail-open. Stripping NULs before awk (tr -d '\000') closes it.
printf 'harmless prefix\000AKIA''IOSFODNN7EXAMPLE\n' >nulafter.txt
git add nulafter.txt
assert_rejects "secret AFTER a NUL byte is still scanned" "AWS access key"

# 19c. scaffold-allow on a COLUMN-0 comment line (leader immediately before the
#      marker) must exempt — the exemption anchor has to tolerate the `grep -n`
#      "NN:" line-number prefix, or the documented start-of-line form never works.
printf '# scaffold-allow expired demo: AKIA''IOSFODNN7EXAMPLE\n' >leadallow.txt
git add leadallow.txt
assert_passes "scaffold-allow on a leading (column-0) comment line is exempt"

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

# 22b. 2025-table-stakes provider token shapes (split so this file carries no
#      real-looking key; the scanner reassembles them in the temp repo).
echo "GL=glp""at-abcdefghij0123456789xy" >p1.txt
git add p1.txt
assert_rejects "GitLab PAT (glpat-) detected" "GitLab"

echo "NPM=npm_""abcdefghij0123456789ABCDEFGHIJ0123456" >p2.txt
git add p2.txt
assert_rejects "npm access token detected" "npm access token"

echo "STRIPE=sk_""live_abcdefghij0123456789XY" >p3.txt
git add p3.txt
assert_rejects "Stripe live key detected" "Stripe"

echo "SLACK=https://hooks.slack.com/serv""ices/T00000000/B00000000/abcdefghij0123456789" >p4.txt
git add p4.txt
assert_rejects "Slack webhook URL detected" "Slack webhook"

echo "OAI=sk-svc""acct-abcdefghij0123456789XY" >p5.txt
git add p5.txt
assert_rejects "OpenAI service-account key detected" "service-account"

echo "HF=hf_""abcdefghijABCDEFGHIJ0123456789klmn" >p6.txt
git add p6.txt
assert_rejects "Hugging Face token detected" "Hugging Face"

# 22c. JWT (header.payload). Split the eyJ prefix so this file carries no token.
echo "JWT=eyJ""hbGciOiJIUzI1NiIsR.eyJ""zdWIiOiIxMjM0NTY3OD" >p7.txt
git add p7.txt
assert_rejects "JWT in source detected" "JWT in source"

# 22d. NEGATIVE: a JWT on a scaffold-allow docs line is exempt.
echo "JWT=eyJ""hbGciOiJIUzI1NiIsR.eyJ""zdWIiOiIxMjM0NTY3OD  # scaffold-allow expired demo token" >p8.txt
git add p8.txt
assert_passes "JWT on a scaffold-allow line is exempt"

# 22e. 2025-26 credential shapes not covered by the older prefixes (split so this
#      file carries no live key; the scanner reassembles each in the temp repo).
echo "BEDROCK=ABSKQmVkcm9ja0""FQSUtleSaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >q1.txt
git add q1.txt
assert_rejects "AWS Bedrock API key (ABSK...) detected" "Bedrock"

echo "SUPA=sb_""secret_abcdefghij0123456789" >q2.txt
git add q2.txt
assert_rejects "Supabase secret key (sb_secret_) detected" "Supabase"

echo "OR=sk-""or-v1-0123456789abcdef0123456789abcdef01234567" >q3.txt
git add q3.txt
assert_rejects "OpenRouter API key (sk-or-v1-) detected" "OpenRouter"

echo "GLRT=gl""rt-abcdefghij0123456789xy" >q4.txt
git add q4.txt
assert_rejects "GitLab runner token (glrt-) detected" "GitLab token"

# 22f. Docker Hub PAT (dckr_pat_). Split the prefix (`dckr_`+`pat_`) so this .sh
#      script line carries no contiguous 20+ match — secrets.txt scans ALL text
#      files including this harness, so the temp repo reassembles the live token.
echo "DOCKER=dckr_""pat_abcdefghij0123456789ABCD" >q5.txt
git add q5.txt
assert_rejects "Docker Hub PAT (dckr_pat_) detected" "Docker Hub"

# 22g. AWS ABIA/ACCA key-id prefixes (STS bearer / context creds) — the pattern
#      previously covered only AKIA/ASIA.
echo "AWS=ABIA""IOSFODNN7EXAMPLE" >r1.txt
git add r1.txt
assert_rejects "AWS ABIA key-id prefix detected" "AWS access key"

# 22h. Slack app-level (xapp-) and config/refresh (xoxe-) tokens.
echo "SLACK=xapp-""1-A01234567-abcdefghij0123456789" >r2.txt
git add r2.txt
assert_rejects "Slack app-level token (xapp-) detected" "Slack app-level"

echo "SLACK=xoxe-""1-abcdefghij0123456789ABCDEFGHIJ" >r3.txt
git add r3.txt
assert_rejects "Slack config/refresh token (xoxe-) detected" "Slack config"

# 22i. Stripe webhook signing secret (whsec_) — forge-signed-events risk.
echo "STRIPE=whsec_""abcdefghij0123456789ABCDEFGH" >r4.txt
git add r4.txt
assert_rejects "Stripe webhook signing secret (whsec_) detected" "webhook signing"

# 22j. JWT with a compact payload (short second segment) — the {17,} floor on the
#      payload missed real minimal-claim tokens; only the header needs the floor.
echo "JWT=eyJ""hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ""pZCI6N30" >r5.txt
git add r5.txt
assert_rejects "JWT with a compact payload is detected" "JWT in source"

# 22k. A non-.txt file under .forbidden-patterns/ is now scanned — the blanket
#      dir skip let a committed creds.env there smuggle a secret unscanned.
echo "AWS=AKIA""IOSFODNN7EXAMPLE" >.forbidden-patterns/creds.env
git add .forbidden-patterns/creds.env
assert_rejects "secret in .forbidden-patterns/creds.env is scanned (not skipped)" "AWS access key"

# 22k2. …and so is a .txt there. Narrowing the dir skip to *.txt (22k) left the
#       last file-level exemption in place: a credential parked in
#       .forbidden-patterns/notes.txt passed the hook AND the whole-tree CI scan.
#       The exemption a pattern config actually needs is per-LINE and only for
#       the regex field, so a file that is not a loaded config is scanned whole.
echo "AWS=AKIA""IOSFODNN7EXAMPLE" >.forbidden-patterns/notes.txt
git add .forbidden-patterns/notes.txt
assert_rejects "secret in .forbidden-patterns/notes.txt is scanned" "AWS access key"

# 22k3. Rule-SHAPED does not mean exempt. A payload dressed as `<secret><TAB>desc`
#       in a file that no check ever loads (no scaffold-extensions header, not one
#       of the four built-in basenames) is still a payload, and is caught.
printf 'AKIA''IOSFODNN7EXAMPLE\tlooks like a rule\n' >.forbidden-patterns/notes.txt
git add .forbidden-patterns/notes.txt
assert_rejects "rule-shaped secret in an unloaded config file is scanned" "AWS access key"

# 22k4. NEGATIVE, and the reason the exemption exists at all: the shipped configs
#       must stay clean. Their regex fields look exactly like the credentials they
#       match (the AWS rule literally spells AKIA), so scanning them naively would
#       fail every commit. Asserts the POSITIVE outcome — exit 0 on the real
#       installed configs — not merely that one message is absent.
if printf '%s\0' .forbidden-patterns/secrets.txt .forbidden-patterns/backend.txt \
     .forbidden-patterns/frontend.txt .forbidden-patterns/shell.txt \
     | .githooks/lib/check-secrets >"$HOOK_OUT" 2>&1; then
  echo "  ✓ shipped pattern configs scan clean (regex fields exempt, exit 0)"; PASS=$((PASS + 1))
else
  echo "  ✗ shipped pattern configs self-matched — the per-line regex exemption is broken"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 22k5. The exemption is the REGEX FIELD only, not the whole line: a secret in a
#       rule's DESCRIPTION (after the TAB) in a loaded config is still caught.
#       Without this, "redact the pattern field" could quietly become "skip the
#       line" and the bypass would reopen one edit later.
printf 'ZZZDECOYZZZ\tsee AKIA''IOSFODNN7EXAMPLE for the real key\n' >>.forbidden-patterns/backend.txt
git add .forbidden-patterns/backend.txt
assert_rejects "secret in a rule description is still scanned" "AWS access key"

# ── Per-rule case sensitivity: the `(?-i)` marker (issue #67) ────────────────
# check-secrets used to apply -i to EVERY rule. `ACCA` is composed entirely of
# hex characters, so case-folded the AWS rule matched inside ordinary SHA-256
# digests — enough to fail any repo with a lockfile, on content holding no
# credential at all, while telling the reader to "rotate immediately".

# 22l. THE FALSE POSITIVE. A hex digest containing `acca` + 16 hex characters
#      must NOT be flagged. Written contiguously on purpose: secrets.txt scans
#      every text file including this harness, so this line is also a live
#      canary — drop the `(?-i)` marker from the AWS rule and the scaffold's own
#      self-lint goes red on this file.
echo "sha256:accab0123456789abcdef0" >fp1.txt
git add fp1.txt
assert_passes "lowercase hex digest containing 'acca' is not an AWS key"

# 22m. THE TRUE POSITIVE it must not cost. A real, correctly-cased ACCA key is
#      still rejected. This also proves the `(?-i)` marker never reaches grep:
#      if it did, the rule would be dropped as an invalid ERE and this passes.
echo "AWS=ACCA""IOSFODNN7EXAMPLE" >tp1.txt
git add tp1.txt
assert_rejects "correctly-cased ACCA key is still detected" "AWS access key"

# 22n. Keyword-shaped rules deliberately KEEP -i (they match human-written
#      prose, where case genuinely varies). An uppercase assignment must still
#      be caught, or the fix over-corrected into a fail-open. Value split
#      (`abcdefghij`+`klmnop1234`) so this harness line carries no contiguous
#      16+ run of its own — secrets.txt scans every text file, this one
#      included, and the keyword rule has no prefix to make it self-exempt.
echo 'PASSWORD = "abcdefghij''klmnop1234"' >kw1.txt
git add kw1.txt
assert_rejects "keyword rule stays case-insensitive (uppercase PASSWORD)" "Hardcoded credential"

# 22o. LOAD-VALIDITY GUARD. The `(?-i)` marker must never reach grep. Both
#      check-secrets and agent-precheck DROP a rule whose ERE grep rejects,
#      rather than failing on it — so a leaked marker does not error, it
#      silently disarms every rule carrying one (a fail-OPEN). Asserting the
#      load is clean turns that into a clear, early failure instead of a
#      confusing "allowed a secret, expected block" further down the suite.
#      Bites on GNU grep, which rejects `(?-i)`; BSD grep accepts it, so this
#      is a Linux-side guard for a bug that is invisible on macOS.
echo "benign content" >clean1.txt
git add clean1.txt
printf '%s\0' clean1.txt | .githooks/lib/check-secrets --ci >"$HOOK_OUT" 2>&1 || true
if grep -qF 'invalid pattern dropped' "$HOOK_OUT"; then
  echo "  ✗ shipped secrets.txt has rules grep rejects — the (?-i) marker leaked:"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
else
  echo "  ✓ every shipped secrets.txt rule loads as a valid ERE (no marker leak)"
  PASS=$((PASS + 1))
fi
reset_repo
