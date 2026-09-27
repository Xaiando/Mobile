import assert from 'node:assert/strict';
import fs from 'node:fs';
import { test } from 'node:test';
import { buildGazetteer } from './build.mjs';
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
