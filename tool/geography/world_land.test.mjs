import assert from 'node:assert/strict';
import {test} from 'node:test';
import {buildNaturalEarth} from './build.mjs';
import {loadConfig,budgets} from './lib.mjs';
import mapshaper from 'mapshaper';
import {geometryContains} from './americas_country_islands.mjs';

test('world country framing dissolves licensed land instead of inventing a border',async()=>{
 const config=loadConfig(),spec=config.layers.find(l=>l.id==='ml_world_land');
 assert.equal(spec.natural_earth.dissolve,true);
 const result=await buildNaturalEarth(config,spec);
 assert.equal(result.table.length,1);
 assert.equal(result.table[0].node,'n_geo_world');
 assert.ok(Buffer.byteLength(JSON.stringify(result.topology))<budgets.layerBytes);
 const output=await mapshaper.applyCommands('-i world.topo.json -o world.json format=geojson',{'world.topo.json':JSON.stringify(result.topology)});
 const world=JSON.parse(output['world.json'].toString()).features[0].geometry;
 for(const place of [[2.35,48.86],[-70.67,-33.45],[-68.85,-32.89],[19,-33],[138.6,-34.9],[169.826546,-44.789698]])assert.ok(geometryContains(place,world),String(place));
 assert.equal(geometryContains([-140,0],world),false,'ocean is not invented land');
});
