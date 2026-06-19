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

  // The Eleventy preset (`@rmdes/indiekit-preset-eleventy`) configures each post
  // type's `post.path`/`url` from the post types registered when its init() runs.
  // Indiekit deep-merges the site plugins AFTER @indiekit/indiekit's own defaults
  // (which already include article/note/reply/like/bookmark/photo), so those
  // default types are configured — but post types that exist ONLY in the site
  // array (repost, video, audio, event, jam, rsvp, …) load after the preset and
  // get no path → "No configuration provided for <type>" on Micropub create.
  // The preset lives in the `core` tier, which is emitted before `post_types`,
  // so move it to just after the last post_types entry to satisfy the preset's
  // ordering contract ("post types MUST be loaded before the preset").
  const presetIndex = selected.findIndex((e) => e.key === "preset-eleventy");
  if (presetIndex !== -1) {
    const [preset] = selected.splice(presetIndex, 1);
    let lastPostTypeIndex = -1;
    for (let i = 0; i < selected.length; i++) {
      if (selected[i].tier === "post_types") lastPostTypeIndex = i;
    }
    const insertAt =
      lastPostTypeIndex === -1 ? selected.length : lastPostTypeIndex + 1;
    selected.splice(insertAt, 0, preset);
  }

  // Build package.json deps.
  // - Skip 'overridden:true' entries: they're auto-installed as transitive deps
  //   of @indiekit/indiekit, and the package.json overrides field swaps them to
  //   @rmdes forks. Adding them as direct deps triggers npm EOVERRIDE conflicts.
  // - 'library:true' entries are real installable packages (just not listed in
  //   the indiekit plugins array), so they DO get a dep entry.
  const dependencies = { ...(basePackageJson.dependencies || {}) };
  for (const entry of selected) {
    if (entry.overridden) continue;
    if (entry.version) {
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

  // Build indiekit.config.js plugins array
  // Skip 'overridden:true' (indiekit core auto-imports them; the package.json
  // overrides field swaps them to @rmdes forks at install time) and 'library:true'
  // (helper libraries like startup-gate, never indiekit plugins).
  const pluginsArrayText = selected
    .filter((e) => !e.overridden && !e.library)
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
