import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/panel/panel_link.dart';
import '../device/streamer.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Wi-Fi, as the web's system/WifiPage.svelte and the glass's screen_wifi.cpp: the
/// network the streamer is on, the networks it hears, joining one, forgetting it — and the access
/// point it falls back to, from its next start.
///
/// Joining is the glass's: the stored network is kept until the new one gives an address, and
/// comes back if it does not. The streamer leaves its network for the seconds the try takes, so
/// the app loses it for that long; the WebSocket brings the outcome (wifi.try) when it is back.
class WifiPage extends ConsumerStatefulWidget {
  const WifiPage({super.key});

  @override
  ConsumerState<WifiPage> createState() => _WifiPageState();
}

enum _Scan { idle, busy, done, failed }

class _WifiPageState extends ConsumerState<WifiPage> {
  List<WifiNetwork> _networks = const [];
  _Scan _scan = _Scan.idle;
  WifiAp? _ap;

  @override
  void initState() {
    super.initState();
    _rescan();
    _loadAp();
  }

  /// Looked for each time the page opens; not while a join is on its way.
  Future<void> _rescan() async {
    final api = ref.read(deviceApiProvider);
    if (_scan == _Scan.busy || api.current.streamer.wifi.trying) return;
    setState(() => _scan = _Scan.busy);
    try {
      final found = await api.wifiScan();
      if (!mounted) return;
      setState(() {
        _networks = found ?? const [];
        _scan = found == null ? _Scan.failed : _Scan.done;
      });
    } on PanelError {
      if (mounted) setState(() => _scan = _Scan.failed);
    }
  }

  Future<void> _loadAp() async {
    try {
      final ap = await ref.read(deviceApiProvider).wifiAp();
      if (mounted) setState(() => _ap = ap);
    } on PanelError catch (e) {
      if (mounted) await sayFailed(context, ref, e);
    }
  }

  void _say(String words) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(words)));

  Future<void> _join(WifiNetwork network) async {
    final l = AppLocalizations.of(context);
    final wifi = ref.read(snapshotProvider).streamer.wifi;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _JoinDialog(
        network: network,
        note: wifi.mode == 'ap'
            ? l.mobWifiJoinNoteAp(network.ssid)
            : l.mobWifiJoinNote(network.ssid),
      ),
    );
    if (password == null || !mounted) return;
    try {
      await ref.read(deviceApiProvider).wifiJoin(network.ssid, password);
      if (mounted) _say(l.wifiJoining(network.ssid));
    } on PanelError catch (e) {
      if (!mounted) return;
      if (e.code == 'busy') {
        _say(l.wifiBusy);
      } else {
        await sayFailed(context, ref, e);
      }
    }
  }

  Future<void> _forget() async {
    final l = AppLocalizations.of(context);
    final wifi = ref.read(snapshotProvider).streamer.wifi;
    final ap = _ap;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.wifiForgetQ(wifi.ssid)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.mobWifiForgetBody),
            if (ap != null) ...[
              const SizedBox(height: 8),
              Text(l.mobWifiForgetBack(ap.ssid, accessPointIp)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.sysCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.wifiForget),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (await act(context, ref, (api) => api.wifiForget()) && mounted) {
      _say(l.wifiForgetting);
    }
  }

  /// What a join's outcome says: news when it changes on this page, not the value found on opening.
  void _outcome(WifiState? was, WifiState now) {
    if (was == null || was.tryState == now.tryState) return;
    final l = AppLocalizations.of(context);
    if (now.tryState == 'ok') {
      _say(l.wifiOk(now.trySsid));
      _rescan();
    } else if (now.tryState == 'fail') {
      _say(l.wifiFail(now.trySsid, _why(l, WifiWhy.of(now.reason))));
    }
  }

  static String _why(AppLocalizations l, WifiWhy why) => switch (why) {
    WifiWhy.password => l.wifiWhyPass,
    WifiWhy.notFound => l.wifiWhyNone,
    WifiWhy.security => l.wifiWhySecurity,
    WifiWhy.silent => l.wifiWhySilent,
    WifiWhy.refused => l.wifiWhyRefused,
  };

  static String _auth(AppLocalizations l, String auth) {
    if (auth == 'open') return l.wifiOpen;
    if (WifiNetwork.old.contains(auth)) return l.wifiOld(auth);
    if (WifiNetwork.joinable.contains(auth)) return auth;
    if (auth.isNotEmpty && auth != 'unknown') return l.wifiUnsupported(auth);
    return l.wifiOther;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    ref.listen(snapshotProvider.select((s) => s.streamer.wifi), _outcome);
    final wifi = ref.watch(snapshotProvider.select((s) => s.streamer.wifi));
    final current = wifi.network;
    final here = [
      for (final n in _networks)
        if (n.ssid == current) n,
    ].firstOrNull;
    final (IconData icon, String title, String sub) = wifi.trying
        ? (Icons.wifi, wifi.trySsid, l.wifiConnecting)
        : current != null
        ? (
            Icons.wifi,
            current,
            '${l.wifiConnected} · ${wifi.ip.isNotEmpty ? wifi.ip : l.wifiNoIp}',
          )
        : wifi.mode == 'ap'
        ? (
            Icons.wifi_off,
            l.wifiApTitle(wifi.ssid),
            '${wifi.ip.isNotEmpty ? wifi.ip : accessPointIp} · ${l.wifiApSub}',
          )
        : (
            Icons.wifi_off,
            wifi.ssid.isNotEmpty ? wifi.ssid : l.wifiNotConnected,
            l.wifiRetrying,
          );
    final ap = _ap;
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi')),
      body: PanelPage(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card.filled(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              color: colors.surfaceContainerLow,
              child: Semantics(
                liveRegion: true,
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: Text(sub),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (here != null && !wifi.trying) _Bars(network: here),
                      // tonal, as the web's card has it
                      if (wifi.mode == 'sta' && !wifi.trying)
                        FilledButton.tonal(
                          onPressed: _forget,
                          child: Text(l.wifiForget),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l.wifiNearby,
                        style: text.titleSmall?.copyWith(color: colors.primary),
                      ),
                    ),
                  ),
                  Text(
                    switch (_scan) {
                      _Scan.busy => l.wifiScanning,
                      _Scan.failed => l.wifiScanFailed,
                      _ => '',
                    },
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: l.wifiScan,
                    onPressed: _scan == _Scan.busy || wifi.trying
                        ? null
                        : _rescan,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (_scan == _Scan.done && _networks.isEmpty)
              ListTile(title: Text(l.wifiNone)),
            for (final n in _networks)
              ListTile(
                enabled: n.ssid == current || (n.canJoin && !wifi.trying),
                selected: n.ssid == current,
                title: Text(n.ssid),
                subtitle: Text(
                  n.ssid == current ? l.wifiConnected : _auth(l, n.auth),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!n.open)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.lock,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    _Bars(network: n),
                  ],
                ),
                onTap: n.ssid == current ? null : () => _join(n),
              ),
            const SizedBox(height: 16),
            if (ap != null)
              _AccessPoint(
                ap: ap,
                onSaved: () {
                  _say(l.wifiApSaved);
                  _loadAp();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A network's signal as the glass's four bars.
class _Bars extends StatelessWidget {
  const _Bars({required this.network});

  final WifiNetwork network;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: AppLocalizations.of(context).wifiSignal('${network.rssi}'),
      child: SizedBox(
        height: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 1; i <= 4; i++)
              Container(
                width: 4,
                height: 3.0 + i * 3,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: i <= network.bars
                      ? colors.onSurfaceVariant
                      : colors.outlineVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Joining a network: its password when it has one, what will happen, and «Підключити». Returns
/// the password to send ('' for an open network), or null.
class _JoinDialog extends StatefulWidget {
  const _JoinDialog({required this.network, required this.note});

  final WifiNetwork network;
  final String note;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _password = TextEditingController();
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _secure => !widget.network.open;

  bool get _ok =>
      !_secure || (joinPasswordOk(_password.text) && sendable(_password.text));

  void _submit() {
    if (_ok) Navigator.of(context).pop(_secure ? _password.text : '');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ssid = widget.network.ssid;
    return AlertDialog(
      title: Text(_secure ? l.wifiPassQ(ssid) : l.wifiJoinQ(ssid)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_secure) ...[
              TextField(
                controller: _password,
                autofocus: true,
                obscureText: !_shown,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l.wifiPassword,
                  helperText: l.wifiPassRule,
                  suffixIcon: IconButton(
                    tooltip: _shown ? l.wifiHide : l.wifiShow,
                    onPressed: () => setState(() => _shown = !_shown),
                    icon: Icon(
                      _shown ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              widget.note,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.sysCancel),
        ),
        FilledButton(onPressed: _ok ? _submit : null, child: Text(l.wifiJoin)),
      ],
    );
  }
}

/// The streamer's own access point: its name, a password or none, its channel — from its next
/// start. A stored password is never shown: «Зберегти» needs it again, or a new one.
class _AccessPoint extends ConsumerStatefulWidget {
  const _AccessPoint({required this.ap, required this.onSaved});

  final WifiAp ap;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AccessPoint> createState() => _AccessPointState();
}

class _AccessPointState extends ConsumerState<_AccessPoint> {
  late final _name = TextEditingController(text: widget.ap.ssid);
  final _password = TextEditingController();
  late bool _lock = widget.ap.passwordSet;
  late int _channel = widget.ap.channel.clamp(1, 13);
  bool _shown = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ok {
    final name = _name.text.trim();
    return name.isNotEmpty &&
        utf8Length(name) <= 32 &&
        sendable(name) &&
        (!_lock || (apPasswordOk(_password.text) && sendable(_password.text)));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final took = await act(
      context,
      ref,
      (api) => api.setWifiAp(
        _name.text.trim(),
        _lock ? _password.text : '',
        _channel,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (took) {
      _password.clear();
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: colors.onSurfaceVariant);
    final ap = widget.ap;
    return ExpansionTile(
      leading: const Icon(Icons.hub_outlined),
      title: Text(l.sysWifiAp),
      subtitle: Text(
        '${l.wifiApSum(ap.ssid, '${ap.channel}')} · '
        '${ap.passwordSet ? l.wifiApLocked : l.wifiApOpen}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          maxLength: 32,
          autocorrect: false,
          decoration: InputDecoration(labelText: l.wifiApName),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.wifiApLock),
          subtitle: Text(_lock ? l.wifiPassRule : l.wifiApLockOff),
          value: _lock,
          onChanged: (on) => setState(() => _lock = on),
        ),
        if (_lock) ...[
          TextField(
            controller: _password,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 63,
            decoration: InputDecoration(
              labelText: l.wifiPassword,
              suffixIcon: IconButton(
                tooltip: _shown ? l.wifiHide : l.wifiShow,
                onPressed: () => setState(() => _shown = !_shown),
                icon: Icon(_shown ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          if (ap.passwordSet) Text(l.wifiApPassAgain, style: small),
        ],
        const SizedBox(height: 8),
        DropdownMenu<int>(
          expandedInsets: EdgeInsets.zero,
          label: Text(l.wifiApChannel),
          initialSelection: _channel,
          dropdownMenuEntries: [
            for (var c = 1; c <= 13; c++)
              DropdownMenuEntry(value: c, label: '$c'),
          ],
          onSelected: (c) {
            if (c != null) setState(() => _channel = c);
          },
        ),
        const SizedBox(height: 8),
        Text(l.wifiApNote, style: small),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy || !_ok ? null : _save,
            child: Text(l.wifiSave),
          ),
        ),
      ],
    );
  }
}
