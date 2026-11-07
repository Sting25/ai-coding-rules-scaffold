#!/usr/bin/env bash
# scaffold-worktree-report.sh: list this repository's registered git worktrees
# and say which look stale (#221). READ-ONLY: it removes nothing, changes no
# worktree, and always exits 0. It is a report to read before you clean up, not
# a gate.
#
#   bash scaffold-worktree-report.sh            run from any worktree of the repo
#
# One line per worktree:
#   PATH  BRANCH  LAST-COMMIT-AGE  MERGED  DIR  [LOCKED]
#
#   BRANCH    the checked-out branch, or "(detached)"
#   AGE       time since the worktree's HEAD commit, e.g. 3d, 5h, 12m
#   MERGED    yes   HEAD is an ancestor of the default branch (nothing is lost
#                   by removing the worktree)
#             no    HEAD has commits the default branch does not
#             squash  the branch's PR is merged on GitHub although its commits
#                   are not ancestors (needs an authenticated `gh`)
#             unknown  the default branch or HEAD could not be resolved
#   DIR       present, or MISSING (the directory was deleted by hand; `git
#             worktree prune` drops the registration)
#
# The default branch is origin/HEAD when set, else main, else master. Set
# SCAFFOLD_REPORT_NO_GH=1 to skip the GitHub lookup (offline, tests).
#
# To remove a worktree you have judged stale: `git worktree remove <path>` (add
# --force only for one you know holds nothing). Locked worktrees are marked.
set -u

git rev-parse --git-dir >/dev/null 2>&1 || { echo "scaffold-worktree-report: not inside a git repository" >&2; exit 0; }

# default_branch: print the ref the "merged" column compares against.
default_branch() {
  local b
  b=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) && [ -n "$b" ] && { echo "$b"; return; }
  for b in main master; do
    git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1 && { echo "$b"; return; }
  done
  return 1
}

# age_of <epoch>: "3d", "5h", "12m", or "-" when unknown.
age_of() {
  local secs now
  [ -n "$1" ] || { echo "-"; return; }
  now=$(date +%s)
  secs=$((now - $1))
  [ "$secs" -ge 0 ] || secs=0
  if [ "$secs" -ge 86400 ]; then echo "$((secs / 86400))d"
  elif [ "$secs" -ge 3600 ]; then echo "$((secs / 3600))h"
  else echo "$((secs / 60))m"; fi
}

base=$(default_branch) || base=""

# merged_state <head-sha> <branch>
merged_state() {
  local sha=$1 branch=$2
  [ -n "$base" ] && [ -n "$sha" ] || { echo unknown; return; }
  if git merge-base --is-ancestor "$sha" "$base" 2>/dev/null; then echo yes; return; fi
  if [ -n "$branch" ] && [ -z "${SCAFFOLD_REPORT_NO_GH:-}" ] && command -v gh >/dev/null 2>&1; then
    local n
    if n=$(gh pr list --state merged --head "$branch" --json number --jq 'length' 2>/dev/null) \
      && [ "${n:-0}" -gt 0 ] 2>/dev/null; then echo squash; return; fi
  fi
  echo no
}

printf '%-52s %-28s %-6s %-8s %s\n' PATH BRANCH AGE MERGED DIR
total=0 missing=0 mergedn=0

emit_row() {
  local path=$1 head=$2 branch=$3 locked=$4 prunable=$5
  local dir=present ts="" age m shown
  if [ ! -d "$path" ]; then dir=MISSING; missing=$((missing + 1)); fi
  if [ -n "$head" ]; then ts=$(git show -s --format=%ct "$head" 2>/dev/null || true); fi
  age=$(age_of "$ts")
  m=$(merged_state "$head" "$branch")
  [ "$m" = yes ] || [ "$m" = squash ] && mergedn=$((mergedn + 1))
  shown=${branch:-(detached)}
  [ "$locked" -eq 0 ] || dir="$dir,LOCKED"
  [ "$prunable" -eq 0 ] || dir="$dir,prunable"
  printf '%-52s %-28s %-6s %-8s %s\n' "$path" "$shown" "$age" "$m" "$dir"
  total=$((total + 1))
}

path="" head="" branch="" locked=0 prunable=0
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    "worktree "*) path=${line#worktree } head="" branch="" locked=0 prunable=0 ;;
    "HEAD "*) head=${line#HEAD } ;;
    "branch "*) branch=${line#branch }; branch=${branch#refs/heads/} ;;
    locked*) locked=1 ;;
    prunable*) prunable=1 ;;
    "") [ -z "$path" ] || emit_row "$path" "$head" "$branch" "$locked" "$prunable"; path="" ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null; echo)

echo "worktrees: $total, directory missing: $missing, merged into ${base:-(no default branch found)}: $mergedn"
exit 0
