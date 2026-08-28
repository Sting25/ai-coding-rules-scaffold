# shellcheck shell=bash
# cases/22-large-file-guard.sh: byte-size guard for accidentally committed
# large binaries (P-15, check-large-files), distinct from check-size's
# 500-LINE cap. Sourced into the driver's shell; cwd is "$WORK".
#
# Fixtures are built from a single repeated non-secret-looking 40-char line
# ("x" * 40, no digits, no keywords) so this file's own source never becomes
# a live example of what it tests. Every fixture uses a ".txt" extension,
# which check-size skip-lists, so these cases stay isolated to the byte-size
# check alone (same convention cases/08-overrides-gitleaks.sh uses for its
# override fixtures). Lines stay 41 bytes each (40 chars + newline), well
# under check-secrets' MAX_LINE_LENGTH cap, so a large fixture here never
# also trips an unrelated "line too long to scan" failure.

echo "Large-file guard test cases:"

LARGE_FILE_LINE=$(printf '%040d' 0 | tr '0' 'x')

# Write $1 copies of LARGE_FILE_LINE (one per line) to $2. Uses `yes | head`,
# whose producer (`yes`) gets SIGPIPE once `head` closes the pipe after $1
# lines. That's the expected, harmless end of this pipeline, but this suite
# inherits `set -o pipefail` from the driver, which would otherwise treat it
# as a failure and abort the whole run under `set -e`. Suppressed only for
# the one pipeline that needs it, restored immediately after.
gen_file() {
  local n=$1 out=$2
  set +o pipefail
  yes "$LARGE_FILE_LINE" | head -n "$n" >"$out"
  set -o pipefail
}

# a. Over the default 500 KB (512000 byte) cap is rejected.
#    20000 lines * 41 bytes/line = 820000 bytes.
gen_file 20000 big1.txt
git add big1.txt
assert_rejects "large-file guard: file over the default 500 KB cap is rejected" "git-lfs"

# b. Under the default cap passes. 1000 lines * 41 bytes/line = 41000 bytes.
gen_file 1000 small1.txt
git add small1.txt
assert_passes "large-file guard: file under the default cap passes"

# c. [large-files] default override LOWERS the cap: the same 41000-byte file
#    that passed in (b) is rejected under a 30000-byte project cap.
printf '[large-files]\ndefault = 30000\n' >.scaffold.toml
gen_file 1000 small2.txt
git add .scaffold.toml small2.txt
assert_rejects "override: [large-files] default lowers the cap" "git-lfs"

# d. [large-files] default override RAISES the cap: the same 820000-byte file
#    that was rejected in (a) now passes under a 2000000-byte project cap.
printf '[large-files]\ndefault = 2000000\n' >.scaffold.toml
gen_file 20000 big2.txt
git add .scaffold.toml big2.txt
assert_passes "override: [large-files] default raises the cap"

# e. [rules.large-files] disabled turns the check off entirely: the
#    over-cap file from (a) passes with no byte-size enforcement at all.
printf '[rules.large-files]\ndisabled = true\n' >.scaffold.toml
gen_file 20000 big3.txt
git add .scaffold.toml big3.txt
assert_passes "override: [rules.large-files] disabled skips the check"

# f. [rules.large-files] severity = "warn" reports the oversize file but does
#    NOT fail the build, the same warn convention every other check honors.
printf '[rules.large-files]\nseverity = "warn"\n' >.scaffold.toml
gen_file 20000 big4.txt
git add .scaffold.toml big4.txt
if .githooks/pre-commit >"$HOOK_OUT" 2>&1; then
  if grep -qF "(warn, .scaffold.toml override)" "$HOOK_OUT" && grep -qF "big4.txt" "$HOOK_OUT"; then
    echo "  ✓ override: [rules.large-files] severity=warn reports without failing"; PASS=$((PASS + 1))
  else
    echo "  ✗ override: large-files warn passed but emitted no warn notice for the file"
    sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ✗ override: [rules.large-files] severity=warn, hook failed, expected pass-with-warning"
  sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
reset_repo
