// Reproduce the bounded 2025 New Zealand planting-rank study facts.
// Source: NZ Winegrowers Vineyard Report 2026, printed pp. 21–22.
// Full PDF stays in the local research cache, not the distributable assets.
import fs from 'node:fs';
import YAML from 'yaml';
import { sha256 } from './lib.mjs';

const regions = [
  ['marlborough', 'Marlborough', ['sauvignon_blanc', 'pinot_noir']],
  ['central_otago', 'Central Otago', ['pinot_noir', 'pinot_gris']],
  ['hawkes_bay', "Hawke’s Bay", ['sauvignon_blanc', 'chardonnay']],
  ['gisborne', 'Gisborne', ['sauvignon_blanc', 'chardonnay']],
  ['nelson', 'Nelson', ['sauvignon_blanc', 'pinot_noir']],
  ['wairarapa', 'Wairarapa', ['sauvignon_blanc', 'pinot_noir']],
];
const names = {
  sauvignon_blanc: 'Sauvignon Blanc', pinot_noir: 'Pinot Noir',
  pinot_gris: 'Pinot Gris', chardonnay: 'Chardonnay',
};
const relation = 'TOP_PLANTED_GRAPE';
const sourceId = 'src_nz_vineyard_report_2026';
const on = '2026-02-26';
const data = {
  relation_types: [{ id: relation, label: 'has a top-two planted variety in its dated record',
    reverse_label: 'is a top-two planted variety in the dated record',
    cardinality: 'many', default_domain_id: 'geography',
    distractor_match_relation_type: 'HAS_BERRY_COLOUR' }],
  relation_type_signatures: [
    { relation_type: relation, subject_node_type: 'statistic', object_node_type: 'grape' },
    { relation_type: 'STATISTIC_IN_AREA', subject_node_type: 'statistic', object_node_type: 'appellation' },
  ],
  knowledge_nodes: [],
  knowledge_relations: [], knowledge_items: [], certification_knowledge_mappings: [],
  source_citations: [{ id: sourceId, kind: 'dataset',
    title: 'New Zealand Winegrowers Vineyard Report 2026', publisher: 'New Zealand Winegrowers',
    document_identifier: '2026 edition; observed regional planted-area record for 2025',
    url: 'https://www.nzwine.com/media/5fzng52v/vineyard-report-2026-final.pdf',
    accessed_on: '2026-09-26' }],
  knowledge_item_citations: [], relation_set_assertions: [],
};
for (const [slug, name, grapes] of regions) {
  const subject = `n_stat_nz_top_two_planted_2025_${slug}`;
  data.knowledge_nodes.push({id: subject, node_type: 'statistic', name: `${name} top-two planted varieties (2025)`});
  data.knowledge_relations.push({subject_id: subject, relation_type: 'STATISTIC_IN_AREA', object_id: `n_geo_${slug}`, valid_from: on});
  const locator = `Printed pp. 21–22, 2025 regional planted hectares: ${name} column; largest two individual-variety entries after ranking all rows. Not producing hectares or 2026 predictions.`;
  data.relation_set_assertions.push({ node_id: subject, relation_type: relation,
    direction: 'forward', member_node_type: 'grape', valid_from: on,
    source_citation_id: sourceId, locator });
  for (const grape of grapes) {
    const object = `n_grape_${grape}`, id = `ki_nz_2025_${slug}_top_${grape}`;
    data.knowledge_relations.push({ subject_id: subject, relation_type: relation, object_id: object, valid_from: on });
    data.knowledge_items.push({ id, subject_id: subject, relation_type: relation,
      object_id: object, domain_id: 'geography',
      assertion_text: `${name}: ${names[grape]} was a top-two planted variety (2025).`,
      ...(grape === 'pinot_gris' ? { mcq_disabled: true } : {}),
      last_verified_at: '2026-09-26T21:10:00.000Z' });
    for (const track of ['WSET_L3', 'CMS_CERTIFIED']) {
      data.certification_knowledge_mappings.push({ certification_id: track,
        knowledge_item_id: id, importance: 'secondary', minimum_depth: 2 });
    }
    data.knowledge_item_citations.push({ knowledge_item_id: id, source_citation_id: sourceId, locator });
  }
}
fs.writeFileSync('assets/curriculum/areas/new_world_plantings.yaml',
  '# Dated planting ranks, not legal grape permissions or an exhaustive cultivation list.\n' +
  '# Completeness covers exactly the two highest individual-variety planted areas\n' +
  '# in the observed 2025 columns; the 2026–28 forecast columns are not used.\n' +
  YAML.stringify(data, { lineWidth: 110 }));
const pdf = '.dart_tool/nz-vineyard-report-2026.pdf';
if (fs.existsSync(pdf)) console.log(`Research PDF SHA-256: ${sha256(fs.readFileSync(pdf))}`);
console.log(`${data.knowledge_items.length} items; ${data.relation_set_assertions.length} bounded pairs.`);
