/// Обслуговування, as the web's system pages have it: the streamer's login (`/api/auth`), its
/// firmware (`/api/ota`) and the two files a person keeps — their own files (`/api/userdata`) and
/// the settings (`/api/backup`, `/api/restore`) — with the rules the firmware holds them to (the
/// firmware's NETWORK.md, "Authentication", "REST API", "OTA").
library;

import 'dart:convert';
import 'dart:typed_data';

/// The streamer's login (`GET /api/auth`, without a login itself).
class AuthInfo {
  const AuthInfo({required this.enabled, required this.username});

  final bool enabled;
  final String username;

  static AuthInfo fromJson(Object? json) {
    final d = json is Map ? json : const {};
    final user = d['username'];
    return AuthInfo(
      enabled: d['enabled'] == true,
      username: user is String && user.isNotEmpty ? user : 'admin',
    );
  }
}

/// A login name the streamer keeps: 1…31 bytes, no `:` — it would split Basic auth's "user:pass"
/// in the wrong place.
bool loginNameOk(String name) {
  final n = name.trim();
  return n.isNotEmpty && utf8.encode(n).length <= 31 && !n.contains(':');
}

/// A new password: 4…63 bytes.
bool loginPasswordOk(String password) =>
    password.length >= 4 && utf8.encode(password).length <= 63;

/// What runs now (`GET /api/ota`, without a login).
class OtaInfo {
  const OtaInfo({
    required this.partition,
    required this.version,
    required this.idf,
    required this.date,
    required this.time,
    required this.board,
  });

  final String partition;
  final String version;
  final String idf;
  final String date;
  final String time;
  final String board;

  static OtaInfo fromJson(Object? json) {
    final d = json is Map ? json : const {};
    String s(String k) => d[k] is String ? d[k] as String : '';
    return OtaInfo(
      partition: s('partition'),
      version: s('version'),
      idf: s('idf'),
      date: s('date'),
      time: s('time'),
      board: s('board'),
    );
  }
}

/// An app slot is 4 MB (ota_0, ota_1 in partitions_p4_16mb.csv): a bigger image is refused.
const otaSlot = 4 * 1024 * 1024;

/// Why a picked file is no firmware for this streamer, before anything is sent.
enum FirmwareRefusal {
  /// Not a `.bin`.
  notBin,

  /// Bigger than an app slot.
  tooBig,

  /// Not an app image: under 256 bytes, or no 0xE9 first.
  notImage,

  /// An app image of another board.
  otherBoard,
}

/// The board an app image is built for — the project_name in its esp_app_desc_t, which sits at
/// 0x20 — or null where it has none.
String? imageBoard(Uint8List image) {
  const desc = 0x20;
  const name = desc + 48;
  if (image.length < name + 32) return null;
  final magic = ByteData.sublistView(image).getUint32(desc, Endian.little);
  if (magic != 0xABCD5432) return null;
  final field = Uint8List.sublistView(image, name, name + 32);
  final end = field.indexOf(0);
  return utf8.decode(
    end < 0 ? field : Uint8List.sublistView(field, 0, end),
    allowMalformed: true,
  );
}

/// A firmware file as the streamer takes it (the firmware's NETWORK.md, "OTA"), looked at before
/// it is sent: a `.bin` that fits the slot, an app image, for [running] — the board the streamer
/// says it runs; unchecked when it said none. An image without an app description is the
/// streamer's to judge, as it does.
FirmwareRefusal? firmwareRefusal(
  String name,
  Uint8List image, {
  String running = '',
}) {
  if (!name.toLowerCase().endsWith('.bin')) return FirmwareRefusal.notBin;
  if (image.length > otaSlot) return FirmwareRefusal.tooBig;
  if (image.length < 256 || image[0] != 0xE9) return FirmwareRefusal.notImage;
  final board = imageBoard(image);
  if (running.isNotEmpty && board != null && board != running) {
    return FirmwareRefusal.otherBoard;
  }
  return null;
}

/// The two backups and the key that says a file is one.
enum BackupKind {
  /// The station list, the EQ and «Власний», the remote devices, the track to resume.
  files('modesp_userdata', 'p4-files'),

  /// Every persisted setting.
  settings('modesp_backup', 'p4-settings');

  const BackupKind(this.marker, this.prefix);

  final String marker;
  final String prefix;

  /// The file's name for [day], as the web names it.
  String fileName(DateTime day) {
    String two(int n) => '$n'.padLeft(2, '0');
    return '$prefix-${day.year}-${two(day.month)}-${two(day.day)}.json';
  }
}

/// Why a picked file is no backup of the kind asked for.
enum BackupRefusal { notJson, wrongKind }

/// A backup file's text read back: the document, or why it is none — not JSON at all, or not this
/// kind: its key missing, or 0, as the web reads it.
({Map<String, Object?>? doc, BackupRefusal? refusal}) backupOf(
  BackupKind kind,
  String text,
) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } on FormatException {
    return (doc: null, refusal: BackupRefusal.notJson);
  }
  final marker = doc is Map ? doc[kind.marker] : null;
  if (marker == null || marker == false || marker == 0 || marker == '') {
    return (doc: null, refusal: BackupRefusal.wrongKind);
  }
  return (doc: (doc! as Map).cast<String, Object?>(), refusal: null);
}

/// A backup as the web saves it: JSON, a space per level.
Uint8List backupBytes(Object? doc) => Uint8List.fromList(
  utf8.encode(const JsonEncoder.withIndent(' ').convert(doc)),
);
