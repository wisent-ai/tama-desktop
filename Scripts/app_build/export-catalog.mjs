#!/usr/bin/env node

// Exports the Tama hook catalog to JSON by shelling out to the native Rust
// CLI (`tama list --json`). The Node implementation of the catalog
// builder was removed; the Rust binary is the single source of truth.

import { execFileSync } from 'node:child_process';
import { closeSync, openSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// argv holds node and this script before the arguments.
const [, , repositoryRoot, outputPath] = process.argv;
if (!repositoryRoot || !outputPath) {
  throw new Error('usage: export-catalog.mjs <tama-root> <output-path>');
}

// The catalog comes from the tama built in that same root (prepare.sh's
// TAMA_PROGRAM), never from whichever tama PATH holds; a root without a
// release build is refused by execFileSync naming the missing program.
const cli = join(repositoryRoot, 'rust', 'target', 'release', 'tama');
// tama writes its catalog straight into the bundle, so no buffer size bounds
// it; the app shows a hook without a category or status, or a catalog
// without its build time, as Tama stating none, never under an invented
// 'Uncategorized' or 'unknown'.
const output = openSync(outputPath, 'w');
try {
  execFileSync(cli, ['list', '--root', repositoryRoot, '--json'], {
    stdio: ['ignore', output, 'inherit'],
  });
} finally {
  closeSync(output);
}
// A catalog the app could not decode is refused here, at build time.
JSON.parse(readFileSync(outputPath, 'utf8'));
