// Reproduce the added New World geography facts and source-derived markers.
// Run from the repository root; --author writes the owned curriculum file.
// UC Davis community polygons are CC0; interior markers are not legal borders.
import fs from 'node:fs';
import crypto from 'node:crypto';
import YAML from 'yaml';

const retrieved = '2026-09-26';
const commit = '7af5b29d45aee5e6c6ce3889e9b1de19085d7107';
const rawUrl = `https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas_aggregated_files/avas.geojson`;
const avaCache = '.dart_tool/new_world_ava_aggregate.geojson';
const ttbCache = '.dart_tool/new_world_ttb.html';
const wikiCache = '.dart_tool/new_world_completion_entities.json';
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const specs = [];
// Each US tuple: node suffix, legal AVA source ID, fully containing parent.
function us(id, ava, parent) { specs.push({id, ava, parent, country:'united_states', type:'appellation'}); }
us('north_coast_us','north_coast','california');
us('northern_sonoma','northern_sonoma','north_coast_us');
for (const id of ['atlas_peak','chiles_valley','coombsville','crystal_springs_of_napa_valley','diamond_mountain_district','howell_mountain','oak_knoll_district_of_napa_valley','spring_mountain_district','yountville','stags_leap_district']) us(id,id,'napa_valley');
us('mount_veeder','mt__veeder','napa_valley');
// Wild Horse Valley and Los Carneros only partly overlap Napa Valley.
us('wild_horse_valley','wild_horse_valley','north_coast_us');
us('west_sonoma_coast','west_sonoma_coast','sonoma_coast');
us('fort_ross_seaview','fort_ross_seaview','west_sonoma_coast');
us('petaluma_gap','petaluma_gap','north_coast_us');
us('green_valley_russian_river','green_valley_of_russian_river_valley','russian_river_valley');
us('chalk_hill','chalk_hill','russian_river_valley');
us('sonoma_valley','sonoma_valley','north_coast_us');
us('moon_mountain_district','moon_mountain_district_sonoma_county','sonoma_valley');
us('sonoma_mountain','sonoma_mountain','sonoma_valley');
us('bennett_valley','bennett_valley','sonoma_valley');
us('knights_valley','knights_valley','northern_sonoma');
us('rockpile','rockpile','north_coast_us');
us('fountaingrove_district','fountaingrove_district','north_coast_us');
us('pine_mountain_cloverdale_peak','pine_mountain_cloverdale_peak','north_coast_us');
for (const [id,ava,parent] of [
  ['laurelwood_district','laurelwood_district','chehalem_mountains'],
  ['lower_long_tom','lower_long_tom','willamette_valley'],
  ['mcminnville_ava','mcminnville','willamette_valley'],
  ['mount_pisgah_oregon','mount_pisgah__polk_county__oregon','willamette_valley'],
  ['tualatin_hills','tualatin_hills','willamette_valley'],
  ['van_duzer_corridor','van_duzer_corridor','willamette_valley'],
  ['yamhill_carlton','yamhill_carlton','willamette_valley'],
]) us(id,ava,parent);
for (const id of ['adelaida_district','creston_district','el_pomar_district','paso_robles_estrella_district','paso_robles_geneseo_district','paso_robles_highlands_district','paso_robles_willow_creek_district','san_juan_creek','san_miguel_district','santa_margarita_ranch','templeton_gap_district']) us(id,id,'paso_robles');
for (const id of ['ballard_canyon','los_olivos_district','happy_canyon_of_santa_barbara']) us(id,id,'santa_ynez_valley');
us('alisos_canyon','alisos_canyon','central_coast');
us('monterey_ava','monterey','central_coast');
us('arroyo_seco','arroyo_seco','monterey_ava');
us('anderson_valley','anderson_valley','mendocino_ava');
us('mendocino_ava','mendocino','north_coast_us');
us('santa_cruz_mountains','santa_cruz_mountains','california');
us('lodi','lodi','california');
for (const id of ['alta_mesa','borden_ranch','clements_hills','cosumnes_river','jahant','mokelumne_river','sloughhouse']) us(id,id,'lodi');
for (const id of ['horse_heaven_hills','wahluke_slope','ancient_lakes_of_columbia_valley','lake_chelan','naches_heights','royal_slope','white_bluffs','the_burn_of_columbia_valley','rocky_reach']) us(id,id,'columbia_valley');
for (const id of ['rattlesnake_hills','snipes_mountain','candy_mountain','goose_gap']) us(id,id,'yakima_valley');
us('rocks_district_milton_freewater','the_rocks_district_of_milton_freewater','walla_walla_valley');
us('puget_sound','puget_sound','washington');
us('columbia_gorge','columbia_gorge','united_states');
us('southern_oregon','southern_oregon','oregon');
us('rogue_valley','rogue_valley','southern_oregon');
us('umpqua_valley','umpqua_valley','southern_oregon');
us('applegate_valley','applegate_valley','rogue_valley');
us('elkton_oregon','elkton_oregon','umpqua_valley');

// Suffix, study name, type, containing area, primary source, exact wiki title.
function group(country, source, rows) {
  for (const line of rows.trim().split('\n')) {
    const [id,name,type,parent,title,site='enwiki'] = line.trim().split('|');
    specs.push({id,name,type,parent,country,source,title,site});
  }
}
group('australia','src_atlas_au_gis',`
lenswood|Lenswood|subregion|adelaide_hills|Lenswood, South Australia
piccadilly_valley|Piccadilly Valley|subregion|adelaide_hills|Piccadilly Valley
pokolbin|Pokolbin|subregion|hunter|Pokolbin, New South Wales
upper_hunter_valley|Upper Hunter Valley|subregion|hunter|Denman, New South Wales
broke_fordwich|Broke Fordwich|subregion|hunter|Broke Fordwich
albany_wine|Albany (wine subregion)|subregion|great_southern|Albany wine region
denmark_wine|Denmark (wine subregion)|subregion|great_southern|Denmark wine region
frankland_river_wine|Frankland River|subregion|great_southern|Frankland River, Western Australia
mount_barker_wine|Mount Barker (wine subregion)|subregion|great_southern|Mount Barker wine region
porongurup_wine|Porongurup|subregion|great_southern|Porongurup, Western Australia
fleurieu_zone|Fleurieu (zone)|region|south_australia|Fleurieu wine zone
langhorne_creek|Langhorne Creek|appellation|fleurieu_zone|Langhorne Creek wine region
padthaway|Padthaway|appellation|limestone_coast|Padthaway wine region
wr attonbully|Wrattonbully|appellation|limestone_coast|Wrattonbully wine region
riverland|Riverland|appellation|south_australia|Riverland
rutherglen_wine|Rutherglen|appellation|victoria|Rutherglen wine region
heathcote_wine|Heathcote|appellation|victoria|Heathcote wine region
geelong_wine|Geelong|appellation|port_phillip|Geelong wine region
macedon_ranges_wine|Macedon Ranges|appellation|port_phillip|Macedon Ranges wine region
king_valley|King Valley|appellation|victoria|King Valley
grampians_wine|Grampians|appellation|victoria|Grampians wine region
great_western_wine|Great Western|subregion|grampians_wine|Great Western, Victoria
goulburn_valley_wine|Goulburn Valley|appellation|victoria|Goulburn Valley
nagambie_lakes|Nagambie Lakes|subregion|goulburn_valley_wine|Nagambie
new_south_wales|New South Wales|region|australia|New South Wales
hunter_valley_zone|Hunter Valley (zone)|region|new_south_wales|Hunter Valley
mudgee_wine|Mudgee|appellation|new_south_wales|Mudgee
orange_wine|Orange|appellation|new_south_wales|Orange wine region
tumbarumba_wine|Tumbarumba|appellation|new_south_wales|Tumbarumba
riverina_wine|Riverina|appellation|new_south_wales|Riverina wine region
canberra_district|Canberra District|appellation|australia|Canberra District wine region
pemberton_wine|Pemberton|appellation|western_australia|Pemberton wine region
swan_district|Swan District|appellation|western_australia|Swan Valley (Western Australia)
swan_valley|Swan Valley|subregion|swan_district|Swan Valley (Western Australia)
`);
// The official NZ Winegrowers named subregions are informal areas, not GIs.
group('new_zealand','src_nwc_nz_otago',`
gibbston|Gibbston|informal_area|central_otago|Gibbston
cromwell_basin|Cromwell Basin|informal_area|central_otago|Cromwell, New Zealand
lowburn|Lowburn|informal_area|central_otago|Lowburn
pisa_wine|Pisa|informal_area|central_otago|Pisa Moorings
bendigo_otago|Bendigo (Central Otago)|informal_area|central_otago|Bendigo, New Zealand
alexandra_otago|Alexandra (Central Otago)|informal_area|central_otago|Alexandra, New Zealand
wanaka_wine|Wānaka|informal_area|central_otago|Wānaka
`);
group('new_zealand','src_nwc_nz_marlborough',`
wairau_valley|Wairau Valley|informal_area|marlborough|Wairau Valley
awatere_valley|Awatere Valley|informal_area|marlborough|Awatere Valley
southern_valleys_marlborough|Southern Valleys (Marlborough)|informal_area|marlborough|Fairhall
`);
group('new_zealand','src_atlas_nz_gis',`
gladstone_wairarapa|Gladstone (Wairarapa)|appellation|wairarapa|Gladstone, New Zealand
waitaki_valley_wine|Waitaki Valley, North Otago|appellation|new_zealand|Kurow
auckland_wine|Auckland|appellation|new_zealand|Kumeū
waiheke_island_wine|Waiheke Island|appellation|auckland_wine|Waiheke Island
kumeu_wine|Kumeu|appellation|auckland_wine|Huapai
northland_wine|Northland|appellation|new_zealand|Northland Region
matakana_wine|Matakana|appellation|auckland_wine|Matakana
central_hawkes_bay|Central Hawke’s Bay|appellation|hawkes_bay|Waipukurau
canterbury_wine|Canterbury|appellation|new_zealand|Canterbury, New Zealand
`);
group('south_africa','src_atlas_za_wo_2026',`
banghoek|Banghoek|subregion|stellenbosch|Banghoek Valley
bottelary|Bottelary|subregion|stellenbosch|Bottelary
devon_valley|Devon Valley|subregion|stellenbosch|Devon Valley
jonkershoek_valley|Jonkershoek Valley|subregion|stellenbosch|Jonkershoek Valley
papegaaiberg|Papegaaiberg|subregion|stellenbosch|Papegaaiberg
polkadraai_hills|Polkadraai Hills|subregion|stellenbosch|Polkadraai Hills
simonsberg_stellenbosch|Simonsberg-Stellenbosch|subregion|stellenbosch|Simonsberg
vlottenburg|Vlottenburg|subregion|stellenbosch|Vlottenburg
upper_hemel_en_aarde|Upper Hemel-en-Aarde Valley|subregion|walker_bay|Upper Hemel-en-Aarde Valley
hemel_en_aarde_ridge|Hemel-en-Aarde Ridge|subregion|walker_bay|Hemel-en-Aarde Ridge
cape_town_wine|Cape Town (wine district)|appellation|coastal_region|Cape Town
durbanville_wine|Durbanville|subregion|cape_town_wine|Durbanville
franschhoek_wine|Franschhoek|appellation|coastal_region|Franschhoek
wellington_wine|Wellington|appellation|coastal_region|Wellington, Western Cape
tulbagh_wine|Tulbagh|appellation|coastal_region|Tulbagh
darling_wine|Darling|appellation|coastal_region|Darling, Western Cape
breede_river_valley|Breede River Valley|region|western_cape|Breede River Valley
robertson_wine|Robertson|appellation|breede_river_valley|Robertson, Western Cape
worcester_wine|Worcester|appellation|breede_river_valley|Worcester, South Africa
breedekloof|Breedekloof|appellation|breede_river_valley|Rawsonville
klein_karoo_wine|Klein Karoo|region|western_cape|Oudtshoorn
calitzdorp_wine|Calitzdorp|appellation|klein_karoo_wine|Calitzdorp
cape_agulhas_wine|Cape Agulhas|appellation|cape_south_coast|Bredasdorp
elim_wine|Elim|subregion|cape_agulhas_wine|Elim, Western Cape
bot_river_wine|Bot River|subregion|walker_bay|Botrivier
overberg_wine|Overberg|appellation|cape_south_coast|Overberg
`);
group('argentina','src_nwc_ar_register',`
los_chacayes|Los Chacayes|appellation|tunuyan|Los Chacayes|eswiki
san_pablo_mendoza|San Pablo (Mendoza)|appellation|tunuyan|San Pablo (Mendoza)|eswiki
pampa_el_cepillo|Pampa El Cepillo|appellation|san_carlos_mendoza|El Cepillo|eswiki
agrelo|Agrelo|appellation|lujan_de_cuyo|Agrelo|eswiki
las_compuertas|Las Compuertas|appellation|lujan_de_cuyo|Las Compuertas|eswiki
vista_flores|Vista Flores|appellation|tunuyan|Vista Flores|eswiki
san_rafael_mendoza|San Rafael (Mendoza)|appellation|mendoza|San Rafael, Mendoza
san_juan_argentina|San Juan|region|argentina|San Juan Province, Argentina
valle_del_pedernal|Valle del Pedernal|appellation|san_juan_argentina|Pedernal (San Juan)|eswiki
patagonia_wine|Patagonia (wine GI)|appellation|argentina|Patagonia
calchaqui_valleys|Calchaquí Valleys|appellation|argentina|Calchaquí Valleys
`);
group('argentina','src_nwc_ar_gualtallary',`
gualtallary|Gualtallary|informal_area|tupungato|Gualtallary|eswiki
`);

const sources = [
  {id:'src_nwc_nz_otago',kind:'reference_work',title:'Central Otago wine subregions',publisher:'New Zealand Winegrowers',jurisdiction:'NZ',url:'https://www.nzwine.com/en/regions/centralotago/',accessed_on:retrieved},
  {id:'src_nwc_nz_marlborough',kind:'reference_work',title:'Marlborough wine subregions',publisher:'New Zealand Winegrowers',jurisdiction:'NZ',url:'https://www.nzwine.com/en/regions/marlborough/',accessed_on:retrieved},
  {id:'src_nwc_nz_cromwell',kind:'government_publication',title:'The Cromwell Story: Cromwell Basin wine-growing subregion',publisher:'Central Otago District Council / Central Otago Tourism',jurisdiction:'NZ',url:'https://www.centralotagonz.com/discover/our-stories/the-cromwell-story/',accessed_on:retrieved},
  {id:'src_nwc_ar_register',kind:'regulator_register',title:'Indicaciones geográficas y denominaciones de origen reconocidas y protegidas de la República Argentina',publisher:'Instituto Nacional de Vitivinicultura',jurisdiction:'AR',url:'https://www.argentina.gob.ar/sites/default/files/i.g._y_d.o.c._de_la_republica_argentina_web_inv_1.pdf_.pdf.pdf_.pdf',accessed_on:retrieved},
  {id:'src_nwc_ar_gualtallary',kind:'government_publication',title:'National plant-quarantine locality register: Gualtallary, Tupungato, Mendoza',publisher:'Servicio Nacional de Sanidad y Calidad Agroalimentaria',jurisdiction:'AR',url:'https://www.argentina.gob.ar/sites/default/files/disposicion_dnpv_472-2019_anexo_i.pdf',accessed_on:retrieved},
  {id:'src_nwc_ar_gualtallary_wine',kind:'reference_work',title:'Aluvional Gualtallary 2021: geographic origin and vineyards',publisher:'Zuccardi Valle de Uco',jurisdiction:'AR',url:'https://zuccardiwines.com/wp-content/uploads/2024/06/FT-ESP-ALUVIONAL-GUALTALLARY-2021.pdf',accessed_on:retrieved},
];
specs.find(s=>s.id==='cromwell_basin').source = 'src_nwc_nz_cromwell';
specs.find(s=>s.id==='wr attonbully').id = 'wrattonbully';
// These source coordinates belong to explicitly named reference settlements.
const referenceTitles = {
  piccadilly_valley:'Piccadilly, South Australia', broke_fordwich:'Broke, New South Wales',
  albany_wine:'Albany, Western Australia', denmark_wine:'Denmark, Western Australia',
  mount_barker_wine:'Mount Barker, Western Australia', fleurieu_zone:'Fleurieu Peninsula',
  wrattonbully:'Wrattonbully, South Australia', geelong_wine:'Geelong',
  macedon_ranges_wine:'Macedon, Victoria', riverina_wine:'Griffith, New South Wales',
  pemberton_wine:'Pemberton, Western Australia', awatere_valley:'Seddon, New Zealand',
  wellington_wine:'Wellington, South Africa', darling_wine:'Darling, South Africa',
  robertson_wine:'Robertson, South Africa', polkadraai_hills:'Zevenwacht',
  calchaqui_valleys:'San Carlos, Salta', canterbury_wine:'Canterbury Region',
};
for(const [id,title] of Object.entries(referenceTitles)) {
  const s=specs.find(s=>s.id===id);s.title=title;s.site='enwiki';
}
specs.find(s=>s.id==='los_chacayes').title='El Manzano Histórico';
// Exact GeoNames rows are pinned in the separate CC BY 4.0 marker snapshot.
const geonamesIds = {
  banghoek:3370221, bottelary:3369564, devon_valley:6465157,
  jonkershoek_valley:3366448, papegaaiberg:3363045, vlottenburg:7576587, polkadraai_hills:3361771,
  upper_hemel_en_aarde:3366895, hemel_en_aarde_ridge:3363910,
  agrelo:3866905, las_compuertas:3848533, san_pablo_mendoza:3836827,
  gualtallary:12594563,
};

async function download(url,path) {
  if(fs.existsSync(path)) return fs.readFileSync(path);
  const response = await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.10 geography research'}});
  if(!response.ok) throw Error(`${response.status}: ${url}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(path,bytes); return bytes;
}
const avaBytes = await download(rawUrl,avaCache);
const avas = JSON.parse(avaBytes).features;
const ttbHtml = (await download('https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/established-avas',ttbCache)).toString();
function plain(html) { return html.replace(/<\/(?:li|p)>/g,'; ').replace(/<[^>]*>/g,' ').replace(/&nbsp;/g,' ').replace(/&(?:ndash|mdash);/g,'-').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim(); }
const ttbRows = [...ttbHtml.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)].map(r=>[...r[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(c=>plain(c[1]))).filter(c=>c.length>=5);
// The widest interval among deterministic horizontal scan lines is interior to
// the source polygon including holes; no centroid extrapolation is allowed.
function pointInRing([x,y],ring) {
  let inside=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++) {
    const [xi,yi]=ring[i], [xj,yj]=ring[j];
    if((yi>y)!==(yj>y) && x<(xj-xi)*(y-yi)/(yj-yi)+xi) inside=!inside;
  }
  return inside;
}
function pointInGeometry(point,geometry) {
  const polygons = geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  return polygons.some(p=>pointInRing(point,p[0])&&!p.slice(1).some(r=>pointInRing(point,r)));
}
function interior(geometry) {
  const polygons = geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates;
  let best=null;
  for(const polygon of polygons) {
    const ys=polygon[0].map(p=>p[1]);const min=Math.min(...ys),max=Math.max(...ys);
    for(let i=1;i<64;i++) {
      const y=min+(max-min)*i/64;
      const xs=[];
      for(const ring of polygon) for(let j=0;j<ring.length-1;j++) {
        const a=ring[j],b=ring[j+1];
        if((a[1]>y)!==(b[1]>y)) xs.push(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]));
      }
      xs.sort((a,b)=>a-b);
      for(let j=0;j<xs.length-1;j++) {
        const p=[(xs[j]+xs[j+1])/2,y],width=xs[j+1]-xs[j];
        if((!best||width>best.width)&&pointInGeometry(p,geometry)) best={point:p,width};
      }
    }
  }
  if(!best||!pointInGeometry(best.point,geometry)) throw Error('No verified polygon interior marker');
  return best.point;
}
const features=[];
for(const s of specs.filter(s=>s.ava)) {
  const f=avas.find(f=>f.properties.ava_id===s.ava&&!f.properties.removed);
  if(!f) throw Error(`Missing current AVA ${s.ava}`);
  s.name=f.properties.name.trim();
  const row=ttbRows.find(r=>r[4].match(/9\.\d+/)?.[0]===f.properties.cfr_index);
  if(!row) throw Error(`No TTB legal register row for ${s.name}, ${f.properties.cfr_index}`);
  const parentSpec=specs.find(x=>x.id===s.parent);
  const parentName=parentSpec?.ava?avas.find(f=>f.properties.ava_id===parentSpec.ava).properties.name.trim():({napa_valley:'Napa Valley',sonoma_coast:'Sonoma Coast',russian_river_valley:'Russian River Valley',chehalem_mountains:'Chehalem Mountains',willamette_valley:'Willamette Valley',paso_robles:'Paso Robles',santa_ynez_valley:'Santa Ynez Valley',central_coast:'Central Coast',columbia_valley:'Columbia Valley',yakima_valley:'Yakima Valley',walla_walla_valley:'Walla Walla Valley'})[s.parent];
  if(parentName) {
    const parentEntry=row[2].split(';').map(x=>x.trim()).find(x=>x.replace(/[◊*]/g,'').trim()===parentName);
    if(!parentEntry||parentEntry.includes('*')) throw Error(`TTB does not confirm full containment: ${s.name} -> ${parentName}: ${row[2]}`);
  }
  s.cfr=f.properties.cfr_index;s.source=`src_nwc_us_${s.ava}`;
  sources.push({id:s.source,kind:'legislation',title:`27 CFR § ${s.cfr}: ${s.name} American viticultural area`,publisher:'Alcohol and Tobacco Tax and Trade Bureau / eCFR',jurisdiction:'US',url:`https://www.ecfr.gov/current/title-27/section-${s.cfr}`,accessed_on:retrieved,document_identifier:`27 CFR § ${s.cfr}`});
  const p=interior(f.geometry);
  features.push({type:'Feature',properties:{node:`n_geo_${s.id}`,node_id:`n_geo_${s.id}`,name:s.name,parent_node_id:`n_geo_${s.parent}`,country_node_id:'n_geo_united_states',point_role:'source_polygon_interior_reference_point',point_place_name:s.name,source_url:`https://raw.githubusercontent.com/UCDavisLibrary/ava/${commit}/avas/${s.ava}.geojson`,source_coordinate_url:rawUrl,source_commit:commit,source_file_sha256:sha(avaBytes),source_feature_id:s.ava,source_cfr_index:s.cfr,derivation:'widest verified interior horizontal scanline interval midpoint; 63 evenly spaced scanlines per polygon',retrieved_on:retrieved,license:'CC0-1.0',attribution:'UC Davis Library and DataLab American Viticultural Areas Project, with UCSB Library and Virginia Tech contributors',label_note:'Reference marker derived from the community digitized AVA polygon. It is not a legal boundary or an official centroid.'},geometry:{type:'Point',coordinates:p}});
}

let entities=fs.existsSync(wikiCache)&&!process.argv.includes('--refresh')?JSON.parse(fs.readFileSync(wikiCache,'utf8')):[];
{
  for(const site of ['enwiki','eswiki']) {
    const titles=[...new Set(specs.filter(s=>!s.ava&&!geonamesIds[s.id]&&s.site===site).map(s=>s.title))].filter(t=>!entities.some(e=>e.sitelinks?.[site]?.title===t));
    for(let i=0;i<titles.length;i+=40) {
      const url=new URL('https://www.wikidata.org/w/api.php');
      Object.entries({action:'wbgetentities',sites:site,titles:titles.slice(i,i+40).join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>url.searchParams.set(k,v));
      let response;
      for(let retry=0;retry<4;retry++) {
        response=await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.10 geography research (local educational atlas authoring)'}});
        if(response.status!==429) break;
        await new Promise(resolve=>setTimeout(resolve,5000*(retry+1)));
      }
      if(!response.ok) throw Error(`Wikidata ${response.status}`);
      const data=await response.json();if(data.error)throw Error(JSON.stringify(data.error));
      entities.push(...Object.values(data.entities));
      await new Promise(resolve=>setTimeout(resolve,1500));
    }
  }
  fs.writeFileSync(wikiCache,JSON.stringify(entities,null,2)+'\n');
}
let missing=0;
const gazetteerFeatures=[];
for(const s of specs.filter(s=>!s.ava)) {
  if(geonamesIds[s.id]) {
    const country=s.country==='south_africa'?'ZA':'AR';
    const path=`.dart_tool/new_world_geonames_${country}/${country}.txt`;
    const bytes=fs.readFileSync(path);
    const row=bytes.toString().split('\n').find(line=>line.startsWith(`${geonamesIds[s.id]}\t`))?.split('\t');
    if(!row||row[8]!==country)throw Error(`Missing GeoNames source row ${s.id}`);
    gazetteerFeatures.push({type:'Feature',properties:{node:`n_geo_${s.id}`,node_id:`n_geo_${s.id}`,name:s.name,parent_node_id:`n_geo_${s.parent}`,country_node_id:`n_geo_${s.country}`,point_role:'named_locality_or_terrain_reference_point',point_place_name:row[1],source_url:`https://www.geonames.org/${row[0]}/`,source_coordinate_url:`https://download.geonames.org/export/dump/${country}.zip`,source_file_sha256:sha(bytes),geonames_id:row[0],geonames_feature_class:row[6],geonames_feature_code:row[7],geonames_modified_on:row[18],retrieved_on:retrieved,license:'CC-BY-4.0',attribution:'Contains GeoNames geographical data, licensed under Creative Commons Attribution 4.0. Reference names and WGS84 coordinates selected from the national gazetteer; no boundaries derived.',label_note:`Reference point: ${row[1]} (${row[7]}). A nearby named locality or terrain feature provides orientation; this is not the wine-area boundary or an official wine-area centroid.`},geometry:{type:'Point',coordinates:[Number(row[5]),Number(row[4])]}});
    continue;
  }
  const entity=entities.find(e=>e.sitelinks?.[s.site]?.title===s.title);
  const claim=entity?.claims?.P625?.find(c=>c.rank!=='deprecated'&&c.mainsnak.datavalue?.value.globe==='http://www.wikidata.org/entity/Q2');
  if(!claim){console.log(`MISSING ${s.id}: ${s.site} ${s.title}`);missing++;continue;}
  const p=claim.mainsnak.datavalue.value;
  features.push({type:'Feature',properties:{node:`n_geo_${s.id}`,node_id:`n_geo_${s.id}`,name:s.name,parent_node_id:`n_geo_${s.parent}`,country_node_id:`n_geo_${s.country}`,point_role:'gazetteer_reference_point',point_place_name:s.title,point_description:entity.descriptions?.en?.value??'',source_url:`https://www.wikidata.org/wiki/${entity.id}`,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,wikidata_id:entity.id,wikidata_coordinate_claim:claim.id,coordinate_precision:p.precision,retrieved_on:retrieved,license:'CC0-1.0',label_note:`Reference point: ${s.title}. This does not represent the wine-area boundary or an official wine-area centroid.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}});
}
if(missing) throw Error(`${missing} unsourced markers; resolve before authoring`);
const oldFiles=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')&&f!=='new_world_atlas_completion.yaml');
const existing=oldFiles.flatMap(f=>YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')).knowledge_nodes??[]);
const existingIds=new Set(existing.map(n=>n.id));
for(const s of specs) if(existingIds.has(`n_geo_${s.id}`))throw Error(`Existing node: ${s.id}`);
const names=Object.fromEntries([...existing.map(n=>[n.id,n.name]),...specs.map(s=>[`n_geo_${s.id}`,s.name])]);
for(const s of specs) if(!names[`n_geo_${s.parent}`])throw Error(`Missing parent ${s.parent}`);
const item=s=>`ki_nwc_${s.id}_location`;
if(process.argv.includes('--author')) {
  const dataset={
    relation_type_signatures:[{relation_type:'LOCATED_IN',subject_node_type:'informal_area',object_node_type:'appellation'}],
    knowledge_nodes:specs.map(s=>({id:`n_geo_${s.id}`,node_type:s.type,name:s.name})),
    node_alternative_names:[
      {knowledge_node_id:'n_geo_mount_veeder',name:'Mount Veeder',kind:'synonym'},
      {knowledge_node_id:'n_geo_moon_mountain_district',name:'Moon Mountain District',kind:'synonym'},
      {knowledge_node_id:'n_geo_mount_pisgah_oregon',name:'Mount Pisgah',kind:'synonym'},
      {knowledge_node_id:'n_geo_central_hawkes_bay',name:"Central Hawke's Bay",kind:'synonym'},
      {knowledge_node_id:'n_geo_rocks_district_milton_freewater',name:'The Rocks District',kind:'synonym'},
    ],
    knowledge_relations:specs.map(s=>({subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,valid_from:'1900-01-01'})),
    knowledge_items:specs.map(s=>({id:item(s),subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,domain_id:'geography',assertion_text:`${s.name} is ${s.type==='informal_area'?'an informal wine-growing area':s.type==='subregion'?'a wine subregion':s.type==='appellation'?'a wine appellation':'a geographic area'} in ${names[`n_geo_${s.parent}`]}.`,verification_status:'unverified',last_verified_at:'2026-09-26T18:00:00.000Z'})),
    certification_knowledge_mappings:specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(cert=>({certification_id:cert,knowledge_item_id:item(s),importance:'secondary',minimum_depth:2}))),
    source_citations:sources,
    knowledge_item_citations:specs.flatMap(s=>[{knowledge_item_id:item(s),source_citation_id:s.source,locator:s.cfr?`27 CFR § ${s.cfr}(c), geographic area; TTB established AVA register full containment, September 2026`:`${s.name}: named area and containing region`}]),
  };
  dataset.knowledge_item_citations.push({knowledge_item_id:'ki_nwc_gualtallary_location',source_citation_id:'src_nwc_ar_gualtallary_wine',locator:'Origin Gualtallary, Tupungato, Valle de Uco, Mendoza; wine-growing locality, without claiming registered IG status'});
  fs.writeFileSync('assets/curriculum/areas/new_world_atlas_completion.yaml','# New World atlas completion: primary-cited geography; track mappings are editorial.\n# All facts await expert review. Points are sourced reference markers, not borders.\n'+YAML.stringify(dataset));
}
const pointPath='tool/geography/new_world_atlas_completion_points.geojson';
fs.writeFileSync(pointPath,JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
fs.writeFileSync('tool/geography/new_world_atlas_completion_gazetteer_points.geojson',JSON.stringify({type:'FeatureCollection',features:gazetteerFeatures},null,2)+'\n');
console.log(JSON.stringify({nodes:specs.length,US:specs.filter(s=>s.ava).length,counts:Object.fromEntries([...new Set(specs.map(s=>s.country))].map(c=>[c,specs.filter(s=>s.country===c).length])),ava_source_sha256:sha(avaBytes),snapshot_sha256:sha(fs.readFileSync(pointPath))},null,2));
