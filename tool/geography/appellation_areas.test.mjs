import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildAppellationAreas } from './build.mjs';

const square = (left) => ({
  type: 'Polygon',
  coordinates: [[
    [left, 6600000], [left + 1000, 6600000],
    [left + 1000, 6601000], [left, 6601000], [left, 6600000],
  ]],
});

test('each appellation retains its complete union when legal areas overlap', async () => {
  // One village AOC sits inside two AOCs with the same two-commune area.
  // Neither partial nor identical overlaps may steal another node's shape.
  const areas = {
    n_geo_broad: { aoc: [1] },
    n_geo_village: { aoc: [2] },
    n_geo_identical: { aoc: [3] },
  };
  const layer = {
    id: 'ml_fixture', appellation_areas: areas,
    simplify: '100%', quantization: 100000,
  };
  const curriculum = { nodes: new Map(Object.keys(areas).map((node) =>
    [node, { name: node }])) };
  const codes = new Map([
    ['n_geo_broad', ['00001', '00002']],
    ['n_geo_village', ['00001']],
    ['n_geo_identical', ['00001', '00002']],
  ]);
  const shapes = new Map([
    ['00001', square(700000)], ['00002', square(701000)],
  ]);
  const result = await buildAppellationAreas(layer, curriculum, codes, shapes);
  const rows = new Map(result.table.map((row) => [row.node, row]));
  const features = new Map(result.topology.objects.layer.geometries.map((feature) =>
    [feature.id, feature]));
  assert.deepEqual([...rows.keys()].sort(), Object.keys(areas).sort());
  assert.deepEqual([...features.keys()].sort(), Object.keys(areas).sort());
  for (const node of Object.keys(areas)) assert.ok(features.get(node).arcs.flat(2).length);
  assert.deepEqual(features.get('n_geo_broad').arcs, features.get('n_geo_identical').arcs);
  assert.equal(rows.get('n_geo_broad').min_lon, rows.get('n_geo_village').min_lon);
  assert.ok(rows.get('n_geo_broad').max_lon > rows.get('n_geo_village').max_lon);
  assert.deepEqual([...result.communes.get('n_geo_broad')], ['00001', '00002']);
});
