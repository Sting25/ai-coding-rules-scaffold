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

    # REQUIRED: every static $SCAFFOLD_DIR/<path> install.sh reads, the two
    # dynamically-globbed dirs (${L}.txt.template / ${check}.template) expanded
    # to their real members, plus the installer scripts and the npm wrapper.
    REQUIRED=$(
      {
        # SC2016 off on purpose: we match the LITERAL text "$SCAFFOLD_DIR" / "${"
        # as it appears in install.sh's source, so single quotes (no expansion)
        # are exactly right.
        # shellcheck disable=SC2016
        grep -oE '\$SCAFFOLD_DIR/[^"'"'"' ]+' "$SCAFFOLD_DIR/install.sh" \
          | sed 's#\$SCAFFOLD_DIR/##' | grep -v '\${'
        ( cd "$SCAFFOLD_DIR" \
            && ls forbidden-patterns/*.txt.template githooks/*.template githooks/lib/*.template )
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
  else
    echo "  ✗ npm pack --dry-run failed"; sed 's/^/      /' "$C11"; FAIL=$((FAIL + 1))
  fi
  rm -f "$C11"
fi