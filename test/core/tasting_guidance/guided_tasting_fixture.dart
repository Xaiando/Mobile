import 'dart:convert';

import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';

import '../../support/fixture.dart';

Map<String, dynamic> guidedTastingFixtureMap() => {
  'schemaVersion': 1,
  'version': 'fixture.1',
  'levels': [
    for (var level = 1; level <= 3; level++)
      {
        'level': level,
        'gridId': 'tg_guided_wine_l${level}_v1',
        'evidencePrompts': level == 3
            ? [
                {
                  'id': 'quality',
                  'prompt': 'Explain the evidence supporting quality.',
                },
                {
                  'id': 'ageing',
                  'prompt': 'Explain the evidence supporting ageing.',
                },
              ]
            : [
                {
                  'id': 'description',
                  'prompt': 'Explain evidence supporting the description.',
                },
              ],
      },
  ],
  'cases': [
    for (var level = 1; level <= 3; level++)
      {
        'id': 'case_l$level',
        'level': level,
        'title': 'Original fixture case Level $level',
        'description':
            'A described fictional wine tastes dry and shows citrus aromas.',
        'itemIds': ['ki_chablis_grape'],
        'referenceObservations': [
          {
            'attributeKey': 'sweetness',
            'valueKeys': ['dry', 'off_dry'],
            'explanation':
                'A transparent reference range for this described case.',
          },
        ],
        'criteria': [
          {
            'id': 'evidence',
            'text': 'Use observations as evidence in the explanation.',
          },
        ],
        'feedback': 'Original case feedback explains the scenario without grading a physical unknown wine.',
      },
  ],
};
GuidedTastingBank guidedTastingFixtureBank() =>
    GuidedTastingBank.fromJson(jsonEncode(guidedTastingFixtureMap()));

Future<void> seedGuidedTastingGrids(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "UPDATE certifications SET is_selectable=1 WHERE id IN ('WSET_L1','WSET_L2')",
    "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L1','ki_chablis_grape','core',1,NULL)",
    for (var level = 1; level <= 3; level++) ...[
      "INSERT INTO tasting_grids VALUES ('tg_guided_wine_l${level}_v1','WSET_SAT','l${level}_v1','Original guided wine Level $level')",
      "INSERT INTO tasting_grid_attributes VALUES ('tg_guided_wine_l${level}_v1','sweetness','Taste','Sweetness',1,'single',1), ('tg_guided_wine_l${level}_v1','aromas','Smell','Aromas',2,'multi',0)",
      "INSERT INTO tasting_grid_values VALUES ('tg_guided_wine_l${level}_v1','sweetness','dry','Dry',1,NULL), ('tg_guided_wine_l${level}_v1','sweetness','off_dry','Off-dry',2,NULL), ('tg_guided_wine_l${level}_v1','aromas','citrus','Citrus fruit',1,NULL)",
    ],
  ]),
);
