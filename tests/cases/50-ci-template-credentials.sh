# shellcheck shell=bash
# cases/50-ci-template-credentials.sh: the token each shipped CI template hands
# to the step that needs it (#195, #196). Sourced into the driver's shell, so
# PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR are in scope. Helpers are prefixed ct_.
#
# Both defects only show on a PRIVATE repo, so the scaffold's own (public) CI
# never saw them and actionlint cannot: the YAML is valid, the credentials are
# just missing.
#   #195  gitleaks-action lists the PR's commits through the API on a
#         pull_request event; with `contents: read` alone that is a 403.
#   #196  coverage.yml's diff-cover step ran `git fetch` after a checkout with
#         persist-credentials: false, so on a private repo it died with exit 128.
#         The checkout already fetched full history, so the fetch is now skipped
#         when origin/$GITHUB_BASE_REF exists and otherwise carries its own
#         one-command token.

echo "cases/50: CI templates carry the credentials their steps need (gitleaks pull-requests: read #195, coverage base-ref fetch #196)"

CT_GL="$SCAFFOLD_DIR/.github/workflows/gitleaks.yml.template"
CT_COV="$SCAFFOLD_DIR/.github/workflows/coverage.yml.template"

# --- (A) gitleaks: job-level pull-requests: read, workflow level stays minimal ---
# Indent tells the two apart: the workflow-level block is 2 spaces deep, the
# job-level one 6.
for ct_f in "$CT_GL" "$SCAFFOLD_DIR/.github/workflows/gitleaks.yml"; do
  if grep -qx '      pull-requests: read' "$ct_f" && ! grep -q '^  pull-requests:' "$ct_f" \
     && [ "$(grep -c 'pull-requests:' "$ct_f")" -eq 1 ]; then
    echo "  ✓ ${ct_f#"$SCAFFOLD_DIR"/}: pull-requests: read is granted at job level only"; PASS=$((PASS + 1))
  else
    echo "  ✗ ${ct_f#"$SCAFFOLD_DIR"/}: expected exactly one 'pull-requests: read', at job level (gitleaks-action 403s on a private repo without it)"; FAIL=$((FAIL + 1))
  fi
done

# --- (B) coverage: the fetch is guarded and authenticated, never persisted -------
# shellcheck disable=SC2016  # $GITHUB_BASE_REF is literal template text here
if ! grep -qE '^ {10}git fetch' "$CT_COV" \
   && grep -qF 'git rev-parse --verify -q "origin/$GITHUB_BASE_REF"' "$CT_COV" \
   && grep -qF 'http.extraheader=' "$CT_COV"; then
  echo "  ✓ coverage.yml.template: the base-ref fetch is guarded by rev-parse and carries an explicit extraheader"; PASS=$((PASS + 1))
else
  echo "  ✗ coverage.yml.template: expected no bare 'git fetch', a rev-parse guard on origin/\$GITHUB_BASE_REF, and an http.extraheader"; FAIL=$((FAIL + 1))
fi
# The token must reach the step through env (masked, not spliced into the
# script text) and the checkout must keep not persisting it.
if [ "$(grep -c 'github\.token' "$CT_COV")" -eq 1 ] && grep -qE '^ +GH_TOKEN: \$\{\{ github\.token \}\}$' "$CT_COV" \
   && ! grep -q 'persist-credentials: true' "$CT_COV" && grep -qF 'persist-credentials: false' "$CT_COV"; then
  echo "  ✓ coverage.yml.template: github.token appears once, as GH_TOKEN in env, and checkout still has persist-credentials: false"; PASS=$((PASS + 1))
else
  echo "  ✗ coverage.yml.template: github.token must appear only as 'GH_TOKEN: \${{ github.token }}' and checkout must keep persist-credentials: false"; FAIL=$((FAIL + 1))
fi

# --- (C) behavior: run the shipped guard against a local origin ------------------
# Lifted out of the template so the test runs the text consumers get. The block
# starts at the explanatory comment and ends before REPORTS="" (the next line of
# the step). No block means the template lost the guard.
ct_blk=$(awk '/# The checkout above \(fetch-depth 0\)/ { inb = 1 } inb && /^ *REPORTS=""/ { exit } inb { sub(/^ {10}/, ""); print }' "$CT_COV")
CT=$(mktemp -d)
git init -q "$CT/up" && ( cd "$CT/up" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git branch -M main )
git clone -q "$CT/up" "$CT/clone"
if [ -z "$ct_blk" ]; then
  echo "  ✗ could not extract the base-ref fetch block from coverage.yml.template"; FAIL=$((FAIL + 2))
else
  # Ref present: the origin URL is made unreachable, so ANY fetch would fail.
  git -C "$CT/clone" remote set-url origin "$CT/does-not-exist"
  if ( cd "$CT/clone" && GH_TOKEN=t GITHUB_BASE_REF=main bash -e -c "$ct_blk" ) >"$HOOK_OUT" 2>&1; then
    echo "  ✓ origin/\$GITHUB_BASE_REF already present: no fetch is attempted"; PASS=$((PASS + 1))
  else
    echo "  ✗ the guard fetched although origin/\$GITHUB_BASE_REF exists"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
  # Ref absent: the block fetches it, and the token value is masked in the log.
  git -C "$CT/clone" remote set-url origin "$CT/up"
  git -C "$CT/clone" update-ref -d refs/remotes/origin/main
  if ( cd "$CT/clone" && GH_TOKEN=secret-token-value GITHUB_BASE_REF=main bash -e -c "$ct_blk" ) >"$HOOK_OUT" 2>&1 \
     && git -C "$CT/clone" rev-parse -q --verify origin/main >/dev/null && ! grep -qF 'secret-token-value' "$HOOK_OUT"; then
    echo "  ✓ origin/\$GITHUB_BASE_REF absent: it is fetched, and the raw token is not echoed"; PASS=$((PASS + 1))
  else
    echo "  ✗ expected the guard to fetch the missing base ref without echoing the token"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$CT"
