#!/usr/bin/env node
'use strict';

// Thin wrapper so `npx ai-coding-rules-scaffold` runs the same install.sh the
// git-clone path uses. The installer is pure bash and reads its templates from
// its own directory ($SCAFFOLD_DIR), writing only into the caller's cwd — so we
// exec it from the package root (read-only node_modules location) with cwd left
// at the user's project. Args pass straight through (--both, --frontend, etc.).
//
// No npm dependencies on purpose: this uses only Node built-ins, so the package
// installs instantly and there is no lockfile / supply-chain surface to audit.

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const pkgRoot = path.resolve(__dirname, '..');
const installer = path.join(pkgRoot, 'install.sh');

if (!fs.existsSync(installer)) {
  process.stderr.write(
    'ai-coding-rules-scaffold: install.sh is missing from the package at ' +
      pkgRoot +
      '.\nThis is a packaging bug — please report it at ' +
      'https://github.com/Sting25/ai-coding-rules-scaffold/issues\n'
  );
  process.exit(1);
}

const result = spawnSync('bash', [installer, ...process.argv.slice(2)], {
  stdio: 'inherit',
  cwd: process.cwd(),
});

if (result.error) {
  if (result.error.code === 'ENOENT') {
    process.stderr.write(
      'ai-coding-rules-scaffold: `bash` was not found on PATH.\n' +
        'This installer needs bash — preinstalled on macOS/Linux; on Windows ' +
        'run it from Git Bash or WSL.\n'
    );
  } else {
    process.stderr.write('ai-coding-rules-scaffold: ' + result.error.message + '\n');
  }
  process.exit(1);
}

// Propagate the installer's exit code (0 ok, non-zero on failure) so CI and
// scripted callers see the real status.
process.exit(result.status === null ? 1 : result.status);
