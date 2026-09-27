// Register checked-in, source-backed coordinate snapshots and their licences.
import fs from 'node:fs';
import YAML from 'yaml';
import { sha256 } from './lib.mjs';
const sourceFile='tool/geography/sources.yaml';
const sources=YAML.parseDocument(fs.readFileSync(sourceFile,'utf8'));
const layerFile='tool/geography/layers.yaml';
const layers=YAML.parseDocument(fs.readFileSync(layerFile,'utf8'));
const citationFile='assets/curriculum/areas/geography.yaml';
const citations=YAML.parseDocument(fs.readFileSync(citationFile,'utf8'));
for(const [file,id,title,licence,url,publisher] of [
 ['current_regions_points.geojson','current_regions','European wine-area location markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['world_atlas_points.geojson','world_atlas','World wine-area location markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['central_europe_atlas_points.geojson','central_europe_atlas','Central European wine-area location markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['france_atlas_points.geojson','france_atlas','French vineyard and wine-area location markers','Licence Ouverte / Open Licence 2.0 (Etalab)','https://www.data.gouv.fr/fr/datasets/delimitation-parcellaire-des-aoc-viticoles-de-linao/','INAO'],
 ['france_champagne_points.geojson','france_champagne','Champagne traditional wine-area location markers','Licence Ouverte / Open Licence 2.0 (Etalab)','https://data.geopf.fr/telechargement/download/ADMIN-EXPRESS-COG-CARTO/ADMIN-EXPRESS-COG-CARTO_4-0__GPKG_LAMB93_FXX_2026-01-01/ADMIN-EXPRESS-COG-CARTO_4-0__GPKG_LAMB93_FXX_2026-01-01.7z','IGN and Wikidata'],
 ['france_chablis_cadastre_points.geojson','france_chablis_cadastre','Chablis Premier Cru vineyard location markers','Licence Ouverte / Open Licence 1.0 (Etalab)','https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89068/cadastre-89068-lieux_dits.json.gz','DGFiP and Etalab'],
 ['france_atlas_completion_points.geojson','france_atlas_completion','Additional Chablis and Alsace vineyard location markers','Licence Ouverte / Open Licence 2.0 (Etalab)','https://static.data.gouv.fr/resources/delimitation-parcellaire-des-aoc-viticoles-de-linao/20260921-213954/2026-09-21-delim-parcellaire-aoc-shp.zip','INAO'],
 ['france_atlas_completion_cadastre_points.geojson','france_atlas_completion_cadastre','Additional Chablis climat location markers','Licence Ouverte / Open Licence 1.0 (Etalab)','https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/','DGFiP and Etalab'],
 ['france_atlas_completion_reference_points.geojson','france_atlas_completion_reference','Chablis climat municipality reference','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['europe_atlas_completion_points.geojson','europe_atlas_completion','Italian and Spanish wine-area location markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['new_world_atlas_completion_points.geojson','new_world_atlas_completion','Additional New World wine-area location markers','CC0 1.0','https://github.com/UCDavisLibrary/ava/tree/7af5b29d45aee5e6c6ce3889e9b1de19085d7107','UC Davis Library and Wikidata'],
 ['new_world_atlas_completion_gazetteer_points.geojson','new_world_atlas_completion_gazetteer','New World locality and terrain reference markers','CC BY 4.0','https://www.geonames.org/','GeoNames'],
 ['british_atlas_points.geojson','british_atlas','England and Wales wine-area reference markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['china_atlas_points.geojson','china_atlas','Chinese wine-area reference markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['diploma_us_atlas_points.geojson','diploma_us_atlas','New York wine-area reference markers','CC0 1.0','https://raw.githubusercontent.com/UCDavisLibrary/ava/7af5b29d45aee5e6c6ce3889e9b1de19085d7107/avas_aggregated_files/avas.geojson','UC Davis Library and Wikidata'],
 ['diploma_regions_points.geojson','diploma_regions','Diploma regional reference markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['new_world_oceania_africa_au_gis_points.geojson','new_world_oceania_africa_au_gis','Australian wine GI interior reference markers','CC BY 4.0','https://services6.arcgis.com/s8j6JbJJCqmhNgh7/arcgis/rest/services/Wine_Geographical_Indications_Australia/FeatureServer','Wine Australia'],
 ['new_world_oceania_africa_reference_points.geojson','new_world_oceania_africa_reference','Australian and South African reference markers','CC0 1.0','https://www.wikidata.org/wiki/Wikidata:Licensing','Wikidata'],
 ['new_world_oceania_africa_gazetteer_points.geojson','new_world_oceania_africa_gazetteer','South African locality and terrain references','CC BY 4.0','https://download.geonames.org/export/dump/ZA.zip','GeoNames'],
 ['new_world_americas_points.geojson','new_world_americas','American wine-area reference markers','CC0 1.0','https://github.com/UCDavisLibrary/ava/blob/7af5b29d45aee5e6c6ce3889e9b1de19085d7107/avas_aggregated_files/avas.geojson','UC Davis Library and Wikidata'],
 ['new_world_americas_gazetteer_points.geojson','new_world_americas_gazetteer','American locality and terrain references','CC BY 4.0','https://download.geonames.org/export/dump/','GeoNames'],
]) {
 const path=`tool/geography/${file}`;
 if(!fs.existsSync(path))continue;
 const sourceId=`src_${id}_markers`,layerId=`ml_${id}_markers`;
 const attribution=publisher==='Wikidata'
  ? 'Location markers from Wikidata (CC0), retrieved 26 September 2026. Points indicate locations, not wine-area boundaries.'
  : publisher==='INAO' ? 'INAO – vineyard parcels, 21 September 2026. Points indicate vineyard locations, not appellation boundaries.'
  : publisher==='DGFiP and Etalab' ? 'DGFiP / Etalab – French cadastre, edition June 2026 (Open Licence 1.0). Points indicate vineyard locations, not Premier Cru boundaries; cadastral names are matched using INAO product definitions.'
  : publisher==='UC Davis Library and Wikidata' ? 'UC Davis Library / DataLab American Viticultural Areas Project, commit 7af5b29d45aee5e6c6ce3889e9b1de19085d7107 (CC0), and Wikidata (CC0), retrieved 26 September 2026. Reference markers indicate locations, not legal wine-area boundaries.'
  : publisher==='GeoNames' ? 'Contains GeoNames geographical data (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), retrieved 26 September 2026. Selected WGS84 locality and terrain coordinates are reference markers, not wine-area boundaries or official centroids.'
  : publisher==='Wine Australia' ? '© Wine Australia, Geographical Indications of Australia (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), retrieved 26 September 2026. Interior reference markers derived from GIS interpretations; legal textual definitions prevail. Points are not official centroids or legal boundaries.'
  : 'IGN – ADMIN EXPRESS COG CARTO, edition 1 January 2026 (Open Licence 2.0); Wikidata (CC0). Points indicate locations, not wine-area boundaries.';
 const snapshotData=JSON.parse(fs.readFileSync(path,'utf8'));
 const qids=[...new Set(snapshotData.features.map(f=>f.properties.wikidata_id).filter(Boolean))];
 const coordinateUrl = publisher==='Wikidata'
  ? `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${qids.slice(0,50).join('|')}&props=claims&format=json`
  : publisher==='IGN and Wikidata' ? 'https://geoservices.ign.fr/adminexpress' : url;
 const source={id:sourceId,title,publisher,url:coordinateUrl,file,snapshot:file,version:'2026-09-26 curated snapshot',retrieved:'2026-09-26',sha256:sha256(fs.readFileSync(path)),license:licence,attribution};
 const sequence=sources.get('sources');
 const index=sequence.items.findIndex(x=>x.get('id')===sourceId);
 if(index>=0)sequence.set(index,sources.createNode(source));else sequence.add(sources.createNode(source));
 const layer={id:layerId,asset:`${id}_markers.topo.json`,display_name:title,geometry:'point',zoom:[4,18],parent:'ml_world_countries',sources:[sourceId],gazetteer:{source:sourceId},simplify:'100%',quantization:100000};
 const layerSequence=layers.get('layers');
 const li=layerSequence.items.findIndex(x=>x.get('id')===layerId);
 if(li>=0)layerSequence.set(li,layers.createNode(layer));else layerSequence.add(layers.createNode(layer));
 const citation={id:sourceId,kind:'dataset',title,publisher,document_identifier:source.version,url:coordinateUrl,accessed_on:'2026-09-26',license:licence,attribution_text:attribution};
 const cs=citations.get('source_citations');
 const ci=cs.items.findIndex(x=>x.get('id')===sourceId);
 if(ci>=0)cs.set(ci,citations.createNode(citation));else cs.add(citations.createNode(citation));
}
// A licensed country-island supplement is a source of the existing country
// layer, rather than a new marker layer. Keep its curriculum citation in sync.
for (const id of ['src_ne_americas_island_parts']) {
 const node=sources.get('sources').items.find(x=>x.get('id')===id);
 if(!node)continue;
 const source=node.toJSON();
 const citation={id,kind:'dataset',title:source.title,publisher:source.publisher,
  document_identifier:source.version,url:source.url,accessed_on:source.retrieved,
  license:source.license,attribution_text:source.attribution};
 const cs=citations.get('source_citations');
 const ci=cs.items.findIndex(x=>x.get('id')===id);
 if(ci>=0)cs.set(ci,citations.createNode(citation));else cs.add(citations.createNode(citation));
}
fs.writeFileSync(sourceFile,String(sources));
fs.writeFileSync(layerFile,String(layers));
fs.writeFileSync(citationFile,String(citations));
