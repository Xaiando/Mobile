// Additive Americas atlas authoring. Run from repository root with --author.
// Ordinary builds consume the checked-in licensed marker snapshots offline.
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';

const retrieved = '2026-09-26';
const commit = '7af5b29d45aee5e6c6ce3889e9b1de19085d7107';
const aggregateSha = 'c90068f7154764519f0a7c6fb2788e597b7c56bf7581e8c0faa979554d984926';
const curriculumPath = 'assets/curriculum/areas/new_world_americas.yaml';
const pointPath = 'tool/geography/new_world_americas_points.geojson';
const gazetteerPath = 'tool/geography/new_world_americas_gazetteer_points.geojson';
const wikiCache = '.dart_tool/new_world_americas_entities.json';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const rawUrl = `https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas_aggregated_files/avas.geojson`;
const registerUrl = 'https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/established-avas';
const source = (id,kind,title,publisher,jurisdiction,url) => ({id,kind,title,publisher,jurisdiction,url,accessed_on:retrieved});
const sources = [
 source('src_nwa_ca_bc','legislation','Wines of Marked Quality Regulation, BC Reg. 168/2018, section 56','Government of British Columbia','CA','https://www.bclaws.gov.bc.ca/civix/document/id/complete/statreg/168_2018/'),
 source('src_nwa_ca_on','regulator_register','Ontario appellations: Niagara regional and sub-appellations','Ontario Wine Appellation Authority','CA','https://vqaontario.ca/ontario-appellations/niagara-peninsula/'),
 source('src_nwa_ca_on_west','regulator_register','West Niagara regional appellation, recognised 2024','Ontario Wine Appellation Authority','CA','https://vqaontario.ca/ontario-appellations/niagara-peninsula/west-niagara/'),
 source('src_nwa_ca_on_south','regulator_register','South Islands sub-appellation, Lake Erie North Shore','Ontario Wine Appellation Authority','CA','https://vqaontario.ca/ontario-appellations/lake-erie-north-shore/south-islands/'),
 source('src_nwa_ar_provinces','government_publication','Provinces of Argentina','Government of Argentina','AR','https://www.argentina.gob.ar/pais/provincias'),
 source('src_nwa_ar_register','regulator_register','Recognised and protected Argentine wine IG/DOC register, linked from the INV protection-of-origin page','Instituto Nacional de Vitivinicultura','AR','https://www.argentina.gob.ar/sites/default/files/i.g._y_d.o.c._de_la_republica_argentina_1.pdf'),
 source('src_nwa_cl_decree','legislation','Decree 464: wine geography, consolidated version 14 July 2026','Ministry of Agriculture / Biblioteca del Congreso Nacional de Chile','CL','https://www.bcn.cl/leychile/Navegar/imprimir?idNorma=13601&idVersion=2026-07-14'),
 source('src_nwa_cl_2018','legislation','Decree 56: amended viticultural zones and named wine areas','Ministry of Agriculture / Biblioteca del Congreso Nacional de Chile','CL','https://www.bcn.cl/leychile/navegar?i=1118954'),
 source('src_nwa_cl_2025','legislation','Decree 27: Austral subregions and Rapa Nui area','Ministry of Agriculture / Diario Oficial de Chile','CL','https://www.diariooficial.interior.gob.cl/publicaciones/2025/05/14/44148/01/2643653.pdf'),
 source('src_nwa_us_columbia_hills','legislation','27 CFR §9.301: Columbia Hills AVA; T.D. TTB-206, effective 16 September 2026','Alcohol and Tobacco Tax and Trade Bureau / Federal Register','US','https://www.govinfo.gov/content/pkg/FR-2026-08-17/pdf/2026-16701.pdf'),
];
const specs=[];
const add=(country,source,rows)=>{
 for(const line of rows.trim().split('\n')){
  const[id,name,type,parent,title,site='enwiki',geonames]=line.trim().split('|');
  specs.push({id,name,type,parent,title,site,country,source,geonames:geonames?Number(geonames):null});
 }
};
// Existing Ontario's three main appellations remain unchanged. Regional groups
// overlap, so all ten Niagara sub-appellations use fully containing Peninsula.
add('canada','src_nwa_ca_on',`
niagara_escarpment_ontario|Niagara Escarpment (Ontario regional appellation)|appellation|niagara_peninsula|Rockway|enwiki|6126530
niagara_on_the_lake_appellation|Niagara-on-the-Lake (regional appellation)|appellation|niagara_peninsula|Niagara-On-The-Lake|enwiki|13680267
beamsville_bench|Beamsville Bench|subregion|niagara_peninsula|Beamsville|enwiki|5895710
twenty_mile_bench|Twenty Mile Bench|subregion|niagara_peninsula|Vineland|enwiki|6174406
short_hills_bench|Short Hills Bench|subregion|niagara_peninsula|Short Hills|enwiki|6147056
st_davids_bench|St. David’s Bench|subregion|niagara_peninsula|St. Davids|enwiki|6155789
lincoln_lakeshore|Lincoln Lakeshore|subregion|niagara_peninsula|Vineland Station|enwiki|6174407
niagara_lakeshore|Niagara Lakeshore|subregion|niagara_peninsula|Mississauga Point|enwiki|6075361
niagara_river_ontario|Niagara River (Ontario sub-appellation)|subregion|niagara_peninsula|Niagara-on-the-Lake|enwiki|6087905
four_mile_creek|Four Mile Creek|subregion|niagara_peninsula|Virgil|enwiki|6174462
creek_shores|Creek Shores|subregion|niagara_peninsula|Jordan Station|enwiki|5987916
vinemount_ridge|Vinemount Ridge|subregion|niagara_peninsula|Fonthill|enwiki|5955278
`);
add('canada','src_nwa_ca_on_west',`west_niagara|West Niagara|appellation|niagara_peninsula|Jordan Harbour|enwiki|5987884`);
add('canada','src_nwa_ca_on_south',`south_islands_ontario|South Islands|subregion|lake_erie_north_shore|Pelee Island|enwiki|6100621`);
// Section 56 explicitly names each of the twelve BC subdivisions and parent.
add('canada','src_nwa_ca_bc',`
fraser_valley_wine|Fraser Valley (wine GI)|appellation|british_columbia|Abbotsford|enwiki|5881791
gulf_islands_wine|Gulf Islands (wine GI)|appellation|british_columbia|Salt Spring Island|enwiki|12042098
lillooet_wine|Lillooet (wine GI)|appellation|british_columbia|Lillooet|enwiki|6945979
kootenays_wine|Kootenays (wine GI)|appellation|british_columbia|Creston|enwiki|5932311
shuswap_wine|Shuswap (wine GI)|appellation|british_columbia|Salmon Arm|enwiki|6139417
thompson_valley_wine|Thompson Valley (wine GI)|appellation|british_columbia|Kamloops|enwiki|5989045
vancouver_island_wine|Vancouver Island (wine GI)|appellation|british_columbia|Vancouver Island|enwiki|6173336
cowichan_valley_wine|Cowichan Valley (wine sub-GI)|subregion|vancouver_island_wine|Duncan|enwiki|5943865
east_kelowna_slopes|East Kelowna Slopes|subregion|okanagan_valley|East Kelowna|enwiki|5945769
golden_mile_slopes|Golden Mile Slopes|subregion|okanagan_valley|Oliver|enwiki|6093514
lake_country_wine|Lake Country (wine sub-GI)|subregion|okanagan_valley|Lake Country|enwiki|6048314
naramata_bench|Naramata Bench|subregion|okanagan_valley|Naramata|enwiki|8449722
okanagan_falls_wine|Okanagan Falls (wine sub-GI)|subregion|okanagan_valley|Okanagan Falls|enwiki|6092889
skaha_bench|Skaha Bench|subregion|okanagan_valley|Penticton|enwiki|6101141
south_kelowna_slopes|South Kelowna Slopes|subregion|okanagan_valley|Okanagan Mission|enwiki|6092896
summerland_bench|Summerland Bench|subregion|okanagan_valley|Summerland|enwiki|6159232
summerland_lakefront|Summerland Lakefront|subregion|okanagan_valley|Trout Creek|enwiki|6169289
summerland_valleys|Summerland Valleys|subregion|okanagan_valley|Garnet Valley|enwiki|5959722
`);
add('argentina','src_nwa_ar_provinces',`
catamarca|Catamarca|region|argentina|Catamarca Province
la_rioja_argentina|La Rioja (Argentina)|region|argentina|La Rioja Province, Argentina
tucuman|Tucumán|region|argentina|Tucumán Province
jujuy|Jujuy|region|argentina|Jujuy Province
chubut|Chubut|region|argentina|Chubut Province
la_pampa|La Pampa|region|argentina|La Pampa Province
buenos_aires_province|Buenos Aires (province)|region|argentina|Buenos Aires Province
cordoba_argentina|Córdoba (Argentina)|region|argentina|Córdoba Province, Argentina
san_luis_argentina|San Luis (Argentina)|region|argentina|San Luis Province
entre_rios_argentina|Entre Ríos (Argentina)|region|argentina|Entre Ríos Province
`);
// Geographic containment from INV register's Departamento y Provincia column;
// multidepartment wine names keep the containing province or country.
add('argentina','src_nwa_ar_register',`
cuyo_wine|Cuyo (wine GI)|appellation|argentina|Mendoza, Argentina
valles_del_famatina|Valles del Famatina|appellation|la_rioja_argentina|Chilecito
valle_de_chanarmuyo|Valle de Chañarmuyo|appellation|la_rioja_argentina|Chañarmuyo|eswiki
tinogasta|Tinogasta|appellation|catamarca|Tinogasta
santa_maria_catamarca|Santa María (Catamarca)|appellation|catamarca|Santa María, Catamarca
belen_catamarca|Belén (Catamarca)|appellation|catamarca|Belén, Catamarca
tafi_wine|Tafí (wine GI)|appellation|tucuman|Tafí del Valle
quebrada_de_humahuaca|Quebrada de Humahuaca|appellation|jujuy|Quebrada de Humahuaca
valle_del_tulum|Valle del Tulum|appellation|san_juan_argentina|San Juan, Argentina
valle_de_zonda|Valle de Zonda|appellation|san_juan_argentina|Villa Basilio Nievas|enwiki|3832080
valle_de_calingasta|Valle de Calingasta|appellation|san_juan_argentina|Calingasta|enwiki|3863362
barreal|Barreal|appellation|valle_de_calingasta|Barreal|enwiki|3864688
cachi_wine|Cachi (wine GI)|appellation|salta|Cachi|enwiki|3863557
molinos_salta|Molinos (Salta)|appellation|salta|Molinos, Salta
san_carlos_salta|San Carlos (Salta)|appellation|salta|San Carlos, Salta
alto_valle_rio_negro|Alto Valle de Río Negro|appellation|rio_negro|General Roca|enwiki|3855065
anelo_wine|Añelo (wine GI)|appellation|neuquen|Añelo
trevelin_wine|Trevelin (wine GI)|appellation|chubut|Trevelin
chapadmalal_wine|Chapadmalal (wine GI)|appellation|buenos_aires_province|Colonia Chapadmalal|enwiki|3435335
villa_ventana_wine|Villa Ventana (wine GI)|appellation|buenos_aires_province|Villa Ventana|enwiki|7646806
colonia_caroya|Colonia Caroya|appellation|cordoba_argentina|Colonia Caroya|enwiki|3860801
victoria_entre_rios_wine|Victoria, Entre Ríos (wine GI)|appellation|entre_rios_argentina|Victoria, Entre Ríos
la_consulta|La Consulta|appellation|san_carlos_mendoza|La Consulta|eswiki
barrancas_maipu|Barrancas (Maipú)|appellation|maipu|Barrancas|enwiki|3864730
lunlunta|Lunlunta|appellation|maipu|Lunlunta|eswiki
distrito_medrano|Distrito Medrano|appellation|mendoza|Medrano|enwiki|3844473
lavalle_mendoza|Lavalle / Desierto de Lavalle|appellation|mendoza|Lavalle Department, Mendoza
san_martin_mendoza|San Martín (Mendoza)|appellation|mendoza|San Martín, Mendoza
rivadavia_mendoza|Rivadavia (Mendoza)|appellation|mendoza|Rivadavia, Mendoza
junin_mendoza|Junín (Mendoza)|appellation|mendoza|Junín|enwiki|3853355
general_alvear_mendoza|General Alvear (Mendoza)|appellation|mendoza|General Alvear, Mendoza
`);
add('chile','src_nwa_cl_decree',`
atacama_wine|Atacama (wine region)|region|chile|Atacama Region
copiapo_valley|Copiapó Valley|subregion|atacama_wine|Copiapó
huasco_valley|Huasco Valley|subregion|atacama_wine|Vallenar
teno_valley|Teno Valley|subregion|curico|Teno|enwiki|3869979
lontue_valley|Lontué Valley|subregion|curico|Molina, Chile
claro_valley|Claro Valley|subregion|maule|Talca
loncomilla_valley|Loncomilla Valley|subregion|maule|San Javier, Chile
tutuven_valley|Tutuvén Valley|subregion|maule|Cauquenes
pirque_wine|Pirque (wine area)|subregion|maipo|Pirque
puente_alto_wine|Puente Alto (wine area)|subregion|maipo|Puente Alto
buin_wine|Buin (wine area)|subregion|maipo|Buin|enwiki|3897774
isla_de_maipo_wine|Isla de Maipo (wine area)|subregion|maipo|Isla de Maipo
peumo_wine|Peumo (wine area)|subregion|cachapoal|Peumo
rancagua_wine|Rancagua (wine area)|subregion|cachapoal|Rancagua
requinoa_wine|Requínoa (wine area)|subregion|cachapoal|Requínoa
rengo_wine|Rengo (wine area)|subregion|cachapoal|Rengo
santa_cruz_chile_wine|Santa Cruz (Chilean wine area)|subregion|colchagua|Santa Cruz, Chile
palmilla_wine|Palmilla (wine area)|subregion|colchagua|Palmilla
peralillo_wine|Peralillo (wine area)|subregion|colchagua|Peralillo
lolol_wine|Lolol (wine area)|subregion|colchagua|Lolol
marchigue_wine|Marchigüe (wine area)|subregion|colchagua|Marchigüe
`);
add('chile','src_nwa_cl_2018',`
lo_abarca_wine|Lo Abarca (wine area)|subregion|san_antonio_valley|Lo Abarca|enwiki|3882820
apalta_wine|Apalta (wine area)|subregion|colchagua|Apalta
los_lingues_wine|Los Lingues (wine area)|subregion|colchagua|Los Lingues|enwiki|3881947
licanten_wine|Licantén (wine area)|subregion|curico|Licantén
`);
add('chile','src_nwa_cl_2025',`
austral_chile_wine|Austral (Chilean wine region)|region|chile|Temuco
cautin_valley|Cautín Valley|subregion|austral_chile_wine|Perquenco
osorno_valley|Osorno Valley|subregion|austral_chile_wine|Osorno, Chile
chiloe_wine|Chiloé (wine subregion)|subregion|austral_chile_wine|Chiloé Archipelago
rapa_nui_wine|Rapa Nui – Isla de Pascua (wine area)|subregion|chile|Easter Island
`);
// This AVA is newer than the pinned open community polygon collection.
// Preserve an exact CC0 named park reference rather than inventing a boundary.
add('united_states','src_nwa_us_columbia_hills',`columbia_hills|Columbia Hills|appellation|columbia_valley|Columbia Hills State Park`);
Object.assign(specs.at(-1),{cfr:'9.301',locator:'27 CFR §9.301; 91 FR 53191–53194, T.D. TTB-206, effective 16 September 2026; entirely within Columbia Valley',assertion:'Columbia Hills is an American viticultural area in Klickitat County, Washington, entirely within Columbia Valley. It became effective on 16 September 2026. Its marker is an exact published park reference, not the legal AVA boundary or its official centroid.'});

// Implementation helpers follow below. No authored files are changed until
// every legal parent and published marker has passed validation.
const oldFiles=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')&&f!=='new_world_americas.yaml');
const oldDocuments=oldFiles.map(f=>YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')));
const existingNodes=oldDocuments.flatMap(d=>d.knowledge_nodes??[]);
const existingSources=oldDocuments.flatMap(d=>d.source_citations??[]);
// Reuse already authored primary registers. This unreleased work may replace
// a duplicate citation draft with its existing canonical citation identity.
const duplicateCitationDrafts=new Map();
for(let i=sources.length-1;i>=0;i--) {
 const draft=sources[i],existing=existingSources.find(s=>s.url===draft.url);
 if(!existing)continue;
 duplicateCitationDrafts.set(draft.id,existing.id);
 for(const spec of specs)if(spec.source===draft.id){spec.source=existing.id;spec.source_origin=draft.id;}
 sources.splice(i,1);
}
const parents=new Map(oldDocuments.flatMap(d=>d.knowledge_relations??[]).filter(r=>r.relation_type==='LOCATED_IN').map(r=>[r.subject_id,r.object_id]));
function belongs(id,country){
 const seen=new Set();while(id&&!seen.has(id)){if(id===`n_geo_${country}`)return true;seen.add(id);id=parents.get(id);}return false;
}
function plain(html){return html.replace(/<\/(?:li|p)>/g,'; ').replace(/<[^>]*>/g,' ').replace(/&nbsp;/g,' ').replace(/&(?:ndash|mdash);/g,'-').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();}
const avaBytes=fs.readFileSync('.dart_tool/new_world_ava_aggregate.geojson');
if(sha(avaBytes)!==aggregateSha)throw Error('AVA source revision changed');
const avas=JSON.parse(avaBytes).features.filter(f=>!f.properties.removed);
const ttbHtml=fs.readFileSync('.dart_tool/new_world_ttb.html','utf8');
if(!ttbHtml.includes('August 18, 2026'))throw Error('Unexpected TTB edition');
const ttbRows=[];let registerSection=null;
for(const row of ttbHtml.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)){
 const stateHeader=row[0].match(/^<tr id="([^"]+)"><td colspan="5">/);if(stateHeader)registerSection=stateHeader[1];
 const cells=[...row[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(c=>plain(c[1]));
 if(cells.length>=5){cells.registerSection=registerSection;ttbRows.push(cells);}
}
const normalName=name=>name.toLowerCase().replace(/\([^)]*\)/g,'').replace(/[^a-z0-9]/g,'');
const usNodes=existingNodes.filter(n=>belongs(n.id,'united_states'));
const avaNode=new Map();
for(const f of avas){
 const id=f.properties.ava_id;
 const node=usNodes.find(n=>n.id===`n_geo_${id}`||normalName(n.name)===normalName(f.properties.name));
 if(node)avaNode.set(id,node.id);
}
const statesFor=f=>f.properties.state?.split('|').map(s=>s.trim()).map(s=>({California:'CA',Oregon:'OR',Washington:'WA'})[s]??s)??[];
const missingAvas=avas.filter(f=>statesFor(f).some(s=>['CA','OR','WA'].includes(s))&&!avaNode.has(f.properties.ava_id));
for(const f of missingAvas){
 let id=f.properties.ava_id.replace(/[^a-z0-9_]/g,'_').replace(/_+/g,'_');
 let name=f.properties.name.trim();
 if(existingNodes.some(n=>n.id===`n_geo_${id}`)){
  const qualifier=f.properties.state==='CA'?'california':'united_states';
  id+=`_${qualifier}`;name+=qualifier==='california'?' (California AVA)':' (US AVA)';
 }
 avaNode.set(f.properties.ava_id,`n_geo_${id}`);
 specs.push({id,ava:f.properties.ava_id,name,type:'appellation',country:'united_states'});
}
for(const s of specs.filter(s=>s.ava)){
 const f=avas.find(f=>f.properties.ava_id===s.ava);
 const row=ttbRows.find(r=>normalName(r[0])===normalName(s.name));
 if(!row)throw Error(`No exact-name TTB entry: ${s.name}`);
 s.cfr=row[4].match(/9\.\d+/)?.[0];
 if(!s.cfr||(f.properties.cfr_index&&f.properties.cfr_index!==s.cfr))throw Error(`Unexpected legal section for ${s.name}`);
 const states=statesFor(f);
 if(states.length===1){
  const stateName={CA:'California',OR:'Oregon',WA:'Washington'}[states[0]];
  // Single-state table column two contains counties; state is its section.
  if(row.registerSection!==stateName)throw Error(`State-register mismatch for ${s.name}: ${row.registerSection}`);
 }
 const fullParentEntries=row[2].split(';').map(p=>p.trim()).filter(p=>p&&!p.includes('*')).map(p=>p.replace(/◊/g,'').trim());
 const candidates=fullParentEntries.map(name=>avas.find(f=>normalName(f.properties.name)===normalName(name))).filter(f=>f&&avaNode.has(f.properties.ava_id));
 // All candidates are regulator-confirmed full containment. Prefer the one
 // whose own regulator row names the largest chain of containing AVAs.
 candidates.sort((a,b)=>{
  const depth=f=>ttbRows.find(r=>normalName(r[0])===normalName(f.properties.name))?.[2].split(';').filter(p=>p.trim()&&!p.includes('*')).length??0;
  return depth(b)-depth(a)||a.properties.ava_id.localeCompare(b.properties.ava_id);
 });
 s.parent=candidates.length?avaNode.get(candidates[0].properties.ava_id).slice(6):states.length===1?({CA:'california',OR:'oregon',WA:'washington'})[states[0]]:'united_states';
 s.source=`src_nwa_us_${s.id}`;
 sources.push(source(s.source,'legislation',`27 CFR §${s.cfr}: ${s.name} AVA`,'Alcohol and Tobacco Tax and Trade Bureau / eCFR','US',`https://www.ecfr.gov/current/title-27/section-${s.cfr}`));
 s.locator=`Defined geographical area in 27 CFR §${s.cfr}; exact-name TTB August 18, 2026 register entry, excluding partial-overlap parents`;
 s.assertion=states.length>1?`${s.name} is a multistate American viticultural area in the United States; the ${states.join('/')} state association does not imply exclusive containment in one state.`:null;
}
function pointInRing([x,y],ring){let inside=false;for(let i=0,j=ring.length-1;i<ring.length;j=i++){const[xi,yi]=ring[i],[xj,yj]=ring[j];if((yi>y)!==(yj>y)&&x<(xj-xi)*(y-yi)/(yj-yi)+xi)inside=!inside;}return inside;}
function pointInGeometry(point,geometry){const polygons=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;return polygons.some(p=>pointInRing(point,p[0])&&!p.slice(1).some(r=>pointInRing(point,r)));}
function interior(geometry){
 const polygons=geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;let best=null;
 for(const polygon of polygons){const ys=polygon[0].map(p=>p[1]),min=Math.min(...ys),max=Math.max(...ys);for(let i=1;i<64;i++){
  const y=min+(max-min)*i/64,xs=[];for(const ring of polygon)for(let j=0;j<ring.length-1;j++){const a=ring[j],b=ring[j+1];if((a[1]>y)!==(b[1]>y))xs.push(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]));}
  xs.sort((a,b)=>a-b);for(let j=0;j<xs.length-1;j++){const point=[(xs[j]+xs[j+1])/2,y],width=xs[j+1]-xs[j];if((!best||width>best.width)&&pointInGeometry(point,geometry))best={point,width};}
 }}if(!best||!pointInGeometry(best.point,geometry))throw Error('No verified polygon-interior marker');return best.point;
}
let entities=fs.existsSync(wikiCache)?JSON.parse(fs.readFileSync(wikiCache,'utf8')):[];
for(const site of ['enwiki','eswiki']){
 const titles=[...new Set(specs.filter(s=>!s.ava&&!s.geonames&&s.site===site).map(s=>s.title))].filter(title=>!entities.some(e=>e.sitelinks?.[site]?.title===title));
 for(let i=0;i<titles.length;i+=35){
  const url=new URL('https://www.wikidata.org/w/api.php');for(const[k,v]of Object.entries({action:'wbgetentities',sites:site,titles:titles.slice(i,i+35).join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en|es',redirects:'yes',format:'json'}))url.searchParams.set(k,v);
  const response=await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.10 licensed geography research'}});if(!response.ok)throw Error(`Wikidata ${response.status}`);const data=await response.json();if(data.error)throw Error(JSON.stringify(data.error));entities.push(...Object.values(data.entities));fs.writeFileSync(wikiCache,JSON.stringify(entities,null,2)+'\n');await new Promise(resolve=>setTimeout(resolve,1500));
 }
}
const features=[],gazetteerFeatures=[],unresolved=[];
const geonameFiles={CA:'.dart_tool/americas_geonames_CA/CA.txt',AR:'.dart_tool/new_world_geonames_AR/AR.txt',CL:'.dart_tool/americas_geonames_CL/CL.txt'};
const geonameData=new Map();
for(const s of specs){
 const common={node:`n_geo_${s.id}`,node_id:`n_geo_${s.id}`,name:s.name,parent_node_id:`n_geo_${s.parent}`,country_node_id:`n_geo_${s.country}`,retrieved_on:retrieved};
 if(s.ava){const f=avas.find(f=>f.properties.ava_id===s.ava);features.push({type:'Feature',properties:{...common,point_role:'source_polygon_interior_reference_point',point_place_name:s.name,source_url:`https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas/${s.ava}.geojson`,source_coordinate_url:rawUrl,source_commit:commit,source_file_sha256:aggregateSha,source_feature_id:s.ava,source_cfr_index:s.cfr,derivation:'widest verified horizontal scanline interval midpoint; 63 scanlines per source polygon, holes excluded',license:'CC0-1.0',attribution:'UC Davis Library and DataLab AVA Project, with UCSB Library and Virginia Tech contributors',label_note:'Community-polygon interior reference; not official centroid or legal boundary geometry.'},geometry:{type:'Point',coordinates:interior(f.geometry)}});continue;}
 if(s.geonames){
  const country={canada:'CA',argentina:'AR',chile:'CL'}[s.country];
  if(!geonameData.has(country)){const bytes=fs.readFileSync(geonameFiles[country]);geonameData.set(country,{hash:sha(bytes),rows:new Map(bytes.toString().split('\n').map(l=>{const r=l.split('\t');return[r[0],r];}))});}
  const data=geonameData.get(country),row=data.rows.get(String(s.geonames));if(!row||row[8]!==country||row[1]!==s.title)throw Error(`Unexpected exact GeoNames reference: ${s.id}`);
  gazetteerFeatures.push({type:'Feature',properties:{...common,point_role:'qualified_named_locality_or_terrain_reference',point_place_name:row[1],geonames_id:row[0],geonames_feature_class:row[6],geonames_feature_code:row[7],geonames_modified_on:row[18],source_url:`https://www.geonames.org/${row[0]}/`,source_coordinate_url:`https://download.geonames.org/export/dump/${country}.zip`,source_file_sha256:data.hash,license:'CC-BY-4.0',attribution:'Contains GeoNames geographical data, licensed under Creative Commons Attribution 4.0. Exact named references and WGS84 coordinates; no boundaries derived.',label_note:`Named reference: ${row[1]}. This is an orientation locality or terrain feature, not an official wine-area centroid; municipality and wine boundaries may differ.`},geometry:{type:'Point',coordinates:[Number(row[5]),Number(row[4])]}});continue;
 }
 const entity=entities.find(e=>e.sitelinks?.[s.site]?.title===s.title);
 const claim=entity?.claims?.P625?.find(c=>c.rank!=='deprecated'&&c.mainsnak.datavalue?.value.globe==='http://www.wikidata.org/entity/Q2');
 if(!claim){unresolved.push({id:s.id,title:s.title,site:s.site,entity:entity?.id});continue;}
 const p=claim.mainsnak.datavalue.value;
 features.push({type:'Feature',properties:{...common,point_role:'qualified_gazetteer_reference_point',point_place_name:s.title,point_description:entity.descriptions?.en?.value??entity.descriptions?.es?.value??'',wikidata_id:entity.id,wikidata_coordinate_claim:claim.id,coordinate_precision:p.precision,source_url:`https://www.wikidata.org/wiki/${entity.id}`,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,license:'CC0-1.0',label_note:`Exact published reference: ${s.title}. This does not establish a legal wine-area boundary, official centroid or coextensive municipality.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}});
}
if(unresolved.length){fs.writeFileSync('.dart_tool/new_world_americas_unresolved.json',JSON.stringify(unresolved,null,2));console.log(JSON.stringify(unresolved,null,2));throw Error(`${unresolved.length} unsourced markers; no authored files written`);}
const names=new Map([...existingNodes,...specs.map(s=>({id:`n_geo_${s.id}`,name:s.name,node_type:s.type}))].map(n=>[n.id,n]));
for(const s of specs){if(existingNodes.some(n=>n.id===`n_geo_${s.id}`))throw Error(`Existing authored ID ${s.id}`);if(!names.has(`n_geo_${s.parent}`))throw Error(`Missing parent ${s.parent}`);}
const combined=[...features,...gazetteerFeatures];
if(new Set(combined.map(f=>f.properties.node_id)).size!==specs.length||combined.length!==specs.length)throw Error('Marker/node mismatch');
for(const feature of combined)if(!feature.geometry.coordinates.every(Number.isFinite))throw Error('Nonfinite coordinate');
const sameTypePoints=new Set();for(const feature of combined){const key=names.get(feature.properties.node_id).node_type+JSON.stringify(feature.geometry.coordinates);if(sameTypePoints.has(key))throw Error(`Coincident same-type point ${feature.properties.node_id}`);sameTypePoints.add(key);}
const item=s=>`ki_nwa_${s.id}_location`;
const signatureKeys=new Set(oldDocuments.flatMap(d=>d.relation_type_signatures??[]).map(s=>[s.relation_type,s.subject_node_type,s.object_node_type].join('|')));
const signatures=[];
for(const s of specs){const objectType=names.get(`n_geo_${s.parent}`).node_type,key=['LOCATED_IN',s.type,objectType].join('|');if(!signatureKeys.has(key)){signatureKeys.add(key);signatures.push({relation_type:'LOCATED_IN',subject_node_type:s.type,object_node_type:objectType});}}
const ttbCitation=existingSources.find(s=>s.url===registerUrl)?.id;if(!ttbCitation)throw Error('Existing TTB register citation required');
if(process.argv.includes('--author')){
 const dataset={
  ...(signatures.length?{relation_type_signatures:signatures}:{}),
  knowledge_nodes:specs.map(s=>({id:`n_geo_${s.id}`,node_type:s.type,name:s.name})),
  knowledge_relations:specs.map(s=>({subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,valid_from:'1900-01-01'})),
  knowledge_items:specs.map(s=>({id:item(s),subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,domain_id:'geography',assertion_text:s.assertion??`${s.name} is ${s.country==='argentina'&&s.type==='region'?'an administrative province':s.ava?'an American viticultural area':s.type==='appellation'?'a recognised wine geographical area':s.type==='subregion'?'a legally named wine subregion or area':'a wine-geography region'} within ${names.get(`n_geo_${s.parent}`).name}. Its marker identifies a qualified published reference, not a legal boundary.`,verification_status:'unverified',last_verified_at:'2026-09-26T20:00:00.000Z'})),
  certification_knowledge_mappings:specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(certification_id=>({certification_id,knowledge_item_id:item(s),minimum_depth:2,importance:'secondary'}))),
  source_citations:sources,
  knowledge_item_citations:specs.flatMap(s=>[{knowledge_item_id:item(s),source_citation_id:s.source,locator:s.locator??(s.source==='src_nwa_ca_bc'?`Section 56(1), ${s.name.replace(/ \([^)]*\)/g,'')} entry and explicit containing subdivision`:(s.source_origin??s.source)==='src_nwa_ar_register'?`${s.name}: register name and Departamento y Provincia column`:s.source==='src_nwa_ar_provinces'?`${s.name}: province list`:s.country==='chile'?`Article 1 wine-geography hierarchy: ${s.name}; containing region/valley and named-area definition`:`${s.name}: current regional/sub-appellation list; containing Niagara Peninsula or Lake Erie North Shore`)},...(s.cfr?[{knowledge_item_id:item(s),source_citation_id:ttbCitation,locator:s.locator}]:[])]),
 };
 if(fs.existsSync(curriculumPath)){const previous=YAML.parse(fs.readFileSync(curriculumPath,'utf8'));for(const key of ['knowledge_nodes','knowledge_items','source_citations'])for(const row of previous[key]??[])if(!dataset[key].some(next=>next.id===row.id)&&!(key==='source_citations'&&duplicateCitationDrafts.has(row.id)))throw Error(`Would delete authored ${row.id}`);}
 fs.writeFileSync(curriculumPath,'# Additive Americas atlas: primary-cited geography, not complete wine analysis.\n# Published locality/interior references are not legal boundary shapes. Expert review remains open.\n'+YAML.stringify(dataset));
}
fs.writeFileSync(pointPath,JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
fs.writeFileSync(gazetteerPath,JSON.stringify({type:'FeatureCollection',features:gazetteerFeatures},null,2)+'\n');
console.log(JSON.stringify({places:specs.length,location_items:specs.length,mappings:specs.length*2,counts:Object.fromEntries([...new Set(specs.map(s=>s.country))].map(country=>[country,specs.filter(s=>s.country===country).length])),cc0_points:features.length,cc_by_points:gazetteerFeatures.length,primary_sources:sources.length,snapshot_sha256:sha(fs.readFileSync(pointPath)),gazetteer_sha256:sha(fs.readFileSync(gazetteerPath)),geonames_sources:Object.fromEntries([...geonameData].map(([country,d])=>[country,d.hash]))},null,2));
