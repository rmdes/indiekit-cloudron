import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import yaml from "js-yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const TIERS = ["core", "post_types", "syndicators", "endpoints"];

export function composeFromInputs(registry, manifest, basePackageJson, template) {
  const warnings = [];
  const selected = [];
  const registryIndex = new Map();
  for (const tier of TIERS) {
    for (const entry of registry[tier] || []) {
      registryIndex.set(entry.key, { ...entry, tier });
    }
  }

  // Core is always selected; never reads from manifest.core
  for (const entry of registry.core || []) {
    selected.push({ ...entry, tier: "core" });
  }

  // Other tiers: combine registry defaults + manifest overrides
  for (const tier of ["post_types", "syndicators", "endpoints"]) {
    const manifestTier = manifest[tier] || {};
    for (const entry of registry[tier] || []) {
      const override = manifestTier[entry.key];
      const enabled = override !== undefined ? override.enabled : entry.default_enabled;
      if (enabled) selected.push({ ...entry, tier });
    }

    // Unregistered plugins referenced in manifest
    for (const key of Object.keys(manifestTier)) {
      if (!registryIndex.has(key)) {
        warnings.push(`unregistered plugin '${key}' in tier '${tier}' — included with no version pin`);
        selected.push({ key, package: `@rmdes/indiekit-endpoint-${key}`, tier });
      }
    }
  }

  // Build package.json deps
  const dependencies = { ...(basePackageJson.dependencies || {}) };
  for (const entry of selected) {
    if (entry.overridden) {
      dependencies[entry.package] = "latest";
    } else if (entry.version) {
      dependencies[entry.package] = entry.version;
    } else {
      dependencies[entry.package] = "*";
    }
  }
  if (!dependencies["@indiekit/indiekit"]) {
    dependencies["@indiekit/indiekit"] = "^1.0.0-beta.27";
  }

  const packageJson = {
    ...basePackageJson,
    dependencies,
  };

  // Build indiekit.config.js
  const pluginsArrayText = selected
    .map((e) => `    "${e.package}",`)
    .join("\n");
  const indiekitConfig = template.replace("{{PLUGINS}}", pluginsArrayText);

  const loadout = {
    site: manifest._site || "unknown",
    timestamp: new Date().toISOString(),
    selected: selected.map((e) => ({ key: e.key, package: e.package, tier: e.tier, version: e.version })),
    warnings,
    summary: {
      total: selected.length,
      core: selected.filter((e) => e.tier === "core").length,
      post_types: selected.filter((e) => e.tier === "post_types").length,
      syndicators: selected.filter((e) => e.tier === "syndicators").length,
      endpoints: selected.filter((e) => e.tier === "endpoints").length,
    },
  };

  return { packageJson, indiekitConfig, loadout, warnings };
}

export async function composeSite(siteName) {
  const registry = yaml.load(await readFile(path.join(ROOT, "plugin-registry/plugin-registry.yaml"), "utf8"));
  const manifestPath = path.join(ROOT, "sites", siteName, "config/plugins.yaml");
  const manifest = yaml.load(await readFile(manifestPath, "utf8")) || {};
  manifest._site = siteName;
  const basePackageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));
  const template = await readFile(path.join(ROOT, "indiekit.config.js.template"), "utf8");

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
