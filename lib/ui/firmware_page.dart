import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/maintenance.dart';
import '../device/models.dart';
import '../device/panel/panel_link.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'caption.dart';
import 'files.dart';
import 'labels.dart';
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Оновлення прошивки, as the web's system/FirmwarePage.svelte: what runs now
/// (`GET /api/ota`) and an update from a `.bin` the person picks (`POST /api/ota`, D11). The app
/// looks at the file first — a `.bin` that fits the slot, an app image, for this board — so a
/// wrong one is said before anything is sent. The streamer writes the image into its other app
/// slot and restarts into it; the web interface is in the data partition and is not part of it.
class FirmwarePage extends ConsumerStatefulWidget {
  const FirmwarePage({super.key});

  @override
  ConsumerState<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends ConsumerState<FirmwarePage> {
  OtaInfo? _info;
  ({String name, Uint8List bytes})? _file;

  /// What has gone out, 0…1, while the image is being sent; null otherwise.
  double? _sent;

  /// Installed: the streamer restarts, and is followed until it is back.
  bool _done = false;
  bool _wentAway = false;
  int _left = 0;
  Timer? _tick;
  Timer? _giveUp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _giveUp?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await ref.read(deviceApiProvider).otaInfo();
      if (mounted) setState(() => _info = info);
    } on PanelError {
      // shown as unknown, as the web does
    }
  }

  void _say(String words) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(words)));

  Future<void> _pick(AppLocalizations l) async {
    final ({String name, Uint8List bytes})? f;
    try {
      f = await ref.read(phoneFilesProvider).open(FileTypes.firmware);
    } on PlatformException catch (e) {
      _say(e.message ?? e.code);
      return;
    }
    if (f == null || !mounted) return;
    final running = _info?.board ?? '';
    final why = firmwareRefusal(f.name, f.bytes, running: running);
    setState(() => _file = why == null ? f : null);
    switch (why) {
      case FirmwareRefusal.notBin:
        _say(l.fwOnlyBin);
      case FirmwareRefusal.tooBig:
        _say(l.fwTooBig(l.fileSize(f.bytes.length)));
      case FirmwareRefusal.notImage:
        _say(l.mobFwNotImage);
      case FirmwareRefusal.otherBoard:
        _say(l.fwBoardMismatch(imageBoard(f.bytes) ?? '', running));
      case null:
        break;
    }
  }

  Future<void> _install(AppLocalizations l) async {
    final file = _file;
    if (file == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.fwConfirmQ),
        content: Text(l.fwConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.sysCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.fwInstall),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _sent = 0;
      _wentAway = false;
    });
    try {
      await ref
          .read(deviceApiProvider)
          .otaUpload(
            file.bytes,
            progress: (p) {
              if (mounted) setState(() => _sent = p);
            },
          );
    } on PanelError catch (e) {
      if (!mounted) return;
      setState(() => _sent = null);
      final said = e.body;
      if (e.code == 'board_mismatch' && said != null) {
        _say(l.fwBoardMismatch('${said['incoming']}', '${said['running']}'));
      } else {
        await sayFailed(context, ref, e);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _sent = 1;
      _done = true;
      _left = 10;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
    _giveUp = Timer(const Duration(minutes: 1), _back);
  }

  /// Followed from the moment the image starts out: the socket may go quiet while the streamer
  /// takes it in, and once it has, the streamer answers and restarts without serving anything
  /// else — so the socket back after that is the new image's.
  void _follow(LinkStatus? was, LinkStatus now) {
    if (_sent == null) return;
    if (now != LinkStatus.ready) {
      _wentAway = true;
    } else if (_wentAway && _done) {
      _back();
    }
  }

  /// The streamer back, or a minute gone: what runs there now.
  void _back() {
    _tick?.cancel();
    _giveUp?.cancel();
    if (!mounted) return;
    setState(() {
      _done = false;
      _wentAway = false;
      _sent = null;
      _file = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(snapshotProvider.select((s) => s.status), _follow);
    final info = _info;
    final file = _file;
    final sent = _sent;
    final colors = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(l.pageFirmware)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Caption(l.fwRunning),
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(info?.version ?? '…'),
              subtitle: info != null ? Text('${info.date} ${info.time}') : null,
            ),
            if (info != null)
              ListTile(
                leading: const Icon(Icons.developer_board),
                title: Text(info.board),
                subtitle: Text(
                  '${l.fwSlot} ${info.partition} · IDF ${info.idf}',
                ),
              ),
            Caption(l.fwUpdate),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: sent != null ? null : () => _pick(l),
                      icon: const Icon(Icons.folder_open),
                      label: Text(l.mobFwPick),
                    ),
                  ),
                  if (file != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${file.name} · ${l.fileSize(file.bytes.length)}',
                      style: small,
                    ),
                  ],
                  if (sent != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: sent,
                      semanticsLabel: l.fwUpdate,
                      semanticsValue: '${(sent * 100).round()} %',
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: _done,
                      child: Text(
                        !_done
                            ? '${(sent * 100).round()} %'
                            : _left > 0
                            ? l.mobFwRestarting('$_left')
                            : l.sysRestarting,
                        style: small,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: file == null || sent != null
                          ? null
                          : () => _install(l),
                      icon: const Icon(Icons.system_update_alt),
                      label: Text(l.fwInstall),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(l.fwNote, style: small),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
