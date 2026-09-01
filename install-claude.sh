# shellcheck shell=bash
# install-claude.sh — Claude Code-specific install steps. Extracted to its
# own file because install.sh and install-lib.sh are both already at the
# scaffold's own 500-line cap (the same reason install-interactive.sh is a
# separate file). SOURCED (not exec'd) so it runs in install.sh's shell,
# after install-lib.sh is loaded and before any file is written.

# install_claude_md — CLAUDE.md is USER-OWNED project memory, not a scaffold
# file. Never replace it (not even with --force). If absent, create it from
# the pointer template. If present, append a marked block importing AGENTS.md
# and coding-rules.md once, and only if no @AGENTS.md import already exists.
# The @coding-rules.md import exists because AGENTS.md only LINKS the rules
# file (links keep AGENTS.md cross-tool), and a linked file is not loaded
# into context at session start: the rules were reachable but not present.
# A CLAUDE.md already wired for @AGENTS.md is never edited in place; the gap
# is surfaced as an advisory note instead.
install_claude_md() {
  # A symlink at CLAUDE.md is suspicious (`[ -e ]` is false for a dangling one
  # and follows a live one): test `-L` first and never write through it, the
  # same A7 defense the cp_* helpers carry, missing from this handler (B1).
  if [ -L "CLAUDE.md" ]; then
    echo "skip (exists, symlink): CLAUDE.md — left untouched; a scaffold path that is a symlink is suspicious. Replace it with a real file to wire the AGENTS.md import."
    return
  fi
  if [ ! -e "CLAUDE.md" ]; then
    cp "$SCAFFOLD_DIR/CLAUDE.md.pointer" "CLAUDE.md"
    echo "installed:    CLAUDE.md (new — pointer to AGENTS.md)"
    return
  fi
  if grep -q '@AGENTS.md' "CLAUDE.md" 2>/dev/null \
     || grep -q 'ai-coding-rules-scaffold:begin' "CLAUDE.md" 2>/dev/null; then
    echo "ok (wired):   CLAUDE.md already imports AGENTS.md — left untouched"
    if ! grep -q '@coding-rules.md' "CLAUDE.md" 2>/dev/null; then
      echo "note: CLAUDE.md does not import coding-rules.md. AGENTS.md only links the rules file, so the rules are NOT loaded into context at session start; add a '@coding-rules.md' line to CLAUDE.md to pin them."
    fi
    return
  fi
  {
    printf '\n<!-- ai-coding-rules-scaffold:begin -->\n'
    printf 'See [AGENTS.md](./AGENTS.md) — agent + project rules (cross-tool convention).\n\n'
    printf '@AGENTS.md\n'
    printf '@coding-rules.md\n'
    printf '<!-- ai-coding-rules-scaffold:end -->\n'
  } >>"CLAUDE.md"
  echo "merged:       appended @AGENTS.md + @coding-rules.md imports to existing CLAUDE.md (your content kept)"
}
