// The host side of the screen tour: `flutter drive` runs it on the computer and
// reports whether tool/android_tour/tour_test.dart passed on the device.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(timeout: const Duration(minutes: 45));
