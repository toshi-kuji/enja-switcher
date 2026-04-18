#!/usr/bin/env node
// Guards against the 2026-04-05 regression that produced URLs like
// `https://toshi-kuji.github.io/enja-switcher/enja-switcher/` in canonical /
// og:url / hreflang, which caused Google to deindex the site.
// Run this after `astro build` (wired in .github/workflows/deploy.yml).

import { readdir, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const distDir = join(scriptDir, '..', 'dist');

const EXPECTED_PREFIX = 'https://toshi-kuji.github.io/enja-switcher/';
const FORBIDDEN_SUBSTRING = 'enja-switcher/enja-switcher';

const PATTERNS = [
  { name: 'canonical', re: /<link[^>]*\brel=["']canonical["'][^>]*\bhref=["']([^"']+)["']/gi },
  { name: 'og:url', re: /<meta[^>]*\bproperty=["']og:url["'][^>]*\bcontent=["']([^"']+)["']/gi },
  { name: 'hreflang', re: /<link[^>]*\brel=["']alternate["'][^>]*\bhreflang=["'][^"']+["'][^>]*\bhref=["']([^"']+)["']/gi },
];

async function* walkHtml(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) yield* walkHtml(full);
    else if (entry.isFile() && entry.name.endsWith('.html')) yield full;
  }
}

const errors = [];
let fileCount = 0;
let urlCount = 0;

for await (const file of walkHtml(distDir)) {
  fileCount++;
  const html = await readFile(file, 'utf8');
  const rel = file.slice(distDir.length + 1);
  for (const { name, re } of PATTERNS) {
    for (const match of html.matchAll(re)) {
      const url = match[1];
      urlCount++;
      if (url.includes(FORBIDDEN_SUBSTRING)) {
        errors.push(`${rel}: ${name} has duplicate base path: ${url}`);
      }
      if (!url.startsWith(EXPECTED_PREFIX)) {
        errors.push(`${rel}: ${name} does not start with ${EXPECTED_PREFIX}: ${url}`);
      }
    }
  }
}

if (fileCount === 0) {
  console.error(`No HTML files found in ${distDir}. Did \`astro build\` run?`);
  process.exit(1);
}

if (errors.length > 0) {
  console.error(`Canonical verification FAILED (${errors.length} issue(s) in ${fileCount} HTML file(s)):`);
  for (const e of errors) console.error('  - ' + e);
  process.exit(1);
}

console.log(`Canonical verification passed: ${urlCount} URL(s) across ${fileCount} HTML file(s) all use ${EXPECTED_PREFIX}`);
