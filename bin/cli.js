#!/usr/bin/env node
'use strict';

// Thin wrapper so `npx ai-coding-rules-scaffold` runs the same install.sh the
// git-clone path uses (and, for `doctor`, scaffold-doctor.sh alongside it).
// Both are pure bash and read their own files relative to $SCAFFOLD_DIR,
// writing/reading only the caller's cwd — so we exec from the package root
// (read-only node_modules location) with cwd left at the user's project. Args
// pass straight through (--both, --frontend, --quiet, etc.) with no parsing
// beyond picking which script to run.
//
// No npm dependencies on purpose: this uses only Node built-ins, so the package
// installs instantly and there is no lockfile / supply-chain surface to audit.

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const pkgRoot = path.resolve(__dirname, '..');

// `doctor` is the one subcommand this CLI dispatches on; everything else
// passes straight through to install.sh unexamined (no allowlist, no flag
// parsing here — see below). It would be more consistent for install.sh to
// grow a `--doctor` flag and keep this file a pure passthrough, but
// install.sh is already pinned at its 500-line module cap (issue #84), so a
// second script gets a second entry point instead of a bigger install.sh.
const args = process.argv.slice(2);
// `assess` is the read-only measurement (scaffold-assess.sh): what each
// component would flag in this repo, with nothing copied. Same shape as
// `doctor`: dispatch on the first word, pass the rest through.
const SUBCOMMANDS = { doctor: 'scaffold-doctor.sh', assess: 'scaffold-assess.sh' };
const isSub = Object.prototype.hasOwnProperty.call(SUBCOMMANDS, args[0]);
const script = isSub ? SUBCOMMANDS[args[0]] : 'install.sh';
const scriptArgs = isSub ? args.slice(1) : args;
const target = path.join(pkgRoot, script);

if (!fs.existsSync(target)) {
  process.stderr.write(
    'ai-coding-rules-scaffold: ' +
      script +
      ' is missing from the package at ' +
      pkgRoot +
      '.\nThis is a packaging bug — please report it at ' +
      'https://github.com/Sting25/ai-coding-rules-scaffold/issues\n'
  );
  process.exit(1);
}

const result = spawnSync('bash', [target, ...scriptArgs], {
  stdio: 'inherit',
  cwd: process.cwd(),
});

if (result.error) {
  if (result.error.code === 'ENOENT') {
    process.stderr.write(
      'ai-coding-rules-scaffold: `bash` was not found on PATH.\n' +
        'This needs bash — preinstalled on macOS/Linux; on Windows run it ' +
        'from Git Bash or WSL.\n'
    );
  } else {
    process.stderr.write('ai-coding-rules-scaffold: ' + result.error.message + '\n');
  }
  process.exit(1);
}

// Propagate the child script's exit code (0 ok, non-zero on failure) so CI
// and scripted callers see the real status.
process.exit(result.status === null ? 1 : result.status);
