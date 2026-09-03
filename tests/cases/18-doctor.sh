# shellcheck shell=bash
# cases/18-doctor.sh — scaffold-doctor must report guardrails that are INSTALLED
# but NOT RUNNING. Sourced into the driver's shell, so the globals
# (PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR) are already in scope.
#
# Every assertion here is mutation-shaped: build a healthy install, break
# exactly ONE arming mechanism, and require the doctor to both name it and exit
# non-zero. A doctor that cannot go red is precisely the failure it exists to
# catch, so "it printed something" is never the assertion.

echo "cases/18 — scaffold-doctor (armed vs merely installed)"

# A fresh installed project. --shell deliberately: a package.json fixture makes
# the hook chase a JS toolchain and go red on one runner only, and that failure
# then gets misread as a verdict on whatever was actually under test.
doc_project() {
  local t
  t=$(mktemp -d)
  ( cd "$t" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" \
    && echo '#!/usr/bin/env bash' >run.sh \
    && "$SCAFFOLD_DIR/install.sh" --shell --no-verify ) >/dev/null 2>&1
  printf '%s' "$t"
}

# Mutations that need a variable expanded at run time are shell FUNCTIONS, not
# `bash -c '...'`: the subshell doc_case spawns inherits them, and a single-quoted
# bash -c carrying a "$VAR" trips SC2016 under CI's `shellcheck -S info`.
doc_hookspath_absolute()  { git config core.hooksPath "$PWD/.githooks"; }
doc_commit_msg_nonexec()  {
  cp "$SCAFFOLD_DIR/githooks/commit-msg.template" .githooks/commit-msg \
    && chmod -x .githooks/commit-msg
}

# doc_case <name> <want-exit> <expect-substring> <mutation cmd...>
# The mutation runs inside the project; `true` means "leave it healthy".
doc_case() {
  local name=$1 want=$2 expect=$3
  shift 3
  local t rc=0
  t=$(doc_project)
  ( cd "$t" && "$@" ) >/dev/null 2>&1 || true
  ( cd "$t" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ] && grep -qF "$expect" "$HOOK_OUT"; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name (exit $rc, wanted $want, or missing: $expect)"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$t"
}

# (A) The healthy baseline. Without this the red cases below prove nothing —
# a doctor that always exits 1 would pass every mutation assertion.
doc_case "a clean install reports 0 gaps and exits 0" 0 "0 gaps" true

# (B) Wiring. The highest-value check: everything else can be perfect and none
# of it runs. install.sh LEAVES a foreign hooksPath alone by design (it only
# warns), so "installed but never wired" is a state install.sh itself produces.
doc_case "a foreign core.hooksPath is reported as not wired" 1 \
  "core.hooksPath = '.husky'" git config core.hooksPath .husky
doc_case "an unset core.hooksPath is reported as not wired" 1 \
  "core.hooksPath is unset" git config --unset core.hooksPath

# ...but git accepts several spellings of the SAME directory and honours every
# one of them (measured: a planted AKIA key is blocked under each). Comparing
# raw strings instead of resolved paths reported all three as gaps — a hard red
# on a project whose guardrails demonstrably work, which is worse than a missed
# note because it teaches the reader to stop trusting the report.
doc_case "an absolute core.hooksPath pointing at .githooks is armed, not a gap" 0 \
  "0 gaps" doc_hookspath_absolute
doc_case "a ./-prefixed core.hooksPath is armed, not a gap" 0 \
  "0 gaps" git config core.hooksPath ./.githooks
doc_case "a trailing-slash core.hooksPath is armed, not a gap" 0 \
  "0 gaps" git config core.hooksPath .githooks/

# ...and none of those spellings may depend on the caller's environment. CDPATH,
# which plenty of shell profiles export, makes `cd` ECHO the directory it landed
# in on STDOUT, where the `2>/dev/null` on those cd's cannot suppress it. The
# relative `cd .githooks` picked up the echo and the absolute one did not, so
# the two resolved paths stopped matching and a demonstrably wired project was
# reported as a hard gap, exit 1. Every case above sets no CDPATH, so the whole
# spelling family was certified healthy in exactly the environment that works.
doc_hookspath_relative() { git config core.hooksPath ./.githooks; }
for doc_spell in doc_hookspath_absolute doc_hookspath_relative; do
  DOCT=$(doc_project)
  ( cd "$DOCT" && "$doc_spell" ) >/dev/null 2>&1
  doc_rc=0
  ( cd "$DOCT" && CDPATH=. "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
  if [ "$doc_rc" -eq 0 ] && grep -qF "0 gaps" "$HOOK_OUT"; then
    echo "  ✓ ${doc_spell#doc_hookspath_} core.hooksPath stays armed with CDPATH set"
    PASS=$((PASS + 1))
  else
    echo "  ✗ CDPATH turned a wired ${doc_spell#doc_hookspath_} hooksPath into a gap (exit $doc_rc)"
    sed 's/^/      /' "$HOOK_OUT"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$DOCT"
done

# (C) git ignores a hook file without the executable bit — no error, no warning,
# no commit blocked.
doc_case "a non-executable pre-commit is reported" 1 \
  ".githooks/pre-commit is not executable" chmod -x .githooks/pre-commit
doc_case "a non-executable commit-msg hook is reported" 1 \
  ".githooks/commit-msg is not executable" \
  doc_commit_msg_nonexec

# (D) Pattern data. check-secrets exits 0 SILENTLY when secrets.txt is absent
# (leniency for pre-install checkouts), so absence is a live hole, not a loud
# failure — measured: with secrets.txt gone, a real AKIA key commits clean.
doc_case "a missing secrets.txt is reported" 1 \
  "secrets.txt is missing" rm -f .forbidden-patterns/secrets.txt
doc_case "a secrets.txt gutted to comments is reported" 1 \
  "no active patterns" bash -c 'printf "# emptied\n" >.forbidden-patterns/secrets.txt'

# check-patterns auto-discovers .forbidden-patterns/*.txt; with the directory
# gone the glob matches nothing, the loop body never runs, and the scanner
# exits 0 — a pattern scanner reporting success while scanning nothing.
doc_case "a missing .forbidden-patterns/ directory is reported" 1 \
  ".forbidden-patterns/ is missing" rm -rf .forbidden-patterns

# A pattern file with no extension mapping is skipped with a warning on hook
# stderr, which scrolls past unread.
doc_case "a pattern file with no scaffold-extensions header is reported" 1 \
  "no '# scaffold-extensions:' header" \
  bash -c 'printf "forbidden\tno header here\n" >.forbidden-patterns/custom.txt'

# Both of those catch only the file gutted to ZERO active rules, which no
# realistic hand-edit produces: a secrets.txt trimmed from its 42 shipped rules
# to ONE stays "armed (1 active patterns)" and sails through every assertion
# above. That drift case, and the narrowing companion that keeps it from going
# red on a project's own added rules, are cases/37 — they judge the file's
# CONTENT against the shipped template rather than its arming, which is the line
# this file stops at.

# (E) Overrides. scaffold-config fails open to EMPTY output when missing, and
# empty output means "no override" — so a .scaffold.toml full of intentional
# overrides is silently ignored.
doc_case "a .scaffold.toml with no scaffold-config helper is reported" 1 \
  "silently ignored" rm -f .githooks/lib/scaffold-config

# A rule switched off in .scaffold.toml is a deliberately disarmed guardrail:
# never a gap (the project asked for it), but the doctor used to pipe the audit
# block through sed and never count or classify a single line of it, so the run
# still summarised as "N check(s) running, 0 gaps" with the whole size rule and
# the 500 KB cap off. Under --quiet, the mode a CI step or an agent asked "what
# is off here?" actually reads, the overrides did not appear at all: the output
# was byte-identical with and without the disables.
doc_disable_rules() {
  cat >.scaffold.toml <<'DISABLED_TOML'
[rules."large-files"]
disabled = true
reason = "large binary fixtures"

[rules."size"]
disabled = true

[rules."shell/curl piped to shell"]
severity = "warn"
DISABLED_TOML
}
doc_raise_caps() {
  cat >.scaffold.toml <<'CAPS_TOML'
[size]
max_lines = 5000
CAPS_TOML
}
# The note count in the summary line, so "the report mentions it somewhere" is
# not mistaken for "the report counts it".
doc_note_count() { sed -n 's/.*, \([0-9][0-9]*\) note(s).*/\1/p' "$1" | tail -1; }

DOCT=$(doc_project)
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
doc_notes_before=$(doc_note_count "$HOOK_OUT")
( cd "$DOCT" && doc_disable_rules ) >/dev/null 2>&1
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
doc_notes_after=$(doc_note_count "$HOOK_OUT")
if [ "$doc_rc" -eq 0 ] \
   && grep -qF 'rule "large-files" is DISABLED' "$HOOK_OUT" \
   && grep -qF 'rule "size" is DISABLED' "$HOOK_OUT" \
   && grep -qF 'rule "shell/curl piped to shell" is downgraded to severity=warn' "$HOOK_OUT" \
   && [ "$doc_notes_after" -eq $((doc_notes_before + 3)) ]; then
  echo "  ✓ --quiet names every disabled rule and counts it as a note"
  PASS=$((PASS + 1))
else
  echo "  ✗ --quiet hid the .scaffold.toml disables (exit $doc_rc, notes $doc_notes_before -> $doc_notes_after)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
# The full report must name them too, as notes rather than as an uncounted
# passthrough of the audit block.
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ] && [ "$(grep -c 'is DISABLED in .scaffold.toml' "$HOOK_OUT")" -eq 2 ]; then
  echo "  ✓ the full report classifies each disable as a note, not a gap"
  PASS=$((PASS + 1))
else
  echo "  ✗ full report mishandled the disables (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# A raised cap disarms a guardrail exactly as a disable does, so it is reported
# the same way, with the new value, because "500 KB" is the thing the reader
# believes is in force.
DOCT=$(doc_project)
( cd "$DOCT" && doc_raise_caps ) >/dev/null 2>&1
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ] && grep -qF "[size] cap overridden in .scaffold.toml: max_lines = 5000" "$HOOK_OUT"; then
  echo "  ✓ --quiet names a raised cap and the value now in force"
  PASS=$((PASS + 1))
else
  echo "  ✗ a raised cap went unreported under --quiet (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# ...and the shipped, override-free .scaffold.toml must stay silent: a doctor
# that reported an off-switch on every clean project would train the reader to
# skip the line that matters.
DOCT=$(doc_project)
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ] && grep -qF "0 gaps" "$HOOK_OUT" \
   && ! grep -qF "in .scaffold.toml" "$HOOK_OUT"; then
  echo "  ✓ an override-free .scaffold.toml reports no off-switches"
  PASS=$((PASS + 1))
else
  echo "  ✗ a clean .scaffold.toml produced override noise (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# (F) In local.d/ the executable bit IS the on/off switch, so a non-executable
# entry is a deliberate state. It must be REPORTED but must NOT count as a gap —
# a doctor that cries wolf about intentional configuration stops being read.
doc_case "a non-executable local.d check is a note, not a gap" 0 \
  "off switch" \
  bash -c 'printf "#!/bin/sh\nexit 0\n" >.githooks/local.d/mine.sh && chmod -x .githooks/local.d/mine.sh'
doc_case "an executable local.d check is reported armed" 0 \
  "local.d/mine.sh armed" \
  bash -c 'printf "#!/bin/sh\nexit 0\n" >.githooks/local.d/mine.sh && chmod +x .githooks/local.d/mine.sh'

# (G) The shipped checks are called unguarded by the orchestrator, so a missing
# one breaks every commit. Loud, not silent — but still worth naming precisely.
doc_case "a shipped check the manifest recorded but that is now missing is a gap" 1 \
  "lib/check-hygiene was installed (recorded in .githooks/.scaffold-manifest) and is now missing" rm -f .githooks/lib/check-hygiene
# Absent AND not in the manifest is a project that adopted a subset by hand
# (COMPONENTS.md): the hook runs what is present, so this is a note, exit 0.
doc_case "a shipped check that was never adopted is a note, not a gap" 0 \
  "lib/check-hygiene not adopted" \
  bash -c 'rm -f .githooks/lib/check-hygiene && grep -v "lib/check-hygiene\$" .githooks/.scaffold-manifest >m.tmp && mv m.tmp .githooks/.scaffold-manifest'

# ...but on-disk-and-executable was the ONLY thing this section tested, which is
# issue #72 restated: an upgrade preserved a customized lint.yml with no
# check-large-files call site, the script sat on disk, and the report said
# "lib/check-large-files armed ... 0 gaps" while an oversized file committed
# clean. A check nothing calls is decoration, and the doctor has to say so.
# The hook and lint.yml call every present scanner through one discovery
# loop over lib/check-*, so "no call site" means that loop line is gone.
doc_drop_ci_callsite() {
  grep -v 'lib/check-\*' .github/workflows/lint.yml >lint.tmp && mv lint.tmp .github/workflows/lint.yml
}
doc_drop_all_callsites() {
  doc_drop_ci_callsite
  grep -v -F "\"\$LIB\"/check-*" .githooks/pre-commit >pc.tmp && mv pc.tmp .githooks/pre-commit
  chmod +x .githooks/pre-commit
}

DOCT=$(doc_project)
( cd "$DOCT" && doc_drop_all_callsites ) >/dev/null 2>&1
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
# The script must still be present AND executable, or this would only be
# re-proving the "missing check" case above.
if [ "$doc_rc" -eq 1 ] && [ -x "$DOCT/.githooks/lib/check-large-files" ] \
   && grep -qF "lib/check-large-files is installed and executable but nothing calls it" "$HOOK_OUT"; then
  echo "  ✓ a check with no call site anywhere is a gap, not \"armed\""
  PASS=$((PASS + 1))
else
  echo "  ✗ an uncalled check was reported armed (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# With only the CI half gone the hook still runs it, so this is half-wired, not
# inert: a note, not a gap. It must survive --quiet, because that is the mode a
# CI step or a pre-flight script reads, and "armed, 0 gaps" over a check no CI
# job runs is the misleading summary #72 was made of.
DOCT=$(doc_project)
( cd "$DOCT" && doc_drop_ci_callsite ) >/dev/null 2>&1
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
# With one discovery loop there is no per-scanner CI call site to lose: losing
# the loop loses the whole server-side mirror, which is a gap (a --no-verify
# commit reaches main unchecked), and --quiet must still show it with its
# section name so a one-line report is not a green one.
if [ "$doc_rc" -eq 1 ] \
   && grep -qF "[server-side backstop] .github/workflows/lint.yml exists but its guardrails job no longer invokes" "$HOOK_OUT"; then
  echo "  ✓ a lint.yml that lost the scanner loop is a --quiet-visible gap, exit 1"
  PASS=$((PASS + 1))
else
  echo "  ✗ missing CI scanner loop misreported under --quiet (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT" | head -6
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

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

DOCT=$(doc_project)
DOCBIN=$(doc_minbin)
cp "$SCAFFOLD_DIR/githooks/lib/check-gitleaks.template" "$DOCT/.githooks/lib/check-gitleaks"
chmod +x "$DOCT/.githooks/lib/check-gitleaks"
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
rm -rf "$DOCT"

# agent-precheck with no jq says NOTHING, anywhere, ever — so it is a gap.
DOCT=$(doc_project)
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

# agent-precheck's executable bit is load-bearing in a way check-gitleaks' is
# not: claude-settings.json and cursor-hooks.json invoke the PATH DIRECTLY as a
# command, with no -x guard anywhere, so a cleared bit yields exit 126 — and the
# agent runtimes block only on exit 2. Measured: the tool call proceeds, and
# nothing is printed anywhere. The doctor reported "armed" for this until it
# was caught in review.
DOCT=$(doc_project)
cp "$SCAFFOLD_DIR/githooks/lib/agent-precheck.template" "$DOCT/.githooks/lib/agent-precheck"
chmod -x "$DOCT/.githooks/lib/agent-precheck"
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 1 ] && grep -qF "exit 126" "$HOOK_OUT"; then
  echo "  ✓ a non-executable agent-precheck is a gap (126 is not the 2 that blocks)"
  PASS=$((PASS + 1))
else
  echo "  ✗ a non-executable agent-precheck was reported armed (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# (I) The shipped checks read their config by bare relative path, which works
# only because git runs hooks from the top of the tree. A doctor run from a
# subdirectory must reproduce that or it reports phantom gaps.
DOCT=$(doc_project)
mkdir -p "$DOCT/src/deep"
doc_rc=0
( cd "$DOCT/src/deep" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 0 ] && grep -qF "0 gaps" "$HOOK_OUT"; then
  echo "  ✓ runs from a subdirectory without reporting phantom gaps"
  PASS=$((PASS + 1))
else
  echo "  ✗ reported gaps when run from a subdirectory (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# (J) Outside a git working tree there is no hooksPath to inspect and no project
# to judge. Exit 2 (usage) keeps that distinguishable from "found gaps".
DOCT=$(mktemp -d)
doc_rc=0
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 2 ] && grep -qF "not a git repository" "$HOOK_OUT"; then
  echo "  ✓ outside a git repo it exits 2, distinct from a gap exit"
  PASS=$((PASS + 1))
else
  echo "  ✗ wrong behavior outside a git repo (exit $doc_rc, wanted 2)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# (K) --quiet is what a CI step or a pre-flight script would call: gaps and the
# summary only, with the section named inline since the headers are suppressed.
doc_rc=0
DOCT=$(doc_project)
chmod -x "$DOCT/.githooks/pre-commit"
( cd "$DOCT" && "$SCAFFOLD_DIR/scaffold-doctor.sh" --quiet ) >"$HOOK_OUT" 2>&1 || doc_rc=$?
if [ "$doc_rc" -eq 1 ] && grep -qF "[hook entry point]" "$HOOK_OUT" && ! grep -qF "✓" "$HOOK_OUT"; then
  echo "  ✓ --quiet prints gaps with their section and suppresses the armed lines"
  PASS=$((PASS + 1))
else
  echo "  ✗ --quiet output wrong (exit $doc_rc)"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$DOCT"

# (L) The .gitignore-derived ESLint ignore check (#76) — eslint.config.js
# calls includeIgnoreFile(.gitignore), so one appended .gitignore line can
# un-lint tracked source at pre-commit AND in CI — is cases/37, with the
# shipped-rule drift check: same content-vs-arming question, and it carries
# its own eslint.config.js fixtures.

reset_repo
