// Attach authored INAO commune-union recipes; fine sites use sourced markers.
// Traditional regions show the union of their named AOC areas, not a new legal boundary.
import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';

const file = 'tool/geography/layers.yaml';
const doc = YAML.parseDocument(fs.readFileSync(file, 'utf8'));
const recipes = YAML.parse(fs.readFileSync('tool/geography/france_atlas_areas.yaml', 'utf8'));
const manifestFile = 'assets/curriculum/curriculum.yaml';
const manifest = YAML.parse(fs.readFileSync(manifestFile, 'utf8'));
const authored = manifest.includes.map((include) =>
  YAML.parse(fs.readFileSync(path.join(path.dirname(manifestFile), include), 'utf8')),
);
const nodes = new Map(authored.flatMap((part) =>
  (part.knowledge_nodes ?? []).map((node) => [node.id, node]),
));
const children = new Map();
for (const part of authored) {
  for (const relation of part.knowledge_relations ?? []) {
    if (relation.relation_type !== 'LOCATED_IN') continue;
    if (!children.has(relation.object_id)) children.set(relation.object_id, new Set());
    children.get(relation.object_id).add(relation.subject_id);
  }
}

const points = new Set();
for (const filename of [
  'france_atlas_points.geojson',
  'france_chablis_cadastre_points.geojson',
  'france_champagne_points.geojson',
]) {
  const pointFile = path.join('tool/geography', filename);
  if (!fs.existsSync(pointFile)) continue;
  for (const feature of JSON.parse(fs.readFileSync(pointFile, 'utf8')).features) {
    if (feature.geometry?.type !== 'Point') {
      throw new Error(`${filename}: ${feature.properties.node} has no sourced point`);
    }
    points.add(feature.properties.node);
  }
}

const layerForType = new Map([
  ['region', 'ml_fr_regions'],
  ['subregion', 'ml_fr_subregions'],
  ['informal_area', 'ml_fr_subregions'],
  ['appellation', 'ml_fr_appellations'],
  ['site', 'ml_fr_appellations'],
]);
const layers = new Map(doc.get('layers').items
  .filter((layer) => [...layerForType.values()].includes(layer.get('id')))
  .map((layer) => [layer.get('id'), layer]));
const allRecipes = new Map();
for (const layer of layers.values()) {
  for (const [node, recipe] of Object.entries(layer.get('appellation_areas').toJSON())) {
    allRecipes.set(node, recipe);
  }
}

// Bucket names are hints from authoring. Actual node types select the layer,
// including ordinary appellations accidentally grouped with fine-site recipes.
for (const bucket of Object.values(recipes)) {
  if (Array.isArray(bucket)) continue;
  for (const [node, recipe] of Object.entries(bucket ?? {})) {
    if (!Array.isArray(recipe.aoc)) throw new Error(`${node}: missing INAO area identifiers`);
    const target = layerForType.get(nodes.get(node)?.node_type);
    if (!target) throw new Error(`${node}: unsupported or missing geographical node type`);
    allRecipes.set(node, recipe);
    for (const layer of layers.values()) {
      if (points.has(node) || layer.get('id') !== target) {
        layer.get('appellation_areas').delete(node);
      }
    }
    if (!points.has(node)) layers.get(target).get('appellation_areas').set(node, recipe);
  }
}
// Also remove any old commune recipe for a node now represented by a precise marker.
for (const layer of layers.values()) {
  for (const node of points) layer.get('appellation_areas').delete(node);
}

function descendantAocIds(node, visiting = new Set()) {
  if (visiting.has(node)) throw new Error(`Location cycle through ${node}`);
  const next = new Set(visiting).add(node);
  const ids = new Set();
  for (const child of children.get(node) ?? []) {
    if (nodes.get(child)?.node_type === 'appellation') {
      for (const ida of allRecipes.get(child)?.aoc ?? []) ids.add(ida);
    }
    for (const ida of descendantAocIds(child, next)) ids.add(ida);
  }
  return ids;
}

// Only broader study groupings gain the sourced areas of their descendants.
// A statutory appellation's own recipe is never expanded by this operation.
const expanded = [];
for (const layer of layers.values()) {
  const areas = layer.get('appellation_areas');
  for (const [node, original] of Object.entries(areas.toJSON())) {
    if (!['region', 'subregion', 'informal_area'].includes(nodes.get(node)?.node_type)) continue;
    const descendants = descendantAocIds(node);
    const aoc = [...new Set([...original.aoc, ...descendants])].sort((a, b) => a - b);
    if (aoc.length === original.aoc.length) continue;
    areas.set(node, {
      ...original,
      aoc,
      note: `${original.note ? original.note + ' ' : ''}` +
        'Study-area footprint: union of the named descendant appellation production communes; ' +
        'this grouping has no independent legal appellation boundary.',
    });
    expanded.push(node);
  }
}

fs.writeFileSync(file, String(doc));
console.log(JSON.stringify({
  preciseMarkers: points.size,
  integratedAreas: [...layers.values()].reduce((total, layer) =>
    total + layer.get('appellation_areas').items.length, 0),
  expandedStudyAreas: expanded,
}, null, 2));
