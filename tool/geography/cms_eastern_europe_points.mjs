// Author the pinned Bulgaria/Romania orientation markers from GeoNames dumps.
// Usage: node tool/geography/cms_eastern_europe_points.mjs BG.txt RO.txt
// Both text files come from https://download.geonames.org/export/dump/.
// A changed dump requires renewed source and location review before refresh.
import fs from 'node:fs';
import { createHash } from 'node:crypto';

const inputs = {
  BG: { path: process.argv[2], sha256: 'd2b3a3bf359e3de6b9f2b193ed9a3f3c7111322296ff321737e8cce22fd52f99' },
  RO: { path: process.argv[3], sha256: '5331ad9cfc2fe3931a1ab82407b81660833356faf26975366666aca73796e18b' },
};
const specs = [
  { node: 'n_geo_danubian_plain_bg', name: 'Danubian Plain (Bulgaria)', country: 'BG', id: '728203', place: 'Pleven', code: 'PPLA', note: 'Pleven is a named town in the PGI locality list, not the PGI centroid or boundary.' },
  { node: 'n_geo_thracian_lowlands_bg', name: 'Thracian Lowlands', country: 'BG', id: '728193', place: 'Plovdiv', code: 'PPLA', note: 'Plovdiv is a southern Bulgarian city reference, not the PGI centroid or boundary.' },
  { node: 'n_geo_melnik_pdo', name: 'Melnik (Bulgaria)', country: 'BG', id: '727447', place: 'Sandanski', code: 'PPL', note: 'Sandanski appears in the Melnik PDO locality list; this town marker is not the PDO centroid or boundary.' },
  { node: 'n_geo_lyubimets_pdo', name: 'Lyubimets', country: 'BG', id: '729466', place: 'Lyubimets', code: 'PPL', note: 'Lyubimets is a named settlement reference, not the PDO centroid or boundary.' },
  { node: 'n_geo_tarnave', name: 'Târnave', country: 'RO', id: '673634', place: 'Mediaş', code: 'PPLA2', note: 'Mediaș is a Târnave subdesignation and reference town, not the DOC centroid or boundary.' },
  { node: 'n_geo_cotnari', name: 'Cotnari', country: 'RO', id: '680491', place: 'Cotnari', code: 'PPLA2', note: 'Cotnari is a settlement reference, not the DOC centroid or boundary.' },
  { node: 'n_geo_dealu_mare', name: 'Dealu Mare', country: 'RO', id: '664150', place: 'Urlaţi', code: 'PPLA2', note: 'Urlați is a Dealu Mare subdesignation and reference town, not the DOC centroid or boundary.' },
  { node: 'n_geo_murfatlar', name: 'Murfatlar', country: 'RO', id: '672620', place: 'Murfatlar', code: 'PPLA2', note: 'Murfatlar is a settlement reference, not the DOC centroid or boundary.' },
  { node: 'n_geo_recas', name: 'Recaș', country: 'RO', id: '669058', place: 'Recaş', code: 'PPLA2', note: 'Recaș is a settlement reference, not the DOC centroid or boundary.' },
];

const records = new Map();
for (const [country, source] of Object.entries(inputs)) {
  if (!source.path) throw new Error(`Pass the pinned GeoNames ${country}.txt path.`);
  const bytes = fs.readFileSync(source.path);
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (hash !== source.sha256) throw new Error(`${country}.txt changed: ${hash}; review before refreshing.`);
  const wanted = new Set(specs.filter((spec) => spec.country === country).map((spec) => spec.id));
  for (const row of bytes.toString('utf8').split(/\r?\n/)) {
    const fields = row.split('\t');
    if (wanted.has(fields[0])) records.set(fields[0], fields);
  }
}
const features = specs.map((spec) => {
  const row = records.get(spec.id);
  if (!row || row[1] !== spec.place || row[6] !== 'P' || row[7] !== spec.code || row[8] !== spec.country) {
    throw new Error(`Missing or changed GeoNames settlement record ${spec.id}.`);
  }
  const latitude = Number(row[4]);
  const longitude = Number(row[5]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) throw new Error(`Invalid point ${spec.id}.`);
  return {
    type: 'Feature',
    properties: {
      node: spec.node,
      name: spec.name,
      point_role: 'qualified named-settlement orientation reference; not a wine-area boundary',
      point_place_name: spec.place,
      point_note: spec.note,
      geonames_id: spec.id,
      source_url: `https://www.geonames.org/${spec.id}`,
      source_country_dump: `${spec.country}.zip`,
      retrieved_on: '2026-09-28',
      license: 'CC BY 4.0',
    },
    geometry: { type: 'Point', coordinates: [longitude, latitude] },
  };
});
fs.writeFileSync('tool/geography/cms_eastern_europe_points.geojson',
  `${JSON.stringify({ type: 'FeatureCollection', features }, null, 2)}\n`);
