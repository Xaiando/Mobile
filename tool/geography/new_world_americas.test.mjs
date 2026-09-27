import fs from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import YAML from 'yaml';
const areaDir=new URL('../../assets/curriculum/areas/',import.meta.url);
const documents=fs.readdirSync(areaDir).filter(f=>f.endsWith('.yaml')).map(f=>YAML.parse(fs.readFileSync(new URL(f,areaDir),'utf8')));
const nodes=new Map(documents.flatMap(d=>d.knowledge_nodes??[]).map(n=>[n.id,n]));
const items=documents.flatMap(d=>d.knowledge_items??[]);
const sources=documents.flatMap(d=>d.source_citations??[]);
const relations=documents.flatMap(d=>d.knowledge_relations??[]);
const authored=YAML.parse(fs.readFileSync(new URL('new_world_americas.yaml',areaDir),'utf8'));
const parentOf=id=>relations.find(r=>r.subject_id===id&&r.relation_type==='LOCATED_IN')?.object_id;

test('Ontario named main/regional/sub-appellations match the current closed regulator lists',()=>{
  // OWAA overview: three main + eleven sub-appellations. 2025 booklet and
  // current West Niagara page: three regional appellations, recognised 2024.
  const main=['niagara_peninsula','lake_erie_north_shore','prince_edward_county'];
  const regional=['niagara_escarpment_ontario','niagara_on_the_lake_appellation','west_niagara'];
  const niagaraSubs=['beamsville_bench','twenty_mile_bench','short_hills_bench','st_davids_bench','lincoln_lakeshore','niagara_lakeshore','niagara_river_ontario','four_mile_creek','creek_shores','vinemount_ridge'];
  const southIslands=['south_islands_ontario'];
  assert.equal(new Set([...main,...regional,...niagaraSubs,...southIslands]).size,17);
  for(const id of main)assert.equal(parentOf(`n_geo_${id}`),'n_geo_ontario');
  for(const id of [...regional,...niagaraSubs])assert.equal(parentOf(`n_geo_${id}`),'n_geo_niagara_peninsula');
  assert.equal(parentOf('n_geo_south_islands_ontario'),'n_geo_lake_erie_north_shore');
  assert.equal(authored.knowledge_nodes.filter(n=>[...regional,...niagaraSubs,...southIslands].includes(n.id.slice(6))).length,14);
});

test('BC section 56 names all nine regional GIs and twelve sub-GIs',()=>{
  const main=['fraser_valley_wine','gulf_islands_wine','lillooet_wine','kootenays_wine','shuswap_wine','thompson_valley_wine','vancouver_island_wine','okanagan_valley','similkameen_valley'];
  const okanagan=['golden_mile_bench','east_kelowna_slopes','golden_mile_slopes','lake_country_wine','naramata_bench','okanagan_falls_wine','skaha_bench','south_kelowna_slopes','summerland_bench','summerland_lakefront','summerland_valleys'];
  assert.equal(new Set([...main,...okanagan,'cowichan_valley_wine']).size,21);
  for(const id of main)assert.equal(parentOf(`n_geo_${id}`),'n_geo_british_columbia');
  for(const id of okanagan)assert.equal(parentOf(`n_geo_${id}`),'n_geo_okanagan_valley');
  assert.equal(parentOf('n_geo_cowichan_valley_wine'),'n_geo_vancouver_island_wine');
});

test('pinned TTB name/CFR inventory closes CA154, OR23 and WA22 without false single-state nesting',()=>{
  const inventory=JSON.parse(fs.readFileSync(new URL('new_world_americas_us_inventory.json',import.meta.url)));
  assert.equal(inventory.register_updated_on,'2026-08-18');
  assert.equal(inventory.entries.length,196);
  const counts={California:0,Oregon:0,Washington:0};
  const ids=new Set(),sections=new Set();
  for(const entry of inventory.entries) {
    assert.ok(nodes.has(entry.node_id),entry.name);
    assert.ok(items.some(i=>i.subject_id===entry.node_id&&i.relation_type==='LOCATED_IN'),entry.name);
    assert.ok(/^9\.\d+$/.test(entry.cfr));
    assert.ok(!ids.has(entry.node_id),entry.name);ids.add(entry.node_id);
    assert.ok(!sections.has(entry.cfr),entry.cfr);sections.add(entry.cfr);
    for(const state of Object.keys(counts))if(entry.section===state||(entry.section==='Multi-State'&&entry.states_or_counties.split(';').map(s=>s.trim()).includes(state)))counts[state]++;
  }
  assert.deepEqual(counts,{California:154,Oregon:23,Washington:22});
  assert.equal(parentOf('n_geo_snake_river_valley'),'n_geo_united_states');
  assert.equal(parentOf('n_geo_lewis_clark_valley'),'n_geo_united_states');
  assert.equal(parentOf('n_geo_columbia_hills'),'n_geo_columbia_valley');
  assert.equal(parentOf('n_geo_beverly_washington'),'n_geo_columbia_valley');
  assert.equal(parentOf('n_geo_san_antonio_valley_california'),'n_geo_central_coast');
  assert.notEqual('n_geo_san_antonio_valley_california','n_geo_san_antonio_valley');
});

test('all additive locations have primary citations, both eligible tracks and unique point identities',()=>{
  assert.equal(authored.knowledge_nodes.length,191);
  assert.equal(authored.knowledge_items.length,191);
  assert.equal(authored.certification_knowledge_mappings.length,382);
  assert.equal(new Set(sources.map(s=>s.url)).size,sources.length,'duplicate primary source URL');
  const citations=authored.knowledge_item_citations;
  const points=['new_world_americas_points.geojson','new_world_americas_gazetteer_points.geojson'].flatMap(f=>JSON.parse(fs.readFileSync(new URL(f,import.meta.url))).features);
  assert.equal(points.length,191);
  assert.equal(new Set(points.map(f=>f.properties.node_id)).size,191);
  for(const item of authored.knowledge_items) {
    assert.equal(item.verification_status,'unverified','expert review must use the ledger');
    assert.equal(item.relation_type,'LOCATED_IN');
    assert.ok(citations.some(c=>c.knowledge_item_id===item.id&&['legislation','regulator_register','government_publication'].includes(sources.find(s=>s.id===c.source_citation_id)?.kind)),item.id);
    for(const track of ['WSET_L3','CMS_CERTIFIED'])assert.ok(authored.certification_knowledge_mappings.some(m=>m.knowledge_item_id===item.id&&m.certification_id===track&&m.minimum_depth>=2),item.id);
    assert.ok(points.some(f=>f.properties.node_id===item.subject_id&&f.properties.parent_node_id===item.object_id),item.id);
  }
  // Avoid two coordinate/namespace mistakes that pass a country-only check.
  const junin=points.find(f=>f.properties.node_id==='n_geo_junin_mendoza');
  assert.equal(junin.properties.geonames_id,'3853355');
  assert.deepEqual(junin.geometry.coordinates,[-68.48727,-33.14653]);
  const barreal=points.find(f=>f.properties.node_id==='n_geo_barreal');
  assert.equal(barreal.properties.geonames_id,'3864688');
  assert.deepEqual(barreal.geometry.coordinates,[-69.47224,-31.64996]);
});
