import fs from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import mapshaper from 'mapshaper';
import {buildNaturalEarth} from './build.mjs';
import {loadConfig, budgets} from './lib.mjs';
import {geometryContains, islandRequests} from './americas_country_islands.mjs';

test('country supplement preserves exact licensed island markers and France map units', async()=>{
  const config=loadConfig();
  const layer=config.layers.find(l=>l.id==='ml_world_countries');
  const built=await buildNaturalEarth(config,layer);
  const bytes=JSON.stringify(built.topology);
  assert.ok(Buffer.byteLength(bytes)<budgets.layerBytes);
  const output=await mapshaper.applyCommands('-i countries.topo.json -o countries.json format=geojson',{'countries.topo.json':bytes});
  const countries=JSON.parse(output['countries.json'].toString()).features;
  const shape=id=>countries.find(f=>f.id===id||f.properties.node===id)?.geometry;
  const markers=['new_world_americas_points.geojson','new_world_americas_gazetteer_points.geojson'].flatMap(f=>JSON.parse(fs.readFileSync(new URL(f,import.meta.url))).features);
  for(const marker of markers) {
    const country=shape(marker.properties.country_node_id);
    assert.ok(country,marker.properties.country_node_id);
    const point=marker.geometry.coordinates;
    assert.ok(geometryContains(point,country),`${marker.properties.node_id}: exact licensed point`);
    assert.ok(geometryContains(point.map(n=>Number(n.toFixed(6))),country),`${marker.properties.node_id}: manifest-rounded point`);
  }
  assert.ok(geometryContains([2.35,48.86],shape('n_geo_france')));
  assert.equal(geometryContains([-61.5,16.2],shape('n_geo_france')),false);
  for(const request of islandRequests) {
    const marker=markers.find(f=>f.properties.node_id===request.node);
    assert.ok(marker,'missing island reference');
    assert.deepEqual(marker.geometry.coordinates,request.key==='CAN'?[-123.49061,48.81852]:[-109.35,-27.12]);
  }
});

test('island supplement has complete source parts and pinned provenance',()=>{
  const data=JSON.parse(fs.readFileSync(new URL('americas_country_islands.geojson',import.meta.url)));
  assert.equal(data.features.length,2);
  const expected={CAN:{index:129,vertices:44},CHL:{index:4,vertices:37}};
  for(const feature of data.features) {
    const properties=feature.properties;
    const record=expected[properties.key];
    assert.ok(record);
    assert.equal(properties.source_adm0_a3,properties.key);
    assert.equal(properties.source_polygon_index,record.index);
    assert.equal(feature.geometry.coordinates.reduce((n,ring)=>n+ring.length,0),record.vertices);
    assert.equal(properties.source_archive_sha256,'ce1ac7036499a0edd641fbc093cd209a98f96a49d2eca8480aaacad35138a7f6');
    assert.equal(properties.license,'Public domain');
    assert.ok(geometryContains(properties.selected_by_exact_point,feature.geometry));
    for(const ring of feature.geometry.coordinates)assert.deepEqual(ring[0],ring.at(-1));
  }
});
