import 'package:flutter/services.dart';

const _regions = MethodChannel('streamer/regions');

/// Countries by their ISO codes, named in [language] by the phone's own locale data, as the web
/// asks Intl.DisplayNames. A code the phone cannot name — or a phone that cannot say — stays a
/// code.
Future<Map<String, String>> regionNames(
  List<String> codes,
  String language,
) async {
  try {
    final names = await _regions.invokeMapMethod<String, String>('names', {
      'codes': codes,
      'language': language,
    });
    return {for (final c in codes) c: names?[c] ?? c};
  } on MissingPluginException {
    return {for (final c in codes) c: c};
  } on PlatformException {
    return {for (final c in codes) c: c};
  }
}
