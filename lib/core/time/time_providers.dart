import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The clock the app reads time from. Tests override it with a fixed clock.
final clockProvider = Provider<Clock>((ref) => const Clock());
