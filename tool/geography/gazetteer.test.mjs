import assert from 'node:assert/strict';
import fs from 'node:fs';
import { test } from 'node:test';
import { buildGazetteer, expectedLayerNodeIds } from './build.mjs';
import { downloadPath } from './lib.mjs';

test('gazetteer markers retain exact coordinates and reject missing provenance', async () => {
  const source={id:'src_fixture',snapshot:'gazetteer_test_fixture.geojson'};
  const file=downloadPath(source);
  const config={sources:new Map([[source.id,source]])};
  const layer={gazetteer:{source:source.id}};
  const f={type:'Feature',properties:{node:'n_geo_fixture',name:'Fixture',source_url:'https://www.wikidata.org/wiki/Q123'},geometry:{type:'Point',coordinates:[7.15,49.42]}};
  const write=features=>fs.writeFileSync(file,JSON.stringify({type:'FeatureCollection',features}));
  try {
    write([f]);
    const result=await buildGazetteer(config,layer);
    assert.deepEqual(result.topology.objects.layer.geometries[0].coordinates,[7.15,49.42]);
    assert.equal(result.table[0].label_lon,7.15);
    assert.equal(result.table[0].label_lat,49.42);
    assert.equal(result.topology.objects.layer.geometries[0].id,'n_geo_fixture');
    write([f,f]);
    await assert.rejects(buildGazetteer(config,layer),/duplicate/);
    delete f.properties.source_url;
    write([f]);
    await assert.rejects(buildGazetteer(config,layer),/invalid/);
    f.properties.source_url='https://example.org/source';
    f.geometry={type:'Polygon',coordinates:[]};
    write([f]);
    await assert.rejects(buildGazetteer(config,layer),/invalid/);
  } finally { fs.unlinkSync(file); }
});

test('selected mixed-source gazetteers preserve legacy keys without duplicate points', async () => {
  const a = { id: 'src_selection_a', snapshot: 'gazetteer_selection_a.geojson' };
  const b = { id: 'src_selection_b', snapshot: 'gazetteer_selection_b.geojson' };
  const config = { sources: new Map([[a.id, a], [b.id, b]]) };
  const point = (node, coordinates) => ({
    type: 'Feature',
    properties: { node, name: node, source_url: 'https://example.org/' + node },
    geometry: { type: 'Point', coordinates },
  });
  const write = (source, features) => fs.writeFileSync(
    downloadPath(source), JSON.stringify({ type: 'FeatureCollection', features }),
  );
  const primary = point('n_geo_castel', [11.24032, 45.46122]);
  const corrected = point('n_geo_brogn', [11.29379, 45.44869]);
  const other = point('n_geo_other', [11.2, 45.5]);
  const mixed = {
    id: 'ml_historic', sources: [a.id, b.id],
    gazetteer: { source: a.id, supplements: [{ source: b.id, include_nodes: ['n_geo_brogn'] }] },
  };
  try {
    write(a, [primary]); write(b, [corrected, other]);
    const defaultBefore = await buildGazetteer(config, { gazetteer: { source: a.id } });
    const joined = await buildGazetteer(config, mixed);
    // This is the exact mapping function consumed by check.mjs, not raw primary members.
    assert.deepEqual(await expectedLayerNodeIds(config, mixed), ['n_geo_brogn', 'n_geo_castel']);
    assert.deepEqual(await expectedLayerNodeIds(config, {
      id: 'ml_other', sources: [b.id],
      gazetteer: { source: b.id, exclude_nodes: ['n_geo_brogn'] },
    }), ['n_geo_other']);
    await assert.rejects(expectedLayerNodeIds(config, {
      ...mixed, gazetteer: { source: a.id, supplements: [{ source: b.id, include_nodes: ['n_geo_missing'] }] },
    }), /unknown/);
    assert.deepEqual(joined.topology.objects.layer.geometries.map((f) => f.id),
      ['n_geo_brogn', 'n_geo_castel']);
    assert.deepEqual(joined.topology.objects.layer.geometries[0].coordinates,
      [11.29379, 45.44869]);
    const separate = await buildGazetteer(config, {
      id: 'ml_other', sources: [b.id],
      gazetteer: { source: b.id, exclude_nodes: ['n_geo_brogn'] },
    });
    assert.deepEqual(separate.table.map((f) => f.node), ['n_geo_other']);
    const all = [...joined.table, ...separate.table].map((f) => f.node);
    assert.equal(all.length, new Set(all).size);
    assert.deepEqual(await buildGazetteer(config, { gazetteer: { source: a.id } }), defaultBefore);
    for (const key of ['include_nodes', 'exclude_nodes']) {
      await assert.rejects(buildGazetteer(config, {
        id: 'ml_bad', sources: [b.id],
        gazetteer: { source: b.id, [key]: ['n_geo_unknown'] },
      }), /unknown/);
      await assert.rejects(buildGazetteer(config, {
        id: 'ml_bad', sources: [b.id],
        gazetteer: { source: b.id, [key]: ['n_geo_brogn', 'n_geo_brogn'] },
      }), /unique/);
    }
    await assert.rejects(buildGazetteer(config, {
      ...mixed, sources: [a.id],
    }), /listed/);
    await assert.rejects(buildGazetteer(config, {
      ...mixed, gazetteer: { source: a.id, supplements: [{ source: 'src_missing' }] },
    }), /known and listed/);
    write(b, [corrected, primary]);
    await assert.rejects(buildGazetteer(config, {
      ...mixed, gazetteer: { source: a.id, supplements: [{ source: b.id }] },
    }), /duplicate selected/);
    write(b, [corrected, { ...other, geometry: { type: 'Point', coordinates: [999, 45] } }]);
    await assert.rejects(buildGazetteer(config, mixed), /invalid/);
    write(b, [corrected, corrected]);
    await assert.rejects(buildGazetteer(config, mixed), /duplicate sourced/);
  } finally {
    for (const source of [a, b]) if (fs.existsSync(downloadPath(source))) fs.unlinkSync(downloadPath(source));
  }
});


test('checker node mapping retains appellation and Natural Earth recipe defaults', async () => {
  assert.deepEqual(await expectedLayerNodeIds({}, {
    appellation_areas: { n_geo_one: ['A'], n_geo_two: ['B'] },
  }), ['n_geo_one', 'n_geo_two']);
  assert.deepEqual(await expectedLayerNodeIds({}, {
    natural_earth: { nodes: { A: 'n_geo_one', B: 'n_geo_two' } },
  }), ['n_geo_one', 'n_geo_two']);
});
