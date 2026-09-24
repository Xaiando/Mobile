import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import 'question_presenter.dart';

final questionPresenterProvider = Provider<QuestionPresenter>(
  (ref) => QuestionPresenter(ref.watch(appDatabaseProvider)),
);
