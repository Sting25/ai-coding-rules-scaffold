# shellcheck shell=bash
# scaffold-doctor-drift.sh: section 9 of scaffold-doctor.sh, template drift.
# SOURCED by scaffold-doctor.sh so it runs with the doctor's counters, helpers
# and `set -euo pipefail`; extracted for the same reason scaffold-doctor-gates.sh
# was, the doctor's own 500-line cap. Not a standalone script: it has no
# shebang on purpose.

# --- 9. template drift (AGENTS.md, coding-rules.md) --------------------------
# AGENTS.md is never rewritten once it exists, and coding-rules.md is replaced
# wholesale only under --force-all — correct, since both are user-owned once
# installed. The flip side is silent: a scaffold release that adds a section
# to either shipped file leaves an install behind with nothing on disk saying
# so (#133). Neither file carries a version marker, so section HEADINGS
# (every `## `/`### ` line) are the inventory, reported as a NOTE never a gap
# since a project may have deliberately trimmed one.
section "template drift"
# doctor_heading_drift <installed> <shipped> <label> <policy-note>. One awk
# pass mirrors section 4's forbidden-patterns-vs-template comparison: only
# headings that were SHIPPED and are now absent are reported (an extra local
# section is healthy, not drift). Headings compare case- and
# whitespace-insensitively (#187), and the template's `## Project` is skipped:
# it is the one section handed to the user to rename. The regex skips a
# `{{...}}`/`<TOKEN>` placeholder install.sh would substitute; neither shipped
# file has one today (checked), so this guards a future heading, not a live case.
doctor_heading_drift() {
  local td_inst=$1 td_shipped=$2 td_label=$3 td_policy=$4 td_quoted
  [ -f "$td_inst" ] || return 0
  if [ ! -f "$td_shipped" ]; then
    note "$(basename "$td_shipped") not found next to scaffold-doctor.sh ($SCAFFOLD_DIR): $td_label drift cannot be checked; re-fetch the full scaffold bundle, not just this one file"
    return 0
  fi
  td_quoted=$(awk '
    function norm(s) { s = tolower(s); gsub(/[ \t\r]+/, " ", s); sub(/ $/, "", s); return s }
    FNR == NR { have[norm($0)] = 1; next }
    !/^(## |### )/ { next }
    /\{\{/ || /<[A-Za-z_-]+>/ { next }
    norm($0) == "## project" { next }
    !(norm($0) in have) { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }
  ' "$td_inst" "$td_shipped" 2>/dev/null || true)
  if [ -z "$td_quoted" ]; then
    ok "$td_label carries every section of the shipped template"
    return 0
  fi
  note "$(basename "$td_inst") predates the shipped template: missing $td_quoted. diff it against $td_shipped and adopt what applies; $td_policy"
}
doctor_heading_drift "AGENTS.md" "$SCAFFOLD_DIR/AGENTS.md.template" "AGENTS.md" \
  "install.sh never rewrites this file"
doctor_heading_drift "coding-rules.md" "$SCAFFOLD_DIR/coding-rules.md" "coding-rules.md" \
  "install.sh --force-all replaces it wholesale (backup in .scaffold-bak); merging by hand keeps local edits"
