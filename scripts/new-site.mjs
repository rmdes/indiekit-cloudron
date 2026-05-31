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

  await writeFile(path.join(dir, "nginx.conf"), `# nginx config for ${name}\n# TODO: configure server block and reverse proxy\n`);
  await writeFile(path.join(dir, "redirects.map"), `# nginx rewrite map for ${name}\n`);
  await writeFile(path.join(dir, "old-blog-redirects.map"), `# legacy redirects for ${name}\n`);
  await writeFile(path.join(dir, "env.sh"), `#!/bin/bash\n# Secrets and connection strings for ${name}\nexport INDIEKIT_MONGO_URL=""\n`);

  console.log(`==> Scaffolded sites/${name}/config/`);
  console.log(`Next steps:`);
  console.log(`  1. Edit sites/${name}/config/plugins.yaml to enable plugins`);
  console.log(`  2. Edit sites/${name}/config/env.sh with secrets`);
  console.log(`  3. Edit sites/${name}/config/nginx.conf for the reverse proxy`);
  console.log(`  4. make compose SITE=${name}`);
  console.log(`  5. make build SITE=${name}`);
}

const name = process.argv[2];
if (!name) { console.error("Usage: new-site.mjs <name>"); process.exit(1); }
await scaffold(name);
