# shellcheck shell=bash
# cases/42-doctor-narrow-path.sh — scaffold-doctor under a PATH narrowed to the
# tools the shipped checks themselves need (bash git grep sed awk basename): the
# "binary not on PATH" classifications, and the doctor finding its own bundle
# without dirname(1). Sourced into the driver's shell after cases/18, so its
# doc_project helper and the globals (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) are in
# scope. Split out of cases/18 (at the 500-line module cap) rather than weakened.
#
# Why this exists as its own file: bash 5.3 (ubuntu-26.04) made `cd ""` fail,
# and the doctor's `$(cd "$(dirname "$0")" && pwd)` became exactly that under
# this PATH, killing it under set -e. The v0.19.0 release run died there.

echo "cases/42 — scaffold-doctor under a narrowed PATH"

# (H) The two opt-in surfaces both fail OPEN when their tool is missing, and the
# doctor's severities deliberately DIVERGE because their loudness does:
# check-gitleaks announces itself on every commit (note), agent-precheck exits 0
# with empty output (gap). Verified by measurement, not by symmetry.
#
# doc_minbin builds a PATH containing only the binaries the doctor itself needs,
# so the result cannot depend on whether a given runner happens to ship jq or
# gitleaks. Symlinks are resolved from the real PATH rather than hardcoded,
# because jq lives in /usr/bin on some machines and /opt/homebrew/bin on others.
doc_minbin() {
  local d tool src
  d=$(mktemp -d)
  for tool in bash git grep sed awk basename; do
    src=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$src" "$d/$tool"
  done
  printf '%s' "$d"
}

doc_project DOCT
DOCBIN=$(doc_minbin)
cp "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" "$DOCT/.githooks/lib/check-gitleaks"
chmod +x "$DOCT/.githooks/lib/check-gitleaks"
# The CI twin too: the paired-artifacts section flags a hook with no gitleaks.yml
# as a gap (exit 1), and it RUNS here. It used to be skipped under this narrowed
# PATH only because dirname(1) was missing and the doctor lost its own bundle,
# so this test's exit 0 was passing on that accident until bash 5.3 made it die.
mkdir -p "$DOCT/.github/workflows"
cp "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template" "$DOCT/.github/workflows/gitleaks.yml"
doc_rc=0
( cd "$DOCT" && PATH="$DOCBIN" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ] && grep -qF "the local scan is a no-op" "$HOOK_OUT"; then
  echo "  ✓ a gitleaks hook with no binary is a note (it warns on every commit itself)"
  PASS=$((PASS + 1))
else
  echo "  ✗ gitleaks-without-binary misclassified (exit $doc_rc, wanted 0 + a note)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
# Positive check that the narrowed PATH cost the doctor nothing but gitleaks
# itself: every other section must report exactly what a full-PATH run reports.
# (The gitleaks line and the armed/note tallies are the only legitimate diffs.)
doc_full=$(mktemp)
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$doc_full" 2>&1 || true
# No multibyte glyph inside a bracket expression: under a C locale grep matches
# it byte-wise and the tally line slips through; match the words instead.
doc_strip() { grep -vE 'check-gitleaks| armed: [0-9]+ check| guardrail\(s\) installed but' "$1"; }
if diff <(doc_strip "$HOOK_OUT") <(doc_strip "$doc_full") >/dev/null; then
  echo "  ✓ the narrowed-PATH report matches the full-PATH report outside the gitleaks line"
  PASS=$((PASS + 1))
else
  echo "  ✗ the narrowed-PATH report diverges from the full-PATH report (bundle not resolved?)"
  # `|| true`: diff exits 1 on a difference, and under the runner's pipefail that
  # would abort the whole suite instead of counting one failure.
  { diff <(doc_strip "$HOOK_OUT") <(doc_strip "$doc_full") || true; } | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi
rm -f "$doc_full"
rm -rf "$DOCT"

# agent-precheck with no jq says NOTHING, anywhere, ever — so it is a gap.
doc_project DOCT
cp "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" "$DOCT/.githooks/lib/agent-precheck"
chmod +x "$DOCT/.githooks/lib/agent-precheck"
doc_rc=0
( cd "$DOCT" && PATH="$DOCBIN" "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 1 ] && grep -qF "jq is not on PATH" "$HOOK_OUT"; then
  echo "  ✓ an agent-precheck with no jq is a gap (it fails open in total silence)"
  PASS=$((PASS + 1))
else
  echo "  ✗ agent-precheck-without-jq misclassified (exit $doc_rc, wanted 1)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT" "$DOCBIN"
