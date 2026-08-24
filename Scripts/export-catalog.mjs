#!/usr/bin/env node

// Exports the Tama hook catalog to JSON by shelling out to the native Rust
// CLI (`tama-cli list --json`). The Node implementation of the catalog
// builder was removed; the Rust binary is the single source of truth.

import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const [repositoryRoot, outputPath] = process.argv.slice(2);
if (!repositoryRoot || !outputPath) {
  throw new Error('usage: export-catalog.mjs <tama-root> <output-path>');
}

const cli = process.env.TAMA_CLI ?? 'tama-cli';
const stdout = execFileSync(cli, ['list', '--root', repositoryRoot, '--json'], {
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024,
});
const sourceCatalog = JSON.parse(stdout);
const catalog = {
  ...sourceCatalog,
  generatedAt: sourceCatalog.generatedAt ?? 'Unknown',
  hooks: sourceCatalog.hooks.map((hook) => ({
    ...hook,
    category: hook.category ?? 'Uncategorized',
    status: hook.status ?? 'unknown',
    events: hook.events.map((event) => ({
      ...event,
      timeout: event.timeout ?? 0,
    })),
  })),
};
writeFileSync(outputPath, `${JSON.stringify(catalog, null, 2)}\n`, 'utf8');
