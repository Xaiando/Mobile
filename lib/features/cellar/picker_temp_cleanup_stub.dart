Future<T> withPickedTemporaryPhoto<T>(
  String path,
  Future<T> Function() action, {
  String? temporaryDirectoryPath,
}) => action();

Future<bool> removePickedTemporaryPhoto(
  String path, {
  String? temporaryDirectoryPath,
  String? iosPickerTemporaryDirectoryPath,
  String? applicationDocumentsDirectoryPath,
}) async => false;
