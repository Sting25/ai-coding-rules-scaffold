# shellcheck shell=bash
# cases/24-claude-skill.sh: the opt-in Claude Code Skill packaging
# (--claude-skill, #118 part 2). SKILL.md is USER-OWNED (a project may
# hand-edit it), so it installs via cp_safe, not cp_scaffold_preserve like
# the CI-workflow opt-ins cases/21 already covers: install if absent, skip
# on drift unless --force (back up first), never a drift NOTE. Sourced into
# the driver's shell, so PASS/FAIL/SCAFFOLD_DIR/HOOK_OUT are already in
# scope.

echo "cases/24: --claude-skill opt-in flag (#118 pt 2)"

_cskill_fixture() {
  local t; t=$(mktemp -d)
  ( cd "$t" && git init --quiet && git config user.email test@test.local && git config user.name "Scaffold Test" && echo '{"name":"x"}' >package.json \
    && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify "$@" ) >/dev/null 2>&1
  printf '%s' "$t"
}

# (T) a default install (no flag) writes no Skill file: stays opt-in.
D=$(_cskill_fixture)
if [ ! -e "$D/.claude/skills/coding-rules/SKILL.md" ]; then
  echo "  ✓ a default install creates no Claude Skill"; PASS=$((PASS + 1))
else
  echo "  ✗ a default install should not create the Claude Skill"; FAIL=$((FAIL + 1))
fi
rm -rf "$D"

# (T) --claude-skill installs SKILL.md, byte-identical to the shipped
# template, with valid frontmatter naming both installed rules files.
K=$(_cskill_fixture --claude-skill)
SKILL_PATH="$K/.claude/skills/coding-rules/SKILL.md"
if [ -f "$SKILL_PATH" ] \
   && cmp -s "$SCAFFOLD_DIR/claude-skill/coding-rules/SKILL.md.template" "$SKILL_PATH" \
   && head -1 "$SKILL_PATH" | grep -qx -- '---' \
   && grep -q '^name: coding-rules$' "$SKILL_PATH" \
   && grep -q '^description:' "$SKILL_PATH" \
   && grep -q 'coding-rules.md' "$SKILL_PATH" \
   && grep -q 'operational-rules.md' "$SKILL_PATH"; then
  echo "  ✓ --claude-skill installs SKILL.md with frontmatter naming both rules files"; PASS=$((PASS + 1))
else
  echo "  ✗ --claude-skill should install a SKILL.md with name/description frontmatter"; FAIL=$((FAIL + 1))
fi
rm -rf "$K"

# (T) cp_safe semantics: a hand-edited SKILL.md is left alone on a plain
# re-run (no drift note, no backup), and --force backs it up then replaces
# it with the shipped version.
S=$(_cskill_fixture --claude-skill)
SKILL_PATH="$S/.claude/skills/coding-rules/SKILL.md"
printf '\nlocal note\n' >>"$SKILL_PATH"
( cd "$S" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --claude-skill ) >"$HOOK_OUT" 2>&1
if grep -qF "local note" "$SKILL_PATH" && [ ! -e "$SKILL_PATH.scaffold-bak" ] \
   && grep -q "skip (exists): .claude/skills/coding-rules/SKILL.md" "$HOOK_OUT"; then
  echo "  ✓ a hand-edited SKILL.md is left alone on a plain re-run (cp_safe)"; PASS=$((PASS + 1))
else
  echo "  ✗ a hand-edited SKILL.md should be skipped, not replaced, on a plain re-run"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
( cd "$S" && "$SCAFFOLD_DIR/install.sh" --frontend --no-verify --claude-skill --force ) >"$HOOK_OUT" 2>&1
if [ -f "$SKILL_PATH.scaffold-bak" ] && grep -qF "local note" "$SKILL_PATH.scaffold-bak" \
   && cmp -s "$SCAFFOLD_DIR/claude-skill/coding-rules/SKILL.md.template" "$SKILL_PATH"; then
  echo "  ✓ --force backs up the edited SKILL.md then installs the shipped version"; PASS=$((PASS + 1))
else
  echo "  ✗ --force should back up the edited SKILL.md then replace it"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$S"

# (T) uninstall.sh removes an unmodified SKILL.md and sweeps the now-empty
# .claude/skills/coding-rules + .claude/skills directories.
U=$(_cskill_fixture --claude-skill)
( cd "$U" && "$SCAFFOLD_DIR/uninstall.sh" ) >"$HOOK_OUT" 2>&1
if [ ! -e "$U/.claude/skills/coding-rules/SKILL.md" ] && [ ! -d "$U/.claude/skills" ]; then
  echo "  ✓ uninstall.sh removes an unmodified SKILL.md and sweeps the emptied dirs"; PASS=$((PASS + 1))
else
  echo "  ✗ uninstall.sh should remove the unmodified SKILL.md and the emptied dirs"; sed 's/^/      /' "$HOOK_OUT"; FAIL=$((FAIL + 1))
fi
rm -rf "$U"
