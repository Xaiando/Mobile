// Audit and reproduce the additive Australian / South African atlas completion.
// Run from the repository root. Legal facts and reusable marker geometry have separate sources.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import sevenZip from '7zip-bin';
import YAML from 'yaml';
const date='2026-09-26';
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const normal=s=>s.replace(/\([^)]*\)/g,'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const slug=s=>s.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_|_$/g,'');
const own='new_world_oceania_africa.yaml';
const docs=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')&&f!==own).map(f=>YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')));
const nodes=docs.flatMap(d=>d.knowledge_nodes??[]);
const parents=new Map(docs.flatMap(d=>d.knowledge_relations??[]).filter(r=>r.relation_type==='LOCATED_IN').map(r=>[r.subject_id,r.object_id]));
const countryOf=n=>{let id=n.id;const seen=new Set();while(parents.has(id)&&!seen.has(id)){seen.add(id);id=parents.get(id);}return id;};
const auKnown=new Map(nodes.filter(n=>countryOf(n)==='n_geo_australia').map(n=>[normal(n.name),n.id]));
const existingIds=new Set(nodes.map(n=>n.id));
const specs=[],sources=[],features=[],wikiFeatures=[],geonamesFeatures=[];
const add=s=>{if(existingIds.has(s.id)||specs.some(x=>x.id===s.id))throw Error(`Duplicate ${s.id}`);specs.push(s);return s;};
const stateIds={SA:'n_geo_south_australia',NSW:'n_geo_new_south_wales',VIC:'n_geo_victoria',WA:'n_geo_western_australia',TAS:'n_geo_tasmania',QLD:'n_geo_au_queensland_zone'};
const regionZone={
  'Granite Belt':'Queensland','South Burnett':'Queensland','Perricoota':'Big Rivers','Cowra':'Central Ranges','Hastings River':'Northern Rivers','New England Australia':'Northern Slopes','Shoalhaven Coast':'South Coast','Southern Highlands':'South Coast','Gundagai':'Southern New South Wales','Hilltops':'Southern New South Wales',
  'Peel':'Greater Perth','Perth Hills':'Greater Perth','Blackwood Valley':'South West Australia','Geographe':'South West Australia','Manjimup':'South West Australia',
  'Upper Goulburn':'Central Victoria','Sunbury':'Port Phillip','Strathbogie Ranges':'Central Victoria','Pyrenees':'Western Victoria','Henty':'Western Victoria','Glenrowan':'North East Victoria','Bendigo':'Central Victoria','Beechworth':'North East Victoria','Alpine Valleys':'North East Victoria',
  'Adelaide Plains':'Mount Lofty Ranges','Currency Creek':'Fleurieu','Kangaroo Island':'Fleurieu','Mount Benson':'Limestone Coast','Mount Gambier':'Limestone Coast','Robe':'Limestone Coast','Southern Fleurieu':'Fleurieu','Southern Flinders Ranges':'Far North',
};
const gisItem='2dd4c385f0ed4d109c2e18ae99e819e2';
const service='https://services6.arcgis.com/s8j6JbJJCqmhNgh7/arcgis/rest/services/Wine_Geographical_Indications_Australia/FeatureServer';
// Download missing authoring inputs, retaining the exact edition used below.
// Changed upstream editions must be reviewed instead of silently rewriting pinned provenance.
fs.mkdirSync('.dart_tool',{recursive:true});
async function input(path,url,expected){
  if(!fs.existsSync(path)){
    const r=await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.13 geography authoring'},signal:AbortSignal.timeout(180000)});
    if(!r.ok)throw Error(`Source download ${r.status}: ${url}`);
    const b=Buffer.from(await r.arrayBuffer());
    if(expected&&sha(b)!==expected)throw Error(`Upstream edition changed: ${url}; review and re-pin before regeneration`);
    fs.writeFileSync(path,b);
  }
  const b=fs.readFileSync(path);
  if(expected&&sha(b)!==expected)throw Error(`Authoring cache hash mismatch: ${path}`);
  return b;
}
await input('.dart_tool/nwoa_wine_australia_metadata.json',`https://www.arcgis.com/sharing/rest/content/items/${gisItem}?f=pjson`);
const rawHashes={0:'67f9179d90cf09e26ccf5f1af0aff2e592fec828f131da0a5c852a079b8c9adb',1:'16ef048525b09b0127f79bf7e3bdbe351677f7e9be8e5016d9766fe45190f719',2:'84601bcde0f164d5a3ab2a51bbe289d17434ed4cbe1873df07c2044cdee7a9f4'};
for(const layer of [0,1,2]){
  const q=new URLSearchParams({where:'1=1',outFields:'*',returnGeometry:'true',outSR:'4326',f:'geojson'});
  await input(`.dart_tool/nwoa_wine_australia_${layer}.geojson`,`${service}/${layer}/query?${q}`,rawHashes[layer]);
}
const gnPath='.dart_tool/new_world_geonames_ZA/ZA.txt';
if(!fs.existsSync(gnPath)){
  fs.mkdirSync('.dart_tool/new_world_geonames_ZA',{recursive:true});
  await input('.dart_tool/nwoa_geonames_ZA.zip','https://download.geonames.org/export/dump/ZA.zip','b36fb219f4baf95c7c1a44c7a9380bf513be3f9e8bd6dbbb5f616009ef447005');
  execFileSync(sevenZip.path7za,['x','-y','.dart_tool/nwoa_geonames_ZA.zip','-o.dart_tool/new_world_geonames_ZA','ZA.txt'],{stdio:'pipe'});
}
await input(gnPath,'https://download.geonames.org/export/dump/ZA.zip','65ab612c4c2ef21c25e6dc33ce0c9714d38fe9e777e36412c478166f1e543be8');
const metadata=JSON.parse(fs.readFileSync('.dart_tool/nwoa_wine_australia_metadata.json','utf8'));
const licence=(metadata.licenseInfo??'').replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
if(metadata.owner!=='WineAustralia'||!/^CC BY \(Attribution\) 4\.0\b/.test(licence)||/BY-SA|Share.?Alike|non.?commercial|internal use/i.test(licence))throw Error('Official GIS owner/licence not confirmed');
const inventories={};
for(const layer of [0,1,2]){
  const bytes=fs.readFileSync(`.dart_tool/nwoa_wine_australia_${layer}.geojson`);
  const collection=JSON.parse(bytes);inventories[layer]=collection.features;
  if(collection.exceededTransferLimit)throw Error('Incomplete official GIS response');
  if(layer===0)continue; // All fourteen registered subregions were already represented.
  for(const f of collection.features){
    const p=f.properties;const key=normal(p.GI_NAME);if(auKnown.has(key))continue;
    const kind=layer===1?'region':'zone';const name=p.GI_NAME==='Mclaren Vale'?'McLaren Vale':p.GI_NAME;
    const id=`n_geo_au_${slug(name)}_${kind}`;
    const s=add({id,name:kind==='zone'?`${name} (zone)`:name,type:kind==='region'?'appellation':'region',country:'n_geo_australia',kind:`Australian wine GI ${kind}`,source:'src_atlas_au_gis',locator:`Register: ${name}, ${kind}; state ${p.STATE}; current national table and footnotes`,gis:f,layer,sourceBytesHash:sha(bytes)});
    auKnown.set(key,id);
  }
}
for(const s of specs){
  const p=s.gis.properties;
  if(s.layer===2)s.parent=p.GI_NAME==='Queensland'?'n_geo_australia':stateIds[p.STATE];
  else s.parent=['Murray Darling','Swan Hill'].includes(p.GI_NAME)?'n_geo_australia':auKnown.get(normal(regionZone[p.GI_NAME]??''))??stateIds[p.STATE];
  if(!s.parent)throw Error(`Missing primary-supported parent ${s.name}`);
}
// Three register entries absent from the polygon service are sourced reference markers.
for(const [id,name,parent,title,kind]of[
  ['n_geo_au_adelaide_super_zone','Adelaide (super zone)','n_geo_south_australia','Adelaide','Australian wine GI super zone'],
  ['n_geo_au_northern_territory','Northern Territory','n_geo_australia','Northern Territory','Australian wine GI state/territory'],
  ['n_geo_au_australian_capital_territory','Australian Capital Territory','n_geo_australia','Australian Capital Territory','Australian wine GI state/territory'],
])add({id,name,parent,title,type:'region',country:'n_geo_australia',kind,source:'src_atlas_au_gis',locator:`Register entry ${name}; listed in national geographical-indication register`,qualified:id==='n_geo_au_adelaide_super_zone'});

// IDs, legal names, canonical node type, containing legal unit, sourced reference entity.
const saRows=`
greater_cape|Greater Cape|region|south_africa|Beaufort West
cape_coast|Cape Coast|region|western_cape|Caledon, South Africa
cape_west_coast|Cape West Coast|subregion|coastal_region|Lambert's Bay
northern_cape|Northern Cape|region|south_africa|Northern Cape
eastern_cape|Eastern Cape|region|south_africa|Eastern Cape
kwazulu_natal|KwaZulu-Natal|region|south_africa|KwaZulu-Natal
free_state|Free State|region|south_africa|Free State (province)
limpopo|Limpopo|region|south_africa|Limpopo
north_west|North West|region|south_africa|North West (South African province)
karoo_hoogland|Karoo-Hoogland|region|za_northern_cape|Karoo Hoogland Local Municipality
lower_duivenhoks_river|Lower Duivenhoks River|appellation|cape_south_coast|Heidelberg, Western Cape
plettenberg_bay|Plettenberg Bay|appellation|cape_south_coast|Plettenberg Bay
swellendam|Swellendam|appellation|cape_south_coast|Swellendam
still_bay|Still Bay|appellation|cape_south_coast|Still Bay
lutzville_valley|Lutzville Valley|appellation|coastal_region|Lutzville
langeberg_garcia|Langeberg-Garcia|appellation|klein_karoo_wine|Garcia's Pass
citrusdal_mountain|Citrusdal Mountain|appellation|olifants_river_wine|Piekenierskloof Pass
citrusdal_valley|Citrusdal Valley|appellation|olifants_river_wine|Citrusdal
ceres_plateau|Ceres Plateau|appellation|western_cape|Ceres, South Africa
nuveld_karoo|Nuveld-Karoo|appellation|western_cape|Nuweveld Mountains
prince_albert|Prince Albert|appellation|western_cape|Prince Albert, South Africa
sutherland_karoo|Sutherland-Karoo|appellation|za_karoo_hoogland|Sutherland, South Africa
central_orange_river|Central Orange River|appellation|za_northern_cape|Upington
douglas|Douglas|appellation|za_northern_cape|Douglas, South Africa
central_drakensberg|Central Drakensberg|appellation|za_kwazulu_natal|Winterton, South Africa
lions_river|Lions River|appellation|za_kwazulu_natal|Lions River
cederberg|Cederberg|subregion|western_cape|Cederberg
nieuwoudtville|Nieuwoudtville|subregion|western_cape|Nieuwoudtville
piekenierskloof|Piekenierskloof|subregion|za_citrusdal_mountain|Piekenierskloof
slanghoek|Slanghoek|subregion|breedekloof|Slanghoek
goudini|Goudini|subregion|breedekloof|Goudini
simonsberg_paarl|Simonsberg-Paarl|subregion|paarl|Simonsberg-Paarl
agter_paarl|Agter-Paarl|subregion|paarl|Agter-Paarl
voor_paardeberg|Voor-Paardeberg|subregion|paarl|Voor-Paardeberg
malmesbury|Malmesbury|subregion|swartland|Malmesbury, South Africa
paardeberg|Paardeberg|subregion|swartland|Paardeberg
porseleinberg|Porseleinberg|subregion|swartland|Porseleinberg
riebeekberg|Riebeekberg|subregion|swartland|Riebeekberg
riebeeksrivier|Riebeeksrivier|subregion|swartland|Riebeeksrivier
groenekloof|Groenekloof|subregion|darling_wine|Groenekloof
koekenaap|Koekenaap|subregion|za_lutzville_valley|Koekenaap
vredendal|Vredendal|subregion|olifants_river_wine|Vredendal
spruitdrift|Spruitdrift|subregion|olifants_river_wine|Spruitdrift
sundays_glen|Sunday's Glen|subregion|walker_bay|Sondagskloof
stanford_foothills|Stanford Foothills|subregion|walker_bay|Stanford, South Africa
malgas|Malgas|subregion|za_swellendam|Malgas
montagu|Montagu|subregion|klein_karoo_wine|Montagu, South Africa
tradouw|Tradouw|subregion|klein_karoo_wine|Barrydale
tradouw_highlands|Tradouw Highlands|subregion|klein_karoo_wine|Tradouw Highlands
`.trim().split('\n').map(r=>r.trim().split('|'));
const wardReferences=JSON.parse(fs.readFileSync('tool/geography/new_world_oceania_africa_ward_references.json','utf8'));
for(const r of wardReferences)saRows.push([r.suffix,r.name,'subregion',r.parent,r.title??r.name]);
for(const [suffix,name,type,parent,title]of saRows){
  const id=`n_geo_za_${suffix}`;
  const kind=type==='appellation'?'Wine of Origin district':type==='subregion'?suffix==='cape_west_coast'?'Wine of Origin subregion':'Wine of Origin ward':suffix==='greater_cape'?'overarching geographical unit':suffix==='cape_coast'?'overarching Wine of Origin region':suffix==='karoo_hoogland'?'Wine of Origin region':'Wine of Origin geographical unit';
  add({id,name,type,parent:`n_geo_${parent}`,country:'n_geo_south_africa',title,kind,source:'src_atlas_za_wo_2026',locator:`February 2026 production-area table: ${name}; ${kind}; listed containing geographical unit/region/district`,qualified:true});
}

function inRing(p,r){let inside=false;for(let i=0,j=r.length-1;i<r.length;j=i++){const a=r[i],b=r[j];if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])inside=!inside;}return inside;}
function inside(p,g){const polys=g.type==='Polygon'?[g.coordinates]:g.coordinates;return polys.some(poly=>inRing(p,poly[0])&&!poly.slice(1).some(r=>inRing(p,r)));}
function interior(g){let best;for(const poly of g.type==='Polygon'?[g.coordinates]:g.coordinates){const lo=poly[0].reduce((v,p)=>Math.min(v,p[1]),Infinity),hi=poly[0].reduce((v,p)=>Math.max(v,p[1]),-Infinity);for(let i=1;i<64;i++){const y=lo+(hi-lo)*i/64,xs=[];for(const ring of poly)for(let j=0;j<ring.length-1;j++){const a=ring[j],b=ring[j+1];if((a[1]>y)!==(b[1]>y))xs.push(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]));}xs.sort((a,b)=>a-b);for(let j=0;j<xs.length-1;j++){const p=[(xs[j]+xs[j+1])/2,y],width=xs[j+1]-xs[j];if((!best||width>best.width)&&inRing(p,poly[0])&&!poly.slice(1).some(r=>inRing(p,r)))best={p,width};}}}if(!best)throw Error('No verified interior point');return best.p;}
for(const s of specs.filter(s=>s.gis)){
  const f=s.gis,p=f.properties,coordinates=interior(f.geometry);
  if(!inside(coordinates,f.geometry))throw Error(`Outside source polygon ${s.name}`);
  features.push({type:'Feature',properties:{node:s.id,node_id:s.id,name:s.name,parent_node_id:s.parent,country_node_id:s.country,point_role:'source_polygon_interior_reference_point',point_place_name:p.GI_NAME,source_url:`${service}/${s.layer}/query?where=GI_NUMBER%3D${p.GI_NUMBER}&outFields=*&outSR=4326&f=geojson`,source_coordinate_url:`${service}/${s.layer}/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson`,source_item_id:gisItem,source_layer_id:s.layer,source_feature_id:f.id??p.OBJECTID??p.OBJECTID_1,source_gi_number:p.GI_NUMBER,source_file_sha256:s.sourceBytesHash,source_metadata_sha256:sha(fs.readFileSync('.dart_tool/nwoa_wine_australia_metadata.json')),source_gi_url:p.GI_URL?.trim(),derivation:'widest verified interior horizontal scanline interval midpoint; 63 evenly spaced scanlines per polygon; holes excluded',retrieved_on:date,license:'CC-BY-4.0',attribution:'Geographical Indications of Australia, © Wine Australia, CC BY 4.0; reference marker derived from official openly licensed GIS polygon.',label_note:'Reference marker inside the official Wine Australia GIS representation. It is not the legal boundary or an official centroid; the textual GI definition takes precedence.'},geometry:{type:'Point',coordinates}});
}
const cache='.dart_tool/nwoa_wikidata_entities.json';
// Explicit national-gazetteer references resolve absent P625 claims; no location is invented.
// IDs were checked against the ZA national export, including province and feature class.
const gazetteerIds={
  n_geo_za_cape_west_coast:'3364847', // Precise Lamberts Bay town point; coarse P625 was outside the simplified country coast.
  n_geo_za_citrusdal_mountain:'3362893', // Piekenierskloof pass, Western Cape.
  n_geo_za_nuveld_karoo:'968879', // Nuweveldberge mountain range, Western Cape.
  n_geo_za_piekenierskloof:'3362894', // Named Piekenierskloof farm, near the pass.
  n_geo_za_slanghoek:'3361469', // Slanghoek populated place, Breede Valley.
  n_geo_za_goudini:'3367548', // Goudini Spa locality, Breede Valley.
  n_geo_za_simonsberg_paarl:'3361622', // Simonsberg terrain reference, not the ward centroid.
  n_geo_za_agter_paarl:'3359354', // Windmeul locality; producer address confirms Agter-Paarl.
  n_geo_za_voor_paardeberg:'3362943', // Perdeberg mountain; producer confirms Voor-Paardeberg slopes.
  n_geo_za_paardeberg:'3361095', // Staart van Paardeberg hill, Swartland reference.
  n_geo_za_porseleinberg:'3362715', // Named Porseleinberg mountain, Swartland.
  n_geo_za_riebeekberg:'3366070', // Kasteelberg mountain, Riebeek valley terrain reference.
  n_geo_za_riebeeksrivier:'3362483', // Named Riebeeksrivier farm, Swartland.
  n_geo_za_groenekloof:'3364342', // Mamreweg station by the Darling Cellars reference locality.
  n_geo_za_spruitdrift:'3361104', // Named Spruitdrif farm, Olifants River area.
  n_geo_za_sundays_glen:'3361365', // Sondagskloof river reference, not river/wine-area geometry.
  n_geo_za_tradouw_highlands:'967674', // Op de Tradouw farm reference, not a legal centroid.
};
const wardById=new Map(wardReferences.map(r=>[`n_geo_za_${r.suffix}`,r]));
for(const [id,r]of wardById)if(r.geonames_id)gazetteerIds[id]=r.geonames_id;
let entityResponse=fs.existsSync(cache)?JSON.parse(fs.readFileSync(cache,'utf8')):{entities:{}};
const titles=[...new Set(specs.filter(s=>!s.gis&&!gazetteerIds[s.id]).map(s=>s.title))].filter(t=>!Object.values(entityResponse.entities).some(e=>e.sitelinks?.enwiki?.title===t));
for(let i=0;i<titles.length;i+=40){const u=new URL('https://www.wikidata.org/w/api.php');Object.entries({action:'wbgetentities',sites:'enwiki',titles:titles.slice(i,i+40).join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>u.searchParams.set(k,v));const r=await fetch(u,{headers:{'User-Agent':'SommelierStudyCompanion/0.13 geography authoring'},signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error(`Wikidata ${r.status}`);const d=await r.json();if(d.error)throw Error(JSON.stringify(d.error));Object.assign(entityResponse.entities,d.entities);fs.writeFileSync(cache,JSON.stringify(entityResponse,null,2)+'\n');}
const missing=[];
for(const s of specs.filter(s=>!s.gis)){
  if(gazetteerIds[s.id]){
    const bytes=fs.readFileSync('.dart_tool/new_world_geonames_ZA/ZA.txt');
    const row=bytes.toString().split('\n').find(r=>r.startsWith(`${gazetteerIds[s.id]}\t`))?.split('\t');
    if(!row||row[8]!=='ZA')throw Error(`Missing checked GeoNames row ${s.id}`);
    const checkedWard=wardById.get(s.id);
    geonamesFeatures.push({type:'Feature',properties:{node:s.id,node_id:s.id,name:s.name,parent_node_id:s.parent,country_node_id:s.country,point_role:'qualified_locality_or_terrain_reference_point',point_place_name:row[1],source_url:`https://www.geonames.org/${row[0]}/`,source_coordinate_url:'https://download.geonames.org/export/dump/ZA.zip',source_file_sha256:sha(bytes),geonames_id:row[0],geonames_feature_class:row[6],geonames_feature_code:row[7],geonames_admin1_code:row[10],geonames_modified_on:row[18],retrieved_on:date,license:'CC-BY-4.0',attribution:'Contains GeoNames ZA national geographical data, CC BY 4.0. Selected WGS84 locality/terrain references; no boundaries derived.',label_note:`Qualified reference: ${row[1]} (${row[7]}). The named locality or nearby terrain feature provides orientation; it does not prove the precise legal wine-area extent or an official centroid.`,...(checkedWard?{reference_qualification:checkedWard.qualification,...(checkedWard.context_url?{reference_context_url:checkedWard.context_url}:{})}:{})},geometry:{type:'Point',coordinates:[Number(row[5]),Number(row[4])]}});
    continue;
  }
  const e=Object.values(entityResponse.entities).find(e=>e.sitelinks?.enwiki?.title===s.title);
  const candidates=e?.claims?.P625?.filter(c=>c.rank!=='deprecated'&&c.mainsnak.datavalue?.value.globe==='http://www.wikidata.org/entity/Q2')??[];
  const c=candidates.find(c=>c.rank==='preferred')??candidates[0];
  if(!c){missing.push({id:s.id,name:s.name,title:s.title});continue;}
  const p=c.mainsnak.datavalue.value;
  wikiFeatures.push({type:'Feature',properties:{node:s.id,node_id:s.id,name:s.name,parent_node_id:s.parent,country_node_id:s.country,point_role:s.qualified?'qualified_locality_or_terrain_reference_point':'gazetteer_reference_point',point_place_name:e.labels?.en?.value??s.title,point_description:e.descriptions?.en?.value??'',source_url:`https://www.wikidata.org/wiki/${e.id}`,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${e.id}.json`,wikidata_id:e.id,wikidata_coordinate_claim:c.id,source_entity_sha256:sha(JSON.stringify(e)),coordinate_precision:p.precision,retrieved_on:date,license:'CC0-1.0',label_note:`Reference location: ${s.title}. This qualified named locality, administrative area or terrain reference provides orientation; it is not the wine-area boundary or an official centroid.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}});
}
fs.writeFileSync('.dart_tool/nwoa_missing_points.json',JSON.stringify(missing,null,2)+'\n');
if(missing.length){console.log('Resolve unsourced reference markers before writing: '+JSON.stringify(missing,null,2));process.exitCode=1;}
else{
  // A source reference still needs to be visible inside its bundled country frame.
  const topo=JSON.parse(fs.readFileSync('assets/geography/world_countries.topo.json','utf8'));
  function decodeArc(index){let x=0,y=0;const a=topo.arcs[index<0?~index:index].map(p=>{x+=p[0];y+=p[1];return[x*topo.transform.scale[0]+topo.transform.translate[0],y*topo.transform.scale[1]+topo.transform.translate[1]];});return index<0?a.reverse():a;}
  function decodeRing(ids){return ids.flatMap((id,i)=>i?decodeArc(id).slice(1):decodeArc(id));}
  const countryPolys={};for(const g of topo.objects.world_countries.geometries.filter(g=>['n_geo_australia','n_geo_south_africa'].includes(g.id)))countryPolys[g.id]=(g.type==='Polygon'?[g.arcs]:g.arcs).map(poly=>poly.map(decodeRing));
  const outside=[];
  for(const f of [...features,...wikiFeatures,...geonamesFeatures])for(const p of [f.geometry.coordinates,f.geometry.coordinates.map(x=>Math.round(x*1e6)/1e6)])if(!countryPolys[f.properties.country_node_id].some(poly=>inRing(p,poly[0])&&!poly.slice(1).some(r=>inRing(p,r))))outside.push({node_id:f.properties.node_id,coordinates:p});
  if(outside.length)throw Error(`Source markers outside displayed country: ${JSON.stringify(outside)}`);
  const allNames=new Map([...nodes.map(n=>[n.id,n.name]),...specs.map(s=>[s.id,s.name])]);
  for(const s of specs)if(!allNames.has(s.parent))throw Error(`Missing containing node ${s.name}: ${s.parent}`);
  const item=s=>`ki_nwoa_${s.id.replace(/^n_geo_/,'')}_location`;
  const dataset={knowledge_nodes:specs.map(s=>({id:s.id,node_type:s.type,name:s.name})),knowledge_relations:specs.map(s=>({subject_id:s.id,relation_type:'LOCATED_IN',object_id:s.parent,valid_from:'1900-01-01'})),knowledge_items:specs.map(s=>({id:item(s),subject_id:s.id,relation_type:'LOCATED_IN',object_id:s.parent,domain_id:'geography',assertion_text:`${s.name} is ${/^[aeiou]/i.test(s.kind)?'an':'a'} ${s.kind} in ${allNames.get(s.parent)}${s.country==='n_geo_south_africa'?' under the Wine of Origin production-area hierarchy':''}.`,verification_status:'unverified',last_verified_at:'2026-09-26T18:00:00.000Z'})),certification_knowledge_mappings:specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(c=>({certification_id:c,knowledge_item_id:item(s),importance:'secondary',minimum_depth:2}))),knowledge_item_citations:specs.map(s=>({knowledge_item_id:item(s),source_citation_id:s.source,locator:s.locator}))};
  if(sources.length)dataset.source_citations=sources;
  fs.writeFileSync(`assets/curriculum/areas/${own}`,'# Additive register-driven Australian / South African atlas completion.\n# Track mappings are editorial; all facts await expert review.\n# Marker snapshots retain licence and coordinate provenance; no boundaries are invented.\n'+YAML.stringify(dataset));
  for(const [suffix,rows]of[['au_gis',features],['reference',wikiFeatures],['gazetteer',geonamesFeatures]])if(rows.length)fs.writeFileSync(`tool/geography/new_world_oceania_africa_${suffix}_points.geojson`,JSON.stringify({type:'FeatureCollection',features:rows},null,2)+'\n');
  console.log(JSON.stringify({nodes:specs.length,AU:specs.filter(s=>s.country==='n_geo_australia').length,ZA:specs.filter(s=>s.country==='n_geo_south_africa').length,types:Object.fromEntries(['region','appellation','subregion'].map(t=>[t,specs.filter(s=>s.type===t).length])),markers:features.length+wikiFeatures.length+geonamesFeatures.length,hashes:Object.fromEntries(['au_gis','reference','gazetteer'].filter(s=>fs.existsSync(`tool/geography/new_world_oceania_africa_${s}_points.geojson`)).map(s=>[s,sha(fs.readFileSync(`tool/geography/new_world_oceania_africa_${s}_points.geojson`))]))},null,2));
}
