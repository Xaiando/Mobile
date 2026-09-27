// Register-to-node audit. Run from repository root after the authoring script.
// This records coverage, not verification of the wine facts or complete Diploma coverage.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import YAML from 'yaml';
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const norm=s=>s.replace(/\([^)]*\)/g,'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const docs=fs.readdirSync('assets/curriculum/areas').filter(f=>f.endsWith('.yaml')).map(f=>YAML.parse(fs.readFileSync(`assets/curriculum/areas/${f}`,'utf8')));
const nodes=docs.flatMap(d=>d.knowledge_nodes??[]);
const parents=new Map(docs.flatMap(d=>d.knowledge_relations??[]).filter(r=>r.relation_type==='LOCATED_IN').map(r=>[r.subject_id,r.object_id]));
const country=id=>{const seen=new Set();while(parents.has(id)&&!seen.has(id)){seen.add(id);id=parents.get(id);}return id;};
const own=YAML.parse(fs.readFileSync('assets/curriculum/areas/new_world_oceania_africa.yaml','utf8'));
const newIds=new Set(own.knowledge_nodes.map(n=>n.id));
const nodeMap=c=>new Map(nodes.filter(n=>country(n.id)===c).map(n=>[norm(n.name),n]));
const au=nodeMap('n_geo_australia'),za=nodeMap('n_geo_south_africa');
const htmlPath='.dart_tool/nwoa_wine_australia_register.html';
if(!fs.existsSync(htmlPath)){
  const r=await fetch('https://www.wineaustralia.com/labelling/register-of-protected-gis-and-other-terms/geographical-indications',{signal:AbortSignal.timeout(30000)});
  assert(r.ok);fs.writeFileSync(htmlPath,await r.text());
}
const html=fs.readFileSync(htmlPath);
const table=html.toString().match(/<table[\s\S]*?<\/table>/g)?.find(t=>t.includes('State/Zone'));
assert(table,'Primary national register table absent');
const clean=s=>s.replace(/<[^>]*>/g,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim().replace(/ [123]$/,'');
const columns=[new Set(),new Set(),new Set()];
for(const row of table.match(/<tr[\s\S]*?<\/tr>/g).slice(1)){
  const cells=row.match(/<t[dh][\s\S]*?<\/t[dh]>/g)?.map(clean)??[];
  for(let i=0;i<3;i++)if(cells[i])columns[i].add(cells[i]);
}
assert.deepEqual(columns.map(c=>c.size),[37,63,14],'Current register classification changed');
const registerRows=columns.flatMap((set,i)=>[...set].map(name=>{
  const n=au.get(norm(name));assert(n,`Missing Australian register name: ${name}`);
  return{register_name:name,register_column:['State/Zone','Region','Subregion'][i],node_id:n.id,node_name:n.name,added:newIds.has(n.id)};
}));
assert.equal(new Set(registerRows.map(r=>r.node_id)).size,114);
const gisLayers=[0,1,2].map(layer=>{
  const path=`.dart_tool/nwoa_wine_australia_${layer}.geojson`,bytes=fs.readFileSync(path),f=JSON.parse(bytes).features;
  return{layer,record_count:f.length,source_file_sha256:sha(bytes),records:f.map(x=>{
    const n=au.get(norm(x.properties.GI_NAME));assert(n,`GIS name unmapped: ${x.properties.GI_NAME}`);
    return{gis_name:x.properties.GI_NAME,gi_number:x.properties.GI_NUMBER,state:x.properties.STATE,node_id:n.id};
  })};
});
assert.deepEqual(gisLayers.map(x=>x.record_count),[14,64,28]);

// English entries transcribed from the February 2026 SAWIS production-area table.
// The primary PDF is bilingual; alternative Afrikaans names and None placeholders
// are not separate places. The source's Stellenbosh typo maps to existing Stellenbosch.
const zaGroups=[
 ['geographical unit','South Africa','Western Cape;Northern Cape;Eastern Cape;KwaZulu-Natal;Free State;Limpopo;North West'],
 ['overarching geographical unit','South Africa','Greater Cape'],
 ['region','South Africa','Cape South Coast;Coastal Region;Breede River Valley;Klein Karoo;Olifants River;Karoo-Hoogland'],
 ['overarching region','Western Cape','Cape Coast'],
 ['subregion','Coastal Region','Cape West Coast'],
 ['district','Cape South Coast','Cape Agulhas;Elgin;Lower Duivenhoks River;Overberg;Plettenberg Bay;Swellendam;Walker Bay;Still Bay'],
 ['district','Coastal Region','Cape Town;Darling;Franschhoek;Lutzville Valley;Paarl;Stellenbosch;Swartland;Tulbagh;Wellington'],
 ['district','Breede River Valley','Breedekloof;Robertson;Worcester'],
 ['district','Klein Karoo','Calitzdorp;Langeberg-Garcia'],
 ['district','Olifants River','Citrusdal Mountain;Citrusdal Valley'],
 ['district','Western Cape','Ceres Plateau;Nuveld-Karoo;Prince Albert'],
 ['district','Karoo-Hoogland','Sutherland-Karoo'],
 ['district','Northern Cape','Central Orange River;Douglas'],
 ['district','KwaZulu-Natal','Central Drakensberg;Lions River'],
 ['ward','Cape South Coast',"Elim;Elandskloof/Kaaimansgat;Greyton;Klein River;Shaw's Mountain;Theewater;Buffeljags;Malgas;Stormsvlei;Bot River;Hemel-en-Aarde Ridge;Hemel-en-Aarde Valley;Sunday's Glen;Springfontein Rim;Stanford Foothills;Upper Hemel-en-Aarde Valley;Goukou River Valley;Herbertsdale;Napier"],
 ['ward','Coastal Region','Constantia;Durbanville;Hout Bay;Philadelphia;Groenekloof;Koekenaap;Agter-Paarl;Simonsberg-Paarl;Voor-Paardeberg;Banghoek;Bottelary;Devon Valley;Jonkershoek Valley;Papegaaiberg;Polkadraai Hills;Simonsberg-Stellenbosch;Vlottenburg;Malmesbury;Paardeberg;Paardeberg South;Piket-Bo-Berg;Porseleinberg;Riebeekberg;Riebeeksrivier;St Helena Bay;Blouvlei;Bovlei;Groenberg;Limietberg;Mid-Berg River;Bamboes Bay;Lamberts Bay'],
 ['ward','Breede River Valley','Goudini;Slanghoek;Agterkliphoogte;Ashton;Boesmansrivier;Bonnievale;Eilandia;Goedemoed;Goree;Goudmyn;Hoopsrivier;Klaasvoogds;Le Chasseur;McGregor;Vinkrivier;Zandrivier;Hex River Valley;Keeromsberg;Moordkuil;Nuy;Rooikrans;Scherpenheuvel;Stettyn'],
 ['ward','Klein Karoo','Groenfontein;Cango Valley;Koo Plateau;Montagu;Outeniqua;Tradouw;Tradouw Highlands;Upper Langkloof'],
 ['ward','Olifants River','Piekenierskloof;Spruitdrift;Vredendal'],
 ['ward','Western Cape','Ceres;Kweekvallei;Prince Albert Valley;Swartberg;Nieuwoudtville;Cederberg;Leipoldtville-Sandveld'],
 ['ward','Northern Cape','Groblershoop;Grootdrink;Kakamas;Keimoes;Upington;Hartswater;Prieska'],
 ['ward','Eastern Cape','St Francis Bay'],
 ['ward','Free State','Rietrivier FS'],
 ['ward','No geographical unit','Lanseria'],
];
const zaRows=zaGroups.flatMap(([kind,group,names])=>names.split(';').map(name=>{
  const n=za.get(norm(name));
  return{register_name:name,register_kind:kind,source_group:group,node_id:n?.id??null,node_name:n?.name??null,added:n?newIds.has(n.id):false};
}));
assert.equal(zaRows.length,150);assert.equal(new Set(zaRows.map(r=>norm(r.register_name))).size,150);
const wards=zaRows.filter(r=>r.register_kind==='ward');
assert.equal(wards.length,102);
assert.equal(zaRows.filter(r=>r.register_kind==='district').length,32);
assert(zaRows.filter(r=>r.register_kind!=='ward').every(r=>r.node_id),'A nonward registered entry is absent');
const missingWards=wards.filter(r=>!r.node_id);
assert.equal(missingWards.length,1);
assert.equal(missingWards[0].register_name,'Paardeberg South');
const snapshots=Object.fromEntries(['au_gis','reference','gazetteer'].map(s=>{
  const path=`tool/geography/new_world_oceania_africa_${s}_points.geojson`,bytes=fs.readFileSync(path);
  return[s,{path,features:JSON.parse(bytes).features.length,sha256:sha(bytes)}];
}));
const saPdfPath='.dart_tool/world_atlas_sa_wo.pdf';
if(!fs.existsSync(saPdfPath)){
  const r=await fetch('https://www.sawis.co.za/cert/download/Production_areas_-_Eng_%26_Afr_-_Feb26.pdf',{signal:AbortSignal.timeout(120000)});
  assert(r.ok);const bytes=Buffer.from(await r.arrayBuffer());
  assert.equal(sha(bytes),'0a0beac0faf48ba2dd079295b69dca46437da5341e37674d060d767bb591c871','Primary legal edition changed');
  fs.writeFileSync(saPdfPath,bytes);
}
assert.equal(sha(fs.readFileSync(saPdfPath)),'0a0beac0faf48ba2dd079295b69dca46437da5341e37674d060d767bb591c871');
const report={audited_on:'2026-09-26',authored:{nodes:own.knowledge_nodes.length,location_items:own.knowledge_items.length,mappings:own.certification_knowledge_mappings.length,snapshots},australia:{source_url:'https://www.wineaustralia.com/labelling/register-of-protected-gis-and-other-terms/geographical-indications',source_html_sha256:sha(html),table_columns:{state_zone:37,region:63,subregion:14},unique_register_names:114,unique_noncountry_nodes:113,represented_names:114,missing_names:[],classification_notes:['The State/Zone column includes Australia, states, territories, zones and Adelaide super zone.','Tasmania is listed in the State/Zone column but also occurs in GIS region and zone layers; both records map to its existing single node.','Queensland doubles as state and zone; its single node is explicitly labelled (zone).','Murray Darling and Swan Hill span NSW and Victoria; existing country containment avoids false single-state nesting.','The register has 63 distinct Region-column names; the GIS region layer has 64 records including Tasmania.'],register_rows:registerRows,gis_layers:gisLayers},south_africa:{source_url:'https://www.sawis.co.za/cert/download/Production_areas_-_Eng_%26_Afr_-_Feb26.pdf',source_pdf_sha256:sha(fs.readFileSync('.dart_tool/world_atlas_sa_wo.pdf')),unique_register_entries:150,represented_entries:zaRows.filter(r=>r.node_id).length,counts:{geographical_units:7,overarching_geographical_units:1,regions:6,overarching_regions:1,subregions:1,districts:32,wards:102,represented_districts:32,represented_wards:101,missing_wards:1},classification_notes:['None placeholders are not places.','Simonsberg-Stellenbosh is a source spelling error mapped to the canonical Simonsberg-Stellenbosch node.','Nieuwoudtville is under the Western Cape Wine of Origin unit in this register, despite its town being politically in Northern Cape.','Lutzville Valley is under Coastal Region / Cape West Coast in this February 2026 register.','Qualified markers provide orientation; nearby locality/terrain references do not prove legal wine-area extent.','Paardeberg South has a verified legal classification but remains without an authored map target: proposed licensed farm references contradict the primary north-west/west locality description.'],register_rows:zaRows,missing_wards:missingWards}};
fs.writeFileSync('tool/geography/new_world_oceania_africa_inventory.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({AU:report.australia.table_columns,AU_names:114,SA:report.south_africa.counts,new:report.authored},null,2));
