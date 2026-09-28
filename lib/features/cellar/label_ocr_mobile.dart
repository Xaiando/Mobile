import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR; caller gates this to Android and iOS.
Future<String> recognizeLabelText(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text;
  } finally {
    try {
      await recognizer.close();
    } catch (_) {
      // Keep the original processing error if the native close call fails.
    }
  }
}
