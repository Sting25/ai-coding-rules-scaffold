#!/usr/bin/env bash
# scaffold-blocks.sh: read-only summary of the durable refusal log (issue #218).
#
# Every gate the scaffold ships appends one tab-separated line to
# <git common dir>/scaffold-blocks.log when it refuses something (see
# .githooks/lib/refusal-log for the line format and what is never recorded).
# This reads that log, and the rotated scaffold-blocks.log.1 before it, and
# prints how often each gate and rule refused, plus the longest run of the same
# refusal repeated back to back, which is what a retry loop looks like.
#
# Usage:  bash scaffold-blocks.sh [--quiet]
#         (or `npx ai-coding-rules-scaffold blocks`)
# Run from anywhere inside the git working tree. Nothing is written or changed.
#   --quiet  print nothing at all when no refusal has been recorded
# Exit:   0 summary printed (or nothing recorded), 1 not inside a git repository,
#         2 usage error.
# awk only, so it runs on the bash 3.2 and awk that ship with macOS.

set -euo pipefail

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,/^# awk only/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: scaffold-blocks.sh [--quiet]" >&2; exit 2 ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not found: scaffold-blocks.sh reads the log under the repository's git directory" >&2
  exit 1
fi
CDIR=$(git rev-parse --git-common-dir 2>/dev/null) || {
  echo "✗ not a git repository: run scaffold-blocks.sh from inside the project" >&2
  exit 1
}
case $CDIR in /*) ;; *) CDIR=$PWD/$CDIR ;; esac
LOG="$CDIR/scaffold-blocks.log"

FILES=()
[ ! -s "$LOG.1" ] || FILES+=("$LOG.1")
[ ! -s "$LOG" ] || FILES+=("$LOG")
if [ ${#FILES[@]} -eq 0 ]; then
  [ "$QUIET" -eq 1 ] || echo "refusal log: $LOG (no refusals recorded)"
  exit 0
fi

# One awk program, four reports selected by `mode`. A retry run is consecutive
# lines with the same gate, rule and file; the first longest run wins a tie.
report() {
  awk -F'\t' -v mode="$1" '
    NF >= 4 {
      n++
      if (n == 1) first = $1
      last = $1
      g[$2]++
      gr[$2 "\t" $3]++
      key = $2 "\t" $3 "\t" $4
      if (key == prev) cur++; else { cur = 1; rs = $1 }
      prev = key
      if (cur > best) { best = cur; bk = key; bs = rs; be = $1 }
    }
    END {
      if (mode == "head") printf "%d\t%s\t%s\n", n, first, last
      else if (mode == "gate") { for (k in g) printf "%d\t%s\n", g[k], k }
      else if (mode == "rule") { for (k in gr) printf "%d\t%s\n", gr[k], k }
      else if (mode == "run" && n > 0) printf "%d\t%s\t%s\t%s\n", best, bk, bs, be
    }
  ' "${FILES[@]}"
}

TAB=$(printf '\t')
IFS=$TAB read -r N FIRST LAST <<EOF_HEAD
$(report head)
EOF_HEAD
if [ "${N:-0}" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] || echo "refusal log: $LOG (no refusals recorded)"
  exit 0
fi

echo "refusal log: $LOG ($N line(s), first $FIRST last $LAST)"
echo "per gate:"
report gate | sort -t "$TAB" -k1,1nr -k2,2 | awk -F'\t' '{ printf "  %d  %s\n", $1, $2 }'
echo "per gate and rule:"
report rule | sort -t "$TAB" -k1,1nr -k2,2 -k3,3 | awk -F'\t' '{ printf "  %d  %s  %s\n", $1, $2, $3 }'
IFS=$TAB read -r RUN RGATE RRULE RFILE RFIRST RLAST <<EOF_RUN
$(report run)
EOF_RUN
echo "longest retry run: $RUN consecutive refusal(s) of $RGATE $RRULE $RFILE (first $RFIRST last $RLAST)"
