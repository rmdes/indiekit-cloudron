import { test } from "node:test";
import assert from "node:assert/strict";
import { composeFromInputs } from "../compose-site.mjs";

const REGISTRY = {
  core: [
    { key: "site-config", package: "@rmdes/indiekit-endpoint-site-config", version: "^1.0.0" },
    { key: "auth", package: "@indiekit/endpoint-auth", overridden: true },
  ],
  post_types: [
    { key: "article", package: "@indiekit/post-type-article", default_enabled: true },
    { key: "jam", package: "@indiekit/post-type-jam", default_enabled: false },
  ],
  endpoints: [
    { key: "github", package: "@rmdes/indiekit-endpoint-github", version: "^1.2.7", default_enabled: false, feature_flag: true },
  ],
};

const BASE_PACKAGE_JSON = {
  name: "indiekit-cloudron",
  private: true,
  overrides: {
    "@indiekit/endpoint-auth": "npm:@rmdes/indiekit-endpoint-auth@^1.0.0",
  },
};

const TEMPLATE = `export default { plugins: [\n{{PLUGINS}}\n] };`;

test("compose includes all core plugins regardless of manifest", () => {
  const manifest = {};
  const r = composeFromInputs(REGISTRY, manifest, BASE_PACKAGE_JSON, TEMPLATE);
  assert.ok(r.packageJson.dependencies["@rmdes/indiekit-endpoint-site-config"]);
  // 'overridden:true' entries are NOT in deps directly — they install as
  // transitive deps of @indiekit/indiekit; overrides field swaps in the fork.
  assert.ok(!r.packageJson.dependencies["@indiekit/endpoint-auth"]);
  assert.ok(r.packageJson.overrides["@indiekit/endpoint-auth"]);
});

test("compose skips overridden entries from plugins array AND deps", () => {
  const r = composeFromInputs(REGISTRY, {}, BASE_PACKAGE_JSON, TEMPLATE);
  // not in plugins array
  assert.ok(!r.indiekitConfig.includes("@indiekit/endpoint-auth"));
  // not in deps
  assert.ok(!r.packageJson.dependencies["@indiekit/endpoint-auth"]);
});

test("compose respects post_type default_enabled", () => {
  const manifest = {};
  const r = composeFromInputs(REGISTRY, manifest, BASE_PACKAGE_JSON, TEMPLATE);
  assert.ok(r.packageJson.dependencies["@indiekit/post-type-article"]);
  assert.ok(!r.packageJson.dependencies["@indiekit/post-type-jam"]);
});

test("compose includes endpoint when enabled in manifest", () => {
  const manifest = { endpoints: { github: { enabled: true } } };
  const r = composeFromInputs(REGISTRY, manifest, BASE_PACKAGE_JSON, TEMPLATE);
  assert.ok(r.packageJson.dependencies["@rmdes/indiekit-endpoint-github"]);
});

test("compose is lenient on unregistered plugins and warns", () => {
  const manifest = { endpoints: { unknown: { enabled: true } } };
  const r = composeFromInputs(REGISTRY, manifest, BASE_PACKAGE_JSON, TEMPLATE);
  assert.equal(r.warnings.length, 1);
  assert.match(r.warnings[0], /unregistered/i);
});

test("compose preserves package.json overrides", () => {
  const r = composeFromInputs(REGISTRY, {}, BASE_PACKAGE_JSON, TEMPLATE);
  assert.ok(r.packageJson.overrides["@indiekit/endpoint-auth"]);
});

test("compose generates plugins array in indiekit.config.js", () => {
  const r = composeFromInputs(REGISTRY, {}, BASE_PACKAGE_JSON, TEMPLATE);
  assert.match(r.indiekitConfig, /"@rmdes\/indiekit-endpoint-site-config"/);
  assert.match(r.indiekitConfig, /"@indiekit\/post-type-article"/);
  assert.ok(!r.indiekitConfig.includes("post-type-jam"));
});

test("compose emits the eleventy preset AFTER every post-type plugin", () => {
  // The preset configures each post type's `post.path`/`url` from the post
  // types registered when its init() runs. Post types listed only in the site
  // array (repost, video, audio, event, jam, rsvp) must register BEFORE the
  // preset, or they get no path → "No configuration provided for <type>".
  const registry = {
    core: [
      { key: "site-config", package: "@rmdes/indiekit-endpoint-site-config", version: "^1.0.0" },
      { key: "preset-eleventy", package: "@rmdes/indiekit-preset-eleventy", version: "^1.0.0" },
      { key: "store-file-system", package: "@indiekit/store-file-system", version: "^1.0.0" },
      { key: "post-type-page", package: "@rmdes/indiekit-post-type-page", version: "^1.0.0" },
    ],
    post_types: [
      { key: "article", package: "@indiekit/post-type-article", default_enabled: true },
      { key: "repost", package: "@indiekit/post-type-repost", default_enabled: true },
    ],
  };
  const r = composeFromInputs(registry, {}, BASE_PACKAGE_JSON, TEMPLATE);
  const lines = r.indiekitConfig.split("\n");
  const idx = (pkg) => lines.findIndex((l) => l.includes(`"${pkg}"`));

  const presetIdx = idx("@rmdes/indiekit-preset-eleventy");
  const articleIdx = idx("@indiekit/post-type-article");
  const repostIdx = idx("@indiekit/post-type-repost");
  const pageIdx = idx("@rmdes/indiekit-post-type-page");

  assert.ok(presetIdx > -1, "preset present in plugins array");
  assert.ok(repostIdx > -1, "repost present in plugins array");
  assert.ok(presetIdx > articleIdx, "preset must come after article");
  assert.ok(presetIdx > repostIdx, "preset must come after repost");
  // post-type-page is a core post type; it too must register before the preset
  assert.ok(presetIdx > pageIdx, "preset must come after post-type-page");
});
