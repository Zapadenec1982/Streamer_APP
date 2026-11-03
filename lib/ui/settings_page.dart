import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../device/panels.dart';
import '../device/streamer.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'caption.dart';
import 'labels.dart';
import 'speakers_page.dart';
import 'writes.dart';

/// Налаштування, as the web's SystemPage.svelte and the glass's screen_set.cpp: the streamer the
/// app talks to; its sound, the device — with its login, its firmware and its backups — its links
/// and its services, each page under its row; and the app's own settings. The crossover stays
/// hidden, as on the web and the glass; «Сервіс» is the web's alone (D13).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// A restart asked for and not over: the streamer has not come back since.
  bool _restarting = false;
  bool _wentAway = false;
  Timer? _giveUp;

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  Future<void> _restart(AppLocalizations l) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.sysRestartQ),
        content: Text(l.sysRestartBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.sysCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.sysRestart),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _restarting = true;
      _wentAway = false;
    });
    // the streamer is back when its socket has gone and come back; a minute at most
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(minutes: 1), () {
      if (mounted) setState(() => _restarting = false);
    });
    if (!await act(context, ref, (api) => api.restart()) && mounted) {
      setState(() => _restarting = false);
    }
  }

  void _follow(LinkStatus? was, LinkStatus now) {
    if (!_restarting) return;
    if (now != LinkStatus.ready) {
      _wentAway = true;
    } else if (_wentAway) {
      _giveUp?.cancel();
      setState(() => _restarting = false);
    }
  }

  Future<void> _airplayMode(AppLocalizations l, int current) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.sysAirplayMode),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.of(context).pop(v),
            child: Column(
              children: [
                const RadioListTile<int>(value: 0, title: Text('AirPlay 2')),
                RadioListTile<int>(value: 1, title: Text(l.sysAirplay1)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await act(context, ref, (api) => api.setAirplayMode(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snapshot = ref.watch(snapshotProvider);
    final language = ref.watch(appLanguageProvider);
    final choice = ref.watch(activePanelProvider);
    ref.listen(snapshotProvider.select((s) => s.status), _follow);
    final s = snapshot.streamer;
    final wifi = s.wifi;
    final mode = s.airplayModeError.isNotEmpty
        ? s.airplayModeError
        : s.airplaySwitching
        ? s.airplayModeStatus
        : '';
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        children: [
          Caption(l.mobPanel),
          switch (choice) {
            NoPanel() => ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l.mobNoPanel),
              subtitle: Text(l.mobNoPanelNote),
              onTap: () => context.go('/settings/panels'),
            ),
            DemoPanel() => ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l.mobDemoPanel),
              subtitle: Text(l.mobDemoNote),
              onTap: () => context.go('/settings/panels'),
            ),
            RealPanel(:final panel) => ListTile(
              leading: const Icon(Icons.speaker),
              title: Text(panel.name),
              subtitle: Text(panel.address),
              onTap: () => context.go('/settings/panels'),
            ),
          },
          if (choice is! NoPanel) ...[
            Caption(l.sysSound),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l.sysTimbreVolume),
              onTap: () => context.go('/settings/sound'),
            ),
            ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l.spkTitle),
              subtitle: Text(l.speakersLine(snapshot.speakers.setup)),
              onTap: () => context.go('/settings/speakers'),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(l.pageTuning),
              onTap: () => context.go('/settings/tuning'),
            ),
            Caption(l.sysDevice),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text(l.sysScreen),
              // the screen at a glance, as the glass's row says it
              subtitle: Text(
                '${s.backlight} % · ${l.schemeName(snapshot.scheme)}',
              ),
              onTap: () => context.go('/settings/display'),
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(l.langPanel),
              subtitle: switch (s.language) {
                final int i when i >= 0 && i < panelLanguages.length => Text(
                  panelLanguages[i],
                ),
                _ => null,
              },
              onTap: () => context.go('/settings/language'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(l.pageTime),
              subtitle: s.time.isNotEmpty ? Text(s.time) : null,
              onTap: () => context.go('/settings/time'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l.pageAccess),
              onTap: () => context.go('/settings/access'),
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: Text(l.pageFirmware),
              onTap: () => context.go('/settings/firmware'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l.pageBackup),
              onTap: () => context.go('/settings/backup'),
            ),
            ListTile(
              enabled: !_restarting,
              leading: const Icon(Icons.restart_alt),
              title: Text(l.sysRestart),
              subtitle: _restarting ? Text(l.sysRestarting) : null,
              onTap: () => _restart(l),
            ),
            Caption(l.sysLinks),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Wi-Fi'),
              subtitle: Text(
                wifi.network != null
                    ? [
                        wifi.ssid,
                        wifi.ip,
                      ].where((x) => x.isNotEmpty).join(' · ')
                    : wifi.mode == 'ap'
                    ? l.sysWifiAp
                    : l.sysWifiOff,
              ),
              onTap: () => context.go('/settings/wifi'),
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Bluetooth'),
              subtitle: Text(
                !s.btLink
                    ? l.sysBtNone
                    : s.btPeer.isNotEmpty
                    ? s.btPeer
                    : l.sysBtReady,
              ),
              onTap: () => context.go('/settings/bt'),
            ),
            Caption(l.sysServices),
            if (s.airplay case final on?) ...[
              SwitchListTile(
                secondary: const Icon(Icons.airplay),
                title: const Text('AirPlay'),
                subtitle: snapshot.name.isNotEmpty ? Text(snapshot.name) : null,
                value: on,
                onChanged: (v) => act(
                  context,
                  ref,
                  (api) => api.setSwitch(PanelSwitch.airplay, v),
                ),
              ),
              // the mode, and under it what is happening to it while something is
              if (on)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(l.sysAirplayMode),
                  subtitle: Text(
                    [
                      s.airplayMode == 1 ? l.sysAirplay1 : 'AirPlay 2',
                      if (mode.isNotEmpty) l.message(mode),
                    ].join(' · '),
                  ),
                  onTap: () => _airplayMode(l, s.airplayMode),
                ),
            ],
            if (s.dlna case final on?)
              SwitchListTile(
                secondary: const Icon(Icons.cast),
                title: const Text('DLNA'),
                subtitle: snapshot.name.isNotEmpty ? Text(snapshot.name) : null,
                value: on,
                onChanged: (v) => act(
                  context,
                  ref,
                  (api) => api.setSwitch(PanelSwitch.dlna, v),
                ),
              ),
            if (s.covers case final on?)
              SwitchListTile(
                secondary: const Icon(Icons.image_outlined),
                title: Text(l.sysCovers),
                value: on,
                onChanged: (v) => act(
                  context,
                  ref,
                  (api) => api.setSwitch(PanelSwitch.covers, v),
                ),
              ),
          ],
          Caption(l.mobApp),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.pageLanguage),
            subtitle: Text(language.endonym ?? l.mobLangPhone),
            onTap: () => _pickLanguage(context, l, language),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l.sysScheme),
            subtitle: Text(
              '${l.schemeName(snapshot.scheme)} · ${l.langAsPanel}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l.mobLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l.mobAppName,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    AppLocalizations l,
    AppLanguage current,
  ) async {
    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.pageLanguage),
        children: [
          RadioGroup<AppLanguage>(
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              children: [
                for (final language in AppLanguage.values)
                  RadioListTile<AppLanguage>(
                    value: language,
                    title: Text(language.endonym ?? l.mobLangPhone),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(appLanguageProvider.notifier).set(picked);
    }
  }
}
