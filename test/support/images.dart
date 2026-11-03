import 'dart:convert';
import 'dart:typed_data';

/// An app image as the streamer reads one (the firmware's NETWORK.md, "OTA"): 0xE9 first, and an
/// esp_app_desc_t at 0x20 naming [board] as its project — or none, [described] false.
Uint8List appImage(String board, {int size = 4096, bool described = true}) {
  final image = Uint8List(size)..[0] = 0xE9;
  if (described) {
    ByteData.sublistView(image).setUint32(0x20, 0xABCD5432, Endian.little);
    image.setRange(0x50, 0x50 + board.length, utf8.encode(board));
  }
  return image;
}
