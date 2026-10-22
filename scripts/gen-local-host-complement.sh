#!/usr/bin/env bash
# scripts/gen-local-host-complement.sh: print the credential-URL rule line of
# forbidden-patterns/secrets.txt.template, exactly as shipped (pattern, TAB,
# description). Maintainer tool; not installed into projects.
#
# Why a generator: POSIX ERE has no lookahead and agent-precheck ORs every rule
# into one ERE, so "a credential URL whose host is NOT local" is written as a
# complement: the first host character cannot start a local host, OR the host
# starts like one and departs from it at some position, OR it is the full local
# name followed by another host character. That is one alternative per prefix of
# every local host, which is easy to get wrong by hand. Edit HOSTS below, run
# this, and paste the output over the shipped line; tests/cases/34 fails when the
# two differ.
#
# Portable to bash 3.2 (macOS); no python. Inside a bracket expression a `]`
# must come first (`[^]]`); outside one a literal `]` is written `[]]`, never
# `\]`, because GNU grep 3.8+ warns on a stray backslash and check-secrets drops
# a rule whose compile prints to stderr.
#
# Usage: bash scripts/gen-local-host-complement.sh

set -euo pipefail

# Local hosts, in the order their alternatives appear in the shipped line. An
# array, never a word list: `[::1]` would be glob-expanded.
HOSTS=(localhost 127.0.0.1 0.0.0.0 ::1 '[::1]')
# What may follow a full local name and still be part of a LONGER host (so
# `localhost.evil.com`, `localhost-x` and `localhost@evil.com` stay refused).
CONT='[A-Za-z0-9._@-]'
# Scheme, then userinfo `user:password@`. Userinfo cannot hold `:` (user) or `@`
# (either half), so the host's alignment after `@` is unique.
PREFIX='[a-zA-Z]+://[^[:space:]:/@]*:[^[:space:]/@]+@'
# The description carries an em dash; written as octal bytes so this script
# holds no literal one.
DESC="URL with embedded credentials $(printf '\342\200\224') use env vars"

# esc <literal>: the ERE that matches <literal> outside a bracket expression.
esc() {
  local s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      .) out="$out\\." ;;
      '[') out="$out\\[" ;;
      ']') out="${out}[]]" ;;
      *) out="$out$c" ;;
    esac
  done
  printf '%s' "$out"
}

# notc <char>: a bracket expression matching any single character but <char>.
notc() {
  if [ "$1" = "]" ]; then printf '[^]]'; else printf '[^%s]' "$1"; fi
}

# First alternative: a host whose first character starts no local host. `:` is
# always excluded (an empty host before a port), as are whitespace and `/`; the
# first character of each local host is appended, skipping `:` already there.
first=':[:space:]/'
for h in "${HOSTS[@]}"; do
  c=${h:0:1}
  [ "$c" = ":" ] && continue
  first="$first$c"
done
alts="[^$first]"

# Then, per host: every proper prefix followed by a different character or the
# end of the line, and the full name followed by a host character.
for h in "${HOSTS[@]}"; do
  for ((i = 1; i < ${#h}; i++)); do
    alts="$alts|$(esc "${h:0:i}")($(notc "${h:i:1}")|\$)"
  done
  alts="$alts|$(esc "$h")$CONT"
done

printf '%s(%s)\t%s\n' "$PREFIX" "$alts" "$DESC"
