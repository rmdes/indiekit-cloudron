import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import yaml from "js-yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const TIERS = ["post_types", "syndicators", "endpoints"];

async function findTier(key) {
  const registry = yaml.load(await readFile(path.join(ROOT, "plugin-registry/plugin-registry.yaml"), "utf8"));
  for (const tier of TIERS) {
    if ((registry[tier] || []).some((e) => e.key === key)) return tier;
  }
  if ((registry.core || []).some((e) => e.key === key)) {
    throw new Error(`Cannot edit core plugin '${key}' — core is unmissable by design`);
  }
  return null;
}

async function editManifest(site, key, action) {
  const tier = await findTier(key);
  if (tier === null) {
    console.warn(`Plugin '${key}' is not in the registry — adding anyway (will produce a warning on compose)`);
  }
  const manifestPath = path.join(ROOT, "sites", site, "config/plugins.yaml");
  const manifest = yaml.load(await readFile(manifestPath, "utf8")) || {};
  const targetTier = tier || "endpoints";
  if (!manifest[targetTier]) manifest[targetTier] = {};
  manifest[targetTier][key] = { enabled: action === "add" };
  await writeFile(manifestPath, yaml.dump(manifest, { indent: 2 }));
  console.log(`${action === "add" ? "Enabled" : "Disabled"} ${key} (${targetTier}) for ${site}`);
  console.log(`Run 'make compose SITE=${site}' to regenerate compiled artifacts.`);
}

const [, , action, site, key] = process.argv;
if (!["add", "remove"].includes(action) || !site || !key) {
  console.error("Usage: plugin-edit.mjs <add|remove> <site> <key>");
  process.exit(1);
}
await editManifest(site, key, action);
