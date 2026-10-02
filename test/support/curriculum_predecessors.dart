import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

/// Loads the exact frozen release 0.24.68 dataset from PR #50 fixtures.
CurriculumDataset loadFrozenRelease68() {
  const fixtureBase = 'test/fixtures/curriculum/v0_24_68';
  return CurriculumDataset.loadSync(curriculumAssetPath, (path) {
    final normalized = path.replaceAll(r'\', '/');
    if (normalized.endsWith('assets/curriculum/curriculum.yaml')) {
      return File('$fixtureBase/curriculum.yaml').readAsStringSync();
    }
    if (normalized.endsWith(
      'assets/curriculum/areas/diploma_sekt_analytical_cases.yaml',
    )) {
      return File('$fixtureBase/areas/diploma_sekt_analytical_cases.yaml')
          .readAsStringSync();
    }
    if (normalized.endsWith(
      'assets/curriculum/templates/diploma_sekt_analytical_cases.yaml',
    )) {
      return File('$fixtureBase/templates/diploma_sekt_analytical_cases.yaml')
          .readAsStringSync();
    }
    return File(path).readAsStringSync();
  });
}

/// Loads the exact frozen release 0.24.69 dataset from PR #51 fixtures.
CurriculumDataset loadFrozenRelease69() {
  const fixtureBase = 'test/fixtures/curriculum/v0_24_69';
  return CurriculumDataset.loadSync(curriculumAssetPath, (path) {
    final normalized = path.replaceAll(r'\', '/');
    if (normalized.endsWith('assets/curriculum/curriculum.yaml')) {
      return File('$fixtureBase/curriculum.yaml').readAsStringSync();
    }
    if (normalized.endsWith(
      'assets/curriculum/areas/diploma_sekt_analytical_cases.yaml',
    )) {
      return File('$fixtureBase/areas/diploma_sekt_analytical_cases.yaml')
          .readAsStringSync();
    }
    if (normalized.endsWith(
      'assets/curriculum/templates/diploma_sekt_analytical_cases.yaml',
    )) {
      return File('$fixtureBase/templates/diploma_sekt_analytical_cases.yaml')
          .readAsStringSync();
    }
    return File(path).readAsStringSync();
  });
}
