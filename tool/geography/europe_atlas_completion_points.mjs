// Explicitly re-author this snapshot with --author. Normal builds use the
// checked-in GeoJSON; coordinate statements never imply legal boundaries.
import fs from 'node:fs';
import YAML from 'yaml';

// suffix, displayed name, type, parent, primary source, gazetteer title,
// optional wiki site, optional assertion. References are intentionally named.
const specs = [];
const add = (id,name,type,parent,source,title=name,wiki='enwiki',assertion=null) => specs.push({id,name,type,parent,source,title,wiki,assertion});
for (const [id,name,title] of [
 ['valle_d_aosta','Valle d’Aosta','Aosta Valley'], ['liguria','Liguria','Liguria'],
 ['trentino_alto_adige','Trentino-Alto Adige','Trentino-Alto Adige/Südtirol'],
 ['emilia_romagna','Emilia-Romagna','Emilia-Romagna'], ['umbria','Umbria','Umbria'],
 ['lazio','Lazio','Lazio'], ['abruzzo','Abruzzo','Abruzzo'], ['molise','Molise','Molise'],
 ['puglia','Puglia','Apulia'], ['basilicata','Basilicata','Basilicata'],
 ['calabria','Calabria','Calabria'], ['sardinia','Sardinia','Sardinia'],
]) add(id,name,'region','italy','istat',title);

const baroloCommunes = [
 ['barolo_commune','Barolo (commune)','Barolo','wholly'],
 ['castiglione_falletto','Castiglione Falletto','Castiglione Falletto','wholly'],
 ['serralunga_d_alba','Serralunga d’Alba',"Serralunga d'Alba",'wholly'],
 ['la_morra','La Morra','La Morra','partly'], ['monforte_d_alba','Monforte d’Alba',"Monforte d'Alba",'partly'],
 ['verduno','Verduno','Verduno','partly'], ['novello','Novello','Novello','partly'],
 ['grinzane_cavour','Grinzane Cavour','Grinzane Cavour','partly'],
 ['diano_d_alba','Diano d’Alba',"Diano d'Alba",'partly'], ['cherasco','Cherasco','Cherasco','partly'], ['roddi','Roddi','Roddi','partly'],
];
for (const [id,name,title,extent] of baroloCommunes) add(id,name,'village','piedmont','barolo',title,'enwiki',`${name} is a Piedmont wine locality; its municipality is ${extent} included in the Barolo production zone. The marker identifies the locality, not the municipality or appellation boundary.`);
for (const [id,name,title] of [['barbaresco_commune','Barbaresco (commune)','Barbaresco'],['neive','Neive','Neive'],['treiso','Treiso','Treiso'],['san_rocco_seno_d_elvio','San Rocco Seno d’Elvio','San Rocco Seno d’Elvio']])
 add(id,name,'village','piedmont','barbaresco',title,id==='san_rocco_seno_d_elvio'?'itwiki':'enwiki',`${name} is a wine locality in Piedmont named in the Barbaresco production-zone specification. For San Rocco Seno d’Elvio, only the delimited part of the Alba frazione is included.`);

for (const [id,name,title] of [
 ['castellina_uga','Castellina','Castellina in Chianti'], ['castelnuovo_berardenga_uga','Castelnuovo Berardenga','Castelnuovo Berardenga'],
 ['gaiole_uga','Gaiole','Gaiole in Chianti'], ['greve_uga','Greve','Greve in Chianti'], ['lamole_uga','Lamole','Lamole'],
 ['montefioralle_uga','Montefioralle','Montefioralle'], ['panzano_uga','Panzano','Panzano in Chianti'],
 ['radda_uga','Radda','Radda in Chianti'], ['san_casciano_uga','San Casciano','San Casciano in Val di Pesa'],
 ['san_donato_in_poggio_uga','San Donato in Poggio','San Donato in Poggio'], ['vagliagli_uga','Vagliagli','Vagliagli'],
]) add(id,name,'subregion','chianti_classico','classico',title,'enwiki',`${name} is a delimited unità geografica aggiuntiva within Chianti Classico. The reference point marks the named locality, not the full UGA; this geography item makes no wine-labelling or vintage claim.`);
for (const [id,name,title] of [
 ['chianti_colli_aretini','Chianti Colli Aretini','Arezzo'], ['chianti_colli_fiorentini','Chianti Colli Fiorentini','Impruneta'],
 ['chianti_colli_senesi','Chianti Colli Senesi','Siena'], ['chianti_colline_pisane','Chianti Colline Pisane','Terricciola'],
 ['chianti_montalbano','Chianti Montalbano','Carmignano'], ['chianti_montespertoli','Chianti Montespertoli','Montespertoli'],
 ['chianti_rufina','Chianti Rufina','Rufina'],
 ['chianti_terre_di_vinci','Chianti Terre di Vinci','Vinci, Tuscany'],
]) add(id,name,'subregion','chianti','chianti',title);

add('valpolicella_classico','Valpolicella Classico','subregion','valpolicella','valpolicella','Fumane');
add('valpantena','Valpantena','subregion','valpolicella','valpolicella','Valpantena','itwiki');
for (const [id,name,title] of [['fumane','Fumane','Fumane'],['marano_di_valpolicella','Marano di Valpolicella','Marano di Valpolicella'],['negrar','Negrar di Valpolicella','Negrar'],['sant_ambrogio_di_valpolicella','Sant’Ambrogio di Valpolicella',"Sant'Ambrogio di Valpolicella"],['san_pietro_in_cariano','San Pietro in Cariano','San Pietro in Cariano']])
 add(id,name,'village','veneto','valpolicella',title,'enwiki',`${name} is a Veneto wine locality in the municipality named by the Valpolicella Classico zone. The map marker is a locality reference, not a wine-area boundary.`);
add('soave_classico','Soave Classico','subregion','soave','soave','Soave');
add('soave_colli_scaligeri','Soave Colli Scaligeri','subregion','soave','soave','Colognola ai Colli');
add('soave_commune','Soave (commune)','village','veneto','soave','Soave');
add('monteforte_d_alpone','Monteforte d’Alpone','village','veneto','soave',"Monteforte d'Alpone");
add('cartizze','Cartizze','subregion','conegliano_valdobbiadene','cartizze','Santo Stefano (Valdobbiadene)','itwiki');
add('conegliano','Conegliano','village','veneto','cartizze','Conegliano');
add('valdobbiadene','Valdobbiadene','village','veneto','cartizze','Valdobbiadene');

add('alto_adige','Alto Adige / Südtirol','appellation','trentino_alto_adige','dop','South Tyrol');
for (const [id,name,title,wiki] of [
 ['alto_adige_valle_isarco','Valle Isarco / Eisacktal','Brixen','enwiki'],
 ['alto_adige_val_venosta','Val Venosta / Vinschgau','Schlanders','enwiki'],
 ['alto_adige_terlano','Terlano / Terlan','Terlan','enwiki'], ['alto_adige_merano','Merano / Meraner','Merano','enwiki'],
 ['alto_adige_colli_bolzano','Colli di Bolzano / Bozner Leiten','Rentsch (Bozen)','dewiki'],
 ['alto_adige_santa_maddalena','Santa Maddalena / St. Magdalener','St. Magdalena (Bozen)','dewiki'],
]) add(id,name,'subregion','alto_adige','alto',title,wiki);
add('friuli_colli_orientali','Friuli Colli Orientali','appellation','friuli_venezia_giulia','friuli','Cividale del Friuli');
add('friuli_cialla','Cialla','subregion','friuli_colli_orientali','friuli','Cialla','itwiki');
add('friuli_rosazzo_subzones','Rosazzo (Colli Orientali subzones)','informal_area','friuli_colli_orientali','friuli','Abbazia di Rosazzo','itwiki','The Ribolla Gialla di Rosazzo and Pignolo di Rosazzo geographical subzones are in Friuli Colli Orientali. This study area groups their common Rosazzo location; it is not a separate appellation or a new legal subzone.');
add('friuli_schioppettino_prepotto','Schioppettino di Prepotto','subregion','friuli_colli_orientali','friuli','Prepotto');
add('friuli_savorgnano','Savorgnano','subregion','friuli_colli_orientali','friuli','Savorgnano del Torre','itwiki');
add('friuli_refosco_faedis','Refosco di Faedis','subregion','friuli_colli_orientali','friuli','Faedis');
add('alto_piemonte','Alto Piemonte (wine area)','informal_area','piedmont','alto_piemonte','Ghemme','enwiki','Alto Piemonte is the northern Piedmont wine-study area associated with Ghemme, Gattinara and the surrounding wine districts. It is an informal geographical grouping, not a separate DOC or DOCG.');

// Existing MASAF register citation: exact appellation names and administrative
// regions, with representative settlements explicitly distinguished in GeoJSON.
for (const [id,name,parent,title,wiki='enwiki'] of [
 ['nebbiolo_d_alba','Nebbiolo d’Alba','piedmont','Alba, Piedmont'],
 ['barbera_del_monferrato','Barbera del Monferrato','piedmont','Nizza Monferrato'],
 ['brachetto_d_acqui','Brachetto d’Acqui','piedmont','Acqui Terme'],
 ['boca','Boca','piedmont','Boca, Piedmont'], ['fara','Fara','piedmont','Fara Novarese'],
 ['lessona','Lessona','piedmont','Lessona'], ['bramaterra','Bramaterra','piedmont','Brusnengo'], ['sizzano','Sizzano','piedmont','Sizzano'],
 ['monferrato','Monferrato','piedmont','Casale Monferrato'],
 ['rosso_di_montalcino','Rosso di Montalcino','tuscany','Montalcino'],
 ['bolgheri_sassicaia','Bolgheri Sassicaia','tuscany','Castagneto Carducci'],
 ['maremma_toscana','Maremma Toscana','tuscany','Grosseto'],
 ['bardolino','Bardolino','veneto','Bardolino'], ['lugana','Lugana','italy','Sirmione'],
 ['gambellara','Gambellara','veneto','Gambellara'], ['breganze','Breganze','veneto','Breganze'],
 ['prosecco','Prosecco','italy','Treviso'],
 ['trentino','Trentino','trentino_alto_adige','Trento'], ['trento_doc','Trento','trentino_alto_adige','Rovereto'],
 ['teroldego_rotaliano','Teroldego Rotaliano','trentino_alto_adige','Mezzolombardo'],
 ['lago_di_caldaro','Lago di Caldaro / Kalterersee','trentino_alto_adige','Kaltern an der Weinstraße'],
 ['valtellina_superiore','Valtellina Superiore','lombardy','Teglio'], ['sforzato_valtellina','Sforzato di Valtellina','lombardy','Sondrio'],
 ['oltrepo_pavese','Oltrepò Pavese','lombardy','Casteggio'],
 ['ramandolo','Ramandolo','friuli_venezia_giulia','Nimis'], ['rosazzo','Rosazzo','friuli_venezia_giulia','Manzano'],
 ['friuli_grave','Friuli Grave','friuli_venezia_giulia','Codroipo'],
 ['colli_orientali_picolit','Colli Orientali del Friuli Picolit','friuli_venezia_giulia','Corno di Rosazzo'],
 ['lambrusco_sorbara','Lambrusco di Sorbara','emilia_romagna','Bomporto'],
 ['lambrusco_grasparossa','Lambrusco Grasparossa di Castelvetro','emilia_romagna','Castelvetro di Modena'],
 ['lambrusco_salamino','Lambrusco Salamino di Santa Croce','emilia_romagna','Carpi, Emilia-Romagna'],
 ['romagna_albana','Romagna Albana','emilia_romagna','Bertinoro'],
 ['montefalco_sagrantino','Montefalco Sagrantino','umbria','Montefalco'], ['torgiano','Torgiano','umbria','Torgiano'],
 ['orvieto','Orvieto','italy','Orvieto'],
 ['verdicchio_matelica','Verdicchio di Matelica','marche','Matelica'], ['conero','Conero','marche','Sirolo'],
 ['montepulciano_abruzzo','Montepulciano d’Abruzzo','abruzzo','Chieti'],
 ['trebbiano_abruzzo','Trebbiano d’Abruzzo','abruzzo','Pescara'],
 ['cerasuolo_abruzzo','Cerasuolo d’Abruzzo','abruzzo','Ortona'],
 ['fiano_avellino','Fiano di Avellino','campania','Avellino'], ['greco_tufo','Greco di Tufo','campania','Tufo, Campania'],
 ['vesuvio','Vesuvio','campania','Mount Vesuvius'], ['aglianico_vulture','Aglianico del Vulture','basilicata','Rionero in Vulture'],
 ['primitivo_manduria','Primitivo di Manduria','puglia','Manduria'], ['salice_salentino','Salice Salentino','puglia','Salice Salentino'],
 ['castel_del_monte','Castel del Monte','puglia','Andria'], ['c iro','Cirò','calabria','Cirò'],
 ['cerasuolo_vittoria','Cerasuolo di Vittoria','sicily','Vittoria, Sicily'], ['marsala','Marsala','sicily','Marsala'],
 ['pantelleria','Pantelleria','sicily','Pantelleria'], ['faro','Faro','sicily','Messina'],
 ['cannonau_sardegna','Cannonau di Sardegna','sardinia','Nuoro'],
 ['vermentino_gallura','Vermentino di Gallura','sardinia','Tempio Pausania'],
 ['vernaccia_oristano','Vernaccia di Oristano','sardinia','Oristano'],
 ['cinque_terre','Cinque Terre','liguria','Riomaggiore'], ['frascati','Frascati','lazio','Frascati'],
]) add(id.replaceAll(' ',''),name,'appellation',parent,'dop',title,wiki);

// Ten current Sherry municipalities; no false assertion of an exclusive triangle.
for (const [id,name,title] of [
 ['jerez_town','Jerez de la Frontera','Jerez de la Frontera'], ['el_puerto_santa_maria','El Puerto de Santa María','El Puerto de Santa María'],
 ['sanlucar_town','Sanlúcar de Barrameda','Sanlúcar de Barrameda'], ['trebujena','Trebujena','Trebujena'],
 ['lebrija','Lebrija','Lebrija'], ['chipiona','Chipiona','Chipiona'], ['rota','Rota','Rota, Andalusia'],
 ['chiclana','Chiclana de la Frontera','Chiclana de la Frontera'], ['puerto_real','Puerto Real','Puerto Real'],
 ['san_jose_del_valle','San José del Valle','San José del Valle'],
]) add(id,name,'village','andalusia','sherry',title,'enwiki',`${name} is an Andalusian municipality in the current Marco de Jerez production and ageing area. The historic Sherry Triangle does not represent the exclusive current ageing zone.`);
for (const [id,name,parent,title] of [
 ['cava_comtats_barcelona','Comtats de Barcelona','cava','Sant Sadurní d’Anoia'],
 ['cava_valle_ebro','Valle del Ebro (Cava)','cava','Logroño'],
 ['cava_almendralejo','Viñedos de Almendralejo','cava','Almendralejo'], ['cava_requena','Requena (Cava)','cava','Requena, Spain'],
 ['cava_anoia_foix','Valls d’Anoia-Foix','cava_comtats_barcelona','Vilafranca del Penedès'],
 ['cava_serra_mar','Serra de Mar','cava_comtats_barcelona','Alella'],
 ['cava_conca_gaia','Conca del Gaià','cava_comtats_barcelona','Vila-rodona'],
 ['cava_serra_prades','Serra de Prades','cava_comtats_barcelona','Vimbodí i Poblet'],
 ['cava_pla_ponent','Pla de Ponent','cava_comtats_barcelona','Lleida'],
 ['cava_alto_ebro','Alto Ebro','cava_valle_ebro','Haro'], ['cava_valle_cierzo','Valle del Cierzo','cava_valle_ebro','Cariñena'],
]) add(id,name,'subregion',parent,'cava',title);

const source = (key,kind,title,publisher,url,jurisdiction='IT') => ({id:`src_eac_${key}`,kind,title,publisher,url,jurisdiction,accessed_on:'2026-09-26',document_identifier:title});
const sources = [
 source('istat','government_publication','Codici delle unità amministrative, aggiornamento 21 febbraio 2026','Istat','https://www.istat.it/classificazione/codici-dei-comuni-delle-province-e-delle-regioni/'),
 source('barolo','legislation','Barolo DOCG, disciplinare consolidato 4 marzo 2026','MASAF','https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F1%252Ff%252FD.1d67b26ddf258a620c54/P/BLOB%3AID%3D24322/E/pdf?mode=download'),
 source('barbaresco','legislation','Barbaresco DOCG, disciplinare consolidato 13 luglio 2021','MASAF','https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/d%252Ff%252Fc%252FD.541a04d94cb951e58c1a/P/BLOB%3AID%3D17249/E/pdf?mode=download'),
 source('classico','legislation','Chianti Classico, disciplinare e UGAs, G.U. 1 luglio 2023','MASAF / Gazzetta Ufficiale','https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252Fa%252F3%252FD.44b01b3b420b36ba8d22/P/BLOB%3AID%3D19090/E/pdf?mode=download'),
 source('chianti','legislation','Chianti DOCG, modifica ordinaria 5 giugno 2026, G.U. 12 giugno 2026','Gazzetta Ufficiale','https://www.gazzettaufficiale.it/atto/vediMenuHTML?atto.codiceRedazionale=26A02927&atto.dataPubblicazioneGazzetta=2026-06-12&tipoSerie=serie_generale&tipoVigenza=originario'),
 source('valpolicella','legislation','Valpolicella DOC, produzione e zone Classico e Valpantena','MASAF','https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F9%252F8%252FD.de597137377d2031a5b1/P/BLOB%3AID%3D20314/E/pdf?mode=download'),
 source('soave','legislation','Soave DOP, disciplinare consolidato 24 ottobre 2019','MASAF','https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/8%252F7%252F4%252FD.23ded3ebd89b0b969edf/P/BLOB%3AID%3D14701/E/pdf?mode=download'),
 source('cartizze','regulator_register','Cartizze and the named Conegliano Valdobbiadene wine localities','Consorzio Conegliano Valdobbiadene Prosecco','https://www.prosecco.it/it/scheda-itinerario/il-pentagono-d-oro-del-cartizze/'),
 source('alto','regulator_register','Alto Adige DOC and its six geographical subzones','Consorzio Vini Alto Adige','https://www.suedtirolwein.com/unser-wein/herkunft-doc'),
 source('friuli','legislation','Friuli Colli Orientali DOC, decreto 7 luglio 2025 e disciplinare consolidato','MASAF','https://www.masaf.gov.it/flex/cm/pages/ServeBLOB.php/L/IT/IDPagina/23484'),
 source('alto_piemonte','government_publication','Northern Piedmont wine districts around Ghemme and Gattinara','Visit Piemonte, official regional tourism agency','https://www.visitpiemonte.com/en/destinations/novara-a-baroque-gem-surrounded-by-plains-and-rice-fields'),
 source('sherry','regulator_register','Marco de Jerez: ten production and ageing municipalities, 14 November 2025','Consejo Regulador Jerez-Xérès-Sherry','https://www.sherry.wine/news/the-sherry-triangle-evolves-from-three-to-ten','ES'),
 source('cava','regulator_register','Cava: four zones and seven subzones','Consejo Regulador DOP Cava','https://www.cava.wine/en/origin-cava/4-zones/','ES'),
];

if (!process.argv.includes('--author')) {
 console.log(`European atlas completion specifications: ${specs.length}. Use --author for an explicit source refresh.`);
 process.exit(0);
}
fs.mkdirSync('.dart_tool/europe_atlas_completion',{recursive:true});
const entities = new Map();
for (const wiki of [...new Set(specs.map(s=>s.wiki))]) {
 const titles=[...new Set(specs.filter(s=>s.wiki===wiki).map(s=>s.title))];
 for(let i=0;i<titles.length;i+=40) {
  const batch=titles.slice(i,i+40), url=new URL('https://www.wikidata.org/w/api.php');
  for(const [k,v] of Object.entries({action:'wbgetentities',sites:wiki,titles:batch.join('|'),props:'labels|descriptions|claims|sitelinks',languages:'en|it|de|es',redirects:'yes',format:'json'})) url.searchParams.set(k,v);
  const cache=`.dart_tool/europe_atlas_completion/${wiki}-${i}.json`;
  await new Promise(resolve=>setTimeout(resolve,1500));
  const response=await fetch(url,{headers:{'User-Agent':'SommelierStudyCompanion/0.10 geography authoring'}});
  if(!response.ok) throw Error(`Wikidata: ${response.status}`);
  const data=await response.json(); fs.writeFileSync(cache,JSON.stringify(data,null,2));
  for(const entity of Object.values(data.entities)) if(entity.sitelinks?.[wiki]?.title) entities.set(`${wiki}:${entity.sitelinks[wiki].title}`,entity);
 }
}
const explicitIds={barolo_commune:'Q18356',novello:'Q20268',barbaresco_commune:'Q18353',san_rocco_seno_d_elvio:'Q18440721',lamole_uga:'Q18487026',panzano_uga:'Q3893502',san_donato_in_poggio_uga:'Q3947022',negrar:'Q46941',soave_classico:'Q47876',soave_commune:'Q47876',cartizze:'Q18502495',friuli_cialla:'Q18450962',rosazzo:'Q53279',ciro:'Q54501',boca:'Q22079',rota:'Q15907',cava_comtats_barcelona:'Q984508',cava_alto_ebro:'Q405292',cava_valle_cierzo:'Q984529'};
const exactResponse=await fetch('https://www.wikidata.org/w/api.php?action=wbgetentities&ids='+[...new Set(Object.values(explicitIds))].join('|')+'&props=labels|descriptions|claims&languages=en|it|de|es&format=json').then(r=>r.json());
fs.writeFileSync('.dart_tool/europe_atlas_completion/explicit.json',JSON.stringify(exactResponse,null,2));
const features=[],missing=[];
for(const s of specs) {
 const entity=explicitIds[s.id]?exactResponse.entities[explicitIds[s.id]]:entities.get(`${s.wiki}:${s.title}`);
 const claim=entity?.claims?.P625?.find(c=>c.rank!=='deprecated' && c.mainsnak?.datavalue?.value?.globe==='http://www.wikidata.org/entity/Q2');
 const p=claim?.mainsnak.datavalue.value;
 if(!p) {missing.push(`${s.id}: ${s.wiki} ${s.title} (${entity?.id??'missing entity'})`);continue;}
 const label=entity.labels?.en?.value??entity.labels?.it?.value??s.title;
 features.push({type:'Feature',properties:{node:`n_geo_${s.id}`,name:s.name,
  point_role:s.type==='village'?'named locality reference point; not municipality or appellation boundary':'explicit gazetteer or settlement reference; not legal wine-area boundary',
  point_place_name:label,point_description:entity.descriptions?.en?.value??entity.descriptions?.it?.value??'',
  wikidata_id:entity.id,source_coordinate_claim:claim.id,source_coordinate_url:`https://www.wikidata.org/wiki/Special:EntityData/${entity.id}.json`,
  source_url:`https://www.wikidata.org/wiki/${entity.id}`,retrieved_on:'2026-09-26',coordinate_precision:p.precision,
  license:'CC0 1.0',label_note:`Reference: ${label}. Point is not the area's legal boundary.`},geometry:{type:'Point',coordinates:[p.longitude,p.latitude]}});
}
fs.writeFileSync('.dart_tool/europe_atlas_completion/missing.json',JSON.stringify(missing,null,2));
if(missing.length) {console.log(missing.join('\n'));throw Error(`${missing.length} unresolved coordinates; no snapshot/content written`);}
const nodes=specs.map(s=>({id:`n_geo_${s.id}`,node_type:s.type,name:s.name}));
const relations=specs.map(s=>({subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,valid_from:'1900-01-01'}));
const parentNames={italy:'Italy',piedmont:'Piedmont',tuscany:'Tuscany',veneto:'Veneto',lombardy:'Lombardy',friuli_venezia_giulia:'Friuli Venezia Giulia',marche:'Marche',campania:'Campania',sicily:'Sicily',andalusia:'Andalusia',chianti:'Chianti',chianti_classico:'Chianti Classico',valpolicella:'Valpolicella',soave:'Soave',conegliano_valdobbiadene:'Conegliano Valdobbiadene Prosecco',cava:'Cava',...Object.fromEntries(specs.map(s=>[s.id,s.name]))};
const items=specs.map(s=>({id:`ki_eac_${s.id}_location`,subject_id:`n_geo_${s.id}`,relation_type:'LOCATED_IN',object_id:`n_geo_${s.parent}`,domain_id:'geography',assertion_text:s.assertion??`${s.name} is located within ${parentNames[s.parent]}. Its map point is an explicitly named geographic reference, not a legal wine-area boundary.`,verification_status:'unverified',last_verified_at:'2026-09-26T12:00:00.000Z'}));
const citations=specs.map(s=>({knowledge_item_id:`ki_eac_${s.id}_location`,source_citation_id:s.source==='dop'?'src_atlas_it_dop_2026':`src_eac_${s.source}`,locator:s.source==='dop'?`Register entry ${s.name}; listed administrative region(s).`:`${s.name}: production-area or geographic-unit section; locality reference ${s.title}.`}));
const tracks=specs.flatMap(s=>['WSET_L3','CMS_CERTIFIED'].map(certification_id=>({certification_id,knowledge_item_id:`ki_eac_${s.id}_location`,minimum_depth:2,importance:'secondary'})));
const aliases=[['barolo_commune','Barolo'],['barbaresco_commune','Barbaresco'],['soave_commune','Soave'],['valle_d_aosta','Aosta Valley'],['puglia','Apulia'],['sardinia','Sardegna'],['alto_adige','Südtirol'],['alto_adige','Alto Adige'],['castellina_uga','Castellina in Chianti'],['gaiole_uga','Gaiole in Chianti'],['greve_uga','Greve in Chianti'],['panzano_uga','Panzano in Chianti'],['radda_uga','Radda in Chianti'],['san_casciano_uga','San Casciano in Val di Pesa'],['negrar','Negrar'],['alto_piemonte','Alto Piemonte'],['alto_adige_valle_isarco','Valle Isarco'],['alto_adige_valle_isarco','Eisacktal'],['alto_adige_val_venosta','Val Venosta'],['alto_adige_val_venosta','Vinschgau'],['alto_adige_terlano','Terlano'],['alto_adige_terlano','Terlan'],['alto_adige_merano','Merano'],['alto_adige_merano','Meraner'],['alto_adige_colli_bolzano','Colli di Bolzano'],['alto_adige_colli_bolzano','Bozner Leiten'],['alto_adige_santa_maddalena','Santa Maddalena'],['alto_adige_santa_maddalena','St. Magdalener'],['lago_di_caldaro','Lago di Caldaro'],['lago_di_caldaro','Kalterersee']].map(([id,name])=>({knowledge_node_id:`n_geo_${id}`,name,kind:'synonym'}));
const content={knowledge_nodes:nodes,node_alternative_names:aliases,knowledge_relations:relations,knowledge_items:items,certification_knowledge_mappings:tracks,knowledge_item_citations:citations,source_citations:sources};
const authoredPath='assets/curriculum/areas/europe_atlas_completion.yaml';
if(fs.existsSync(authoredPath)) {
 const previous=YAML.parse(fs.readFileSync(authoredPath,'utf8'));
 for(const table of ['knowledge_nodes','knowledge_items','source_citations']) {
  const nextIds=new Set(content[table].map(row=>row.id));
  const missing=(previous[table]??[]).filter(row=>!nextIds.has(row.id)).map(row=>row.id);
  if(missing.length) throw Error(`Refusing to delete authored ${table}: ${missing.join(', ')}`);
 }
}
fs.writeFileSync('assets/curriculum/areas/europe_atlas_completion.yaml','# European geography completion. Source-cited facts remain unverified.\n# Municipality markers are locality references, not complete wine-zone boundaries.\n'+YAML.stringify(content));
fs.writeFileSync('tool/geography/europe_atlas_completion_points.geojson',JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
console.log(`Authored ${nodes.length} geography nodes, ${items.length} location items and ${features.length} CC0 points.`);
