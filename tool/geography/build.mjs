// Builds the map layers of layers.yaml from the cached sources
// (docs/design/geography.md §7). It writes each layer's TopoJSON asset,
// assets/geography/manifest.yaml and the build report, report.md. The same
// sources give byte-identical outputs.
//
//   npm run build               write into the repository
//   npm run build -- --out DIR  write into DIR instead (check uses this)
import fs from 'node:fs';
import path from 'node:path';
import mapshaper from 'mapshaper';
import YAML from 'yaml';
import {
  budgets,
  downloadPath,
  forward,
  isArchive,
  loadConfig,
  readCurriculum,
  repoDir,
  round,
  sha256,
  unpackedDir,
} from './lib.mjs';

/** Every file below [dir], recursively. */
function filesIn(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? filesIn(full) : [full];
  });
}

/** The unpacked file of [source] named [name], or with [extension]. */
function sourceFile(source, { name, extension }) {
  if (!isArchive(source)) return downloadPath(source);
  const dir = unpackedDir(source);
  if (!fs.existsSync(path.join(dir, '.sha256'))) {
    throw new Error(`${source.id} is not unpacked: run npm run fetch`);
  }
  const match = filesIn(dir).find((file) =>
    name ? path.basename(file) === name : file.endsWith(extension),
  );
  if (!match) throw new Error(`${source.id} has no ${name ?? `*${extension}`}`);
  return forward(match);
}

/** The first of [layer]'s sources that holds a shapefile named [input]. */
function shapefile(config, layer, input) {
  for (const id of layer.sources) {
    const source = config.sources.get(id);
    if (!isArchive(source)) continue;
    const dir = unpackedDir(source);
    if (fs.existsSync(dir) && filesIn(dir).some((f) => path.basename(f) === `${input}.shp`)) {
      return sourceFile(source, { name: `${input}.shp` });
    }
  }
  throw new Error(`${layer.id}: no source holds ${input}.shp (run npm run fetch)`);
}

/** A JavaScript string literal for a mapshaper expression. */
const literal = (value) => JSON.stringify(value).replaceAll('"', "'");

/**
 * Runs mapshaper [commands] on in-memory [inputs] and returns its outputs:
 * the TopoJSON (`layer.topo.json`) and the feature table (`table.json`).
 */
async function run(commands, inputs = {}) {
  const outputs = await mapshaper.applyCommands(commands, inputs);
  return {
    topology: JSON.parse(outputs['layer.topo.json'].toString()),
    table: JSON.parse(outputs['table.json'].toString()),
  };
}

/**
 * The commands every layer ends with: simplify, drop features left without
 * a shape, measure each feature (its bounds and a point inside it), then
 * write the feature table and the TopoJSON with only the node key and the
 * name.
 */
const finish = (layer) =>
  `-simplify ${layer.simplify} keep-shapes -filter remove-empty ` +
  `-each "min_lon = this.bounds[0], min_lat = this.bounds[1], ` +
  `max_lon = this.bounds[2], max_lat = this.bounds[3], ` +
  `label_lon = this.innerX === undefined ? null : this.innerX, ` +
  `label_lat = this.innerY === undefined ? null : this.innerY" ` +
  `-o table.json format=json ` +
  `-filter-fields node,name ` +
  `-o layer.topo.json format=topojson id-field=node quantization=${layer.quantization}`;

async function buildNaturalEarth(config, layer) {
  const recipe = layer.natural_earth;
  const nodes = recipe.nodes ?? {};
  const nodeOf = `(${literal(nodes)})[${recipe.key ? 'key' : 'null'}] || null`;
  const nameOf = (field) => (field ? `${field} || null` : 'null');
  const main = shapefile(config, layer, recipe.input);
  let commands;
  if (recipe.replace) {
    const other = shapefile(config, layer, recipe.replace.input);
    const [a, b] = [recipe.input, recipe.replace.input];
    commands =
      `-i "${main}" "${other}" combine-files ` +
      `-filter "!(${recipe.replace.where})" target=${a} ` +
      `-each "key = ${recipe.key}, name = ${nameOf(recipe.name)}" target=${a} ` +
      `-filter "${recipe.replace.where}" target=${b} ` +
      `-each "key = ${recipe.replace.key}, name = ${nameOf(recipe.name)}" target=${b} ` +
      `-filter-fields key,name target=${a},${b} ` +
      `-merge-layers target=${a},${b} name=layer force ` +
      `-each "node = ${nodeOf}" `;
  } else {
    commands =
      `-i "${main}" name=layer ` +
      (recipe.where ? `-filter "${recipe.where}" ` : '') +
      `-each "key = ${recipe.key ?? 'null'}, name = ${nameOf(recipe.name)}" ` +
      `-each "node = ${nodeOf}" `;
  }
  const built = await run(commands + finish(layer));
  const missing = Object.entries(nodes).filter(
    ([, node]) => !built.table.some((row) => row.node === node),
  );
  if (missing.length > 0) {
    throw new Error(`${layer.id}: no feature for ${missing.map(([k, n]) => `${n} (${k})`).join(', ')}`);
  }
  return { ...built, communes: new Map() };
}

/** INAO's geographical areas: appellation ID to the INSEE codes of its communes. */
function readInaoAreas(config) {
  const source = config.sources.get('src_inao_areas');
  const text = new TextDecoder('latin1').decode(fs.readFileSync(downloadPath(source)));
  const areas = new Map();
  const lines = text.split(/\r?\n/).filter((line) => line.trim() !== '');
  const header = lines[0].split(';');
  const code = header.indexOf('CI');
  const id = header.indexOf('IDA');
  if (code < 0 || id < 0) throw new Error('src_inao_areas: no CI or IDA column');
  for (const line of lines.slice(1)) {
    const cells = line.split(';');
    const ida = Number(cells[id]);
    if (!areas.has(ida)) areas.set(ida, new Set());
    areas.get(ida).add(cells[code]);
  }
  return areas;
}

/**
 * A GeoPackage geometry blob as a GeoJSON geometry: its header, then
 * well-known binary. Polygons and multipolygons, with or without Z or M.
 */
function decodeGeometry(blob) {
  if (blob[0] !== 0x47 || blob[1] !== 0x50) throw new Error('not a GeoPackage geometry');
  const envelope = [0, 32, 48, 48, 64][(blob[3] >> 1) & 0x07];
  const view = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
  let offset = 8 + envelope;
  const read = () => {
    const little = view.getUint8(offset) === 1;
    const raw = view.getUint32(offset + 1, little);
    offset += 5;
    const type = (raw & 0xffff) % 1000;
    const iso = Math.floor((raw & 0xffff) / 1000);
    const dims = 2 + (raw & 0x80000000 || iso === 1 || iso === 3 ? 1 : 0) +
      (raw & 0x40000000 || iso === 2 || iso === 3 ? 1 : 0);
    const count = () => {
      const n = view.getUint32(offset, little);
      offset += 4;
      return n;
    };
    const point = () => {
      const p = [view.getFloat64(offset, little), view.getFloat64(offset + 8, little)];
      offset += 8 * dims;
      return p;
    };
    const ring = () => Array.from({ length: count() }, point);
    const polygon = () => Array.from({ length: count() }, ring);
    if (type === 3) return { type: 'Polygon', coordinates: polygon() };
    if (type === 6) {
      return {
        type: 'MultiPolygon',
        coordinates: Array.from({ length: count() }, () => read().coordinates),
      };
    }
    throw new Error(`unsupported geometry type ${raw}`);
  };
  return read();
}

/**
 * The communes with INSEE [codes], by code, as GeoJSON geometries in
 * Lambert-93 (EPSG:2154), read straight from ADMIN EXPRESS's GeoPackage.
 */
async function communes(config, codes) {
  const { DatabaseSync } = await import('node:sqlite');
  const gpkg = sourceFile(config.sources.get('src_ign_admin_express'), {
    extension: '.gpkg',
  });
  // IGN's archive nests the file deep enough to pass Windows's 260
  // character path limit, which the extended-length prefix lifts.
  const db = new DatabaseSync(
    process.platform === 'win32' ? `\\\\?\\${path.resolve(gpkg)}` : gpkg,
    { readOnly: true },
  );
  try {
    const shapes = new Map();
    // INAO still lists some communes merged into a commune nouvelle by
    // their old code: ADMIN EXPRESS keeps those as delegated communes.
    for (const table of ['commune', 'commune_associee_ou_deleguee']) {
      const list = [...codes].filter((code) => !shapes.has(code)).sort();
      if (list.length === 0) break;
      const rows = db
        .prepare(
          `SELECT code_insee, geometrie FROM ${table} WHERE code_insee IN ` +
            `(${list.map(() => '?').join(', ')}) ORDER BY code_insee`,
        )
        .all(...list);
      for (const row of rows) {
        if (!shapes.has(row.code_insee)) {
          shapes.set(row.code_insee, decodeGeometry(row.geometrie));
        }
      }
    }
    return shapes;
  } finally {
    db.close();
  }
}

/**
 * For each node of [layer], the INSEE codes of its communes, sorted: a
 * code INAO still uses for a merged commune stands for its successor. The
 * area must list the successor too, so that drawing it adds no territory.
 */
function communeCodes(layer, inao, successors) {
  const result = new Map();
  for (const [node, area] of Object.entries(layer.appellation_areas)) {
    const codes = new Set();
    for (const ida of area.aoc) {
      const members = inao.get(ida);
      if (!members) throw new Error(`${layer.id}: ${node}: no INAO area ${ida}`);
      for (const code of members) {
        if (!area.departments || area.departments.some((d) => code.startsWith(d))) {
          const successor = successors.get(code);
          if (successor && !members.has(successor)) {
            throw new Error(
              `${layer.id}: ${node}: INAO area ${ida} lists ${code}, merged into ` +
                `${successor}, but not ${successor}; drawing it would enlarge the area`,
            );
          }
          codes.add(successor ?? code);
        }
      }
    }
    result.set(node, [...codes].sort());
  }
  return result;
}

async function buildAppellationAreas(layer, curriculum, codesOf, geometries) {
  const features = [];
  const communesOf = new Map();
  for (const node of Object.keys(layer.appellation_areas)) {
    const sorted = codesOf.get(node);
    const unknown = sorted.filter((code) => !geometries.has(code));
    if (unknown.length > 0) {
      throw new Error(`${layer.id}: ${node}: communes not in ADMIN EXPRESS: ${unknown.join(', ')}`);
    }
    communesOf.set(node, new Set(sorted));
    const name = curriculum.nodes.get(node)?.name ?? null;
    for (const code of sorted) {
      features.push({
        type: 'Feature',
        properties: { node, name },
        geometry: geometries.get(code),
      });
    }
  }
  const input = JSON.stringify({ type: 'FeatureCollection', features });
  const built = await run(
    `-i communes.json name=layer -dissolve node copy-fields=name ` +
      `-proj wgs84 init=EPSG:2154 ` +
      finish(layer),
    { 'communes.json': input },
  );
  return { ...built, communes: communesOf };
}

/**
 * The asset's TopoJSON, its one object named [name]: the node key as `id`
 * only, and the name only when there is one; keys in a fixed order, so
 * equal inputs give equal bytes.
 */
function tidy(topology, name) {
  const [object] = Object.values(topology.objects);
  // Quantization can collapse a thin feature to nothing: a context feature
  // is then left out, but a node's feature must survive.
  object.geometries = object.geometries.filter((geometry) => {
    const empty = Array.isArray(geometry.arcs) && geometry.arcs.flat(2).length === 0;
    if (empty && geometry.id != null) {
      throw new Error(`${name}: ${geometry.id} collapses at this quantization`);
    }
    return !empty;
  });
  for (const geometry of object.geometries) {
    const { node, name } = geometry.properties ?? {};
    delete geometry.properties;
    if (node == null) delete geometry.id;
    if (name != null) geometry.properties = { name };
  }
  return JSON.stringify({
    type: topology.type,
    transform: topology.transform,
    objects: { [name]: object },
    arcs: topology.arcs,
  });
}

/** Pairs of node features of [topology] that share an arc. */
function sharedArcs(topology) {
  const [object] = Object.values(topology.objects);
  const users = new Map();
  const visit = (value, node) => {
    if (typeof value === 'number') {
      const arc = value < 0 ? ~value : value;
      if (!users.has(arc)) users.set(arc, new Set());
      users.get(arc).add(node);
    } else if (Array.isArray(value)) {
      for (const inner of value) visit(inner, node);
    }
  };
  for (const geometry of object.geometries) {
    if (geometry.id != null) visit(geometry.arcs ?? [], geometry.id);
  }
  const pairs = new Set();
  for (const nodes of users.values()) {
    const sorted = [...nodes].sort();
    for (let i = 0; i < sorted.length; i++) {
      for (let j = i + 1; j < sorted.length; j++) pairs.add(`${sorted[i]} ${sorted[j]}`);
    }
  }
  return [...pairs].sort();
}

const kb = (bytes) => `${(bytes / 1024).toFixed(1)} KB`;

export async function build(outDir) {
  const config = loadConfig();
  const curriculum = readCurriculum();
  for (const source of config.sources.values()) {
    if (source.sha256 === 'PENDING') throw new Error(`${source.id}: record its SHA-256 first`);
  }

  // The communes every French layer needs, read once.
  const french = config.layers.filter((layer) => layer.appellation_areas);
  const codes = new Map();
  let communeShapes = new Map();
  if (french.length > 0) {
    const inao = readInaoAreas(config);
    for (const layer of french) codes.set(layer.id, communeCodes(layer, inao, config.successors));
    const all = new Set([...codes.values()].flatMap((byNode) => [...byNode.values()].flat()));
    communeShapes = await communes(config, all);
  }

  const built = [];
  for (const layer of config.layers) {
    const result = layer.natural_earth
      ? await buildNaturalEarth(config, layer)
      : await buildAppellationAreas(layer, curriculum, codes.get(layer.id), communeShapes);
    for (const row of result.table) {
      if (row.node != null && !curriculum.nodes.has(row.node)) {
        throw new Error(`${layer.id}: ${row.node} is not a node of the curriculum`);
      }
    }
    const asset = tidy(result.topology, layer.asset.replace('.topo.json', ''));
    built.push({ layer, asset, ...result });
  }

  const assets = path.join(outDir, 'assets', 'geography');
  fs.mkdirSync(assets, { recursive: true });
  const layers = [];
  const geometries = [];
  for (const { layer, asset, table } of built) {
    fs.writeFileSync(path.join(assets, layer.asset), asset);
    const attribution = [
      ...new Set(layer.sources.map((id) => config.sources.get(id).attribution)),
    ].join(' ');
    layers.push({
      id: layer.id,
      display_name: layer.display_name,
      geometry_kind: layer.geometry,
      asset_path: `assets/geography/${layer.asset}`,
      asset_sha256: sha256(asset),
      asset_bytes: Buffer.byteLength(asset),
      min_zoom: layer.zoom[0],
      max_zoom: layer.zoom[1],
      parent_layer_id: layer.parent ?? null,
      source_citation_ids: layer.sources,
      attribution,
    });
    for (const row of table.filter((r) => r.node != null).sort((a, b) => a.node.localeCompare(b.node))) {
      geometries.push({
        knowledge_node_id: row.node,
        map_layer_id: layer.id,
        feature_key: row.node,
        min_lon: round(row.min_lon),
        min_lat: round(row.min_lat),
        max_lon: round(row.max_lon),
        max_lat: round(row.max_lat),
        label_lon: round(row.label_lon),
        label_lat: round(row.label_lat),
      });
    }
  }
  const manifest =
    '# Generated by tool/geography (npm run build) from sources.yaml and\n' +
    '# layers.yaml. Do not edit; npm run check compares it.\n' +
    YAML.stringify({ map_layers: layers, node_geometries: geometries }, {
      lineWidth: 0,
      flowCollectionPadding: false,
    });
  fs.writeFileSync(path.join(assets, 'manifest.yaml'), manifest);

  // The report: sizes, containment and proposed BORDERS pairs.
  const lines = [
    '# Geography build report',
    '',
    'Generated by `npm run build` (tool/geography). `npm run check` compares it.',
    '',
    '## Layers',
    '',
    '| Layer | Asset | Kind | Features | Node features | Size | Budget |',
    '|---|---|---|--:|--:|--:|---|',
  ];
  let total = 0;
  for (const { layer, asset, table } of built) {
    const bytes = Buffer.byteLength(asset);
    total += bytes;
    const [object] = Object.values(JSON.parse(asset).objects);
    lines.push(
      `| \`${layer.id}\` | ${layer.asset} | ${layer.geometry} | ${object.geometries.length} | ` +
        `${table.filter((r) => r.node != null).length} | ${kb(bytes)} | ` +
        `${bytes <= budgets.layerBytes ? 'ok' : '**over 1.5 MB**'} |`,
    );
  }
  lines.push(
    '',
    `Total: ${kb(total)} of ${kb(budgets.totalBytes)} ` +
      `(${total <= budgets.totalBytes ? 'ok' : '**over budget**'}).`,
    '',
    '## Containment',
    '',
    'Each French area is a union of communes, so a node lies inside its ' +
      '`LOCATED_IN` parent when every commune of the node is a commune of the ' +
      'parent. Countries have no parent geometry yet.',
    '',
  );
  const communesOf = new Map();
  for (const { communes } of built) for (const [node, set] of communes) communesOf.set(node, set);
  const failures = [];
  for (const [node, set] of [...communesOf].sort(([a], [b]) => a.localeCompare(b))) {
    for (const parent of curriculum.parents.get(node) ?? []) {
      const parentSet = communesOf.get(parent);
      if (!parentSet) {
        lines.push(`- \`${node}\` in \`${parent}\`: the parent is a country; checked by construction.`);
        continue;
      }
      const outside = [...set].filter((code) => !parentSet.has(code));
      if (outside.length === 0) {
        lines.push(`- \`${node}\` in \`${parent}\`: ${set.size === 1 ? 'its commune' : `all ${set.size} communes`}.`);
      } else {
        failures.push(`${node} in ${parent}`);
        lines.push(`- \`${node}\` in \`${parent}\`: **${outside.length} communes outside**: ${outside.join(', ')}.`);
      }
    }
  }
  lines.push('', failures.length === 0 ? 'No containment failures.' : `**Failures: ${failures.join('; ')}.**`);
  lines.push(
    '',
    '## Proposed `BORDERS` pairs',
    '',
    'Node features of one layer whose outlines touch and that share no ' +
      'commune. They are proposals for the content tasks, never inserted ' +
      '(geography §3).',
    '',
  );
  const proposals = [];
  const overlaps = [];
  for (const { layer, topology, communes } of built) {
    for (const pair of sharedArcs(topology)) {
      const [a, b] = pair.split(' ');
      const shared = communes.size > 0 && [...(communes.get(a) ?? [])].some((c) => communes.get(b)?.has(c));
      (shared ? overlaps : proposals).push(`\`${layer.id}\`: \`${a}\` – \`${b}\``);
    }
  }
  lines.push(...(proposals.length ? proposals.map((p) => `- ${p}`) : ['None.']));
  lines.push('', '## Overlapping node features', '', 'Node features of one layer that share communes.', '');
  lines.push(...(overlaps.length ? overlaps.map((p) => `- ${p}`) : ['None.']), '');
  fs.writeFileSync(path.join(outDir, 'tool', 'geography', 'report.md'), lines.join('\n'));
  return { total, failures, built };
}

if (process.argv[1]?.endsWith('build.mjs')) {
  const at = process.argv.indexOf('--out');
  const outDir = at >= 0 ? path.resolve(process.argv[at + 1]) : repoDir;
  fs.mkdirSync(path.join(outDir, 'tool', 'geography'), { recursive: true });
  try {
    const { total, failures } = await build(outDir);
    console.log(`Built ${forward(path.relative(repoDir, path.join(outDir, 'assets', 'geography')) || 'assets/geography')}: ${kb(total)}.`);
    if (failures.length > 0) {
      console.log(`Containment failures: ${failures.join('; ')}`);
      process.exit(1);
    }
  } catch (error) {
    console.error(`error: ${error.stack}`);
    process.exit(1);
  }
}
