import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Photos are reduced before they are sent: the reader needs legible print,
/// not a 50-megapixel file, and a smaller upload is faster and cheaper.
const labelAiLongestSide = 1568;

/// Re-encodes [bytes] as an upright JPEG whose longest side is at most
/// [labelAiLongestSide]. Re-encoding drops the camera's metadata, location
/// included. Returns null for bytes that are not an image.
///
/// This decodes a full photo, so call it from a background isolate.
Uint8List? prepareLabelPhoto(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // Some decoders throw on bytes that are not their format.
    return null;
  }
  if (decoded == null) return null;
  var photo = img.bakeOrientation(decoded);
  final longest = photo.width > photo.height ? photo.width : photo.height;
  if (longest > labelAiLongestSide) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: labelAiLongestSide)
        : img.copyResize(photo, height: labelAiLongestSide);
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 85));
}
