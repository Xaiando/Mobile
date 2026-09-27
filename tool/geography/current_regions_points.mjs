// Reproduce the existing European atlas's CC0 gazetteer snapshot.
// Explicit region or representative municipality titles: never a guessed boundary.
import fs from 'node:fs';
import { readCurriculum } from './lib.mjs';
const c = readCurriculum();
const specs = [
 ['piedmont','Piedmont'],['tuscany','Tuscany'],['langhe','Langhe'],
 ['barolo','Barolo','Q18356'],['barbaresco','Barbaresco','Q18353'],['brunello_di_montalcino','Montalcino'],['chianti_classico','Greve in Chianti'],
 ['ahr','Bad Neuenahr-Ahrweiler'],['baden','Freiburg im Breisgau'],['franken','Würzburg'],
 ['hessische_bergstrasse','Bensheim'],['mittelrhein','Bacharach'],['mosel','Bernkastel-Kues'],
 ['nahe','Bad Kreuznach'],['pfalz','Neustadt an der Weinstraße'],['rheingau','Rüdesheim am Rhein'],
 ['rheinhessen','Mainz'],['saale_unstrut','Freyburg','Q529853'],['sachsen','Meissen'],['wuerttemberg','Stuttgart'],
 ['niederoesterreich','Lower Austria'],['burgenland','Burgenland'],['steiermark','Styria'],['wien','Vienna'],
 ['thermenregion','Gumpoldskirchen'],['kremstal','Krems an der Donau'],['kamptal','Langenlois'],['wagram','Kirchberg am Wagram'],
 ['traisental','Traismauer'],['carnuntum','Petronell-Carnuntum'],['wachau','Wachau'],['weinviertel','Poysdorf'],
 ['suedsteiermark','Gamlitz'],['weinviertel_dac','Poysdorf'],['kamptal_dac','Langenlois'],
 ['mittelburgenland','Deutschkreutz'],['mittelburgenland_dac','Deutschkreutz'],
 ['valais','Valais'],['vaud','Vaud'],['geneva','Canton of Geneva'],['ticino','Ticino'],
 ['lavaux','Lavaux'],['la_cote','Rolle'],['chablais_vaud','Aigle'],['tokaj','Tokaj'],
 ['peloponnese','Peloponnese'],['macedonia','Macedonia (Greece)'],['cyclades','Cyclades'],
 ['nemea','Nemea (town)'],['naoussa','Naousa, Imathia'],['santorini','Santorini'],
];
const titles = [...new Set(specs.map(x=>x[1]))];
const url = new URL('https://www.wikidata.org/w/api.php');
Object.entries({action:'wbgetentities',sites:'enwiki',titles:titles.join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en',redirects:'yes',format:'json'}).forEach(([k,v])=>url.searchParams.set(k,v));
const res = await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.9 Geography'}});
if (!res.ok) throw Error(`Wikidata ${res.status}`);
const data = await res.json();
const extra = await fetch('https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q18356|Q18353|Q529853&props=labels|claims&format=json').then(r=>r.json());
fs.writeFileSync('.dart_tool/current_region_entities.json',JSON.stringify(data,null,2));
const features=[];
for(const [suffix,title,id] of specs) {
 const entity = id ? extra.entities[id] : Object.values(data.entities).find(x=>x.sitelinks?.enwiki?.title===title);
 const p = entity?.claims?.P625?.find(x=>x.rank!=='deprecated')?.mainsnak?.datavalue?.value;
 if (!p) {console.log(`MISSING ${suffix} ${title}`);continue;}
 const node=`n_geo_${suffix}`;
 features.push({type:'Feature',properties:{node,name:c.nodes.get(node).name,
  point_role:'gazetteer marker; not a wine-area boundary',point_place_name:title,
  wikidata_id:entity.id,source_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,
  retrieved_on:'2026-09-26',license:'CC0 1.0'},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}});
 console.log(`${node}: ${title} (${entity.id}) ${p.longitude},${p.latitude}`);
}
fs.writeFileSync('tool/geography/current_regions_points.geojson',JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
