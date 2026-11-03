import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/device/maintenance.dart';
import 'package:streamer/ui/files.dart';

import 'support/images.dart';

void main() {
  test('the login as the streamer says it, and what it keeps', () {
    final auth = AuthInfo.fromJson({'enabled': true, 'username': 'kitchen'});
    expect((auth.enabled, auth.username), (true, 'kitchen'));
    final none = AuthInfo.fromJson(null);
    expect((none.enabled, none.username), (false, 'admin'));
    // a name: 1…31 bytes, no ':' — Basic auth splits "user:pass" at the first
    expect(loginNameOk(''), isFalse);
    expect(loginNameOk('  '), isFalse);
    expect(loginNameOk('admin'), isTrue);
    expect(loginNameOk('a:b'), isFalse);
    expect(loginNameOk('a' * 31), isTrue);
    expect(loginNameOk('a' * 32), isFalse);
    expect(loginNameOk('ж' * 15), isTrue);
    expect(loginNameOk('ж' * 16), isFalse);
    // a new password: 4…63 bytes
    expect(loginPasswordOk('abc'), isFalse);
    expect(loginPasswordOk('abcd'), isTrue);
    expect(loginPasswordOk('a' * 63), isTrue);
    expect(loginPasswordOk('a' * 64), isFalse);
    expect(loginPasswordOk('ж' * 31), isTrue);
    expect(loginPasswordOk('ж' * 32), isFalse);
  });

  test('a firmware file is looked at before it is sent: a .bin that fits '
      'the slot, an app image, for this board', () {
    const board = 'modesp_p4_player';
    final image = appImage(board);
    expect(imageBoard(image), board);
    expect(firmwareRefusal('p4.bin', image, running: board), isNull);
    expect(firmwareRefusal('P4.BIN', image, running: board), isNull);
    expect(
      firmwareRefusal('p4.txt', image, running: board),
      FirmwareRefusal.notBin,
    );
    expect(
      firmwareRefusal('p4.bin', appImage(board, size: otaSlot + 1)),
      FirmwareRefusal.tooBig,
    );
    expect(firmwareRefusal('p4.bin', appImage(board, size: otaSlot)), isNull);
    expect(
      firmwareRefusal('p4.bin', appImage(board, size: 200)),
      FirmwareRefusal.notImage,
    );
    expect(
      firmwareRefusal('p4.bin', Uint8List(4096)),
      FirmwareRefusal.notImage,
    );
    final other = appImage('modesp_c6_bridge');
    expect(imageBoard(other), 'modesp_c6_bridge');
    expect(
      firmwareRefusal('c6.bin', other, running: board),
      FirmwareRefusal.otherBoard,
    );
    // the board unknown, or no app description to read it from: the streamer's to judge
    expect(firmwareRefusal('c6.bin', other), isNull);
    final bare = appImage(board, described: false);
    expect(imageBoard(bare), isNull);
    expect(firmwareRefusal('p4.bin', bare, running: board), isNull);
  });

  test('a backup by its name for the day, as JSON a space per level, and '
      'read back only as its own kind', () {
    final day = DateTime(2026, 11, 3, 23, 59);
    expect(BackupKind.files.fileName(day), 'p4-files-2026-11-03.json');
    expect(BackupKind.settings.fileName(day), 'p4-settings-2026-11-03.json');
    final doc = {
      'modesp_backup': 1,
      'keys': {'audio.volume': 30},
    };
    final bytes = backupBytes(doc);
    expect(
      utf8.decode(bytes),
      '{\n "modesp_backup": 1,\n "keys": {\n  "audio.volume": 30\n }\n}',
    );
    final back = backupOf(BackupKind.settings, utf8.decode(bytes));
    expect(back.doc, doc);
    expect(back.refusal, isNull);
    expect(
      backupOf(BackupKind.files, utf8.decode(bytes)).refusal,
      BackupRefusal.wrongKind,
    );
    expect(
      backupOf(BackupKind.files, '{"modesp_userdata":0}').refusal,
      BackupRefusal.wrongKind,
    );
    expect(backupOf(BackupKind.files, '[1]').refusal, BackupRefusal.wrongKind);
    expect(
      backupOf(BackupKind.files, 'Filter 1: ON PK').refusal,
      BackupRefusal.notJson,
    );
  });

  test('a text file as the web reads one: UTF-8, a broken byte as U+FFFD, '
      'no byte order mark', () {
    expect(
      textOf(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Ще')])),
      'Ще',
    );
    expect(textOf(Uint8List.fromList([0x41, 0xFF, 0x42])), 'A�B');
  });
}
