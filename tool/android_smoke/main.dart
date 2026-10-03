// Checks what a release build of the app can do on Android without the rest
// of the app.
//
// It draws a wine label, reads it back with the function the cellar uses
// (recognizeLabelText: ML Kit's bundled Latin model), parses the text as a
// label proposal, and calls the other plugins that have Android code with a
// request that needs no screen. It prints one OCR_CHECK line, as JSON, to
// logcat. tool/android/ocr_smoke.sh builds on that line. CI builds this app
// in release mode, where R8 shrinks the code and debug builds do not, to show
// that recognition and the plugins still work on Android 16 in an APK that
// holds no INTERNET permission.
//
//   flutter build apk --release -t tool/android_smoke/main.dart \
//       --target-platform android-x64
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sommelier/core/journal/label_proposal.dart';
import 'package:sommelier/features/cellar/label_ocr.dart';

const _label = 'CHATEAU EXEMPLE\nGRAND VIN 2019\nALC. 14.5% VOL.';
const _size = ui.Size(1200, 800);

/// A black-on-white label as a PNG in the app's temporary folder.
Future<String> _drawLabel() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Offset.zero & _size);
  canvas.drawRect(
    ui.Offset.zero & _size,
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  TextPainter(
      text: const TextSpan(
        text: _label,
        style: TextStyle(
          color: ui.Color(0xFF000000),
          fontSize: 96,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )
    ..layout(maxWidth: _size.width - 100)
    ..paint(canvas, const ui.Offset(50, 60));
  final image = await recorder.endRecording().toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final folder = await getTemporaryDirectory();
  final file = File('${folder.path}/ocr_check.png');
  await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
  return file.path;
}

/// "ok" when a plugin answers a request that needs no screen, or the error
/// it raised: a plugin whose Android classes the release build stripped fails
/// here.
Future<String> _answers(Future<Object?> Function() request) async {
  try {
    await request();
    return 'ok';
  } on Object catch (error) {
    return 'error: $error';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('OCR check')),
    ),
  );
  final timer = Stopwatch()..start();
  Map<String, Object?> result;
  try {
    final text = await recognizeLabelText(await _drawLabel());
    final proposal = LabelProposal.fromRecognizedText(text);
    result = {
      'text': text.replaceAll('\n', ' | '),
      'vintage': proposal.vintage,
      'abv': proposal.abvPercent,
      'warnings': proposal.warnings,
    };
  } on Object catch (error) {
    result = {'error': '$error'};
  }
  result['plugins'] = {
    'image_picker': await _answers(() => ImagePicker().retrieveLostData()),
    'file_picker': await _answers(FilePicker.clearTemporaryFiles),
  };
  result['ms'] = timer.elapsedMilliseconds;
  debugPrint('OCR_CHECK ${jsonEncode(result)}');
}
