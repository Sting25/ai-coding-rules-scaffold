# shellcheck shell=bash
# cases/38-components-catalog.sh: COMPONENTS.md is executable documentation.
# Sourced into the driver's shell, so PASS/FAIL/SKIP/SCAFFOLD_DIR/HOOK_OUT are
# already in scope.
#
# WHY. The catalog tells a person or an agent how to adopt each component by
# hand, with no installer, and promises a verify command that proves the guard
# is armed. A doc like that rots the first time a scanner is renamed, a
# template moves, or a verify command drifts from what the guard actually
# does; and nothing else in the tree opens the file. So this case extracts
# every fenced `sh adopt=<name>` and `sh verify=<name>` block from the catalog
# and runs them, in order, in one throwaway repository with $SCAFFOLD pointing
# at this checkout. A verify block that exits non-zero fails the case with the
# component's name. The commands under test are the ones the reader runs, not
# a parallel copy that could pass while the doc is wrong.
#
# Components are adopted cumulatively, in catalog order, because later entries
# state a prerequisite on earlier ones (patterns need the core; commit-msg
# needs core.hooksPath). Adopt blocks run under `set -e` so a failing cp is a
# failure, not a silently half-adopted component.
#
# Blocks are keyed by the fence info string, which markdown renderers ignore.
# `verify` blocks that depend on an optional tool (ruff, actionlint) already
# branch on its presence inside the block, so this case has no tool gate of
# its own: every assertion runs on a bare machine.

echo "cases/38: COMPONENTS.md adopt and verify blocks run as written, in a fresh repo"

_cc_doc="$SCAFFOLD_DIR/COMPONENTS.md"

# _cc_block KIND NAME: print the body of the fenced block whose info string is
# "sh KIND=NAME". Exactly one such block must exist; zero or many is a doc bug
# and is reported as a failure by the caller.
_cc_block() {
  awk -v want="sh $1=$2" '
    $0 == "```" want { inb = 1; next }
    inb && $0 == "```" { inb = 0; next }
    inb { print }
  ' "$_cc_doc"
}

# Every adopt=NAME in the doc, in document order. This is the component list.
_cc_names=()
while IFS= read -r _cc_name; do _cc_names+=("$_cc_name"); done < <(grep -oE '^```sh adopt=[a-z-]+$' "$_cc_doc" | sed 's/^```sh adopt=//')

if [ "${#_cc_names[@]}" -eq 0 ]; then
  echo "  ✗ COMPONENTS.md has no 'sh adopt=<name>' fences: the catalog is not executable"
  FAIL=$((FAIL + 1))
else
  _cc_repo=$(mktemp -d)
  ( cd "$_cc_repo" && git init -q && git config user.email t@test.local && git config user.name "Scaffold Test" \
      && git config commit.gpgsign false && printf '# verify fixture\n' > README.md && git add README.md && git commit -q -m "init" )
  for _cc_name in "${_cc_names[@]}"; do
    _cc_adopt=$(_cc_block adopt "$_cc_name")
    _cc_verify=$(_cc_block verify "$_cc_name")
    _cc_nv=$(grep -c "^\`\`\`sh verify=$_cc_name\$" "$_cc_doc")
    if [ "$_cc_nv" -ne 1 ]; then
      echo "  ✗ $_cc_name: expected exactly one 'sh verify=$_cc_name' block, found $_cc_nv"
      FAIL=$((FAIL + 1))
      continue
    fi
    if ! ( cd "$_cc_repo" && SCAFFOLD="$SCAFFOLD_DIR" bash -e -c "$_cc_adopt" ) >"$HOOK_OUT" 2>&1; then
      echo "  ✗ $_cc_name: adopt block failed as written"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
      continue
    fi
    if ( cd "$_cc_repo" && SCAFFOLD="$SCAFFOLD_DIR" bash -c "$_cc_verify" ) >"$HOOK_OUT" 2>&1 \
       && grep -q '^verified:' "$HOOK_OUT"; then
      echo "  ✓ $_cc_name: $(grep -m1 '^verified:' "$HOOK_OUT" | cut -c11-)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ $_cc_name: verify block did not prove the component is armed"
      sed 's/^/      /' "$HOOK_OUT"
      FAIL=$((FAIL + 1))
    fi
  done
  # The catalog's own count must match what this case exercised, so a new
  # entry without adopt/verify fences cannot hide behind the ones that have them.
  _cc_headings=$(grep -cE '^##+ [0-9]+[a-z]?\. ' "$_cc_doc")
  if [ "$_cc_headings" -eq "${#_cc_names[@]}" ]; then
    echo "  ✓ every numbered entry ($_cc_headings) has an adopt block"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $_cc_headings numbered entries but ${#_cc_names[@]} adopt blocks: an entry ships without executable commands"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$_cc_repo"
  # Each scanner alone: a fresh repo, the hook (entry 1) plus ONE scanner
  # (1a to 1f), then that scanner's verify. This is the promise that a
  # project may take a subset; the cumulative pass above cannot prove it,
  # because there every earlier scanner is already present.
  for _cc_name in "${_cc_names[@]}"; do
    case "$_cc_name" in scanner-*) ;; *) continue ;; esac
    _cc_repo=$(mktemp -d)
    ( cd "$_cc_repo" && git init -q && git config user.email t@test.local && git config user.name "Scaffold Test" \
        && git config commit.gpgsign false && printf '# solo fixture\n' > README.md && git add README.md && git commit -q -m "init" )
    if ( cd "$_cc_repo" && SCAFFOLD="$SCAFFOLD_DIR" bash -e -c "$(_cc_block adopt hook)" && SCAFFOLD="$SCAFFOLD_DIR" bash -e -c "$(_cc_block adopt "$_cc_name")" ) >"$HOOK_OUT" 2>&1 \
       && ( cd "$_cc_repo" && SCAFFOLD="$SCAFFOLD_DIR" bash -c "$(_cc_block verify "$_cc_name")" ) >"$HOOK_OUT" 2>&1 \
       && grep -q '^verified:' "$HOOK_OUT" \
       && [ "$(find "$_cc_repo/.githooks/lib" -name 'check-*' | wc -l | tr -d ' ')" -eq 1 ]; then
      echo "  ✓ $_cc_name alone (hook + one scanner): $(grep -m1 '^verified:' "$HOOK_OUT" | cut -c11-)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ $_cc_name alone: adopt or verify failed with only the hook and this scanner present"
      sed 's/^/      /' "$HOOK_OUT" | head -8
      FAIL=$((FAIL + 1))
    fi
    rm -rf "$_cc_repo"
  done
fi
unset _cc_doc _cc_names _cc_name _cc_adopt _cc_verify _cc_nv _cc_repo _cc_headings
unset -f _cc_block
