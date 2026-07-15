import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import yaml from "js-yaml";
import { composeFromInputs } from "../plugin-registry/scripts/compose-core.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

// Thin cloudron I/O wrapper around the shared compose-core (in the
// plugin-registry submodule). Reads this repo's per-site layout, calls the
// pure composeFromInputs(), and writes the compiled artifacts. The compile
// ALGORITHM lives in plugin-registry/scripts/compose-core.mjs so cloudron and
// indiekit-deploy can never drift on how they turn the registry into a set.
export async function composeSite(siteName) {
  const registry = yaml.load(await readFile(path.join(ROOT, "plugin-registry/plugin-registry.yaml"), "utf8"));
  const manifestPath = path.join(ROOT, "sites", siteName, "config/plugins.yaml");
  const manifest = yaml.load(await readFile(manifestPath, "utf8")) || {};
  manifest._site = siteName;
  const basePackageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));
  // Composer reads the SITE'S indiekit.config.js as its template, NOT the generic
  // template at repo root. This preserves per-site config (MongoDB URL, locale,
  // publication, plugin-specific config blocks). The per-site file must have a
  // {{PLUGINS}} placeholder inside its plugins:[] array — if absent, the composer
  // is a no-op for indiekit.config.js (only package.json gets composed).
  const template = await readFile(path.join(ROOT, "sites", siteName, "config/indiekit.config.js"), "utf8");

  const result = composeFromInputs(registry, manifest, basePackageJson, template);

  const outDir = path.join(ROOT, "sites", siteName, ".compiled");
  await mkdir(outDir, { recursive: true });
  await writeFile(path.join(outDir, "package.json"), JSON.stringify(result.packageJson, null, 2));
  await writeFile(path.join(outDir, "indiekit.config.js"), result.indiekitConfig);
  await writeFile(path.join(outDir, "plugin-loadout.json"), JSON.stringify(result.loadout, null, 2));

  console.log(`${siteName}: ${result.loadout.summary.core} core + ${result.loadout.summary.post_types} post_types + ${result.loadout.summary.syndicators} syndicators + ${result.loadout.summary.endpoints} endpoints = ${result.loadout.summary.total} packages (${result.warnings.length} warnings)`);
  for (const w of result.warnings) console.warn(`  warning: ${w}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const site = process.env.SITE || process.argv[2];
  if (!site) {
    console.error("Usage: SITE=foo node compose-site.mjs  (or: compose-site.mjs foo)");
    process.exit(1);
  }
  await composeSite(site);
}
