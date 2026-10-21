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
  local tpl=$1 base line pattern description rest xfield lfield has_x has_l hdr p_err n=0 d1 d2 _fp_flds _fp_f
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
    rest=${line#*$'\t'}
    # Optional trailing fields `exclude=<glob>,<glob>` (per-rule path excludes)
    # and `linter=eslint|ruff` (linter dedupe), either order, read by
    # check-patterns. Split exactly as the loader does: the description ends at
    # the first TAB that starts one of them, and any other TAB-separated text
    # after it is flagged here because the loader would ignore it.
    description=$rest
    xfield=""
    lfield=""
    has_x=0
    has_l=0
    case "$rest" in
      *$'\t'exclude=*|*$'\t'linter=*)
        d1=${rest%%$'\t'exclude=*}; d2=${rest%%$'\t'linter=*}
        if [ "${#d1}" -le "${#d2}" ]; then description=$d1; else description=$d2; fi
        IFS=$'\t' read -r -a _fp_flds <<<"${rest#"$description"}"
        for _fp_f in "${_fp_flds[@]}"; do
          case "$_fp_f" in
            exclude=*) xfield=${_fp_f#exclude=}; has_x=1 ;;
            linter=*) lfield=${_fp_f#linter=}; has_l=1 ;;
            *) printf '%s: a TAB-separated field that is neither exclude= nor linter= would be ignored by the loader: %s\n' "$base" "$line" ;;
          esac
        done
        ;;
      *$'\t'*)
        printf '%s: a second TAB after the description that is not an exclude= or linter= field would be read as part of the description: %s\n' "$base" "$line"
        ;;
    esac
    if [ "$has_x" -eq 1 ]; then
      if [ "$base" = "secrets.txt" ]; then
        printf '%s: secrets.txt takes no exclude= field, secret scanning is never path-exempt: %s\n' "$base" "$line"
      fi
      if ! printf '%s' "$xfield" | grep -qE '^[^,[:space:]]+(,[^,[:space:]]+)*$'; then
        printf '%s: malformed exclude= field (want comma-separated globs, no empty entry, no whitespace): %s\n' "$base" "$line"
      fi
    fi
    if [ "$has_l" -eq 1 ]; then
      if [ "$base" = "secrets.txt" ]; then
        printf '%s: secrets.txt takes no linter= field, secret scanning is never linter-deduped: %s\n' "$base" "$line"
      fi
      case "$lfield" in
        eslint|ruff) ;;
        *) printf '%s: malformed linter= field (want eslint or ruff, an unknown name never skips anything): %s\n' "$base" "$line" ;;
      esac
    fi
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

# (X) the format check above accepts the exclude= field and still rejects a
# malformed one. Two throwaway templates, one per verdict, run through the same
# _fp_check the shipped files use; a check that cannot fail is not a check.
_fp_dir=$(mktemp -d)
printf '# scaffold-extensions: py\nfoo\tgood rule\texclude=tests/*,scripts/*\n' >"$_fp_dir/good.txt.template"
printf '# scaffold-extensions: py\nfoo\tbad rule\texclude=\n' >"$_fp_dir/bad.txt.template"
if [ -z "$(_fp_check "$_fp_dir/good.txt.template")" ] \
   && _fp_check "$_fp_dir/bad.txt.template" | grep -qF 'malformed exclude= field'; then
  echo "  ✓ the format check accepts exclude=<globs> and flags an empty one"
  PASS=$((PASS + 1))
else
  echo "  ✗ the format check must accept a valid exclude= field and flag an empty one"
  _fp_check "$_fp_dir/good.txt.template" | sed 's/^/      good: /'
  _fp_check "$_fp_dir/bad.txt.template" | sed 's/^/      bad:  /'
  FAIL=$((FAIL + 1))
fi
rm -rf "$_fp_dir"
unset _fp_dir

# (L) the format check accepts linter=eslint|ruff in either order beside
# exclude=, and flags an unknown or empty linter name and a stray extra field.
_fp_dir=$(mktemp -d)
printf '# scaffold-extensions: py\nfoo\tgood rule\tlinter=ruff\texclude=tests/*\nbar\tgood rule 2\texclude=tests/*\tlinter=eslint\n' >"$_fp_dir/good.txt.template"
printf '# scaffold-extensions: py\nfoo\tbad rule\tlinter=pylint\n' >"$_fp_dir/bad.txt.template"
printf '# scaffold-extensions: py\nfoo\tbad rule\tlinter=\n' >"$_fp_dir/empty.txt.template"
printf '# scaffold-extensions: py\nfoo\tbad rule\tlinter=ruff\tjunk\n' >"$_fp_dir/junk.txt.template"
if [ -z "$(_fp_check "$_fp_dir/good.txt.template")" ] \
   && _fp_check "$_fp_dir/bad.txt.template" | grep -qF 'malformed linter= field' \
   && _fp_check "$_fp_dir/empty.txt.template" | grep -qF 'malformed linter= field' \
   && _fp_check "$_fp_dir/junk.txt.template" | grep -qF 'neither exclude= nor linter='; then
  echo "  ✓ the format check accepts linter=eslint|ruff and flags an unknown name, an empty one and a stray field"
  PASS=$((PASS + 1))
else
  echo "  ✗ the format check must accept linter=eslint|ruff in either order and flag the bad forms"
  for _fp_n in good bad empty junk; do _fp_check "$_fp_dir/$_fp_n.txt.template" | sed "s/^/      $_fp_n: /"; done
  FAIL=$((FAIL + 1))
fi
rm -rf "$_fp_dir"
unset _fp_dir _fp_n

# (D) the shipped defaults are actually shipped: every print-style rule carries
# an exclude= list naming the CLI/script/test paths, and the Go ones add
# *_test.go. Counted per file so dropping one field from a rule fails here.
_fp_d_bad=""
_fp_tail='tests/*,test/*,scripts/*,bin/*,cmd/*,src/main.rs,src/bin/*,examples/*'
# _fp_has <stem> <description prefix> <expected globs>: some rule in the
# template has that description and exactly that third field.
_fp_has() {
  awk -F'\t' -v d="$2" -v e="exclude=$3" 'index($2, d) == 1 && $3 == e { f = 1 } END { exit !f }' \
    "$SCAFFOLD_DIR/forbidden-patterns/$1.txt.template"
}
_fp_has backend 'Use structlog (or the project' "$_fp_tail" || _fp_d_bad="$_fp_d_bad backend/print()"
_fp_has go 'Remove fmt.Print/Println/Printf' "*_test.go,$_fp_tail" || _fp_d_bad="$_fp_d_bad go/fmt.Print"
_fp_has go 'Remove the builtin println()' "*_test.go,$_fp_tail" || _fp_d_bad="$_fp_d_bad go/println"
_fp_has rust 'Use the project logger (log/tracing), not println!()' "$_fp_tail" || _fp_d_bad="$_fp_d_bad rust/println!"
_fp_has rust 'Use the project logger (log/tracing), not print!()' "$_fp_tail" || _fp_d_bad="$_fp_d_bad rust/print!"
_fp_has rust 'Use the project logger (log/tracing), not eprintln!()' "$_fp_tail" || _fp_d_bad="$_fp_d_bad rust/eprintln!"
_fp_has rust 'Use the project logger (log/tracing), not eprint!()' "$_fp_tail" || _fp_d_bad="$_fp_d_bad rust/eprint!"
if [ -z "$_fp_d_bad" ]; then
  echo "  ✓ the print-style rules in backend.txt, go.txt and rust.txt ship their default excludes"
  PASS=$((PASS + 1))
else
  echo "  ✗ default exclude= missing or wrong on:$_fp_d_bad"
  FAIL=$((FAIL + 1))
fi
unset _fp_d_bad _fp_tail
unset -f _fp_has

# (P) the linter-dedupe pairs are actually shipped: exactly these six rules carry
# a linter= field, each naming the linter whose shipped config enforces it
# (eslint.config.js: no-console, no-debugger, ban-ts-comment; ruff.toml: PTH118,
# PGH003). Counted per rule, and any OTHER rule carrying one fails here, so a
# `linter=` cannot be added to a rule its linter does not actually cover.
_fp_p_bad=""
_fp_pair() {
  awk -F'\t' -v d="$2" -v e="linter=$3" 'index($2, d) == 1 && $3 == e { f = 1 } END { exit !f }' \
    "$SCAFFOLD_DIR/forbidden-patterns/$1.txt.template"
}
_fp_pair frontend 'Use the project logger, not console.log' eslint || _fp_p_bad="$_fp_p_bad frontend/console.log"
_fp_pair frontend 'Remove debugger statement' eslint || _fp_p_bad="$_fp_p_bad frontend/debugger"
_fp_pair frontend 'Use @ts-expect-error with a justification' eslint || _fp_p_bad="$_fp_p_bad frontend/@ts-ignore"
_fp_pair frontend 'Do not disable type-checking for a whole file' eslint || _fp_p_bad="$_fp_p_bad frontend/@ts-nocheck"
_fp_pair backend 'Use pathlib.Path(), not os.path.join' ruff || _fp_p_bad="$_fp_p_bad backend/os.path.join"
# shellcheck disable=SC2016  # the backticks are literal text in the rule description
_fp_pair backend 'Bare `# type: ignore`' ruff || _fp_p_bad="$_fp_p_bad backend/type-ignore"
_fp_p_n=$(cat "$SCAFFOLD_DIR"/forbidden-patterns/*.txt.template | grep -v '^#' | grep -cE $'\tlinter=' || true)
[ "$_fp_p_n" -eq 6 ] || _fp_p_bad="$_fp_p_bad (${_fp_p_n} rules carry linter=, expected 6)"
if [ -z "$_fp_p_bad" ]; then
  echo "  ✓ the six rules duplicated by eslint and ruff ship their linter= field, and no other rule does"
  PASS=$((PASS + 1))
else
  echo "  ✗ linter= missing or misplaced on:$_fp_p_bad"
  FAIL=$((FAIL + 1))
fi
unset _fp_p_bad _fp_p_n
unset -f _fp_pair _fp_check

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
