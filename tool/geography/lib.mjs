// Shared by fetch.mjs, build.mjs and check.mjs (docs/design/geography.md §7).
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

export const toolDir = path.dirname(fileURLToPath(import.meta.url));
export const repoDir = path.resolve(toolDir, '..', '..');

/** Where downloads and their unpacked files live: outside the repository. */
export const cacheDir =
  process.env.SOMMELIER_GEO_CACHE ??
  path.join(os.homedir(), '.cache', 'sommelier-geography');

/** Layer assets, as the app bundles them (G2). */
export const assetsDir = path.join(repoDir, 'assets', 'geography');

/** GEO-11: at most 1.5 MB per layer and 8 MB in all. */
export const budgets = { layerBytes: 1.5 * 1024 * 1024, totalBytes: 8 * 1024 * 1024 };

/** mapshaper reads backslashes as escapes, so paths use forward slashes. */
export const forward = (file) => file.replaceAll('\\', '/');

export const sha256 = (data) =>
  crypto.createHash('sha256').update(data).digest('hex');

/** The SHA-256 of [file], read as a stream. */
export async function hashOf(file) {
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(file), hash);
  return hash.digest('hex');
}

export const readYaml = (file) => YAML.parse(fs.readFileSync(file, 'utf8'));

/** The cached download of [source]. */
export const downloadPath = (source) => path.join(cacheDir, source.file);

/** Where [source]'s archive is unpacked; the download itself otherwise. */
export const unpackedDir = (source) => path.join(cacheDir, source.id);

export const isArchive = (source) => /\.(zip|7z)$/.test(source.file);

/**
 * Whether [source]'s cached copy is the edition sources.yaml records:
 * `ok`, `missing` (not fetched, or an archive not unpacked yet) or `stale`
 * (another edition). The build reads an archive's unpacked files, so an
 * archive is judged by the SHA-256 they were unpacked from.
 */
export async function cacheState(source) {
  if (isArchive(source)) {
    const stamp = path.join(unpackedDir(source), '.sha256');
    if (!fs.existsSync(stamp)) return 'missing';
    return fs.readFileSync(stamp, 'utf8') === source.sha256 ? 'ok' : 'stale';
  }
  const file = downloadPath(source);
  if (!fs.existsSync(file)) return 'missing';
  return (await hashOf(file)) === source.sha256 ? 'ok' : 'stale';
}

/**
 * The licences GEO-5 allows, each spelled out: a pattern like `^CC BY`
 * would also admit CC BY-NC, and dl-de has a non-commercial variant too.
 */
const licences = [
  /^Public domain$/,
  /^CC0 1\.0( Universal)?$/,
  /^CC BY [1-4]\.0( International)?$/,
  /^Licence Ouverte( \/ Open Licence)? [12]\.0( \(Etalab\))?$/,
  /^Datenlizenz Deutschland – (Namensnennung|Zero) – Version 2\.0$/,
];

/** Whether [licence] allows bundling derived data in a proprietary app. */
export const isOpenLicence = (licence) => licences.some((l) => l.test(licence));

/** The attribution a layer shows: its sources' texts, each once, in order. */
export const layerAttribution = (config, layer) =>
  [...new Set(layer.sources.map((id) => config.sources.get(id).attribution))].join(' ');

/**
 * sources.yaml and layers.yaml, checked. Throws an Error listing every
 * problem.
 */
export function loadConfig() {
  const problems = [];
  const sourcesFile = readYaml(path.join(toolDir, 'sources.yaml'));
  const layersFile = readYaml(path.join(toolDir, 'layers.yaml'));
  const sources = sourcesFile?.sources ?? [];
  const excluded = sourcesFile?.excluded ?? [];
  const layers = layersFile?.layers ?? [];

  const sourceIds = new Set();
  for (const [i, s] of sources.entries()) {
    const where = `sources.yaml: source ${s?.id ?? i}`;
    for (const key of ['id', 'title', 'publisher', 'url', 'file', 'version', 'retrieved', 'sha256', 'license', 'attribution']) {
      if (typeof s?.[key] !== 'string' || s[key].trim() === '') problems.push(`${where} needs ${key}`);
    }
    if (typeof s?.id === 'string') {
      if (!/^src_[a-z0-9_]+$/.test(s.id)) problems.push(`${where}: an ID is src_ and lowercase words`);
      if (sourceIds.has(s.id)) problems.push(`${where} is listed twice`);
      sourceIds.add(s.id);
    }
    if (typeof s?.url === 'string' && !s.url.startsWith('https://')) problems.push(`${where}: its url is not https`);
    if (typeof s?.retrieved === 'string' && !/^\d{4}-\d{2}-\d{2}$/.test(s.retrieved)) problems.push(`${where}: retrieved is not YYYY-MM-DD`);
    if (typeof s?.sha256 === 'string' && !/^([0-9a-f]{64}|PENDING)$/.test(s.sha256)) {
      problems.push(`${where}: sha256 is neither a SHA-256 nor PENDING`);
    }
    if (typeof s?.license === 'string' && !isOpenLicence(s.license)) {
      problems.push(`${where}: "${s.license}" is not an open licence GEO-5 allows`);
    }
  }
  for (const [i, e] of excluded.entries()) {
    if (typeof e?.name !== 'string' || typeof e?.reason !== 'string') problems.push(`sources.yaml: excluded ${i} needs a name and a reason`);
  }

  const layerIds = new Set();
  const assets = new Set();
  for (const [i, l] of layers.entries()) {
    const where = `layers.yaml: layer ${l?.id ?? i}`;
    for (const key of ['id', 'asset', 'display_name', 'geometry']) {
      if (typeof l?.[key] !== 'string') problems.push(`${where} needs ${key}`);
    }
    if (typeof l?.id === 'string') {
      if (!/^ml_[a-z0-9_]+$/.test(l.id)) problems.push(`${where}: an ID is ml_ and lowercase words`);
      if (layerIds.has(l.id)) problems.push(`${where} is listed twice`);
      layerIds.add(l.id);
    }
    if (typeof l?.asset === 'string') {
      if (!/^[a-z0-9_]+\.topo\.json$/.test(l.asset)) problems.push(`${where}: asset must be <name>.topo.json`);
      if (assets.has(l.asset)) problems.push(`${where}: asset ${l.asset} is used twice`);
      assets.add(l.asset);
    }
    if (!['area', 'line', 'point'].includes(l?.geometry)) problems.push(`${where}: geometry must be area, line or point`);
    const zoom = l?.zoom;
    if (!Array.isArray(zoom) || zoom.length !== 2 || !zoom.every(Number.isFinite) || zoom[0] >= zoom[1] || zoom[0] < 0 || zoom[1] > 22) {
      problems.push(`${where}: zoom must be [min, max) within 0 to 22`);
    }
    if (!Array.isArray(l?.sources) || l.sources.length === 0) {
      problems.push(`${where} needs sources`);
    } else {
      for (const id of l.sources) if (!sourceIds.has(id)) problems.push(`${where}: unknown source ${id}`);
    }
    if (l?.parent !== undefined && !layers.some((other) => other?.id === l.parent)) problems.push(`${where}: unknown parent ${l.parent}`);
    if (!/^\d+(\.\d+)?%$/.test(String(l?.simplify))) problems.push(`${where}: simplify must be a share of vertices, e.g. 40%`);
    if (!Number.isInteger(l?.quantization) || l.quantization < 1000) problems.push(`${where}: quantization must be an integer of at least 1000`);
    const recipes = ['natural_earth', 'appellation_areas'].filter((key) => l?.[key] !== undefined);
    if (recipes.length !== 1) problems.push(`${where} needs exactly one of natural_earth and appellation_areas`);
    if (l?.appellation_areas !== undefined) {
      for (const [node, area] of Object.entries(l.appellation_areas ?? {})) {
        if (!Array.isArray(area?.aoc) || area.aoc.length === 0 || !area.aoc.every(Number.isInteger)) {
          problems.push(`${where}: ${node} needs aoc, a list of INAO appellation IDs`);
        }
        if (area?.departments !== undefined && (!Array.isArray(area.departments) || !area.departments.every((d) => typeof d === 'string'))) {
          problems.push(`${where}: ${node}: departments must be a list of department codes as text`);
        }
      }
    }
    if (l?.natural_earth !== undefined && typeof l.natural_earth?.input !== 'string') problems.push(`${where}: natural_earth needs input`);
  }
  const successors = layersFile?.commune_successors ?? {};
  for (const [from, to] of Object.entries(successors)) {
    if (!/^\d[\dAB]\d{3}$/.test(from) || typeof to !== 'string' || !/^\d[\dAB]\d{3}$/.test(to)) {
      problems.push(`layers.yaml: commune_successors ${from}: ${to} is not a pair of INSEE codes`);
    }
  }
  if (problems.length > 0) throw new Error(problems.join('\n'));
  return {
    sources: new Map(sources.map((s) => [s.id, s])),
    excluded,
    layers,
    successors: new Map(Object.entries(successors)),
  };
}

/**
 * The curriculum's nodes and their `LOCATED_IN` parents, read from the
 * dataset's manifest and its includes (docs/domain-model.md §7).
 */
export function readCurriculum() {
  const manifest = path.join(repoDir, 'assets', 'curriculum', 'curriculum.yaml');
  const files = [manifest, ...(readYaml(manifest).includes ?? []).map((f) => path.join(path.dirname(manifest), f))];
  const nodes = new Map();
  const parents = new Map();
  for (const file of files) {
    const data = readYaml(file) ?? {};
    for (const node of data.knowledge_nodes ?? []) nodes.set(node.id, node);
    for (const r of data.knowledge_relations ?? []) {
      if (r.relation_type !== 'LOCATED_IN' || (r.valid_until != null)) continue;
      if (!parents.has(r.subject_id)) parents.set(r.subject_id, []);
      parents.get(r.subject_id).push(r.object_id);
    }
  }
  return { nodes, parents };
}

/** [value] rounded to [digits] decimals, as a number. */
export const round = (value, digits = 6) => Number(value.toFixed(digits));
