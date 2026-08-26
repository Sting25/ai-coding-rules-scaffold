# shellcheck shell=bash
# cases/11-npm-bundle.sh — guard the npm package against bundle drift. The npm
# distribution (`npx ai-coding-rules-scaffold`) ships the SAME install.sh +
# template tree as the git-clone path, selected by package.json's "files"
# allowlist. If install.sh starts reading a new template but it's forgotten in
# "files", git-clone users are fine while npm users get a SILENT broken install
# (a missing source file surfaces only mid-install on someone else's machine).
# So derive the required-file set from install.sh itself and assert every entry
# is in the packed tarball — the allowlist can't drift out of sync undetected.
#
# Skips (does not fail) when npm or jq is unavailable, so the suite still runs on
# a minimal box; GitHub runners have both, so this is real coverage in CI.

echo "cases/11 — npm package bundle completeness"

if ! command -v npm >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "  ~ skipped (npm or jq not available)"
else
  C11=$(mktemp)
  # PACKED: exactly what `npm publish` would ship, per the "files" allowlist.
  if ( cd "$SCAFFOLD_DIR" && npm pack --dry-run --json 2>/dev/null ) >"$C11"; then
    PACKED=$(jq -r '.[0].files[].path' "$C11" 2>/dev/null | sort -u)

    # REQUIRED: every static $SCAFFOLD_DIR/<path> install.sh reads, the
    # dynamically-globbed dirs (${L}.txt.template / ${check}.template + every
    # workflow template) expanded to their real members, plus the installer
    # scripts and the npm wrapper.
    #
    # The workflow glob is load-bearing: gitleaks.yml.template and
    # dependency-review.yml.template are "copy it in" templates the user applies
    # by hand (TECHNICAL.md's Opt-in layers section covers gitleaks and
    # dependency-review; install.sh only names them),
    # so install.sh never READS them via $SCAFFOLD_DIR and the grep above can't
    # see them. Without this glob an npm/npx user silently lacks two security-CI
    # gates git-clone/Homebrew users get (audit B3). Globbing every
    # .github/workflows/*.yml.template makes the guard fail closed on any
    # documented-but-unbundled workflow — present or added later.
    REQUIRED=$(
      {
        # SC2016 off on purpose: we match the LITERAL text "$SCAFFOLD_DIR" / "${"
        # as it appears in install.sh's source, so single quotes (no expansion)
        # are exactly right.
        # shellcheck disable=SC2016
        grep -oE '\$SCAFFOLD_DIR/[^"'"'"' ]+' "$SCAFFOLD_DIR/install.sh" \
          | sed 's#\$SCAFFOLD_DIR/##' | grep -v '\${'
        ( cd "$SCAFFOLD_DIR" \
            && ls forbidden-patterns/*.txt.template githooks/*.template githooks/lib/*.template \
                  .github/workflows/*.yml.template )
        printf '%s\n' install.sh uninstall.sh bin/cli.js
      } | sort -u
    )

    missing=0
    while IFS= read -r req; do
      [ -z "$req" ] && continue
      if ! grep -qxF "$req" <<<"$PACKED"; then
        echo "  ✗ MISSING from npm bundle (add to package.json \"files\"): $req"
        missing=$((missing + 1))
      fi
    done <<<"$REQUIRED"

    n=$(grep -c . <<<"$REQUIRED")
    if [ "$missing" -eq 0 ] && [ -n "$PACKED" ]; then
      echo "  ✓ every install.sh source file is in the npm bundle ($n checked)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ npm bundle is missing $missing of $n required source file(s)"
      FAIL=$((FAIL + 1))
    fi

    # Docs referenced by SHIPPED/INSTALLED files (pytest.ini.template,
    # coverage.yml.template, agent-precheck, README relative links) but not read
    # via $SCAFFOLD_DIR, so the grep above can't see them. They were absent from
    # the tarball, leaving npx users with dangling "see RECOMMENDATIONS.md" links.
    docs_missing=0
    for d in RECOMMENDATIONS.md CHANGELOG.md; do
      grep -qxF "$d" <<<"$PACKED" || { echo "  ✗ referenced doc missing from npm bundle: $d"; docs_missing=$((docs_missing + 1)); }
    done
    if [ "$docs_missing" -eq 0 ]; then
      echo "  ✓ referenced docs (RECOMMENDATIONS.md, CHANGELOG.md) are bundled"; PASS=$((PASS + 1))
    else
      echo "  ✗ npm bundle is missing $docs_missing referenced doc(s)"; FAIL=$((FAIL + 1))
    fi

    # Scripts reached through bin/cli.js's subcommand dispatch rather than
    # through install.sh's $SCAFFOLD_DIR paths. The grep above walks install.sh
    # only, so it cannot see `doctor`'s target — and an unbundled
    # scaffold-doctor.sh would ship a CLI subcommand that ENOENTs for every npx
    # user. Derived from cli.js rather than hardcoded, so a SECOND subcommand
    # added later is covered the day it lands instead of the day it breaks.
    cli_missing=0
    cli_scripts=$(grep -oE "'[A-Za-z0-9_-]+\.sh'" "$SCAFFOLD_DIR/bin/cli.js" | tr -d "'" | sort -u)
    for s in $cli_scripts; do
      grep -qxF "$s" <<<"$PACKED" || {
        echo "  ✗ script dispatched by bin/cli.js missing from npm bundle: $s"
        cli_missing=$((cli_missing + 1))
      }
    done
    if [ "$cli_missing" -eq 0 ]; then
      echo "  ✓ every script bin/cli.js can dispatch to is bundled ($(grep -c . <<<"$cli_scripts") checked)"; PASS=$((PASS + 1))
    else
      echo "  ✗ npm bundle is missing $cli_missing CLI-dispatched script(s)"; FAIL=$((FAIL + 1))
    fi
  else
    echo "  ✗ npm pack --dry-run failed"; sed 's/^/      /' "$C11"; FAIL=$((FAIL + 1))
  fi
  rm -f "$C11"
fi

# (B8) The npm package must NOT carry an `os` allowlist that EBADPLATFORM-blocks a
# native-Windows / Git-Bash install (win32). cli.js already emits the "run from Git
# Bash or WSL" hint at runtime, so a hard os gate only stops the user reaching it —
# npm refuses the install first. Assert there is no os field, or (if present) that
# it permits win32. jq-only, so it runs even where npm is unavailable; reverting the
# fix (re-adding os:[darwin,linux]) turns this red.
if command -v jq >/dev/null 2>&1; then
  os_ok=$(jq -r 'if has("os") then ((.os | index("win32")) != null) else true end' \
            "$SCAFFOLD_DIR/package.json" 2>/dev/null)
  if [ "$os_ok" = "true" ]; then
    echo "  ✓ package.json os field does not block Windows/Git-Bash npm install (B8)"; PASS=$((PASS + 1))
  else
    echo "  ✗ package.json os EBADPLATFORM-blocks win32 — drop the field or add win32 (B8)"; FAIL=$((FAIL + 1))
  fi
else
  echo "  ~ skipped B8 os-field check (jq not available)"
fi