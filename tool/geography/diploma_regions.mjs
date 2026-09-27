// Reproduce ten bounded macro-region geography additions; no boundaries inferred.
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';
const date='2026-09-26';
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
// id, display name, country, coordinate entity title, primary fact citation, locator.
const rows=[
  ['valencian_community','Valencia (autonomous community)','spain','Valencian Community','src_diploma_es_autonomous','Code 10: Comunitat Valenciana'],
  ['region_murcia','Murcia (autonomous community)','spain','Region of Murcia','src_diploma_es_autonomous','Code 14: Murcia, Región de'],
  ['castilla_la_mancha','Castilla-La Mancha','spain','Castilla–La Mancha','src_diploma_es_autonomous','Code 08: Castilla - La Mancha'],
  ['la_rioja_region','La Rioja (autonomous community)','spain','La Rioja','src_diploma_es_autonomous','Code 17: Rioja, La; administrative community, not Rioja DOCa'],
  ['navarra_region','Navarra (autonomous community)','spain','Navarre','src_diploma_es_autonomous','Code 15: Navarra, Comunidad Foral de; administrative community, not Navarra DO'],
  ['lisboa_wine','Lisboa (wine region)','portugal','Torres Vedras','src_diploma_pt_lisboa','Description of Lisboa Region: Portugal; Torres Vedras among its central denominations'],
  ['olifants_river_wine','Olifants River (wine region)','south_africa','Vredendal','src_atlas_za_wo_2026','Geographical unit Western Cape: region Olifants River / Olifantsrivier; Vredendal ward'],
  ['north_island','North Island','new_zealand','North Island','src_diploma_nz_island_names','North Island / Te Ika-a-Māui: northern of the two main islands of New Zealand'],
  ['south_island','South Island','new_zealand','South Island','src_diploma_nz_island_names','South Island / Te Waipounamu: southern of the two main islands of New Zealand'],
  ['south_eastern_australia','South Eastern Australia','australia','Melbourne','src_atlas_au_gis','South Eastern Australia zone; footnote 1: all NSW, Victoria and Tasmania, parts of Queensland and South Australia'],
];
const sources=[
  {id:'src_diploma_es_autonomous',kind:'government_publication',title:'Relación de comunidades y ciudades autónomas con sus códigos',publisher:'Instituto Nacional de Estadística',jurisdiction:'ES',url:'https://www.ine.es/daco/daco42/codmun/cod_ccaa.htm',accessed_on:date},
  {id:'src_diploma_pt_lisboa',kind:'reference_work',title:'Lisboa wine region: geography and denominations',publisher:'ViniPortugal / Wines of Portugal',jurisdiction:'PT',url:'https://www.winesofportugal.com/en/discover/wine-regions/lisboa/',accessed_on:date},
  {id:'src_diploma_nz_island_names',kind:'government_publication',title:'Te Ika-a-Māui North Island and Te Waipounamu South Island',publisher:'Toitū Te Whenua Land Information New Zealand / New Zealand Geographic Board',jurisdiction:'NZ',url:'https://www.linz.govt.nz/our-work/new-zealand-geographic-board/place-name-stories/te-ika-maui-north-island-and-te-waipounamu-south-island',accessed_on:date},
  {id:'src_diploma_za_olifants',kind:'reference_work',title:'Winelands of South Africa: Olifants River',publisher:'Wines of South Africa',jurisdiction:'ZA',url:'https://www.wosa.co.za/The-Industry/Winegrowing-Areas/Winelands-of-South-Africa/',accessed_on:date},
];
const cache='.dart_tool/diploma_regions_entities.json';
let response;
if(fs.existsSync(cache)&&!process.argv.includes('--refresh'))response=JSON.parse(fs.readFileSync(cache,'utf8'));
else {
  const u=new URL('https://www.wikidata.org/w/api.php');
  Object.entries({action:'wbgetentities',sites:'enwiki',titles:rows.map(r=>r[3]).join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>u.searchParams.set(k,v));
  const res=await fetch(u,{headers:{'User-Agent':'SommelierStudyCompanion/0.12 geography source research'}});
  if(!res.ok)throw Error(`Wikidata ${res.status}`);
  response=await res.json();if(response.error)throw Error(JSON.stringify(response.error));
  fs.mkdirSync('.dart_tool',{recursive:true});fs.writeFileSync(cache,JSON.stringify(response,null,2)+'\n');
}
const entities=Object.values(response.entities);
const features=rows.map(([id,name,country,title])=>{
  const entity=entities.find(e=>e.sitelinks?.enwiki?.title===title);
  const candidates=entity?.claims?.P625?.filter(c=>c.rank!=='deprecated'&&c.mainsnak.datavalue?.value.globe==='http://www.wikidata.org/entity/Q2')??[];
  const claim=candidates.find(c=>c.rank==='preferred')??candidates[0];
  if(!claim)throw Error(`Missing exact Earth P625: ${title}`);
  const p=claim.mainsnak.datavalue.value;
  if(!Number.isFinite(p.longitude)||!Number.isFinite(p.latitude)||Math.abs(p.longitude)>180||Math.abs(p.latitude)>90)throw Error(`Invalid WGS84 ${title}`);
  const qualified=['lisboa_wine','olifants_river_wine','south_eastern_australia'].includes(id);
  const qualifier=id==='lisboa_wine'?'Torres Vedras, a named locality in the Lisboa wine region. The marker represents neither Lisbon city nor the wine-region boundary.':id==='olifants_river_wine'?'Vredendal, a named locality in the Olifants River wine region. This marker does not represent the river geometry.':id==='south_eastern_australia'?'Melbourne in Victoria, which is wholly included in the South Eastern Australia wine GI. This is a locality reference, not the GI centroid.':`Reference point for ${name}.`;
  return {type:'Feature',properties:{node:`n_geo_${id}`,node_id:`n_geo_${id}`,name,parent_node_id:`n_geo_${country}`,country_node_id:`n_geo_${country}`,point_role:qualified?'qualified_locality_reference_point':'gazetteer_reference_point',point_place_name:entity.labels?.en?.value??title,point_description:entity.descriptions?.en?.value??'',source_url:`https://www.wikidata.org/wiki/${entity.id}`,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,wikidata_id:entity.id,wikidata_coordinate_claim:claim.id,source_entity_sha256:sha(JSON.stringify(entity)),coordinate_precision:p.precision,retrieved_on:date,license:'CC0-1.0',label_note:`${qualifier} No boundary or official centroid is derived from this point.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}};
});
const existingFiles=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')&&f!=='diploma_regions.yaml');
const existing=existingFiles.map(f=>YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')));
const existingIds=new Set(existing.flatMap(d=>(d.knowledge_nodes??[]).map(n=>n.id)));
const existingSources=new Set(existing.flatMap(d=>(d.source_citations??[]).map(s=>s.id)));
for(const [id,,country,,source] of rows){if(existingIds.has(`n_geo_${id}`))throw Error(`Duplicate node ${id}`);if(!existingIds.has(`n_geo_${country}`))throw Error(`Missing country ${country}`);if(!existingSources.has(source)&&!sources.some(s=>s.id===source))throw Error(`Missing citation ${source}`);}
const item=id=>`ki_diploma_${id}_location`;
const assertion=([id,name,country])=>id==='lisboa_wine'?'Lisboa is a wine-growing region of Portugal, distinct from the city of Lisbon.':id==='olifants_river_wine'?'Olifants River is a Wine of Origin region in South Africa.':id==='south_eastern_australia'?'South Eastern Australia is a registered Australian wine geographical-indication zone.':id==='north_island'||id==='south_island'?`${name} is one of the two main islands of New Zealand. This item describes the geographic island, not a wine GI.`:`${name} is an autonomous community of Spain; this geography item describes the administrative region.`;
const dataset={
  knowledge_nodes:rows.map(([id,name])=>({id:`n_geo_${id}`,node_type:'region',name})),
  node_alternative_names:[
    {knowledge_node_id:'n_geo_valencian_community',name:'Valencian Community',kind:'synonym'},
    {knowledge_node_id:'n_geo_valencian_community',name:'Comunitat Valenciana',kind:'synonym'},
    {knowledge_node_id:'n_geo_region_murcia',name:'Region of Murcia',kind:'synonym'},
    {knowledge_node_id:'n_geo_castilla_la_mancha',name:'Castilla–La Mancha',kind:'synonym'},
    {knowledge_node_id:'n_geo_navarra_region',name:'Navarre (autonomous community)',kind:'synonym'},
    {knowledge_node_id:'n_geo_north_island',name:'Te Ika-a-Māui',kind:'synonym'},
    {knowledge_node_id:'n_geo_south_island',name:'Te Waipounamu',kind:'synonym'},
  ],
  knowledge_relations:rows.map(([id,,country])=>({subject_id:`n_geo_${id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${country}`,valid_from:'1900-01-01'})),
  knowledge_items:rows.map(r=>({id:item(r[0]),subject_id:`n_geo_${r[0]}`,relation_type:'LOCATED_IN',object_id:`n_geo_${r[2]}`,domain_id:'geography',assertion_text:assertion(r),verification_status:'unverified',last_verified_at:'2026-09-26T18:00:00.000Z'})),
  certification_knowledge_mappings:rows.flatMap(([id])=>['WSET_L3','CMS_CERTIFIED'].map(cert=>({certification_id:cert,knowledge_item_id:item(id),importance:'secondary',minimum_depth:2}))),
  source_citations:sources,
  knowledge_item_citations:rows.map(([id,,,,source,locator])=>({knowledge_item_id:item(id),source_citation_id:source,locator})),
};
dataset.knowledge_item_citations.push({knowledge_item_id:item('olifants_river_wine'),source_citation_id:'src_diploma_za_olifants',locator:'Olifants River: wine region incorporates Vredendal and Spruitdrift wards; named reference locality'});
const pointPath='tool/geography/diploma_regions_points.geojson';
fs.writeFileSync('assets/curriculum/areas/diploma_regions.yaml','# Ten bounded macro-region geography additions; not complete Diploma coverage.\n# Administrative regions, islands and wine areas are distinguished in assertions.\n# Exact CC0 reference points are not boundaries; all facts await qualified review.\n'+YAML.stringify(dataset));
fs.writeFileSync(pointPath,JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
console.log(JSON.stringify({nodes:10,items:10,mappings:20,features:10,snapshot_sha256:sha(fs.readFileSync(pointPath)),markers:features.map(f=>[f.properties.node_id,f.properties.wikidata_id,f.properties.point_place_name])},null,2));
