import 'dart:convert';

import 'package:sommelier/core/rehearsal/rehearsal.dart';

Map<String, dynamic> rehearsalFixtureMap({bool blueprint = false}) => {
  'schemaVersion': 1,
  'version': 'test.1',
  'levels': [
    {
      'level': 1,
      'mcqCount': 30,
      'writtenCount': 0,
      'durationSeconds': 2700,
      if (blueprint) 'blueprint': {'process': 6, 'styles': 18, 'service': 6},
    },
    {'level': 2, 'mcqCount': 50, 'writtenCount': 0, 'durationSeconds': 3600},
    {'level': 3, 'mcqCount': 50, 'writtenCount': 4, 'durationSeconds': 7200},
  ],
  'mcqs': [
    for (var i = 0; i < 50; i++)
      {
        'id': 'mcq_$i',
        'prompt': 'Original fixture question $i?',
        'levels': [1, 2, 3],
        'itemIds': ['ki_chablis_grape'],
        'options': [
          {'id': 'a', 'text': 'Correct choice $i'},
          {'id': 'b', 'text': 'Other choice $i'},
        ],
        'correctOptionId': 'a',
        'explanation': 'Deferred fixture explanation $i.',
        'blueprintByLevel': {
          '1': i < 10
              ? 'process'
              : i < 35
              ? 'styles'
              : 'service',
        },
      },
  ],
  'written': [
    for (var i = 0; i < 4; i++)
      {
        'id': 'written_$i',
        'prompt': 'Explain the fixture topic $i.',
        'levels': [3],
        'criteria': [
          {
            'id': 'criterion_$i',
            'text': 'Support your fixture explanation $i with evidence.',
            'itemIds': ['ki_chablis_grape'],
          },
        ],
      },
  ],
};

RehearsalBank rehearsalFixtureBank({bool blueprint = false}) =>
    RehearsalBank.fromJson(
      jsonEncode(rehearsalFixtureMap(blueprint: blueprint)),
    );
