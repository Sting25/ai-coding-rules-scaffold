# shellcheck shell=bash
# cases/37-doctor-content-drift.sh — the two scaffold-doctor checks that judge
# CONTENT rather than arming: has the installed pattern data drifted from what
# the scaffold shipped, and has .gitignore taken tracked source out of ESLint's
# reach. Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) are already in scope.
#
# WHY THESE TWO LIVE TOGETHER, AND NOT IN cases/18. Every other doctor
# assertion asks "is this mechanism armed": a bit, a path, a call site, a file's
# presence. These two ask a harder question — the mechanism is armed and the
# file is there, but its CONTENT no longer covers what it is supposed to cover.
# Both derive their expectation from something else on disk instead of
# hardcoding it (the shipped forbidden-patterns template; the project's own
# .gitignore), so both are one sloppy edit away from the same failure mode: a
# check that widens into "report any difference", goes red on legitimate
# customization, gets switched off, and leaves the real hole open under a green
# report. That is why each of them is a PAIR here — the red half and the
# narrowing half — and why the pairs are worth keeping side by side.
#
# cases/18 keeps the arming checks and points here; splitting them was also what
# kept both files under the 500-line cap in coding-rules.md rule 1.
#
# Helpers are prefixed docd_ and this file builds its own fixture project rather
# than reusing cases/18's doc_project: case files are sourced into one shell, so
# borrowing a function defined by an earlier file would make the ORDER of the
# case list load-bearing and would break this file when run on its own.

echo "cases/37: scaffold-doctor's content-drift checks (shipped rules, .gitignore lint holes)"

# A fresh installed project. --shell deliberately: a package.json fixture makes
# the hook chase a JS toolchain and go red on one runner only, and that failure
# then gets misread as a verdict on whatever was actually under test.
docd_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" \
    && echo '#!/usr/bin/env bash' >run.sh \
    && "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (A) SHIPPED-RULE DRIFT. Counting active patterns only catches the file gutted
# to ZERO (cases/18 covers that one), which no realistic hand-edit produces. A
# secrets.txt trimmed from its 42 shipped rules to ONE left every layer green —
# "armed (1 active patterns)", check-secrets fails closed only at zero, and
# pre-commit's deleted-config guard fires only on whole-file deletion — so an
# agent could drop the AWS/JWT/PEM rules in one commit and land a live key in
# the next. The count is derived from the shipped template rather than
# hardcoded, so adding a rule to the scaffold does not turn this into a false
# red.
docd_trim_secrets() {
  grep -vE '^[[:space:]]*(#|$)' .forbidden-patterns/secrets.txt | head -1 >secrets.tmp \
    && mv secrets.tmp .forbidden-patterns/secrets.txt
}
DOCD=$(docd_project)
( cd "$DOCD" && docd_trim_secrets ) >/dev/null 2>&1
docd_rc=0
( cd "$DOCD" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docd_rc=$?
docd_shipped=$(grep -cvE '^[[:space:]]*(#|$)' "$SCAFFOLD_DIR/forbidden-patterns/secrets.txt.template" || true)
docd_missing=$(sed -n 's/.*secrets\.txt is missing \([0-9][0-9]*\) shipped rule(s).*/\1/p' "$HOOK_OUT" | tail -1)
# The file must still be present and still counted armed, or this would only be
# re-proving cases/18's "missing secrets.txt" and "no active patterns" cases.
if [ "$docd_rc" -eq 1 ] && [ -s "$DOCD/.forbidden-patterns/secrets.txt" ] \
   && grep -qF "secrets.txt armed (1 active patterns)" "$HOOK_OUT" \
   && grep -qF "shipped rule(s)" "$HOOK_OUT" \
   && [ "${docd_missing:-0}" -eq $((docd_shipped - 1)) ] \
   && grep -q '^        - ' "$HOOK_OUT"; then
  echo "  ✓ a secrets.txt trimmed to one rule is reported as shipped-rule drift"
  PASS=$((PASS + 1))
else
  echo "  ✗ trimmed secrets.txt not reported as drift (exit $docd_rc, missing ${docd_missing:-none} of $docd_shipped)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCD"

# ...and the narrowing companion, without which "report missing shipped rules"
# could quietly widen into "report any difference" one edit later. These files
# are shipped-then-EXTENDED by design: a project adding its own denylist rules
# has lost nothing, so the doctor must stay silent and exit 0. A drift check
# that goes red on legitimate customization gets switched off, and then the
# trimmed-secrets hole above is open again.
docd_extend_patterns() {
  printf '(?-i)ACME_INTERNAL_[A-Z0-9]{16}\tacme internal token\n' >>.forbidden-patterns/secrets.txt
  printf '# a house rule of our own\n' >>.forbidden-patterns/shell.txt
  printf 'acme_deploy_prod\tno prod deploys from a shell script\n' >>.forbidden-patterns/shell.txt
}
DOCD=$(docd_project)
( cd "$DOCD" && docd_extend_patterns ) >/dev/null 2>&1
docd_rc=0
( cd "$DOCD" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docd_rc=$?
if [ "$docd_rc" -eq 0 ] && grep -qF "0 gaps" "$HOOK_OUT" \
   && ! grep -qF "shipped rule(s)" "$HOOK_OUT"; then
  echo "  ✓ pattern files with locally ADDED rules report no drift"
  PASS=$((PASS + 1))
else
  echo "  ✗ locally added pattern rules were reported as drift (exit $docd_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCD"

# (B) ESLint's ignore list is DERIVED from .gitignore: eslint.config.js.template
# calls includeIgnoreFile(.gitignore) (#76 — a hardcoded list only covers the
# names someone thought of). The derivation stays; what was unguarded is its
# cost. One appended .gitignore line un-lints a whole tree, at pre-commit AND in
# CI, because both hand eslint explicit paths and an ignored-but-modified file
# yields only a non-fatal warning and exit 0 — while gitignore untracks nothing,
# so the code keeps shipping with every rule off. That is a diff nobody reads as
# a lint change, and it was the one edit an agent could make to silence lint.
docd_eslint_derived() {
  cat >eslint.config.js <<'ESLINT_DERIVED'
import fs from 'node:fs';
import path from 'node:path';

import { includeIgnoreFile } from '@eslint/compat';

const gitignorePath = path.resolve(import.meta.dirname, '.gitignore');
const gitignore = fs.existsSync(gitignorePath) ? [includeIgnoreFile(gitignorePath)] : [];

export default [...gitignore];
ESLINT_DERIVED
}
# A TRACKED source file put out of ESLint's reach by one .gitignore line. It has
# to be tracked or it proves nothing: ignoring a file does not untrack it, and
# "still committed, no longer linted" is the entire hole.
docd_ignore_source() {
  docd_eslint_derived
  mkdir -p src
  printf 'export const answer = 42;\n' >src/legacy.ts
  git add -f src/legacy.ts
  printf 'node_modules/\ndist/\nsrc/legacy.ts\n' >>.gitignore
}
# ...and the .gitignore of a normal, correct project: build output, a vendored
# library, a minified bundle and a type stub, all tracked, all ignored, none of
# them a lint hole. Named build/vendor/generated paths are exactly what a
# .gitignore is FOR, so every one of these must stay silent.
docd_ignore_build_output() {
  docd_eslint_derived
  mkdir -p src dist vendor
  printf 'export const answer = 42;\n' >src/app.ts
  printf 'var b = 1;\n' >dist/bundle.js
  printf 'var v = 1;\n' >vendor/jquery.js
  printf 'var m = 1;\n' >app.min.js
  printf 'export declare const x: number;\n' >types.d.ts
  git add -f src/app.ts dist/bundle.js vendor/jquery.js app.min.js types.d.ts
  printf 'node_modules/\ndist/\nbuild/\ncoverage/\n*.min.js\nvendor/\n*.d.ts\n.next/\nout/\n' >>.gitignore
}

DOCD=$(docd_project)
( cd "$DOCD" && docd_ignore_source ) >/dev/null 2>&1
docd_rc=0
( cd "$DOCD" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docd_rc=$?
# The detail line is asserted in full: naming the count without naming the FILE
# and the RULE that hides it leaves the reader with nothing to act on, and a
# check that reported a bare number would pass a laxer assertion.
if [ "$docd_rc" -eq 1 ] \
   && grep -qF "hides 1 tracked source file(s) from ESLint" "$HOOK_OUT" \
   && grep -qF "        - src/legacy.ts  (.gitignore: src/legacy.ts)" "$HOOK_OUT"; then
  echo "  ✓ a tracked source file ignored by .gitignore is reported as unlinted"
  PASS=$((PASS + 1))
else
  echo "  ✗ a .gitignore'd tracked source file was not reported (exit $docd_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCD"

# ...and the narrowing companion, without which "report source hidden from the
# linter" widens into "report any .gitignore entry" one edit later. Every real
# .gitignore names node_modules/, dist/, coverage/ and *.min.js, and some of
# those paths are tracked in real repos (a committed bundle, a vendored lib).
# A doctor that went red there would be switched off within a day, and then the
# hole above is open again with a green report over it. The armed line is
# asserted too: without it, a check that had stopped running entirely would sail
# through this case on exit 0 alone.
DOCD=$(docd_project)
( cd "$DOCD" && docd_ignore_build_output ) >/dev/null 2>&1
docd_rc=0
( cd "$DOCD" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || docd_rc=$?
if [ "$docd_rc" -eq 0 ] && grep -qF "0 gaps" "$HOOK_OUT" \
   && ! grep -qF "tracked source file(s) from ESLint" "$HOOK_OUT" \
   && grep -qF "eslint.config.js derives ESLint's ignores from .gitignore" "$HOOK_OUT"; then
  echo "  ✓ a normal .gitignore (node_modules, dist, coverage, *.min.js) stays silent"
  PASS=$((PASS + 1))
else
  echo "  ✗ a normal .gitignore produced lint-ignore noise (exit $docd_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCD"

unset DOCD docd_rc docd_shipped docd_missing
unset -f docd_project docd_trim_secrets docd_extend_patterns
unset -f docd_eslint_derived docd_ignore_source docd_ignore_build_output
reset_repo
