# shellcheck shell=bash
# cases/12-install-backup-cap.sh — install.sh's _backup >99-cap must not abort the
# whole run (audit B12). Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) and helpers (reset_repo) are already in scope.
# Split out of cases/09 (which is at the 500-line module cap) rather than weakened.

echo "cases/12 — install backup-cap skip (B12)"

# With all 100 .scaffold-bak[.N] slots taken for one --force'd file, _backup used
# to `return 1`; the bare cp_safe call then aborted the entire script under set -e,
# leaving hooks unwired with no summary. It now SKIPS that one file — leaving the
# user's version untouched (no backup ⇒ no safe overwrite) — and finishes the rest.
B12=$(mktemp -d)
( cd "$B12" && git init --quiet && echo '{"name":"x"}' >package.json && echo 'name="x"' >pyproject.toml \
  && "$SCAFFOLD_DIR/install.sh" --both --no-verify >/dev/null 2>&1 )
# Make ruff.toml (a user-owned cp_safe file) differ so --force will try to back it up.
echo '# LOCAL EDIT B12' >>"$B12/ruff.toml"
# Saturate the backup slots: base + .1..99 = 100 existing ⇒ the cap trips.
: >"$B12/ruff.toml.scaffold-bak"
for i in $(seq 1 99); do : >"$B12/ruff.toml.scaffold-bak.$i"; done
if ( cd "$B12" && "$SCAFFOLD_DIR/install.sh" --both --force --no-verify ) >"$HOOK_OUT" 2>&1 \
   && grep -q 'too many .scaffold-bak' "$HOOK_OUT" \
   && grep -q 'Done' "$HOOK_OUT" \
   && grep -q 'LOCAL EDIT B12' "$B12/ruff.toml"; then
  echo "  ✓ install skips an over-backup-capped file and completes (no mid-run abort) (B12)"; PASS=$((PASS + 1))
else
  echo "  ✗ install aborted on the backup cap or clobbered the capped file (B12)"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$B12"
reset_repo
