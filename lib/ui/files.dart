import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the person picks, and one saved where they choose, through the phone's own document
/// picker (Android's Storage Access Framework: no storage permission) — what the web takes from an
/// `<input type=file>` and gives as a download: a firmware image, a backup, a playlist, EQ filters.
class PhoneFiles {
  const PhoneFiles();

  static const _channel = MethodChannel('streamer/files');

  /// The file picked, by its name and bytes; null when none was, or while another picker is open.
  /// [types] are the MIME types the picker offers ([FileTypes]). A file the phone could not read
  /// throws a [PlatformException] with its reason.
  Future<({String name, Uint8List bytes})?> open(List<String> types) async {
    final Map<String, Object?>? got;
    try {
      got = await _channel.invokeMapMethod<String, Object?>('open', {
        'types': types,
      });
    } on PlatformException catch (e) {
      if (e.code == 'busy') return null;
      rethrow;
    }
    if (got == null) return null;
    return (
      name: got['name'] is String ? got['name']! as String : '',
      bytes: got['bytes'] is Uint8List
          ? got['bytes']! as Uint8List
          : Uint8List(0),
    );
  }

  /// [bytes] saved as [name], where the person chooses: false when they did not. A file the phone
  /// could not write throws a [PlatformException] with its reason.
  Future<bool> save(String name, String type, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>('save', {
            'name': name,
            'type': type,
            'bytes': bytes,
          }) ??
          false;
    } on PlatformException catch (e) {
      if (e.code == 'busy') return false;
      rethrow;
    }
  }
}

final phoneFilesProvider = Provider<PhoneFiles>((ref) => const PhoneFiles());

/// What a picker offers for each kind of file: the types Android knows it by, and the generic one
/// it gives a file whose extension it does not know — a type left out leaves such a file
/// unoffered.
abstract final class FileTypes {
  static const firmware = ['application/octet-stream'];
  static const json = [
    'application/json',
    'text/plain',
    'application/octet-stream',
  ];
  static const text = ['text/plain', 'application/octet-stream'];
  static const playlist = [
    'audio/x-mpegurl',
    'audio/mpegurl',
    'application/x-mpegurl',
    'application/vnd.apple.mpegurl',
    'audio/x-scpls',
    'text/plain',
    'application/octet-stream',
  ];
}

/// A text file as the web's `File.text()` reads it: UTF-8, a byte that is none of it as U+FFFD,
/// the byte order mark gone.
String textOf(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}
