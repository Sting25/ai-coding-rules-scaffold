# shellcheck shell=bash
# cases/34-shipped-pattern-files.sh: the SHIPPED forbidden-patterns/*.txt.template
# files must load cleanly. Sourced into the driver's shell, so
# PASS/FAIL/SCAFFOLD_DIR/HOOK_OUT/WORK and the helpers are already in scope.
#
# WHY THIS EXISTS. Line numbers are deliberately absent below: check-patterns
# and check-secrets are edited often and every citation here rotted within a
# release. The faults are named by their behaviour and by the exact warning text
# they print, which is what this case greps for anyway.
#
# check-patterns and check-secrets both survive four separate load-time faults
# in a shipped pattern file, three of them without failing:
#   * a line with no TAB separator      -> stderr "line has no TAB separator,
#     skipped", that rule is dropped, exit 0.
#   * an empty pattern before the TAB   -> a bare `continue` in both loaders with
#     NO warning at all. The quietest of the four: nothing appears in any log.
#   * a pattern that is not a valid ERE -> stderr "invalid pattern dropped", that
#     rule is dropped, exit 0. (check-patterns only fail_closed()s if EVERY
#     pattern in the file was invalid, so one bad rule among thirty is silent
#     apart from that one stderr line.)
#   * no `# scaffold-extensions:` header -> this one DOES fail_closed(), so it is
#     not silent — but only in the consumer repo, at their commit time, once
#     something is staged. Shipping it is still a defect; it just detonates
#     downstream instead of here.
#
# The suite proves the warn-and-continue contract against an INJECTED bad pattern
# (cases/02), but nothing asserted the files the scaffold actually SHIPS are free
# of such faults. So a one-character typo in a shipped ERE — an unbalanced
# bracket, a PCRE `\d` that ERE rejects, spaces where the TAB belongs after an
# edit — deletes that rule from every downstream install while the hook exits 0,
# self-lint.yml exits 0 (it runs check-patterns and only reads its exit code) and
# this suite exits 0. Same fail-open class the repo already closed INSIDE the
# scanner (3ef4ad9, "fail closed"), left open one level up at the shipped-asset
# layer.
#
# The checks below are deliberately the loader's own, applied to the templates
# directly rather than to an installed copy: same blank/`#`-comment skip, same
# TAB split, same `printf '' | grep -E -- "$p"` validity probe (empty stderr
# means valid), so a rule this file accepts is a rule the hook will arm. The
# probe is why this is worth having at all — an invalid ERE is not a syntax
# error anywhere else, it is a rule that quietly does nothing.

echo "cases/34: every shipped forbidden-patterns template loads with no dropped rules"

# _fp_check <template>: print one diagnostic line per fault found, nothing at
# all if the file is clean. Runs in a subshell via $(...) so its locals and its
# per-line loop cannot disturb the driver's state.
_fp_check() {
  local tpl=$1 base line pattern description hdr p_err n=0
  base=$(basename "$tpl" .template)

  # (1) The `# scaffold-extensions:` header. Without it (and without the
  # optional `# scaffold-filenames:`) check-patterns' exts_for() returns empty
  # and the file names nothing to scan, so every rule in it is dead.
  # check-patterns does fail_closed() on that — but in the consumer's repo, at
  # their commit time, which is far too late to learn it here. secrets.txt is
  # the one exemption and not an oversight: check-patterns' discovery loop skips
  # it by name because it is check-secrets' domain, and check-secrets scans ALL
  # tracked text files with no extension filter, so a header there would be
  # inert.
  if [ "$base" != "secrets.txt" ]; then
    hdr=$(grep -m1 -E '^#[[:space:]]*scaffold-extensions:' "$tpl" \
            | sed -E 's/^#[[:space:]]*scaffold-extensions:[[:space:]]*//; s/[[:space:]]+$//') || true
    if [ -z "$hdr" ]; then
      printf '%s: no non-empty "# scaffold-extensions:" header — none of its rules would ever run\n' "$base"
    fi
  fi

  # (2) Per rule, in exactly the loader's parse order: CRLF strip, skip blank,
  # skip `#` comment (unindented only — an indented `#` is a PATTERN to the
  # loader, so it is one here too, and gets reported as the TAB fault it is).
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    n=$((n + 1))
    case "$line" in
      *$'\t'*) ;;
      *) printf '%s: line has no TAB separator, the loader would skip it: %s\n' "$base" "$line"; continue ;;
    esac
    pattern=${line%%$'\t'*}
    description=${line#*$'\t'}
    # An empty pattern half is the quietest of the four faults: both loaders
    # `continue` on it with NO warning at all, so a line that begins with the
    # TAB vanishes without a trace in any log.
    if [ -z "$pattern" ]; then
      printf '%s: empty pattern before the TAB, silently dropped by the loader: %s\n' "$base" "$line"
      continue
    fi
    # The `(?-i)` case-sensitivity marker is a scaffold convention, not ERE:
    # check-secrets strips it before grep ever sees it. check-patterns
    # does NOT — it has no such marker — so the pattern is validated raw there,
    # and a `(?-i)` that wandered into a non-secrets file is correctly reported
    # below (grep -E warns "? at start of expression", i.e. the loader drops it).
    if [ "$base" = "secrets.txt" ]; then
      pattern=${pattern#'(?-i)'}
    fi
    # POSIX ERE has no PCRE shorthand, and this is the fault the validity probe
    # below CANNOT see: grep -E reads `\d` as a literal `d` and `(?=...)` as an
    # ordinary group, so such a rule is accepted, armed, and permanently silent
    # — worse than one that is dropped loudly. `\\` pairs are stripped first so
    # a rule that legitimately hunts for a literal backslash-d in scanned SOURCE
    # (`new RegExp\("\\\\d"\)`) is not flagged.
    #
    # Two severities, one verdict, because both are wrong HERE. `\d \D \A \Z`
    # and `(?=` `(?!` `(?<` are broken under every grep -E on earth. `\b \s \w`
    # and their negations happen to work under GNU grep, so they are not silent
    # on Linux — but these hooks run on the macOS developers of consumer repos,
    # where grep -E is BSD grep and they match a literal `b`, `s`, `w`. A rule
    # that enforces on CI and quietly does nothing on half the team's laptops is
    # the worst of the three outcomes, so there is no per-rule escape hatch:
    # rewrite with a bracket expression ([0-9], [[:space:]], [A-Za-z0-9_],
    # [^A-Za-z0-9_]) or drop the rule.
    if printf '%s' "${pattern//\\\\/}" | grep -qE '\\[dDwWsSbBAZ]|\(\?[=!<]'; then
      printf '%s: PCRE/GNU-only syntax in a POSIX ERE — grep -E accepts it and matches the wrong thing (or nothing) on BSD grep: %s\n' "$base" "$pattern"
    fi
    p_err=$(printf '' | grep -E -- "$pattern" 2>&1 1>/dev/null || true)
    if [ -n "$p_err" ]; then
      printf '%s: invalid ERE, the loader would DROP this rule: %s — %s\n' "$base" "$pattern" "$p_err"
    fi
    # A blank description is what lands in the ::error annotation and in the
    # developer's terminal; an unnamed rule is an unactionable one.
    if [ -z "$description" ]; then
      printf '%s: rule has an empty description: %s\n' "$base" "$pattern"
    fi
  done <"$tpl"

  # A shipped file with zero rules is the gutting case check-patterns fails
  # closed on at commit time ("has no patterns"); catch it here instead.
  if [ "$n" -eq 0 ]; then
    printf '%s: contains no rules at all\n' "$base"
  fi
}

for _fp_tpl in "$SCAFFOLD_DIR"/forbidden-patterns/*.txt.template; do
  _fp_faults=$(_fp_check "$_fp_tpl")
  if [ -z "$_fp_faults" ]; then
    echo "  ✓ $(basename "$_fp_tpl") loads cleanly (TAB, valid ERE, description, header)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $(basename "$_fp_tpl") has load-time faults — the rules below do NOT run in any consumer repo"
    printf '%s\n' "$_fp_faults" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
done
unset _fp_tpl _fp_faults
unset -f _fp_check

# (T) end-to-end: the same files, INSTALLED, through the real hook. The static
# pass above reads the templates; this proves the artifacts install.sh actually
# wrote into .forbidden-patterns/ load without either loader emitting one of its
# three load-time warnings. Verdict is ignored on purpose (`|| true`) — the
# probe file is benign, but this assertion is about the LOADER, not about
# whether some other check objected to the fixture.
# shellcheck disable=SC2164  # set -euo pipefail is inherited from the driver, so a failed cd aborts the run
cd "$WORK"
printf 'a benign line with no forbidden pattern in it\n' >shipped-pattern-load-probe.txt
git add shipped-pattern-load-probe.txt
.githooks/pre-commit >"$HOOK_OUT" 2>&1 || true
if grep -qE 'invalid pattern dropped|line has no TAB separator|no .# scaffold-extensions:. .*header' "$HOOK_OUT"; then
  echo "  ✗ an installed .forbidden-patterns file failed to load cleanly through the hook"
  sed 's/^/      /' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ every installed pattern file loads through the hook with no dropped rules"
  PASS=$((PASS + 1))
fi
reset_repo
