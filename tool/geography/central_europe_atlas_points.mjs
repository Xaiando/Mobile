// Reproduce the sourced CC0 gazetteer markers of the Central European atlas.
// Wine areas use an explicitly named representative settlement where their
// own reusable shape/coordinate is unavailable; no boundary is inferred.
import fs from 'node:fs';
import YAML from 'yaml';

// id, name, type, parent, primary source key, coordinate title, optional wiki
const specs = [
  ['saar','Saar','subregion','mosel','mosel','Wiltingen'],
  ['ruwer','Ruwer','subregion','mosel','mosel','Mertesdorf'],
  ['bernkastel_bereich','Bernkastel (Mittelmosel)','subregion','mosel','mosel','Bernkastel-Kues'],
  ['burg_cochem','Burg Cochem (Terrassenmosel)','subregion','mosel','mosel','Cochem'],
  ['obermosel','Obermosel','subregion','mosel','mosel','Nittel'],
  ['moseltor','Moseltor','subregion','mosel','mosel','Perl, Saarland'],
  ['mittelhaardt','Mittelhaardt-Deutsche Weinstraße','subregion','pfalz','districts','Bad Dürkheim'],
  ['suedliche_weinstrasse','Südliche Weinstraße','subregion','pfalz','districts','Landau'],
  ['kaiserstuhl','Kaiserstuhl','subregion','baden','baden','Kaiserstuhl (Baden-Württemberg)'],
  ['ortenau','Ortenau','subregion','baden','baden','Offenburg'],
  ['markgraeflerland','Markgräflerland','subregion','baden','baden','Müllheim im Markgräflerland','dewiki'],
  ['tuniberg','Tuniberg','subregion','baden','baden','Tuniberg'],
  ['breisgau','Breisgau','subregion','baden','baden','Freiburg im Breisgau'],
  ['kraichgau','Kraichgau','subregion','baden','baden','Kraichgau'],
  ['badische_bergstrasse','Badische Bergstraße','subregion','baden','baden','Weinheim'],
  ['tauberfranken','Tauberfranken','subregion','baden','baden','Tauberbischofsheim'],
  ['bodensee_baden','Bodensee (Baden)','subregion','baden','baden','Meersburg'],
  ['piesport','Piesport','village','mosel','vdp_mosel','Piesport'],
  ['wehlen','Wehlen','village','mosel','vdp_mosel','Wehlen (Bernkastel-Kues)','dewiki'],
  ['bernkastel','Bernkastel-Kues','village','mosel','vdp_mosel','Bernkastel-Kues'],
  ['wiltingen','Wiltingen','village','mosel','vdp_mosel','Wiltingen'],
  ['ruedesheim','Rüdesheim am Rhein','village','rheingau','rheingau','Rüdesheim am Rhein'],
  ['geisenheim','Geisenheim','village','rheingau','rheingau','Geisenheim'],
  ['johannisberg','Johannisberg','village','rheingau','rheingau','Johannisberg (Geisenheim)','dewiki'],
  ['assmannshausen','Assmannshausen','village','rheingau','rheingau','Assmannshausen'],
  ['scharzhofberg','Scharzhofberg','site','wiltingen','vdp_mosel','Wiltinger Scharzhofberg','dewiki'],
  ['bernkasteler_doctor','Bernkasteler Doctor','site','bernkastel','vdp_mosel','Bernkasteler Doctor','dewiki'],
  ['wehlener_sonnenuhr','Wehlener Sonnenuhr','site','wehlen','vdp_mosel','Wehlener Sonnenuhr','dewiki'],
  ['piesporter_goldtroepfchen','Piesporter Goldtröpfchen','site','piesport','vdp_mosel','Piesporter Goldtröpfchen','dewiki'],
  ['neusiedlersee','Neusiedlersee','region','burgenland','at_regions','Gols','dewiki'],
  ['leithaberg','Leithaberg','region','burgenland','at_regions','Eisenstadt'],
  ['eisenberg','Eisenberg','region','burgenland','at_regions','Deutsch Schützen-Eisenberg'],
  ['rosalia','Rosalia','region','burgenland','at_regions','Mattersburg'],
  ['weststeiermark','Weststeiermark','region','steiermark','at_regions','Deutschlandsberg'],
  ['vulkanland_steiermark','Vulkanland Steiermark','region','steiermark','at_regions','Bad Gleichenberg'],
  ['rust','Rust','village','burgenland','at_regions','Rust, Burgenland'],
  ['neusiedlersee_dac','Neusiedlersee DAC','appellation','neusiedlersee','at_dacs','Gols','dewiki'],
  ['leithaberg_dac','Leithaberg DAC','appellation','leithaberg','at_dacs','Eisenstadt'],
  ['eisenberg_dac','Eisenberg DAC','appellation','eisenberg','at_dacs','Deutsch Schützen-Eisenberg'],
  ['rosalia_dac','Rosalia DAC','appellation','rosalia','at_dacs','Mattersburg'],
  ['ruster_ausbruch_dac','Ruster Ausbruch DAC','appellation','rust','at_dacs','Rust, Burgenland'],
  ['weststeiermark_dac','Weststeiermark DAC','appellation','weststeiermark','at_dacs','Deutschlandsberg'],
  ['vulkanland_steiermark_dac','Vulkanland Steiermark DAC','appellation','vulkanland_steiermark','at_dacs','Bad Gleichenberg'],
  ['suedsteiermark_dac','Südsteiermark DAC','appellation','suedsteiermark','at_dacs','Gamlitz'],
  ['villany','Villány','appellation','hungary','hu_districts','Villány'],
  ['eger','Eger','appellation','hungary','hu_districts','Eger'],
  ['somlo','Somló','appellation','hungary','hu_districts','Somló'],
  ['szekszard','Szekszárd','appellation','hungary','hu_districts','Szekszárd'],
  ['badacsony','Badacsony','appellation','hungary','hu_districts','Badacsony'],
  ['balatonfured_csopak','Balatonfüred-Csopak','appellation','hungary','hu_districts','Balatonfüred'],
  ['sopron','Sopron','appellation','hungary','hu_districts','Sopron'],
];

const sources = [
  ['mosel','Mosel: the six wine-growing districts','Moselwein e.V.','https://www.weinland-mosel.de/de/die-region/die-teilregionen','DE'],
  ['districts','German wine-growing regions and their districts','Deutsches Weininstitut','https://www.deutscheweine.de/fileadmin/DWI/Seminare-KD/pdf/Seminarhandbuch.pdf','DE'],
  ['baden','Baden: nine wine-growing districts','Deutsches Weininstitut','https://www.deutscheweine.de/anbaugebiet/65/baden','DE'],
  ['rheingau','Rheingau: wine villages and geography','Deutsches Weininstitut','https://www.deutscheweine.de/anbaugebiet/69/rheingau','DE'],
  ['vdp_mosel','Mosel, Saar and Ruwer: vineyard locations and their villages','VDP.Mosel-Saar-Ruwer','https://www.vdp.de/fileadmin/user_upload/Downloads/VDPM_2024_Katalog_Meisterwerke_Versteigerung.pdf','DE'],
  ['at_regions','Austrian wine-growing regions and their geographic hierarchy','Austrian Wine Marketing Board','https://www.austrianvineyards.com/','AT'],
  ['at_dacs','Austrian wine-growing regions and protected designations (DAC)','Austrian Wine Marketing Board','https://www.oesterreichwein.at/fileadmin/content/Documents/01_AVZ_Prowine_Shanghai_2023_FINAL_online.pdf','AT'],
  ['hu_districts','Hungarian wine districts and their regional hierarchy','Hungarian Wine Marketing Agency','https://bor.hu/en/','HU'],
];

if (process.argv.includes('--author')) {
  const parentNames = Object.fromEntries(specs.map(x=>[x[0],x[1]]));
  Object.assign(parentNames,{mosel:'Mosel',pfalz:'Pfalz',baden:'Baden',rheingau:'Rheingau',burgenland:'Burgenland',steiermark:'Steiermark',suedsteiermark:'Südsteiermark',hungary:'Hungary'});
  const item = s=>`ki_ce_${s[0]}_location`;
  const d = {
    node_types:[{id:'village',label:'wine locality'}],
    relation_type_signatures:[
      {relation_type:'LOCATED_IN',subject_node_type:'village',object_node_type:'region'},
      {relation_type:'LOCATED_IN',subject_node_type:'site',object_node_type:'village'},
      {relation_type:'LOCATED_IN',subject_node_type:'appellation',object_node_type:'village'},
    ],
    knowledge_nodes:specs.map(([id,name,type])=>({id:`n_geo_${id}`,node_type:type,name})),
    knowledge_relations:specs.map(([id,,,parent])=>({subject_id:`n_geo_${id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${parent}`,valid_from:'1900-01-01'})),
    knowledge_items:specs.map(s=>({id:item(s),subject_id:`n_geo_${s[0]}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s[3]}`,domain_id:'geography',assertion_text:`${s[1]} is ${s[2]==='village'?'a wine locality':s[2]==='site'?'a vineyard site':s[2]==='appellation'?'a wine appellation':'a wine-growing area'} in ${parentNames[s[3]]}.`,last_verified_at:'2026-09-26T12:00:00.000Z',verification_status:'unverified'})),
    certification_knowledge_mappings:specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(cert=>({certification_id:cert,knowledge_item_id:item(s),importance:s[2]==='village'||s[2]==='site'?'secondary':'core',minimum_depth:1}))),
    source_citations:sources.map(([id,title,publisher,url,jurisdiction])=>({id:`src_ce_${id}`,kind:'reference_work',title,publisher,jurisdiction,url,accessed_on:'2026-09-26'})),
    knowledge_item_citations:specs.map(s=>({knowledge_item_id:item(s),source_citation_id:`src_ce_${s[4]}`,locator:`${s[1]}: geographic location and parent wine area`})),
  };
  fs.writeFileSync('assets/curriculum/areas/central_europe_atlas.yaml','# Central European atlas: sourced districts, wine villages and vineyard sites.\n# Coordinates are separate CC0 gazetteer markers, never invented boundaries.\n# Track importance is editorial; all location facts await expert review.\n'+YAML.stringify(d));
}

const entities = [];
for (const site of ['enwiki','dewiki']) {
  const titles = [...new Set(specs.filter(s=>(s[6]??'enwiki')===site).map(s=>s[5]))];
  if (!titles.length) continue;
  const url = new URL('https://www.wikidata.org/w/api.php');
  Object.entries({action:'wbgetentities',sites:site,titles:titles.join('|'),props:'labels|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>url.searchParams.set(k,v));
  const response = await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.9 Geography'}});
  if(!response.ok) throw Error(`Wikidata ${response.status}`);
  const data = await response.json();
  if (data.error) throw Error(JSON.stringify(data.error));
  entities.push(...Object.values(data.entities));
}
fs.writeFileSync('.dart_tool/central_europe_entities.json',JSON.stringify(entities,null,2));
const features=[];
let missing=0;
for(const [suffix,name,,, ,title,site='enwiki'] of specs) {
  const entity = entities.find(e=>e.sitelinks?.[site]?.title===title);
  const coordinate = entity?.claims?.P625?.find(c=>c.rank!=='deprecated'&&c.mainsnak.datavalue)?.mainsnak.datavalue.value;
  if(!coordinate) {console.log(`MISSING ${suffix}: ${site} ${title}`);missing++;continue;}
  features.push({type:'Feature',properties:{node:`n_geo_${suffix}`,name,point_role:'sourced gazetteer marker; not a wine-area boundary',point_place_name:title,wikidata_id:entity.id,source_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,retrieved_on:'2026-09-26',license:'CC0 1.0'},geometry:{type:'Point',coordinates:[coordinate.longitude,coordinate.latitude]}});
  console.log(`${suffix}: ${entity.id} ${coordinate.longitude},${coordinate.latitude}`);
}
fs.writeFileSync('tool/geography/central_europe_atlas_points.geojson',JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
if(missing) throw Error(`${missing} missing coordinates; resolve explicit entities before bundling`);
