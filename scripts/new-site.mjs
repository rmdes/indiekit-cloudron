import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const TEMPLATE_PLUGINS_YAML = `# Plugin manifest for {{NAME}}
# core is implicit — see plugin-registry/plugin-registry.yaml

post_types:
  # Enable non-default post types or disable defaults

syndicators:
  # mastodon: { enabled: true }

endpoints:
  # Enable per-site endpoints
`;

async function scaffold(name) {
  const dir = path.join(ROOT, "sites", name, "config");
  await mkdir(dir, { recursive: true });

  await writeFile(
    path.join(dir, "plugins.yaml"),
    TEMPLATE_PLUGINS_YAML.replaceAll("{{NAME}}", name),
  );

  // env.sh is the only config file with no *.template fallback in the repo
  // (secrets can't sensibly be templated). Other config files (nginx.conf,
  // redirects.map, old-blog-redirects.map) intentionally LEFT UNCREATED so
  // `make prepare` falls back to the repo's nginx.conf.template etc.
  // Per-site overrides for those files are optional — create them only when
  // the site needs to diverge from the shared template.
  await writeFile(path.join(dir, "env.sh"), `#!/bin/bash\n# Secrets and connection strings for ${name}\nexport INDIEKIT_MONGO_URL=""\n`);

  console.log(`==> Scaffolded sites/${name}/config/`);
  console.log(`    Created: plugins.yaml, env.sh`);
  console.log(`    Not created (use template fallback): nginx.conf, redirects.map, old-blog-redirects.map`);
  console.log(`Next steps:`);
  console.log(`  1. Edit sites/${name}/config/plugins.yaml to enable plugins`);
  console.log(`  2. Edit sites/${name}/config/env.sh with secrets`);
  console.log(`  3. (Optional) Create sites/${name}/config/nginx.conf if you need per-site nginx config`);
  console.log(`  4. make compose SITE=${name}`);
  console.log(`  5. make build SITE=${name}`);
}

const name = process.argv[2];
if (!name) { console.error("Usage: new-site.mjs <name>"); process.exit(1); }
await scaffold(name);
