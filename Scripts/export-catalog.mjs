#!/usr/bin/env node

import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [repositoryRoot, outputPath] = process.argv.slice(2);
if (!repositoryRoot || !outputPath) {
  throw new Error('usage: export-catalog.mjs <hooks-rotator-root> <output-path>');
}

const catalogModuleURL = pathToFileURL(join(repositoryRoot, 'src', 'core', 'catalog.mjs')).href;
const { buildCatalog } = await import(catalogModuleURL);
const sourceCatalog = buildCatalog(repositoryRoot);
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
