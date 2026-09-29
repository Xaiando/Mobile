/// A sanitized, app-owned photo recovered after Android killed the picker.
class RecoveredScanFile {
  const RecoveredScanFile({
    required this.id,
    required this.path,
    required this.mimeType,
  });

  final String id;
  final String path;
  final String mimeType;
}
