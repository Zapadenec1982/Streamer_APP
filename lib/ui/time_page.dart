import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/panel/panel_link.dart';
import '../device/streamer.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'link_state.dart';
import 'writes.dart';

/// Налаштування › Час, as the web's system/TimePage.svelte: the streamer's clock — from the internet
/// or set by hand — and its time zone, over `GET`/`POST /api/time`. A change shows at once and is
/// taken back if the streamer refuses it.
class TimePage extends ConsumerStatefulWidget {
  const TimePage({super.key});

  @override
  ConsumerState<TimePage> createState() => _TimePageState();
}

class _TimePageState extends ConsumerState<TimePage> {
  PanelTime? _time;
  String? _failed;
  bool _ntp = true;
  String _zone = '';
  DateTime _manual = DateTime.now();
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(deviceApiProvider).panelTime();
      if (!mounted) return;
      setState(() {
        _time = t;
        _failed = null;
        _ntp = t.ntp;
        _zone = t.timezone;
        _manual = t.synced
            ? DateTime.fromMillisecondsSinceEpoch(t.unix * 1000)
            : DateTime.now();
      });
    } on PanelError catch (e) {
      if (mounted) setState(() => _failed = e.code ?? '${e.status}');
    }
  }

  /// Sent; the page reads the clock again a moment later, as the streamer sets it.
  Future<void> _save({
    required bool ntp,
    required String zone,
    int? unix,
  }) async {
    final l = AppLocalizations.of(context);
    final took = await act(
      context,
      ref,
      (api) => api.setPanelTime(ntp: ntp, timezone: zone, unix: unix),
    );
    if (!mounted) return;
    if (!took) {
      // refused: what the streamer keeps, unless it was changed again meanwhile
      setState(() {
        if (_ntp == ntp) _ntp = _time?.ntp ?? _ntp;
        if (_zone == zone) _zone = _time?.timezone ?? _zone;
      });
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.timeSaved)));
    _again?.cancel();
    _again = Timer(const Duration(milliseconds: 1500), _load);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _manual,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_manual),
    );
    if (time == null || !mounted) return;
    setState(
      () => _manual = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = ref.watch(snapshotProvider.select((s) => s.streamer));
    final t = _time;
    final Widget body;
    if (t == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _failed == null
              ? const CircularProgressIndicator()
              : Column(
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
        ),
      );
    } else {
      final known = timezones.any((z) => z.tz == _zone);
      final local = MaterialLocalizations.of(context);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  s.time.isNotEmpty ? s.time : t.time,
                  style: text.displayMedium,
                ),
                Text(
                  s.date.isNotEmpty ? s.date : t.date,
                  style: text.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (!t.synced)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l.timeNotSet,
                      style: text.bodyMedium?.copyWith(color: colors.error),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            secondary: const Icon(Icons.sync_alt),
            title: Text(l.timeNtp),
            value: _ntp,
            onChanged: (on) {
              setState(() => _ntp = on);
              _save(ntp: on, zone: _zone);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DropdownMenu<String>(
              key: ValueKey(_zone),
              expandedInsets: EdgeInsets.zero,
              label: Text(l.timeZone),
              initialSelection: _zone,
              menuHeight: 360,
              dropdownMenuEntries: [
                if (!known && _zone.isNotEmpty)
                  DropdownMenuEntry(value: _zone, label: _zone),
                for (final z in timezones)
                  DropdownMenuEntry(value: z.tz, label: z.label),
              ],
              onSelected: (zone) {
                if (zone == null || zone == _zone) return;
                setState(() => _zone = zone);
                _save(ntp: _ntp, zone: zone);
              },
            ),
          ),
          if (!_ntp) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Semantics(
                header: true,
                child: Text(
                  l.timeManual,
                  style: text.titleSmall?.copyWith(color: colors.primary),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(
                '${local.formatMediumDate(_manual)} · '
                '${local.formatTimeOfDay(TimeOfDay.fromDateTime(_manual), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
              ),
              onTap: _pickDateTime,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _save(
                      ntp: false,
                      zone: _zone,
                      unix: _manual.millisecondsSinceEpoch ~/ 1000,
                    ),
                    child: Text(l.timeSet),
                  ),
                  TextButton.icon(
                    onPressed: () => _save(
                      ntp: false,
                      zone: _zone,
                      unix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    ),
                    icon: const Icon(Icons.smartphone),
                    label: Text(l.timeFromDevice),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.pageTime)),
      body: PanelPage(child: body),
    );
  }
}
