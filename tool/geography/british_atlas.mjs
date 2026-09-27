// Reproduce source-derived British atlas markers and the owned curriculum file.
// Run from the repository root. No boundaries or legal permission sets are authored.
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';

const retrieved = '2026-09-26';
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const specs = [];
function add(id, name, type, parent, title, assertion, source, locator) {
  specs.push({id, name, type, parent, title, assertion, source, locator});
}
for (const [id,name] of [['england','England'],['wales','Wales']]) {
  add(id,name,'region','united_kingdom',name,`${name} is a constituent country of the United Kingdom and a wine-growing area.`, 'src_british_ons_administrative', `${name}: constituent country within UK administrative geographies`);
}
const counties = [
  ['kent','Kent'], ['essex','Essex'], ['hampshire','Hampshire'], ['surrey','Surrey'],
  ['dorset','Dorset'], ['wiltshire','Wiltshire'], ['isle_of_wight','Isle of Wight'],
  ['cornwall','Cornwall'], ['devon','Devon'], ['somerset','Somerset'],
  ['herefordshire','Herefordshire'], ['gloucestershire','Gloucestershire'],
  ['norfolk','Norfolk'], ['suffolk','Suffolk'],
];
for (const [id,name] of counties) {
  add(id,name,'region','england',id==='somerset'?'Taunton':name,`${name} is an English county represented in WineGB's wine-growing geography.`, 'src_british_winegb_associations', `${name}: county membership under South East, East, Wessex or West; England's wine-growing counties`);
}
add('sussex','Sussex','informal_area','england','Sussex','Sussex is a historical English county and wine-growing area; WineGB groups East Sussex and West Sussex in its South East region. This geography item does not describe the Sussex PDO.', 'src_british_winegb_regions','Largest five counties: Sussex; South East: East Sussex and West Sussex');
add('wessex_wine','Wessex (WineGB region)','informal_area','england','Dorchester, Dorset','The WineGB Wessex wine-growing region covers Dorset, Hampshire, the Isle of Wight and Wiltshire in England; it is a regional association area rather than a wine appellation.', 'src_british_winegb_associations','Wessex: Dorset, Hampshire, Isle of Wight and Wiltshire');
for (const [id,name] of [['monmouthshire','Monmouthshire'],['carmarthenshire','Carmarthenshire'],['pembrokeshire','Pembrokeshire'],['ceredigion','Ceredigion']]) {
  add(id,name,'region','wales',name,`${name} is a Welsh county with vineyards represented in WineGB's Welsh wine-growing geography.`, 'src_british_winegb_regions', `Wales: named county ${name}`);
}
const sourceCitations = [
  {id:'src_british_ons_administrative',kind:'government_publication',title:'Administrative geographies: constituent countries of the United Kingdom',publisher:'Office for National Statistics',jurisdiction:'GB',url:'https://www.ons.gov.uk/methodology/geography/ukgeographies/administrativegeography',accessed_on:retrieved},
  {id:'src_british_winegb_regions',kind:'reference_work',title:'Wine regions of England and Wales',publisher:'Wines of Great Britain',jurisdiction:'GB',url:'https://winegb.co.uk/wines/regions/',accessed_on:retrieved},
  {id:'src_british_winegb_associations',kind:'reference_work',title:'WineGB regional associations and county membership',publisher:'Wines of Great Britain',jurisdiction:'GB',url:'https://winegb.co.uk/about/regional-associations/',accessed_on:retrieved},
];
const cachePath = '.dart_tool/british_atlas_entities.json';
let entityResponse=fs.existsSync(cachePath)&&!process.argv.includes('--refresh')?JSON.parse(fs.readFileSync(cachePath,'utf8')):{entities:{}};
const missingTitles=[...new Set(specs.map(s=>s.title))].filter(title=>!Object.values(entityResponse.entities).some(e=>e.sitelinks?.enwiki?.title===title));
if (missingTitles.length) {
  const url=new URL('https://www.wikidata.org/w/api.php');
  Object.entries({action:'wbgetentities',sites:'enwiki',titles:missingTitles.join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>url.searchParams.set(k,v));
  const response=await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.11 British geography research'}});
  if (!response.ok) throw Error(`Wikidata ${response.status}`);
  const additions=await response.json();
  if (additions.error) throw Error(JSON.stringify(additions.error));
  Object.assign(entityResponse.entities,additions.entities);
  fs.mkdirSync('.dart_tool',{recursive:true});
  fs.writeFileSync(cachePath,JSON.stringify(entityResponse,null,2)+'\n');
}
const entities=Object.values(entityResponse.entities);
const features=specs.map(s=>{
  const entity=entities.find(e=>e.sitelinks?.enwiki?.title===s.title);
  const candidates=entity?.claims?.P625?.filter(c=>c.rank!=='deprecated' && c.mainsnak.datavalue?.value.globe==='http://www.wikidata.org/entity/Q2') ?? [];
  const claim=candidates.find(c=>c.rank==='preferred') ?? candidates[0];
  if (!claim) throw Error(`Missing exact Earth P625 coordinate: ${s.title}`);
  const p=claim.mainsnak.datavalue.value;
  if (!Number.isFinite(p.longitude) || !Number.isFinite(p.latitude) || Math.abs(p.latitude)>90 || Math.abs(p.longitude)>180) throw Error(`Invalid WGS84: ${s.title}`);
  const qualifier=s.id==='wessex_wine'?'Dorchester in Dorset is a qualified inland reference location for the WineGB Wessex area; this is not the extent of the historic kingdom of Wessex.':s.id==='somerset'?'Taunton, the county town of Somerset, is a qualified inland reference location for the county; this is not the county centroid.':s.id==='sussex'?'Reference point for the historical Sussex area; this marker does not represent the Sussex PDO.':`Reference point for ${s.name}.`;
  return {type:'Feature',properties:{node:`n_geo_${s.id}`,node_id:`n_geo_${s.id}`,name:s.name,parent_node_id:`n_geo_${s.parent}`,country_node_id:'n_geo_united_kingdom',point_role:['wessex_wine','somerset'].includes(s.id)?'qualified_locality_reference_point':'gazetteer_reference_point',point_place_name:entity.labels?.en?.value??s.title,point_description:entity.descriptions?.en?.value??'',source_url:`https://www.wikidata.org/wiki/${entity.id}`,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,wikidata_id:entity.id,wikidata_coordinate_claim:claim.id,source_entity_revision:entity.lastrevid,source_entity_sha256:sha(JSON.stringify(entity)),coordinate_precision:p.precision,retrieved_on:retrieved,license:'CC0-1.0',label_note:`${qualifier} This point does not represent a wine-area boundary or an official centroid.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}};
});
const names=Object.fromEntries([['united_kingdom','United Kingdom'],...specs.map(s=>[s.id,s.name])]);
const files=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')&&f!=='british_atlas.yaml');
const existingIds=new Set(files.flatMap(f=>(YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')).knowledge_nodes??[]).map(n=>n.id)));
for (const s of [{id:'united_kingdom'},...specs]) if(existingIds.has(`n_geo_${s.id}`)) throw Error(`Existing node ${s.id}`);
for (const s of specs) if(!names[s.parent])throw Error(`Unknown parent ${s.parent}`);
const item=s=>`ki_british_${s.id}_location`;
const dataset={
  knowledge_nodes:[{id:'n_geo_united_kingdom',node_type:'country',name:'United Kingdom'},...specs.map(s=>({id:`n_geo_${s.id}`,node_type:s.type,name:s.name}))],
  node_alternative_names:[{knowledge_node_id:'n_geo_united_kingdom',name:'UK',kind:'synonym'},{knowledge_node_id:'n_geo_wessex_wine',name:'Wessex wine region',kind:'synonym'}],
  knowledge_relations:specs.map(s=>({subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,valid_from:'1900-01-01'})),
  knowledge_items:specs.map(s=>({id:item(s),subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,domain_id:'geography',assertion_text:s.assertion,verification_status:'unverified',last_verified_at:'2026-09-26T18:00:00.000Z'})),
  certification_knowledge_mappings:specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(cert=>({certification_id:cert,knowledge_item_id:item(s),importance:'secondary',minimum_depth:2}))),
  source_citations:sourceCitations,
  knowledge_item_citations:specs.map(s=>({knowledge_item_id:item(s),source_citation_id:s.source,locator:s.locator})),
};
for (const s of specs.filter(s=>s.id==='england'||s.id==='wales')) dataset.knowledge_item_citations.push({knowledge_item_id:item(s),source_citation_id:'src_british_winegb_regions',locator:`${s.name}: Wine Standards 2025 area and wine-growing geography`});
const yamlPath='assets/curriculum/areas/british_atlas.yaml';
const pointPath='tool/geography/british_atlas_points.geojson';
if(!process.argv.includes('--points-only')) fs.writeFileSync(yamlPath,'# British atlas: bounded primary-cited geography, not full Diploma coverage.\n# Counties, constituent countries and informal wine areas are distinct.\n# CC0 markers are sourced reference locations, not boundaries or PDO centroids.\n# Track mappings are editorial; all knowledge items await qualified review.\n'+YAML.stringify(dataset));
fs.writeFileSync(pointPath,JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
console.log(JSON.stringify({nodes:dataset.knowledge_nodes.length,noncountry_nodes:specs.length,location_items:dataset.knowledge_items.length,mappings:dataset.certification_knowledge_mappings.length,features:features.length,snapshot_sha256:sha(fs.readFileSync(pointPath)),yaml_sha256:sha(fs.readFileSync(yamlPath)),qid_names:features.map(f=>[f.properties.name,f.properties.wikidata_id,f.properties.point_place_name])},null,2));
