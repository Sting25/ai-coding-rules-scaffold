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
