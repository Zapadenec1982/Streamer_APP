import 'dart:io';

import 'package:flutter/services.dart';

/// Roboto and the Material icons from the Flutter SDK, for a test that measures text as a phone
/// does: the test font draws every glyph as a square as wide as it is tall, so words come out
/// about twice as wide as Roboto's.
Future<void> loadPhoneFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('$dir/$file').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}
