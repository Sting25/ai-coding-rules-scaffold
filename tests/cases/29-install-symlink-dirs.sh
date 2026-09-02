# shellcheck shell=bash
# cases/29-install-symlink-dirs.sh: what install.sh does when a scaffold PARENT
# directory (.githooks, .github, .claude, .cursor) is a symlink. Sourced into
# the driver's shell, so PASS/FAIL/HOOK_OUT/SCAFFOLD_DIR and reset_repo are
# already in scope.
#
# History. install's cp_* helpers dropped a symlink at the LEAF file, but a
# plain `mkdir -p "$(dirname "$dst")"` still FOLLOWED a symlinked PARENT: every
# scanner, hook and CI workflow was written THROUGH the link and landed outside
# the repo, clobbering whatever was there, while the in-tree path stayed a
# symlink. A silent write-through plus a fail-open guardrail. _mkdir_safe (A7 /
# B4) closed that by walking the path top-down.
#
# What it closed it WITH was the remaining defect (audit code-install-policy-2):
# it `rm -f`'d the symlink component and carried on. A `.claude -> ../shared`
# the user had put there was deleted by an installer, with no warning line, no
# backup and no summary, and the shared directory it pointed at was orphaned;
# the only thing the log said was "installed: .claude/settings.json". Every LEAF
# symlink is refused ("skip (exists, symlink)") rather than deleted, and a
# directory link is a bigger decision, not a smaller one.
#
# So the policy is now: refuse. Nothing is written under the link, nothing is
# deleted, the link and its target are named with the two commands that resolve
# it, and the run ends with an "INSTALL INCOMPLETE" summary and a non-zero exit,
# because an install that could not write .githooks/ did not install anything
# that matters and must not report success.

echo "cases/29: install refuses a symlinked scaffold directory (audit code-install-policy-2)"

# (T) .githooks -> an outside directory. Assert the whole contract at once:
#     the outside tree is untouched (no write-through, no clobber), the user's
#     link still exists (no silent delete), the refusal names the path, the
#     end-of-run summary lists it, and install.sh exits non-zero.
USG=$(mktemp -d)
mkdir -p "$USG/repo" "$USG/outside/lib"
printf 'PRECIOUS_DO_NOT_TOUCH\n' >"$USG/outside/lib/check-secrets"
ln -s "$USG/outside" "$USG/repo/.githooks"
USG_RC=0
( cd "$USG/repo" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || USG_RC=$?
if grep -q 'PRECIOUS_DO_NOT_TOUCH' "$USG/outside/lib/check-secrets" \
   && [ ! -e "$USG/outside/pre-commit" ] \
   && [ -L "$USG/repo/.githooks" ] \
   && [ "$USG_RC" -ne 0 ] \
   && grep -q 'error: .githooks is a symlink' "$HOOK_OUT" \
   && grep -q 'INSTALL INCOMPLETE' "$HOOK_OUT" \
   && grep -q -- '- .githooks' "$HOOK_OUT"; then
  echo "  ✓ a symlinked .githooks is refused by name: no write-through, no delete, non-zero exit"; PASS=$((PASS + 1))
else
  echo "  ✗ a symlinked .githooks should be refused by name with a non-zero exit, not followed or deleted"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USG"

# (T) .claude -> an outside directory, with --claude. This is the audit's own
#     repro: the link used to disappear and the outside notes were orphaned
#     while the log said only "installed: .claude/settings.json". Assert the
#     link and its target survive, no settings.json was written on either side
#     of it, and the refusal is explained rather than merely absent.
USC=$(mktemp -d)
mkdir -p "$USC/repo" "$USC/shared-claude"
printf 'team notes\n' >"$USC/shared-claude/NOTES.md"
ln -s "$USC/shared-claude" "$USC/repo/.claude"
USC_RC=0
( cd "$USC/repo" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --claude ) >"$HOOK_OUT" 2>&1 || USC_RC=$?
if [ -L "$USC/repo/.claude" ] \
   && grep -q 'team notes' "$USC/shared-claude/NOTES.md" \
   && [ ! -e "$USC/shared-claude/settings.json" ] \
   && [ "$USC_RC" -ne 0 ] \
   && grep -q 'error: .claude is a symlink' "$HOOK_OUT" \
   && grep -q 'refusing to delete it' "$HOOK_OUT" \
   && ! grep -q 'installed:    .claude/settings.json' "$HOOK_OUT"; then
  echo "  ✓ a symlinked .claude survives the install, with the refusal explained"; PASS=$((PASS + 1))
else
  echo "  ✗ a symlinked .claude should survive with an explained refusal, not be deleted silently"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USC"

# (T) the refusal is printed ONCE per directory, not once per file underneath
#     it: .githooks alone takes ~10 writes on a plain install, and ten copies of
#     a six-line explanation is noise the reader stops reading.
USO=$(mktemp -d)
mkdir -p "$USO/repo" "$USO/outside"
ln -s "$USO/outside" "$USO/repo/.githooks"
( cd "$USO/repo" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || true
if [ "$(grep -c 'error: .githooks is a symlink' "$HOOK_OUT")" -eq 1 ]; then
  echo "  ✓ the symlinked-directory refusal is explained exactly once per directory"; PASS=$((PASS + 1))
else
  echo "  ✗ the symlinked-directory refusal should print once per directory, not once per file"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USO"

# (T) the control: with a REAL .githooks directory nothing changes. The refusal
#     must not fire on the normal path, and a plain install still lands an
#     executable pre-commit and exits 0.
USN=$(mktemp -d)
USN_RC=0
( cd "$USN" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
  && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify ) >"$HOOK_OUT" 2>&1 || USN_RC=$?
if [ "$USN_RC" -eq 0 ] \
   && [ -x "$USN/.githooks/pre-commit" ] \
   && ! grep -q 'INSTALL INCOMPLETE' "$HOOK_OUT" \
   && ! grep -q 'is a symlink, not a real directory' "$HOOK_OUT"; then
  echo "  ✓ a real scaffold directory installs normally and exits 0 (no false refusal)"; PASS=$((PASS + 1))
else
  echo "  ✗ a real scaffold directory should install normally with no refusal"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$USN"

reset_repo
