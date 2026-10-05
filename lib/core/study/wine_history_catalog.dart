// Only the historical portion of the optional enrichment bridge belongs here.
// Sake and cigar items share its prefix but remain outside the wine timeline.
const wineHistoryBridgeItemIds = {
  'ki_enrich_amarna_labels_content',
  'ki_enrich_amarna_labels_object',
  'ki_enrich_case_ancient_evidence_action',
  'ki_enrich_case_ancient_evidence_reason',
  'ki_enrich_case_ancient_evidence_tradeoff',
  'ki_enrich_case_ancient_evidence_limit',
};

bool isWineHistoryItem(String id) =>
    id.startsWith('ki_hist_') ||
    id.startsWith('ki_hcourse_') ||
    id.startsWith('ki_htime_') ||
    wineHistoryBridgeItemIds.contains(id);

/// Milestones group related source-cited assertions without introducing new
/// completion requirements. Each lesson still opens its normal source sheet.
class WineHistoryMoment {
  const WineHistoryMoment(this.id, this.date, this.title, this.identifiers);

  final String id;
  final String date;
  final String title;
  final List<String> identifiers;
}

const wineHistoryMoments = <WineHistoryMoment>[
  WineHistoryMoment(
    'early-evidence',
    'c. 6000–4000 BCE',
    'Earliest evidence and Areni-1',
    [
      'ki_hist_georgia_wine',
      'ki_hist_areni_cave',
      'n_hcourse_evidence',
      'n_hcourse_case_oldest',
    ],
  ),
  WineHistoryMoment(
    'amarna',
    'Fourteenth century BCE',
    'Amarna wine-jar inscriptions',
    ['n_enrich_amarna_labels', 'n_enrich_case_ancient_evidence'],
  ),
  WineHistoryMoment(
    'greek-symposium',
    'c. 550 BCE',
    'Greek wine at the symposium',
    ['n_htime_greek_symposium', 'n_htime_case_greek_roman_vessels'],
  ),
  WineHistoryMoment('roman', 'Roman era', 'Vineyards and wine trade', [
    'ki_hist_pliny_falernian',
    'n_hcourse_rome',
    'n_htime_roman_trade',
  ]),
  WineHistoryMoment(
    'medieval-burgundy',
    'High Middle Ages',
    'Monastic Burgundy and the Climats',
    ['n_htime_burgundy_medieval'],
  ),
  WineHistoryMoment('aquitaine', '1152', 'Aquitaine and English trade', [
    'n_htime_aquitaine',
  ]),
  WineHistoryMoment('gamay', '1395', 'Burgundy’s Gamay restriction', [
    'n_htime_ducal_rule',
  ]),
  WineHistoryMoment(
    'colonial-americas',
    'Sixteenth century',
    'Wine crosses to South America',
    ['ki_htime_south_america_colonial'],
  ),
  WineHistoryMoment('glass', '1650s', 'English glass wine bottles', [
    'ki_htime_vessels_glass1650',
    'n_htime_case_vessel_story',
  ]),
  WineHistoryMoment('cape', '1652–1659', 'The Cape wine settlement', [
    'n_htime_cape',
  ]),
  WineHistoryMoment('sparkling', '1662', 'Merrett and sparkling wine', [
    'ki_hist_merret_1662',
    'ki_hist_perignon_myth',
    'n_hcourse_sparkling',
    'n_hcourse_case_bubble',
  ]),
  WineHistoryMoment('methuen', '1703', 'The Methuen trade treaty', [
    'ki_hist_methuen_1703',
    'ki_hcourse_commerce_duty',
  ]),
  WineHistoryMoment('cork', '1730', 'A surviving corked bottle', [
    'ki_htime_vessels_cork1730',
  ]),
  WineHistoryMoment('douro', '1756', 'The Douro charter', [
    'ki_hist_douro_1756',
    'ki_hcourse_commerce_charter',
    'n_hcourse_case_boundary',
  ]),
  WineHistoryMoment('australia-first', '1788', 'The First Fleet vines', [
    'ki_htime_australia_origins_first1788',
  ]),
  WineHistoryMoment(
    'revolution',
    '1789 onward',
    'Revolution and vineyard ownership',
    ['n_htime_revolution'],
  ),
  WineHistoryMoment('napoleon-i', '1806', 'Napoleon I and the blockade', [
    'ki_hist_berlin_1806',
    'ki_hcourse_names_blockade',
  ]),
  WineHistoryMoment('busby', '1832', 'Busby’s Australian cuttings', [
    'ki_htime_australia_origins_busby1832',
  ]),
  WineHistoryMoment('malbec', '1853', 'Mendoza and Malbec', [
    'ki_htime_south_america_malbec1853',
  ]),
  WineHistoryMoment(
    'classification',
    '1855',
    'Napoleon III and the Bordeaux classification',
    ['ki_hist_classement_1855', 'ki_hcourse_names_list'],
  ),
  WineHistoryMoment(
    'pasteur',
    '1857–1865',
    'Pasteur, fermentation and wine faults',
    ['n_htime_pasteur'],
  ),
  WineHistoryMoment(
    'phylloxera',
    '1863–1893',
    'Phylloxera and resistant rootstocks',
    [
      'ki_hist_phylloxera_graft',
      'n_hcourse_phylloxera',
      'n_hcourse_case_phylloxera',
    ],
  ),
  WineHistoryMoment('prohibition', '1920–1933', 'US Prohibition and repeal', [
    'ki_hist_prohibition_18th',
    'ki_hist_repeal_21st',
    'ki_hcourse_modern_ban',
  ]),
  WineHistoryMoment('aoc', '1935 onward', 'French appellations', [
    'ki_hist_aoc_1935',
    'ki_hcourse_modern_aoc',
  ]),
  WineHistoryMoment('italy-1963', '1963', 'Italian origin-law categories', [
    'ki_hcourse_doc_name',
    'ki_hcourse_doc_unread',
    'ki_hcourse_doc_three',
    'ki_hcourse_doc_semplice',
    'n_hcourse_case_doc',
  ]),
  WineHistoryMoment('cape-wo', '1972–1973', 'Cape Wine of Origin', [
    'ki_htime_modern_origin_cape_wo',
  ]),
  WineHistoryMoment('paris', '1976', 'The Judgment of Paris', [
    'ki_hist_paris_1976',
    'ki_hcourse_modern_tasting',
  ]),
  WineHistoryMoment('ava', '1980', 'The first US AVA', [
    'ki_htime_modern_origin_usa_ava',
    'n_htime_case_newworld_names',
  ]),
  WineHistoryMoment('italy-2010', '2010', 'Italian origin-law reform', [
    'ki_hcourse_doc_repeal',
    'ki_hcourse_doc_2010',
    'n_hcourse_case_repeal',
  ]),
  WineHistoryMoment('gi', '2013 onward', 'Modern geographic indications', [
    'ki_hist_eu_wine_definition',
    'ki_htime_modern_origin_australia_gi',
  ]),
  WineHistoryMoment('italy-2016', '2016', 'Italian DOC, DOCG and IGT law', [
    'ki_hcourse_doc_now',
    'n_hcourse_case_letters',
  ]),
  WineHistoryMoment('chile-oiv', '2024', 'Chile and OIV sustainability work', [
    'ki_htime_present_chile2024',
    'ki_htime_present_oiv2024',
  ]),
  WineHistoryMoment('oiv-current', '2026', 'The current wine sector', [
    'ki_htime_present_oiv2026',
  ]),
  WineHistoryMoment('names-today', 'Today', 'Napoleon on Cognac labels', [
    'ki_hcourse_names_age',
    'n_hcourse_case_napoleon',
  ]),
];
