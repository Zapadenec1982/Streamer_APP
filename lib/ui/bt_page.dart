import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/panel/panel_link.dart';
import '../device/streamer.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Bluetooth, as the web's system/BtPage.svelte and the glass's screen_bt.cpp: the
/// phone that is connected, the radio, visibility, auto-reconnect, the name — the one every
/// phone, AirPlay and DLNA list the streamer by — the codecs and the phones the module remembers,
/// over `GET`/`POST /api/bt`. bt.cfg_rev says the settings moved: the page reads them again.
class BtPage extends ConsumerStatefulWidget {
  const BtPage({super.key});

  @override
  ConsumerState<BtPage> createState() => _BtPageState();
}

class _BtPageState extends ConsumerState<BtPage> {
  BtInfo? _bt;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bt = await ref.read(deviceApiProvider).bt();
      if (mounted) {
        setState(() {
          _bt = bt;
          _failed = null;
        });
      }
    } on PanelError catch (e) {
      if (mounted) setState(() => _failed = e.code ?? '${e.status}');
    }
  }

  /// A request to the module; a refusal in its own words.
  Future<void> _send(Future<void> Function() request) async {
    final l = AppLocalizations.of(context);
    try {
      await request();
    } on PanelError catch (e) {
      if (!mounted) return;
      final why = switch (btRefusal(e.code)) {
        BtRefusal.noSatellite => l.btErrNoSatellite,
        BtRefusal.oldSatellite => l.btErrOld,
        BtRefusal.notKnownYet => l.btErrWait,
        BtRefusal.name => l.btErrName,
        _ => null,
      };
      if (why == null) {
        await sayFailed(context, ref, e);
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(why)));
      }
    }
  }

  /// Shown at once, as the module will say on the next bt.cfg_rev.
  void _switch(BtInfo next, Future<void> Function() request) {
    setState(() => _bt = next);
    _send(request);
  }

  Future<void> _rename(BtInfo bt) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(name: bt.name),
    );
    if (name == null || !mounted) return;
    final api = ref.read(deviceApiProvider);
    await _send(() => api.btSet(name: name));
  }

  Future<void> _forget(BtBond? bond) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          bond == null
              ? l.btForgetAllQ
              : l.btForgetQ(bond.name.isNotEmpty ? bond.name : bond.addr),
        ),
        content: Text(l.btForgetBody),
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
            child: Text(l.btForget),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final api = ref.read(deviceApiProvider);
    await _send(() => api.btForget(bond?.addr ?? 'all'));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // the module's settings moved — here, on the glass, in another client: read them again
    ref.listen(
      snapshotProvider.select((s) => s.streamer.btConfigRev),
      (_, _) => _load(),
    );
    final streamer = ref.watch(snapshotProvider.select((s) => s.streamer));
    final api = ref.read(deviceApiProvider);
    final bt = _bt;
    Widget message(String words) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(words, textAlign: TextAlign.center),
      ),
    );
    final Widget body;
    if (bt == null) {
      body = _failed == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.appLoadFailed),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() => _failed = null);
                      _load();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(l.appRetry),
                  ),
                ],
              ),
            );
    } else if (!bt.linked) {
      body = message(l.btNoSatellite);
    } else {
      final phone = streamer.btPeer;
      final caption = text.titleSmall?.copyWith(color: colors.primary);
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(phone.isNotEmpty ? phone : l.btNoPhone),
            subtitle: phone.isNotEmpty
                ? Text(
                    streamer.btCodec.isNotEmpty
                        ? streamer.btCodec
                        : l.btConnected,
                  )
                : null,
            trailing: phone.isNotEmpty
                ? FilledButton.tonal(
                    onPressed: () => _send(api.btDisconnect),
                    child: Text(l.btDisconnect),
                  )
                : null,
          ),
          if (!bt.settings)
            message(l.btOldSatellite)
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l.btSettings, style: caption),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bluetooth),
              title: const Text('Bluetooth'),
              subtitle: Text(
                !bt.known
                    ? '…'
                    : bt.radio
                    ? l.btOn
                    : l.btOff,
              ),
              value: bt.radio,
              onChanged: bt.known
                  ? (on) => _switch(
                      bt.copyWith(radio: on),
                      () => api.btSet(radio: on),
                    )
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bluetooth_searching),
              title: Text(l.btVisible),
              subtitle: Text(bt.discoverable ? l.btVisibleOn : l.btVisibleOff),
              value: bt.discoverable,
              onChanged: bt.known
                  ? (on) => _switch(
                      bt.copyWith(discoverable: on),
                      () => api.btSet(discoverable: on),
                    )
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.link),
              title: Text(l.btAuto),
              value: bt.autoReconnect,
              onChanged: bt.known
                  ? (on) => _switch(
                      bt.copyWith(autoReconnect: on),
                      () => api.btSet(autoReconnect: on),
                    )
                  : null,
            ),
            ListTile(
              enabled: bt.known,
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.btName),
              subtitle: Text(bt.name.isNotEmpty ? bt.name : '…'),
              onTap: () => _rename(bt),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l.btCodecs, style: caption),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  // SBC is always on
                  const FilterChip(
                    label: Text('SBC'),
                    selected: true,
                    onSelected: null,
                  ),
                  for (final c in btCodecs)
                    if (bt.codecsSupported & c.bit != 0)
                      FilterChip(
                        label: Text(c.name),
                        selected: bt.codecsEnabled & c.bit != 0,
                        onSelected: (_) {
                          final next = bt.codecsEnabled ^ c.bit;
                          _switch(
                            bt.copyWith(codecsEnabled: next),
                            () => api.btSet(codecs: next | 1),
                          );
                        },
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l.btPhones('${bt.total}'), style: caption),
            ),
            if (bt.bonds.isEmpty) ListTile(title: Text(l.btNoPhones)),
            for (final b in bt.bonds)
              ListTile(
                selected: b.connected,
                leading: const Icon(Icons.smartphone),
                title: Text(b.name.isNotEmpty ? b.name : b.addr),
                subtitle: Text(
                  b.connected
                      ? l.btConnected
                      : b.last
                      ? l.btLast
                      : b.addr,
                ),
                trailing: TextButton(
                  onPressed: () => _forget(b),
                  child: Text(l.btForget),
                ),
              ),
            if (bt.bonds.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: () => _forget(null),
                    child: Text(l.btForgetAll),
                  ),
                ),
              ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth')),
      body: PanelPage(child: body),
    );
  }
}

/// The name every phone, AirPlay and DLNA list the streamer by: 1…32 bytes.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.name});

  final String name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.name);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ok {
    final n = _name.text.trim();
    return n.isNotEmpty && utf8Length(n) <= btNameMax && sendable(n);
  }

  void _submit() {
    if (_ok) Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.btNameTitle),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: btNameMax,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: l.btName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.sysCancel),
        ),
        FilledButton(onPressed: _ok ? _submit : null, child: Text(l.btSave)),
      ],
    );
  }
}

/// A phone asks to pair: the question over any page of the app, with the streamer's own words
/// and code, as the web's PairDialog has it and the glass at the same moment. The first answer
/// wins on the streamer; when it came from elsewhere, the dialog says where. The code comes from
/// `GET /api/bt`, behind the login.
class PairingWatcher extends ConsumerStatefulWidget {
  const PairingWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PairingWatcher> createState() => _PairingWatcherState();
}

class _PairingWatcherState extends ConsumerState<PairingWatcher> {
  int _shown = 0;

  void _follow(PairingState? was, PairingState now) {
    if (now.active && now.seq != 0 && now.seq != _shown) {
      _shown = now.seq;
      showDialog<void>(
        context: context,
        builder: (_) => _PairDialog(seq: now.seq),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(snapshotProvider.select((s) => s.streamer.pairing), _follow);
    return widget.child;
  }
}

class _PairDialog extends ConsumerStatefulWidget {
  const _PairDialog({required this.seq});

  final int seq;

  @override
  ConsumerState<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends ConsumerState<_PairDialog> {
  int? _code;
  bool _canAnswer = true;

  /// This app answered.
  bool _mine = false;

  /// Said instead of the question once it is answered.
  String? _note;
  bool _done = false;
  Timer? _closer;

  /// The glass's PAIR_RESULT_MS.
  static const _resultShown = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _readCode();
  }

  @override
  void dispose() {
    _closer?.cancel();
    super.dispose();
  }

  Future<void> _readCode() async {
    try {
      final bt = await ref.read(deviceApiProvider).bt();
      if (mounted && bt.pairingSeq == widget.seq) {
        setState(() => _code = bt.pairingCode);
      }
    } on PanelError catch (e) {
      // without the login the question still stands: it is answered on the glass
      if (mounted && e.unauthorized) setState(() => _canAnswer = false);
    }
  }

  Future<void> _answer(bool accept) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _mine = true;
      _note = accept ? l.pairConfirmPhone : l.pairRejecting;
    });
    try {
      await ref.read(deviceApiProvider).btPair(accept: accept, seq: widget.seq);
    } on PanelError catch (e) {
      if (!mounted) return;
      setState(
        () => _note = e.code == 'answered'
            ? (e.body?['by'] == 1 ? l.pairAnsweredPanel : l.mobPairElsewhere)
            : l.pairFailed,
      );
    }
  }

  void _follow(PairingState p) {
    if (p.seq != widget.seq || _done) return;
    final l = AppLocalizations.of(context);
    final name = p.name.isNotEmpty ? p.name : l.pairPhone;
    if (!p.active && p.result != 255) {
      _done = true;
      _note = switch (p.result) {
        0 => l.pairOk(name),
        1 => l.pairRejected,
        2 => l.pairTimeout,
        _ => l.pairFailed,
      };
      _closer = Timer(_resultShown, () {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else if (!_mine && p.by != 0) {
      _note = p.by == 1 ? l.pairAnsweredPanel : l.mobPairElsewhere;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(snapshotProvider.select((s) => s.streamer.pairing));
    _follow(p);
    final name = p.name.isNotEmpty ? p.name : l.pairPhone;
    final question = switch (p.kind) {
      PairKind.passkey => l.pairPasskey(name),
      PairKind.consent => l.pairConsent(name),
      PairKind.numeric => l.pairNumeric(name),
    };
    final note = _note;
    final answering = note == null && _canAnswer && p.kind != PairKind.passkey;
    return AlertDialog(
      title: _done ? null : Text(l.pairTitle),
      // at a large text size the question and its code are taller than the screen
      content: SingleChildScrollView(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note ?? question),
              if (note == null && p.kind != PairKind.consent)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _code != null ? pairCode(_code!) : '··· ···',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              if (note == null && !_canAnswer && p.kind != PairKind.passkey)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.pairOnPanel),
                ),
            ],
          ),
        ),
      ),
      actions: answering
          ? [
              TextButton(
                onPressed: () => _answer(false),
                child: Text(l.pairReject),
              ),
              FilledButton(
                onPressed: () => _answer(true),
                child: Text(l.pairConnect),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.pairHide),
              ),
            ],
    );
  }
}
