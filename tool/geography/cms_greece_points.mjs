// Rebuild the pinned CMS Greece orientation markers from the GeoNames GR dump.
// Usage: node tool/geography/cms_greece_points.mjs path/to/GR.txt
// GR.txt is extracted from https://download.geonames.org/export/dump/GR.zip.
// A source change needs fresh factual review and an updated hash below.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const input = process.argv[2];
if (!input) throw new Error('Pass the pinned GeoNames GR.txt path.');
const source = fs.readFileSync(input);
const sourceSha256 = createHash('sha256').update(source).digest('hex');
const expectedSha256 = 'd0ac77295171579078dd70a323b35741f6c17ccc89bec63fd48b83218fd421be';
if (sourceSha256 !== expectedSha256) {
  throw new Error(`GeoNames GR.txt changed: ${sourceSha256}; review before refreshing.`);
}

const specs = [
  {
    node: 'n_geo_halkidiki', name: 'Halkidiki', parent: 'n_geo_macedonia',
    id: '735804', featureClass: 'A', featureCode: 'ADM2',
    role: 'qualified administrative orientation reference',
    note: 'The Halkidiki regional-unit reference locates the parent area; it is not a wine-region boundary.',
  },
  {
    node: 'n_geo_sithonia', name: 'Sithonia', parent: 'n_geo_halkidiki',
    id: '734264', featureClass: 'T', featureCode: 'PEN',
    role: 'qualified peninsula orientation reference',
    note: 'The Sithonia peninsula reference locates the landform; it is not a vineyard or PDO boundary.',
  },
  {
    node: 'n_geo_slopes_of_meliton', name: 'Slopes of Meliton', parent: 'n_geo_sithonia',
    id: '735219', featureClass: 'T', featureCode: 'PK',
    role: 'qualified named-peak orientation reference',
    note: 'Mount Meliton is a named terrain reference near the PDO vineyards, not their legal centroid or boundary.',
  },
  {
    node: 'n_geo_achaea', name: 'Achaea', parent: 'n_geo_peloponnese',
    id: '265712', featureClass: 'L', featureCode: 'RGN',
    role: 'qualified regional orientation reference',
    note: 'The Achaea named-region reference locates the parent area; it is not a wine-region boundary.',
  },
  {
    node: 'n_geo_patra', name: 'Patra', parent: 'n_geo_achaea',
    id: '255683', featureClass: 'P', featureCode: 'PPLA',
    role: 'qualified named-city orientation reference',
    note: 'The city of Patra is a named reference for the wider PDO, not its legal centroid or boundary.',
  },
];

const wanted = new Set(specs.map(spec => spec.id));
const records = new Map();
for (const line of source.toString('utf8').split(/\r?\n/)) {
  const columns = line.split('\t');
  if (wanted.has(columns[0])) records.set(columns[0], columns);
}
const features = specs.map(spec => {
  const columns = records.get(spec.id);
  if (!columns || columns[6] !== spec.featureClass || columns[7] !== spec.featureCode || columns[8] !== 'GR') {
    throw new Error(`Missing or changed Greek GeoNames record ${spec.id}.`);
  }
  const latitude = Number(columns[4]);
  const longitude = Number(columns[5]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error(`Invalid coordinates for Greek GeoNames record ${spec.id}.`);
  }
  return {
    type: 'Feature',
    properties: {
      node: spec.node,
      node_id: spec.node,
      name: spec.name,
      parent_node_id: spec.parent,
      country_node_id: 'n_geo_greece',
      point_role: spec.role,
      point_place_name: columns[1],
      source_url: `https://www.geonames.org/${spec.id}/`,
      source_coordinate_url: 'https://download.geonames.org/export/dump/GR.zip',
      source_file_sha256: 'e71b24a515472009a99156fc059b1fa9df1e20048e3231698dea64516bafee1c',
      geonames_id: spec.id,
      geonames_feature_class: columns[6],
      geonames_feature_code: columns[7],
      geonames_admin1_code: columns[10],
      geonames_modified_on: columns[18],
      retrieved_on: '2026-09-28',
      license: 'CC-BY-4.0',
      attribution: 'Contains GeoNames GR data, licensed CC BY 4.0; selected WGS84 orientation references only.',
      label_note: spec.note,
    },
    geometry: { type: 'Point', coordinates: [longitude, latitude] },
  };
});

const output = path.resolve('tool/geography/cms_greece_points.geojson');
fs.writeFileSync(output, `${JSON.stringify({ type: 'FeatureCollection', features }, null, 2)}\n`);
console.log(`${output}: ${features.length} pinned Greek reference points`);
