// Checks the committed map layers, offline: CI fails when the assets drift
// from layers.yaml, sources.yaml or the manifest (docs/design/geography.md
// §7). When every source is in the cache, it also rebuilds the layers and
// compares them byte for byte.
//
//   npm run check
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import YAML from 'yaml';
import {
  assetsDir,
  budgets,
  downloadPath,
  isArchive,
  loadConfig,
  readCurriculum,
  repoDir,
  sha256,
  toolDir,
  unpackedDir,
} from './lib.mjs';

const problems = [];
const notes = [];
const fail = (message) => problems.push(message);

let config;
try {
  config = loadConfig();
} catch (error) {
  console.error(`geography: ${error.message}`);
  process.exit(1);
}
for (const source of config.sources.values()) {
  if (source.sha256 === 'PENDING') fail(`${source.id}: record its SHA-256 with npm run fetch -- --record`);
}

const manifestFile = path.join(assetsDir, 'manifest.yaml');
if (!fs.existsSync(manifestFile)) {
  console.error('geography: assets/geography/manifest.yaml is missing; run npm run build');
  process.exit(1);
}
const manifest = YAML.parse(fs.readFileSync(manifestFile, 'utf8'));
const layers = manifest?.map_layers ?? [];
const geometries = manifest?.node_geometries ?? [];

// The manifest describes exactly the layers of layers.yaml.
const expected = config.layers.map((l) => l.id).join(', ');
const actual = layers.map((l) => l.id).join(', ');
if (expected !== actual) fail(`manifest layers are ${actual}; layers.yaml has ${expected}`);

const keysOf = new Map();
let total = 0;
for (const layer of layers) {
  const spec = config.layers.find((l) => l.id === layer.id);
  if (!spec) continue;
  const same = (field, value) => {
    if (JSON.stringify(layer[field]) !== JSON.stringify(value)) {
      fail(`${layer.id}: manifest ${field} ${JSON.stringify(layer[field])} differs from layers.yaml ${JSON.stringify(value)}`);
    }
  };
  same('display_name', spec.display_name);
  same('geometry_kind', spec.geometry);
  same('asset_path', `assets/geography/${spec.asset}`);
  same('min_zoom', spec.zoom[0]);
  same('max_zoom', spec.zoom[1]);
  same('parent_layer_id', spec.parent ?? null);
  same('source_citation_ids', spec.sources);

  const file = path.join(repoDir, layer.asset_path);
  if (!fs.existsSync(file)) {
    fail(`${layer.id}: ${layer.asset_path} is missing`);
    continue;
  }
  const bytes = fs.readFileSync(file);
  total += bytes.length;
  if (sha256(bytes) !== layer.asset_sha256) fail(`${layer.id}: ${layer.asset_path} does not match its SHA-256 in the manifest`);
  if (bytes.length !== layer.asset_bytes) fail(`${layer.id}: ${layer.asset_path} is ${bytes.length} bytes, not ${layer.asset_bytes}`);
  if (bytes.length > budgets.layerBytes) fail(`${layer.id}: ${bytes.length} bytes is over the 1.5 MB budget (GEO-11)`);
  try {
    const topology = JSON.parse(bytes.toString('utf8'));
    const [object] = Object.values(topology.objects ?? {});
    keysOf.set(layer.id, new Set((object?.geometries ?? []).map((g) => g.id).filter((id) => id != null)));
  } catch (error) {
    fail(`${layer.id}: ${layer.asset_path} is not TopoJSON: ${error.message}`);
  }
}
if (total > budgets.totalBytes) fail(`the layers total ${total} bytes, over the 8 MB budget (GEO-11)`);

// No stray files among the assets.
const known = new Set(['manifest.yaml', ...config.layers.map((l) => l.asset)]);
for (const name of fs.readdirSync(assetsDir)) {
  if (!known.has(name)) fail(`assets/geography/${name} belongs to no layer`);
}

// Every geometry is a feature of its layer, for a node of the curriculum.
const curriculum = readCurriculum();
const expectedNodes = new Set();
for (const spec of config.layers) {
  const nodes = spec.appellation_areas
    ? Object.keys(spec.appellation_areas)
    : Object.values(spec.natural_earth.nodes ?? {});
  for (const node of nodes) expectedNodes.add(`${spec.id} ${node}`);
}
for (const g of geometries) {
  const where = `node_geometries ${g.map_layer_id} ${g.knowledge_node_id}`;
  if (!curriculum.nodes.has(g.knowledge_node_id)) fail(`${where}: not a node of the curriculum`);
  if (!keysOf.get(g.map_layer_id)?.has(g.feature_key)) fail(`${where}: feature ${g.feature_key} is not in the layer`);
  if (!(g.min_lon <= g.label_lon && g.label_lon <= g.max_lon && g.min_lat <= g.label_lat && g.label_lat <= g.max_lat)) {
    fail(`${where}: its label point is outside its bounding box`);
  }
  if (!expectedNodes.delete(`${g.map_layer_id} ${g.knowledge_node_id}`)) fail(`${where}: layers.yaml does not map it`);
}
for (const missing of expectedNodes) fail(`node_geometries lacks ${missing}`);

// With every source cached, the committed files are what the sources give.
const cached = [...config.sources.values()].every((source) => {
  const file = downloadPath(source);
  if (!fs.existsSync(file)) return false;
  if (!isArchive(source)) return true;
  const stamp = path.join(unpackedDir(source), '.sha256');
  return fs.existsSync(stamp) && fs.readFileSync(stamp, 'utf8') === source.sha256;
});
if (cached && problems.length === 0) {
  const { build } = await import('./build.mjs');
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'geography-'));
  try {
    fs.mkdirSync(path.join(out, 'tool', 'geography'), { recursive: true });
    await build(out);
    const text = (file) => fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
    for (const name of known) {
      if (text(path.join(out, 'assets', 'geography', name)) !== text(path.join(assetsDir, name))) {
        fail(`assets/geography/${name} differs from what the sources build: run npm run build`);
      }
    }
    if (text(path.join(out, 'tool', 'geography', 'report.md')) !== text(path.join(toolDir, 'report.md'))) {
      fail('tool/geography/report.md differs from the build\'s: run npm run build');
    }
    notes.push('rebuilt from the cached sources: identical');
  } finally {
    fs.rmSync(out, { recursive: true, force: true });
  }
} else if (!cached) {
  notes.push('sources not cached, so not rebuilt (npm run fetch caches them)');
}

if (problems.length > 0) {
  for (const problem of problems) console.error(`geography: ${problem}`);
  process.exit(1);
}
console.log(
  `Map layers match their manifest: ${layers.length} layers, ` +
    `${(total / 1024).toFixed(1)} KB of ${budgets.totalBytes / 1024 / 1024} MB; ${notes.join('; ')}.`,
);
