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
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Резервна копія, as the web's system/BackupPage.svelte: two files a person keeps,
/// each saved where they choose and read back from a file they pick.
///  - Their own files (`GET`/`POST /api/userdata`): the station list, the EQ and «Власний», the
///    remote devices, the track to resume. A restore is staged and goes in at the next start,
///    because the modules hold their own copies — so it ends with a restart.
///  - The settings (`GET /api/backup`, `POST /api/restore`): every persisted key, applied at once;
///    the streamer restarts with them by itself.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  /// The backup a request is on its way for.
  BackupKind? _busy;

  void _say(String words) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(words)));

  Future<void> _save(BackupKind kind) async {
    final api = ref.read(deviceApiProvider);
    setState(() => _busy = kind);
    try {
      final doc = switch (kind) {
        BackupKind.files => await api.userFiles(),
        BackupKind.settings => await api.settingsBackup(),
      };
      await ref
          .read(phoneFilesProvider)
          .save(
            kind.fileName(DateTime.now()),
            'application/json',
            backupBytes(doc),
          );
    } on PanelError catch (e) {
      if (mounted) await sayFailed(context, ref, e);
    } on PlatformException catch (e) {
      if (mounted) _say(e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore(BackupKind kind, AppLocalizations l) async {
    final ({String name, Uint8List bytes})? file;
    try {
      file = await ref.read(phoneFilesProvider).open(FileTypes.json);
    } on PlatformException catch (e) {
      _say(e.message ?? e.code);
      return;
    }
    if (file == null || !mounted) return;
    final read = backupOf(kind, textOf(file.bytes));
    final doc = read.doc;
    if (doc == null) {
      _say(switch (read.refusal) {
        BackupRefusal.wrongKind => l.backupWrongKind,
        _ => l.backupNotJson,
      });
      return;
    }
    final api = ref.read(deviceApiProvider);
    setState(() => _busy = kind);
    try {
      switch (kind) {
        case BackupKind.files:
          final staged = await api.restoreUserFiles(doc);
          if (staged > 0 && mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _StagedDialog(staged: staged),
            );
          }
        case BackupKind.settings:
          await api.restoreSettings(doc);
          if (mounted) _say(l.backupSettingsDone);
      }
    } on PanelError catch (e) {
      if (!mounted) return;
      final said = e.body;
      if (e.code == 'bad_file' && said != null) {
        _say(l.backupBadFile('${said['file']}'));
      } else {
        await sayFailed(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget group(BackupKind kind, String caption, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Caption(caption),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(sub, style: small),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy != null ? null : () => _save(kind),
                icon: const Icon(Icons.download),
                label: Text(l.mobBackupSave),
              ),
              TextButton.icon(
                onPressed: _busy != null ? null : () => _restore(kind, l),
                icon: const Icon(Icons.upload_file),
                label: Text(l.backupRestore),
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.pageBackup)),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            group(BackupKind.files, l.backupFiles, l.backupFilesSub),
            const SizedBox(height: 8),
            group(BackupKind.settings, l.backupSettings, l.backupSettingsSub),
          ],
        ),
      ),
    );
  }
}

/// Files staged on the streamer: they go in when it restarts — now, or later. A restart asked for
/// is followed until the streamer is back, a minute at most.
class _StagedDialog extends ConsumerStatefulWidget {
  const _StagedDialog({required this.staged});

  final int staged;

  @override
  ConsumerState<_StagedDialog> createState() => _StagedDialogState();
}

class _StagedDialogState extends ConsumerState<_StagedDialog> {
  bool _restarting = false;
  bool _wentAway = false;
  Timer? _giveUp;

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  Future<void> _restart() async {
    setState(() {
      _restarting = true;
      _wentAway = false;
    });
    _giveUp = Timer(const Duration(minutes: 1), _close);
    if (!await act(context, ref, (api) => api.restart()) && mounted) {
      _giveUp?.cancel();
      setState(() => _restarting = false);
    }
  }

  void _follow(LinkStatus? was, LinkStatus now) {
    if (!_restarting) return;
    if (now != LinkStatus.ready) {
      _wentAway = true;
    } else if (_wentAway) {
      _close();
    }
  }

  void _close() {
    _giveUp?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(snapshotProvider.select((s) => s.status), _follow);
    return AlertDialog(
      title: Text(l.backupStaged('${widget.staged}')),
      content: Text(_restarting ? l.sysRestarting : l.backupStagedBody),
      actions: [
        if (!_restarting) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.backupLater),
          ),
          FilledButton(onPressed: _restart, child: Text(l.sysRestart)),
        ],
      ],
    );
  }
}
