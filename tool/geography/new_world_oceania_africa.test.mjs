import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';
const root=new URL('../../',import.meta.url);
const read=p=>fs.readFileSync(new URL(p,root));
const json=p=>JSON.parse(read(p));
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const dataset=YAML.parse(read('assets/curriculum/areas/new_world_oceania_africa.yaml').toString());
const inventory=json('tool/geography/new_world_oceania_africa_inventory.json');
const snapshots=Object.values(inventory.authored.snapshots).map(s=>({s,bytes:read(s.path),data:json(s.path)}));
const points=snapshots.flatMap(x=>x.data.features);
const norm=s=>s.replace(/\([^)]*\)/g,'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');

test('national register inventories distinguish legal categories and explicit ward gaps',()=>{
  const au=inventory.australia,za=inventory.south_africa;
  assert.deepEqual(au.table_columns,{state_zone:37,region:63,subregion:14});
  assert.equal(new Set(au.register_rows.map(r=>r.node_id)).size,114);
  assert(au.register_rows.every(r=>r.node_id));assert.deepEqual(au.missing_names,[]);
  assert.deepEqual(au.gis_layers.map(l=>l.record_count),[14,64,28]);
  const tasmania=au.gis_layers.flatMap(l=>l.records).filter(r=>r.gis_name==='Tasmania');
  assert.equal(tasmania.length,2);assert.equal(new Set(tasmania.map(r=>r.node_id)).size,1);
  assert.equal(za.register_rows.length,150);
  assert.equal(za.register_rows.filter(r=>r.register_kind==='district').length,32);
  assert(za.register_rows.filter(r=>r.register_kind!=='ward').every(r=>r.node_id));
  assert.equal(za.register_rows.filter(r=>r.register_kind==='ward'&&r.node_id).length,101);
  assert.equal(za.missing_wards.length,1);assert.equal(za.missing_wards[0].register_name,'Paardeberg South');
  assert.deepEqual(za.missing_wards,za.register_rows.filter(r=>r.register_kind==='ward'&&!r.node_id));
  assert.equal(za.register_rows.find(r=>r.register_name==='Lutzville Valley').source_group,'Coastal Region');
  assert.equal(za.register_rows.find(r=>r.register_name==='Nieuwoudtville').source_group,'Western Cape');
});

test('every authored place has a primary-cited map item and both inherited track mappings',()=>{
  assert.equal(dataset.knowledge_nodes.length,170);assert.equal(points.length,170);
  const byId=new Map(points.map(p=>[p.properties.node_id,p]));assert.equal(byId.size,170);
  for(const node of dataset.knowledge_nodes){
    const item=dataset.knowledge_items.find(i=>i.subject_id===node.id&&i.relation_type==='LOCATED_IN');assert(item,node.id);
    const point=byId.get(node.id);assert(point,node.id);assert.equal(point.properties.parent_node_id,item.object_id);
    assert(point.geometry.coordinates.length===2&&point.geometry.coordinates.every(Number.isFinite));
    assert(point.geometry.coordinates[0]>=-180&&point.geometry.coordinates[0]<=180);
    assert(point.geometry.coordinates[1]>=-90&&point.geometry.coordinates[1]<=90);
    const cites=dataset.knowledge_item_citations.filter(c=>c.knowledge_item_id===item.id);
    assert.equal(cites.length,1);assert(['src_atlas_au_gis','src_atlas_za_wo_2026'].includes(cites[0].source_citation_id));
    for(const track of ['WSET_L3','CMS_CERTIFIED'])assert(dataset.certification_knowledge_mappings.some(m=>m.knowledge_item_id===item.id&&m.certification_id===track&&m.minimum_depth>=1), `${item.id} retains location exercise depth on ${track}`);
  }
  const docs=fs.readdirSync(new URL('assets/curriculum/areas/',root)).filter(f=>f.endsWith('.yaml')).map(f=>YAML.parse(read(`assets/curriculum/areas/${f}`).toString()));
  const all=docs.flatMap(d=>d.knowledge_nodes??[]);const ids=new Set(all.map(n=>n.id));
  const parents=new Map(docs.flatMap(d=>d.knowledge_relations??[]).filter(r=>r.relation_type==='LOCATED_IN').map(r=>[r.subject_id,r.object_id]));
  const country=id=>{const seen=new Set();while(parents.has(id)&&!seen.has(id)){seen.add(id);id=parents.get(id);}return id;};
  for(const item of dataset.knowledge_items)assert(ids.has(item.object_id));
  const ownIds=new Set(dataset.knowledge_nodes.map(n=>n.id));
  for(const n of dataset.knowledge_nodes)assert(!all.some(other=>other.id!==n.id&&!ownIds.has(other.id)&&country(n.id)===country(other.id)&&norm(n.name)===norm(other.name)),`Name collision within country: ${n.name}`);
  const siblingTargets=new Set();
  for(const p of points){const key=p.properties.parent_node_id+'|'+p.geometry.coordinates.join(',');assert(!siblingTargets.has(key),`Identical sibling map targets: ${p.properties.name}`);siblingTargets.add(key);}
});

test('point licences, pinned hashes and coordinate provenance remain explicit',()=>{
  for(const {s,bytes,data}of snapshots){
    assert.equal(data.features.length,s.features);assert.equal(sha(bytes),s.sha256);
    for(const f of data.features){
      const p=f.properties;assert.equal(p.retrieved_on,'2026-09-26');assert(p.source_url&&p.source_coordinate_url&&p.label_note);
      if(p.wikidata_id){assert.equal(p.license,'CC0-1.0');assert(p.wikidata_coordinate_claim.toLowerCase().startsWith(p.wikidata_id.toLowerCase()+'$'));assert(/^[0-9a-f]{64}$/.test(p.source_entity_sha256));}
      else{assert.equal(p.license,'CC-BY-4.0');assert(p.attribution);assert(/^[0-9a-f]{64}$/.test(p.source_file_sha256));}
    }
  }
});

test('authoring licence gate rejects share-alike and incompatible metadata',()=>{
  const script=read('tool/geography/new_world_oceania_africa.mjs').toString();
  const guard=script.slice(script.indexOf('const licence='),script.indexOf('const inventories='));
  assert(guard.length>0);const accept=new Function('metadata',guard);
  assert.doesNotThrow(()=>accept({owner:'WineAustralia',licenseInfo:'<p>CC BY (Attribution) 4.0 Geographical Indications of Australia</p>'}));
  for(const licenseInfo of ['CC BY-SA 4.0','CC BY (Attribution) 4.0 ShareAlike','CC BY (Attribution) 4.0 noncommercial','CC BY (Attribution) 4.0 internal use','CC BY 3.0','All rights reserved'])assert.throws(()=>accept({owner:'WineAustralia',licenseInfo}));
  assert.throws(()=>accept({owner:'SomeoneElse',licenseInfo:'CC BY (Attribution) 4.0'}));
});

test('qualified GeoNames references preserve exact coordinates from the pinned national export',t=>{
  const path=new URL('.dart_tool/new_world_geonames_ZA/ZA.txt',root);
  if(!fs.existsSync(path)){t.skip('Raw gazetteer cache is optional for the offline build');return;}
  const bytes=fs.readFileSync(path),hash=sha(bytes),rows=new Map(bytes.toString().split('\n').filter(Boolean).map(r=>{const a=r.split('\t');return[a[0],a];}));
  const gn=points.filter(p=>p.properties.geonames_id);assert.equal(gn.length,80);
  for(const p of gn){
    const props=p.properties,row=rows.get(props.geonames_id);assert(row,props.name);
    assert.equal(props.source_file_sha256,hash);assert.equal(row[8],'ZA');
    assert.deepEqual(p.geometry.coordinates,[Number(row[5]),Number(row[4])]);
    assert.equal(props.point_place_name,row[1]);assert.equal(props.geonames_admin1_code,row[10]);
  }
});

test('Wikidata markers preserve the cited exact P625 claim when authoring entity caches are available',t=>{
  const path=new URL('.dart_tool/nwoa_wikidata_entities.json',root);
  if(!fs.existsSync(path)){t.skip('Raw entity cache is optional for the offline build');return;}
  const entities=JSON.parse(fs.readFileSync(path)).entities;
  for(const f of points.filter(p=>p.properties.wikidata_id)){
    const p=f.properties,e=entities[p.wikidata_id];assert(e,p.name);assert.equal(sha(JSON.stringify(e)),p.source_entity_sha256);
    const c=e.claims.P625.find(c=>c.id===p.wikidata_coordinate_claim);assert(c,p.name);
    assert.notEqual(c.rank,'deprecated');const v=c.mainsnak.datavalue.value;
    assert.equal(v.globe,'http://www.wikidata.org/entity/Q2');assert.deepEqual(f.geometry.coordinates,[v.longitude,v.latitude]);
  }
});

function inRing(p,r){let inside=false;for(let i=0,j=r.length-1;i<r.length;j=i++){const a=r[i],b=r[j];if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])inside=!inside;}return inside;}
test('Australian derived references lie within pinned official polygons when raw caches are available',t=>{
  const gis=points.filter(p=>p.properties.source_item_id);
  const layers=[1,2];if(layers.some(l=>!fs.existsSync(new URL(`.dart_tool/nwoa_wine_australia_${l}.geojson`,root)))){t.skip('Raw authoring cache is optional; committed snapshots serve the offline build');return;}
  const raw=new Map(layers.map(l=>{const b=read(`.dart_tool/nwoa_wine_australia_${l}.geojson`);return[l,{sha:sha(b),features:JSON.parse(b).features}];}));
  assert.equal(gis.length,55);
  for(const point of gis){
    const p=point.properties,source=raw.get(p.source_layer_id);assert.equal(source.sha,p.source_file_sha256);
    const feature=source.features.find(f=>f.properties.GI_NUMBER===p.source_gi_number);assert(feature,p.name);
    const poly=feature.geometry.type==='Polygon'?[feature.geometry.coordinates]:feature.geometry.coordinates;
    assert(poly.some(r=>inRing(point.geometry.coordinates,r[0])&&!r.slice(1).some(h=>inRing(point.geometry.coordinates,h))),p.name);
  }
});
