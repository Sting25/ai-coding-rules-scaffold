#!/usr/bin/env bash
# scripts/dev-setup.sh — bootstrap local dogfooding for the scaffold's OWN repo.
#
# The scaffold can't install itself (install.sh refuses to run with the scaffold
# dir as the target, by design), so a fresh clone has NO active hooks. This
# renders the *.template sources into the gitignored .githooks/ and
# .forbidden-patterns/ — the same files install.sh writes into a consumer project
# and self-lint.yml renders in CI — and points core.hooksPath at .githooks. After
# running it, committing in this repo runs the scaffold's own guardrails,
# including the opt-in commit-msg (Conventional Commits) hook.
#
# Idempotent: re-run any time to refresh after editing a template. The rendered
# files are gitignored build artifacts; only the *.template sources are tracked,
# so there is exactly one source of truth.
#
#   dev-setup.sh            render the templates and wire core.hooksPath
#   dev-setup.sh --check    render NOTHING; exit non-zero if any rendered
#                           artifact no longer matches the template it came
#                           from. Wired into this clone's own pre-commit via
#                           the generated .githooks/local.d/00-template-drift,
#                           because a stale render means this repo commits
#                           under older guardrails than it ships, and no CI job
#                           can see it (.githooks/ is gitignored).

set -euo pipefail

MODE=render
case ${1:-} in
  --check) MODE=check ;;
  "")      ;;
  *)       echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac

# Resolve the repo root from this script's own location, so it works from any cwd.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f githooks/pre-commit.template ]; then
  echo "error: run this from a clone of ai-coding-rules-scaffold (githooks/*.template not found)" >&2
  exit 1
fi

# Mirror install.sh's A7 symlink defenses (_cp_replace). .githooks/ and
# .forbidden-patterns/ are gitignored, so a leftover or planted symlink there
# survives across checkouts; a bare `cp` follows a symlink at a rendered path and
# writes the scanner THROUGH the link to a target OUTSIDE the repo, and `mkdir -p`
# follows a symlinked DIR (sending every scanner outside). Drop any symlink before
# writing so we always land a real file/dir in the tree, never through a link.
_mkdir_safe() {           # create a real dir, never follow a symlink into one
  local d=$1
  if [ -L "$d" ]; then rm -f "$d"; fi
  mkdir -p "$d"
}
_cp() {                   # write a real regular file, never through a symlink
  local src=$1 dst=$2
  rm -f "$dst"
  cp "$src" "$dst"
}

# ONE manifest, two consumers: the render pass writes every pair below and
# --check compares the same pairs. They are deliberately not two lists. A
# template that lands in the renderer but not in the drift check is exactly how
# "the rendered hook is stale and nothing notices" happens.
#
# Parallel arrays rather than an associative array: bash 3.2 (the macOS default)
# has no `declare -A`.
RENDER_SRC=()
RENDER_DST=()
_plan() { RENDER_SRC+=("$1"); RENDER_DST+=("$2"); }

# Top-level hooks — including the opt-in commit-msg: the repo dogfoods everything
# it ships, even the hooks that are opt-in for downstream consumers.
_plan githooks/pre-commit.template .githooks/pre-commit
_plan githooks/commit-msg.template .githooks/commit-msg

# Scanner libs + language/secret pattern files.
for t in githooks/lib/*.template; do
  _plan "$t" ".githooks/lib/$(basename "$t" .template)"
done
for t in forbidden-patterns/*.txt.template; do
  _plan "$t" ".forbidden-patterns/$(basename "$t" .template)"
done
# The project-local extension point install.sh gives consumers, so this clone's
# .githooks/ is shaped like a real install instead of missing a directory.
if [ -f githooks/local.d/README.md.template ]; then
  _plan githooks/local.d/README.md.template .githooks/local.d/README.md
fi

if [ "$MODE" = "check" ]; then
  drift=0
  i=0
  while [ "$i" -lt "${#RENDER_SRC[@]}" ]; do
    src=${RENDER_SRC[$i]}
    dst=${RENDER_DST[$i]}
    if [ ! -f "$dst" ]; then
      echo "drift: $dst is missing (never rendered from $src)" >&2
      drift=1
    elif ! cmp -s "$src" "$dst"; then
      echo "drift: $dst is stale against $src" >&2
      drift=1
    fi
    i=$((i + 1))
  done
  if [ "$drift" -ne 0 ]; then
    echo "" >&2
    echo "The rendered guardrails no longer match their *.template sources, so this" >&2
    echo "clone commits under OLDER checks than it ships. Fix it, do not skip it:" >&2
    echo "  bash scripts/dev-setup.sh" >&2
    exit 1
  fi
  echo "✓ ${#RENDER_SRC[@]} rendered artifacts match their templates"
  exit 0
fi

_mkdir_safe .githooks
_mkdir_safe .githooks/lib
_mkdir_safe .githooks/local.d
_mkdir_safe .forbidden-patterns

i=0
while [ "$i" -lt "${#RENDER_SRC[@]}" ]; do
  _cp "${RENDER_SRC[$i]}" "${RENDER_DST[$i]}"
  i=$((i + 1))
done

# Wire the drift check into THIS clone's commits. The rendered hooks are
# gitignored, so no CI job can ever see them go stale; commit time is the only
# moment the question can be asked, and local.d/ is the extension point the
# scaffold tells everyone to use instead of editing a scaffold-owned hook.
# Generated rather than tracked because it is maintainer-only: install.sh never
# writes into local.d/, so no consumer receives it.
#
# It resolves dev-setup.sh from its OWN location, not from the committing
# working tree: several worktrees can share one core.hooksPath, and the clone
# whose hooks actually ran is the clone that has to be current.
cat >.githooks/local.d/00-template-drift <<'DRIFT'
#!/usr/bin/env bash
# GENERATED by scripts/dev-setup.sh. Do not edit; re-run that script instead.
# Fails the commit when a rendered .githooks/ artifact is older than the
# *.template it came from. The staged list on stdin and the --ci flag are
# ignored on purpose: the question is about this clone's build artifacts, not
# about what happens to be staged.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$root/scripts/dev-setup.sh" ] || exit 0
if out=$(bash "$root/scripts/dev-setup.sh" --check 2>&1); then
  exit 0
fi
printf '%s\n' "$out" >&2
exit 1
DRIFT
chmod +x .githooks/local.d/00-template-drift

chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/lib/*

# Wire the hook — mirror install.sh's two guards. Only set core.hooksPath when it
# is unset or already .githooks, so a pre-existing Husky/lefthook path is preserved
# rather than silently clobbered. Guard on a real git dir (`git rev-parse
# --git-dir`, which also covers worktrees/submodules) so a non-git checkout — a
# tarball download, or a clone before `git init` — warns and continues instead of
# aborting with a raw `fatal: not in a git directory` (exit 128) after every file
# is already rendered.
if git rev-parse --git-dir >/dev/null 2>&1; then
  existing_hooks_path=$(git config --get core.hooksPath || true)
  if [ -z "$existing_hooks_path" ] || [ "$existing_hooks_path" = ".githooks" ]; then
    git config core.hooksPath .githooks
    hooks_status="core.hooksPath -> .githooks"
  else
    hooks_status="core.hooksPath left as '$existing_hooks_path' (pre-existing — not clobbered)"
    echo "warning: core.hooksPath is already '$existing_hooks_path' — leaving it alone." >&2
    echo "         Point it at .githooks or chain the scaffold's hook into your setup." >&2
  fi
else
  hooks_status="core.hooksPath NOT set (not a git repo)"
  echo "warning: not in a git repo — run 'git config core.hooksPath .githooks' after 'git init'." >&2
fi

libs=(.githooks/lib/*)
pats=(.forbidden-patterns/*.txt)
echo "✓ dev hooks rendered; $hooks_status"
echo "  active: pre-commit, commit-msg, ${#libs[@]} scanners, ${#pats[@]} pattern files"
echo "  (gitignored build artifacts — edit the *.template sources, then re-run this script)"
