// Select two complete source polygon parts. Never sketch, buffer or offset.
// Download and unpack the pinned Natural Earth 10m archive under .dart_tool.
import fs from 'node:fs';
import crypto from 'node:crypto';
import mapshaper from 'mapshaper';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
export function ringContains([x,y],ring) {
  let inside=false;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++) {
    const a=ring[i],b=ring[j];
    if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;
  }
  return inside;
}
export function polygonContains(point,polygon) {
  return ringContains(point,polygon[0])&&!polygon.slice(1).some(r=>ringContains(point,r));
}
export function geometryContains(point,geometry) {
  return (geometry.type==='Polygon'?[geometry.coordinates]:geometry.coordinates).some(p=>polygonContains(point,p));
}
const sourceUrl='https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip';
const sourceZip='.dart_tool/americas_ne_10m_admin_0_countries.zip';
const sourceShp='.dart_tool/americas_ne_10m_admin_0_countries/ne_10m_admin_0_countries.shp';
export const islandRequests=[
  {key:'CAN',name:'Canada',node:'n_geo_gulf_islands_wine',island:'Salt Spring Island'},
  {key:'CHL',name:'Chile',node:'n_geo_rapa_nui_wine',island:'Rapa Nui / Easter Island'},
];
if(process.argv.includes('--author')) {
  const markerFiles=['new_world_americas_points.geojson','new_world_americas_gazetteer_points.geojson'];
  const markers=markerFiles.flatMap(f=>JSON.parse(fs.readFileSync(`tool/geography/${f}`)).features);
  const archiveHash=sha(fs.readFileSync(sourceZip));
  const output=await mapshaper.applyCommands(`-i "${sourceShp}" -filter "ADM0_A3 == 'CAN' || ADM0_A3 == 'CHL'" -o source.json format=geojson`);
  const countries=JSON.parse(output['source.json'].toString()).features;
  const features=islandRequests.map(request=>{
    const marker=markers.find(f=>f.properties.node_id===request.node);
    if(!marker)throw Error(`Missing exact source marker ${request.node}`);
    const feature=countries.find(f=>f.properties.ADM0_A3===request.key);
    if(!feature)throw Error(`Missing source country ${request.key}`);
    const polygons=feature.geometry.type==='Polygon'?[feature.geometry.coordinates]:feature.geometry.coordinates;
    const selected=polygons.map((polygon,index)=>({polygon,index})).filter(p=>polygonContains(marker.geometry.coordinates,p.polygon));
    if(selected.length!==1)throw Error(`Expected one complete polygon part for ${request.island}, got ${selected.length}`);
    const {polygon,index}=selected[0];
    return {type:'Feature',properties:{key:request.key,name:request.name,source_adm0_a3:feature.properties.ADM0_A3,source_name_en:feature.properties.NAME_EN,source_polygon_index:index,source_country_polygon_parts:polygons.length,source_country_geometry_sha256:sha(JSON.stringify(feature.geometry)),source_archive_sha256:archiveHash,source_url:sourceUrl,source_version:'5.1.1',retrieved_on:'2026-09-26',selected_by_node:request.node,selected_by_exact_point:marker.geometry.coordinates,island_reference_name:request.island,derivation:'Complete original Natural Earth polygon part containing the exact licensed marker; all exterior and hole vertices preserved, no clipping, buffering, tracing or coordinate changes.',license:'Public domain',attribution:'Made with Natural Earth.'},geometry:{type:'Polygon',coordinates:polygon}};
  });
  const target='tool/geography/americas_country_islands.geojson';
  fs.writeFileSync(target,JSON.stringify({type:'FeatureCollection',features},null,2)+'\n');
  console.log(JSON.stringify({source_archive_sha256:archiveHash,snapshot_sha256:sha(fs.readFileSync(target)),features:features.map(f=>({key:f.properties.key,index:f.properties.source_polygon_index,parts:f.properties.source_country_polygon_parts,vertices:f.geometry.coordinates.reduce((n,r)=>n+r.length,0)}))},null,2));
}
