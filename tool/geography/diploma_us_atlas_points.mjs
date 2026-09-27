// Explicit New York atlas authoring; ordinary builds consume the pinned snapshot.
// Run from the repository root. --author writes only the owned curriculum file.
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';

const retrieved = '2026-09-26';
const commit = '7af5b29d45aee5e6c6ce3889e9b1de19085d7107';
const aggregateSha = 'c90068f7154764519f0a7c6fb2788e597b7c56bf7581e8c0faa979554d984926';
const aggregatePath = '.dart_tool/new_world_ava_aggregate.geojson';
const ttbPath = '.dart_tool/new_world_ttb.html';
const wikiPath = '.dart_tool/diploma_us_new_york_q1384.json';
const output = 'tool/geography/diploma_us_atlas_points.geojson';
const curriculumPath = 'assets/curriculum/areas/diploma_us_atlas.yaml';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const rawUrl = `https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas_aggregated_files/avas.geojson`;
const registerUrl = 'https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/established-avas';
const specs = [
  ['cayuga_lake', 'finger_lakes'],
  ['champlain_valley_of_new_york', 'new_york'],
  ['finger_lakes', 'new_york'],
  ['hudson_river_region', 'new_york'],
  ['long_island', 'new_york'],
  ['niagara_escarpment', 'new_york'],
  ['north_fork_of_long_island', 'long_island'],
  ['seneca_lake', 'finger_lakes'],
  ['the_hamptons_long_island', 'long_island'],
  ['upper_hudson', 'new_york'],
  ['lake_erie', 'united_states'],
].map(([id, parent]) => ({id, parent, type: 'appellation'}));

function pointInRing([x, y], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function pointInGeometry(point, geometry) {
  const polygons = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates;
  return polygons.some(p => pointInRing(point, p[0]) && !p.slice(1).some(r => pointInRing(point, r)));
}
// Same source-interior scanline procedure as new_world_atlas_completion.mjs.
function interior(geometry) {
  const polygons = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates;
  let best = null;
  for (const polygon of polygons) {
    const ys = polygon[0].map(p => p[1]), min = Math.min(...ys), max = Math.max(...ys);
    for (let i = 1; i < 64; i++) {
      const y = min + (max - min) * i / 64, xs = [];
      for (const ring of polygon) for (let j = 0; j < ring.length - 1; j++) {
        const a = ring[j], b = ring[j + 1];
        if ((a[1] > y) !== (b[1] > y)) xs.push(a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]));
      }
      xs.sort((a, b) => a - b);
      for (let j = 0; j < xs.length - 1; j++) {
        const point = [(xs[j] + xs[j + 1]) / 2, y], width = xs[j + 1] - xs[j];
        if ((!best || width > best.width) && pointInGeometry(point, geometry)) best = {point, width};
      }
    }
  }
  if (!best || !pointInGeometry(best.point, geometry)) throw Error('No verified polygon interior marker');
  return best.point;
}
function plain(html) {
  return html.replace(/<\/(?:li|p)>/g, '; ').replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&(?:ndash|mdash);/g, '-').replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ').trim();
}
const avaBytes = fs.readFileSync(aggregatePath);
if (sha(avaBytes) !== aggregateSha) throw Error('Pinned AVA aggregate hash changed');
const avas = JSON.parse(avaBytes).features;
const ttbHtml = fs.readFileSync(ttbPath, 'utf8');
if (!ttbHtml.includes('August 18, 2026')) throw Error('Unexpected TTB register edition');
const ttbRows = [...ttbHtml.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)]
  .map(r => [...r[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(c => plain(c[1])))
  .filter(c => c.length >= 5);
const nySources = avas.filter(f => !f.properties.removed && f.properties.state?.split('|').includes('NY'));
if (nySources.length !== 11 || nySources.some(f => !specs.some(s => s.id === f.properties.ava_id))) {
  throw Error('The complete NY-associated source feature set changed');
}
if (!fs.existsSync(wikiPath)) {
  const url = new URL('https://www.wikidata.org/w/api.php');
  for (const [key, value] of Object.entries({action: 'wbgetentities', ids: 'Q1384', props: 'labels|descriptions|claims', languages: 'en', format: 'json'})) url.searchParams.set(key, value);
  const response = await fetch(url, {headers: {'User-Agent': 'SommelierStudyCompanion geography research'}});
  if (!response.ok) throw Error(`Wikidata ${response.status}`);
  const entity = (await response.json()).entities?.Q1384;
  if (!entity) throw Error('Missing New York entity');
  fs.writeFileSync(wikiPath, JSON.stringify(entity, null, 2) + '\n');
}
const entity = JSON.parse(fs.readFileSync(wikiPath, 'utf8'));
const claim = entity.claims?.P625?.find(c => c.rank !== 'deprecated' && c.mainsnak.datavalue?.value.globe === 'http://www.wikidata.org/entity/Q2');
if (!claim || entity.id !== 'Q1384') throw Error('Missing sourced Earth-coordinate statement for New York');
const coordinate = claim.mainsnak.datavalue.value;
const newYork = {id: 'new_york', parent: 'united_states', type: 'region', name: 'New York', source: 'src_dus_ny_state'};
const features = [{
  type: 'Feature',
  properties: {
    node: 'n_geo_new_york', node_id: 'n_geo_new_york', name: 'New York',
    parent_node_id: 'n_geo_united_states', country_node_id: 'n_geo_united_states',
    point_role: 'gazetteer_state_reference_point', point_place_name: 'New York',
    point_description: entity.descriptions?.en?.value ?? '', wikidata_id: entity.id,
    wikidata_coordinate_claim: claim.id, coordinate_precision: coordinate.precision,
    source_url: 'https://www.wikidata.org/wiki/Q1384',
    source_coordinate_url: 'https://www.wikidata.org/wiki/Special:EntityData/Q1384.json',
    retrieved_on: retrieved, license: 'CC0-1.0',
    label_note: 'Exact gazetteer reference for New York state; not a state boundary or an official vineyard centroid.',
  },
  geometry: {type: 'Point', coordinates: [coordinate.longitude, coordinate.latitude]},
}];
for (const spec of specs) {
  const feature = nySources.find(f => f.properties.ava_id === spec.id);
  spec.name = feature.properties.name.trim();
  spec.cfr = feature.properties.cfr_index;
  spec.source = `src_dus_us_${spec.id}`;
  // Match the actual name: TTB's Long Island link incorrectly repeats 9.101.
  const row = ttbRows.find(r => r[0] === spec.name);
  if (!row) throw Error(`No exact TTB register name for ${spec.name}`);
  const tableCfr = row[4].match(/9\.\d+/)?.[0];
  if (tableCfr !== spec.cfr && !(spec.id === 'long_island' && tableCfr === '9.101' && spec.cfr === '9.170')) {
    throw Error(`Unexpected CFR mismatch for ${spec.name}: ${tableCfr}/${spec.cfr}`);
  }
  if (spec.id === 'lake_erie') {
    if (feature.properties.state !== 'NY|OH|PA' || !row[1].includes('New York') || !row[1].includes('Ohio') || !row[1].includes('Pennsylvania')) throw Error('Lake Erie multistate geography changed');
  } else if (feature.properties.state !== 'NY') throw Error(`${spec.name} is not wholly New York`);
  if (!['new_york', 'united_states'].includes(spec.parent)) {
    const parentName = nySources.find(f => f.properties.ava_id === spec.parent)?.properties.name.trim();
    const legalParent = row[2].split(';').map(x => x.trim()).find(x => x.replace(/[◊*]/g, '').trim() === parentName);
    if (!legalParent || legalParent.includes('*')) throw Error(`No full legal containment: ${spec.name} -> ${parentName}`);
  }
  features.push({
    type: 'Feature',
    properties: {
      node: `n_geo_${spec.id}`, node_id: `n_geo_${spec.id}`, name: spec.name,
      parent_node_id: `n_geo_${spec.parent}`, country_node_id: 'n_geo_united_states',
      point_role: 'source_polygon_interior_reference_point', point_place_name: spec.name,
      source_url: `https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas/${spec.id}.geojson`,
      source_coordinate_url: rawUrl, source_commit: commit, source_file_sha256: aggregateSha,
      source_feature_id: spec.id, source_cfr_index: spec.cfr,
      derivation: 'widest verified interior horizontal scanline interval midpoint; 63 evenly spaced scanlines per polygon',
      retrieved_on: retrieved, license: 'CC0-1.0',
      attribution: 'UC Davis Library and DataLab American Viticultural Areas Project, with UCSB Library and Virginia Tech contributors',
      label_note: 'Reference marker derived from the community digitized AVA polygon. It is not a legal boundary or an official centroid.',
    },
    geometry: {type: 'Point', coordinates: interior(feature.geometry)},
  });
}
const all = [newYork, ...specs];
const oldFiles = fs.readdirSync('assets/curriculum/areas').filter(f => f.endsWith('.yaml') && f !== 'diploma_us_atlas.yaml');
const oldData = oldFiles.map(f => YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`, 'utf8')));
const existingNodes = oldData.flatMap(d => d.knowledge_nodes ?? []);
const existingSources = oldData.flatMap(d => d.source_citations ?? []);
const names = new Map([...existingNodes, ...all.map(s => ({id: `n_geo_${s.id}`, name: s.name}))].map(n => [n.id, n.name]));
for (const spec of all) {
  if (existingNodes.some(n => n.id === `n_geo_${spec.id}`)) throw Error(`Duplicate existing node ${spec.id}`);
  if (!names.has(`n_geo_${spec.parent}`)) throw Error(`Missing parent ${spec.parent}`);
}
const registerCitation = existingSources.find(s => s.url === registerUrl)?.id;
const sources = [
  {id: 'src_dus_ny_state', kind: 'government_publication', title: 'ANSI codes for states: New York, FIPS 36, USPS NY', publisher: 'United States Census Bureau', jurisdiction: 'US', url: 'https://www.census.gov/library/reference/code-lists/ansi/ansi-codes-for-states.html', accessed_on: retrieved, document_identifier: 'New York state: 36 / NY'},
  ...specs.map(s => ({id: s.source, kind: 'legislation', title: `27 CFR § ${s.cfr}: ${s.name} American viticultural area`, publisher: 'Alcohol and Tobacco Tax and Trade Bureau / eCFR', jurisdiction: 'US', url: `https://www.ecfr.gov/current/title-27/section-${s.cfr}`, accessed_on: retrieved, document_identifier: `27 CFR § ${s.cfr}`})),
];
if (!registerCitation) throw Error('Existing official TTB register citation required');
const item = spec => `ki_dus_${spec.id}_location`;
if (process.argv.includes('--author')) {
  const dataset = {
    knowledge_nodes: all.map(s => ({id: `n_geo_${s.id}`, node_type: s.type, name: s.name})),
    node_alternative_names: [{knowledge_node_id: 'n_geo_the_hamptons_long_island', name: 'The Hamptons', kind: 'synonym'}],
    knowledge_relations: all.map(s => ({subject_id: `n_geo_${s.id}`, relation_type: 'LOCATED_IN', object_id: `n_geo_${s.parent}`, valid_from: '1900-01-01'})),
    knowledge_items: all.map(s => ({
      id: item(s), subject_id: `n_geo_${s.id}`, relation_type: 'LOCATED_IN', object_id: `n_geo_${s.parent}`, domain_id: 'geography',
      assertion_text: s.id === 'new_york' ? 'New York is a state of the United States.' : s.id === 'lake_erie' ? 'Lake Erie is a multistate American viticultural area in the United States, spanning New York, Ohio and Pennsylvania; it is not wholly within New York.' : `${s.name} is an American viticultural area wholly within ${names.get(`n_geo_${s.parent}`)}.`,
      verification_status: 'unverified', last_verified_at: '2026-09-26T20:00:00.000Z',
    })),
    certification_knowledge_mappings: all.flatMap(s => ['WSET_L3', 'CMS_CERTIFIED'].map(cert => ({certification_id: cert, knowledge_item_id: item(s), minimum_depth: 2, importance: 'secondary'}))),
    source_citations: sources,
    knowledge_item_citations: all.flatMap(s => [
      {knowledge_item_id: item(s), source_citation_id: s.source, locator: s.cfr ? `27 CFR § ${s.cfr}(c): defined geographical area and state/containing AVA` : 'FIPS codes for the states and District of Columbia: New York, 36, NY'},
      ...(s.cfr ? [{knowledge_item_id: item(s), source_citation_id: registerCitation, locator: `${s.name}: ${s.id === 'lake_erie' ? 'multi-state NY/OH/PA register' : 'New York single-state register'}; current August 18, 2026 edition${s.id === 'long_island' ? '; CFR link typo corrected against current eCFR §9.170' : ''}`}]: []),
    ]),
  };
  if (fs.existsSync(curriculumPath)) {
    const previous = YAML.parse(fs.readFileSync(curriculumPath, 'utf8'));
    for (const key of ['knowledge_nodes', 'knowledge_items', 'source_citations']) for (const row of previous[key] ?? []) {
      if (!dataset[key].some(candidate => candidate.id === row.id)) throw Error(`Would remove authored ${row.id}`);
    }
  }
  fs.writeFileSync(curriculumPath, '# Diploma New York geography support. Facts are primary-cited and await expert review.\n# Map points identify source-derived locations, not legal boundary shapes.\n' + YAML.stringify(dataset));
}
const collisions = new Set();
for (const feature of features) {
  const key = JSON.stringify(feature.geometry.coordinates);
  if (collisions.has(key)) throw Error('Duplicate new marker coordinates');
  collisions.add(key);
}
fs.writeFileSync(output, JSON.stringify({type: 'FeatureCollection', features}, null, 2) + '\n');
console.log(JSON.stringify({places: all.length,avas: specs.length,source_citations: sources.length,mappings: all.length * 2,snapshot_sha256: sha(fs.readFileSync(output)),aggregate_sha256: aggregateSha}, null, 2));
