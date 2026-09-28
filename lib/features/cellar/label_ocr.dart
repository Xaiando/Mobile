// The web compiler sees only the stub; Google ML Kit's package imports dart:io.
export 'label_ocr_stub.dart' if (dart.library.io) 'label_ocr_mobile.dart';
