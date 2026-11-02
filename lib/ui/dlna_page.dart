import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/media.dart';
import '../device/models.dart';
import '../device/panel/panel_link.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'writes.dart';

/// The path this page opened its way down, kept while the app is open: coming back to the page
/// finds the crumbs where they were.
List<String?> _kept = const [];

/// The routine status lines — counts, the search, loading, what was queued or plays — the page
/// says in its own way; the rest (an error, «Скасовано») it shows.
final _routine = RegExp(
  r'^@(dlna\.st_servers|dlna\.st_page|dlna\.searching|app\.loading|dlna\.queued|dlna\.st_playing)(\u001f|$)',
);

/// DLNA media servers: servers › folders › tracks — the browser the glass's DLNA page and the web's
/// drive (components/dlna_client), with the same snapshot (`GET /api/dlna/browser`) and the same
/// revision-stamped commands (`dlna.browse_cmd`). One browser for all three: a folder opened on the
/// glass is the folder this page shows.
///
/// The snapshot is not in the WebSocket's state, so it is asked for: every 0.4 s while something
/// is being fetched or a command is on its way, every 4 s otherwise, never in the background.
class DlnaPage extends ConsumerStatefulWidget {
  const DlnaPage({super.key});

  @override
  ConsumerState<DlnaPage> createState() => _DlnaPageState();
}

class _DlnaPageState extends ConsumerState<DlnaPage> {
  /// «Медіасервери» climbs until the servers' list is reached, however deep the path this page does
  /// not know: the browser keeps sixteen levels (DEPTH, dlna_browser.cpp), and the top one more.
  static const _toServers = 17;

  late final AppLifecycleListener _life;
  final _scroll = ScrollController();
  DlnaView? _view;
  String? _error;
  List<String?> _crumbs = _kept;

  /// What the command on its way should do to the path.
  BrowseStep? _expect;

  /// The revision the command on its way was sent from; null when none is on its way.
  int? _sentRev;
  DateTime _sentAt = DateTime.now();
  int _sentCmd = 0;

  /// The revision the crumbs were last fitted to.
  int _applied = -1;

  /// ← still to send after this one, to reach a crumb.
  int _climbing = 0;
  bool _discovered = false;
  Timer? _timer;
  bool _alive = true;

  /// One request at a time, so answers cannot arrive out of order.
  bool _inFlight = false;
  bool _again = false;

  /// The page is on screen: its section is the one shown (a section kept behind another has its
  /// tickers off), and the app is not in the background.
  bool _onScreen = false;

  bool get _waiting => _view == null || _view!.busy || _sentRev != null;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _poll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen == _onScreen) return;
    _onScreen = onScreen;
    if (onScreen) {
      _poll();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _timer?.cancel();
    _life.dispose();
    _scroll.dispose();
    _kept = _crumbs;
    super.dispose();
  }

  Future<void> _poll() async {
    _timer?.cancel();
    if (_inFlight) {
      _again = true;
      return;
    }
    if (!_onScreen) return;
    _inFlight = true;
    final shown = switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed => true,
      _ => false,
    };
    if (shown) {
      try {
        final view = await ref.read(deviceApiProvider).dlnaView();
        if (_alive) _take(view);
        _error = null;
      } on PanelError catch (e) {
        if (!e.unauthorized) _error = e.code ?? '${e.status}';
      }
    }
    _inFlight = false;
    if (!_alive) return;
    setState(() {});
    if (!_onScreen) return;
    final view = _view;
    final next = _again
        ? Duration.zero
        : view != null && (view.busy || _sentRev != null)
        ? const Duration(milliseconds: 400)
        : const Duration(seconds: 4);
    _again = false;
    _timer = Timer(next, _poll);
  }

  void _soon() {
    if (!_alive) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _poll);
  }

  void _take(DlnaView view) {
    _view = view;
    if (view.busy) return;
    // The snapshot the command was chosen from is not its answer. A command the browser turned
    // down (its revision had moved) changes nothing, so after 3 s the page stops waiting.
    if (_sentRev != null &&
        view.revision == _sentRev &&
        DateTime.now().difference(_sentAt) < const Duration(seconds: 3)) {
      return;
    }
    if (view.revision != _applied) {
      _crumbs = nextCrumbs(_crumbs, _expect, (
        title: view.title,
        servers: view.servers,
      ));
      _applied = view.revision;
      // a page or a folder this page asked for starts at its top
      if (_sentRev != null && _scroll.hasClients) _scroll.jumpTo(0);
    }
    _expect = null;
    _sentRev = null;
    if (_climbing > 0 && !view.servers) {
      _climbing--;
      _send(Browse.back, step: const WentBack());
    } else {
      _climbing = 0;
    }
    // Servers are looked for when the page opens and none have been found yet, as on the glass.
    if (!_discovered && view.servers && view.count == 0) {
      _discovered = true;
      _send(Browse.discover);
    }
    _discovered = true;
  }

  Future<void> _send(int command, {int row = 0, BrowseStep? step}) async {
    final view = _view;
    if (view == null) return;
    final code = browseCode(command, row, view.revision);
    // Queue and Cancel only change the status line; the rest publish a new revision.
    final moves = command != Browse.queue && command != Browse.cancel;
    if (moves) {
      _sentRev = view.revision;
      _sentAt = DateTime.now();
      _sentCmd = command;
      _expect = step;
    }
    final took = await act(context, ref, (api) => api.dlnaCommand(code));
    if (!_alive) return;
    if (!took) {
      setState(() {
        _sentRev = null;
        _expect = null;
        _climbing = 0;
      });
      return;
    }
    setState(() {});
    _soon();
  }

  void _open(DlnaRow row, int i) {
    if (_waiting) return;
    _send(Browse.open, row: i, step: row.folder ? Opened(row.title) : null);
    // a track plays, and the Player is where that is shown — as the glass goes there
    if (!row.folder && row.playable) context.go('/player');
  }

  Future<void> _queue(DlnaRow row, int i) async {
    if (_waiting) return;
    final l = AppLocalizations.of(context);
    await _send(Browse.queue, row: i);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.dlnaQueued(row.title))));
    }
  }

  /// A crumb: [levels] up — one ← at a time, each once the last has landed.
  void _climb(int levels) {
    if (_waiting || levels < 1) return;
    _climbing = levels - 1;
    _send(Browse.back, step: const WentBack());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final view = _view;
    final waiting = _waiting;
    final searching =
        view != null &&
        (view.busy
            ? view.status.startsWith('@dlna.searching')
            : _sentCmd == Browse.discover);
    final status = view == null
        ? ''
        : waiting
        ? (searching ? l.dlnaSearching : l.appLoading)
        : _routine.hasMatch(view.status)
        ? ''
        : l.message(view.status);

    final crumbs = <Widget>[];
    if (view != null && !view.servers) {
      crumbs.add(
        _Crumb(
          label: l.dlnaServers,
          onTap: waiting ? null : () => _climb(_toServers),
        ),
      );
      for (var i = 0; i < _crumbs.length; i++) {
        final c = _crumbs[i];
        crumbs.add(
          Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
        );
        crumbs.add(
          i == _crumbs.length - 1
              ? _Crumb(label: c ?? l.message(view.title))
              : _Crumb(
                  label: c ?? '…',
                  tooltip: c ?? l.dlnaUp,
                  onTap: waiting ? null : () => _climb(_crumbs.length - 1 - i),
                ),
        );
      }
    } else {
      crumbs.add(_Crumb(label: l.dlnaServers));
    }

    Widget centre(List<Widget> children) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    final Widget body;
    if (_error case final error? when view == null) {
      body = centre([
        Text(
          l.dlnaUnavailable(error),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.error),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _poll,
          icon: const Icon(Icons.refresh),
          label: Text(l.appRetry),
        ),
      ]);
    } else if (view == null) {
      body = centre([const CircularProgressIndicator()]);
    } else if (view.count == 0 && !waiting) {
      body = centre([
        Text(
          view.servers ? l.dlnaNone : l.dlnaEmpty,
          textAlign: TextAlign.center,
        ),
        if (view.servers) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => _send(Browse.discover),
            icon: const Icon(Icons.refresh),
            label: Text(l.dlnaFind),
          ),
        ],
      ]);
    } else {
      final pager = !view.servers && (view.previous || view.next);
      body = ListView(
        controller: _scroll,
        children: [
          for (final (i, row) in view.rows.indexed)
            ListTile(
              enabled: !waiting && (row.folder || row.playable),
              leading: Icon(
                view.servers
                    ? Icons.hub
                    : row.folder
                    ? Icons.folder
                    : Icons.music_note,
              ),
              title: Text(
                row.title.isEmpty ? '—' : row.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: row.folder
                  ? null
                  : Text(
                      row.playable ? row.artist : l.dlnaUnsupported,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: row.folder
                  ? const Icon(Icons.chevron_right)
                  : row.playable
                  ? IconButton(
                      tooltip: l.dlnaQueue,
                      onPressed: waiting ? null : () => _queue(row, i),
                      icon: const Icon(Icons.playlist_add),
                    )
                  : null,
              onTap: () => _open(row, i),
            ),
          if (pager)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: l.dlnaPrev,
                    onPressed: waiting || !view.previous
                        ? null
                        : () => _send(Browse.previous),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    tooltip: l.dlnaNext,
                    onPressed: waiting || !view.next
                        ? null
                        : () => _send(Browse.next),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.pageDlna),
        actions: [
          if (view != null && view.busy)
            IconButton(
              tooltip: l.commonCancel,
              onPressed: () => _send(Browse.cancel),
              icon: const Icon(Icons.close),
            )
          else if (view != null && view.servers)
            IconButton(
              tooltip: l.dlnaFind,
              onPressed: waiting ? null : () => _send(Browse.discover),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: l.dlnaPath,
            container: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: crumbs,
              ),
            ),
          ),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  style: text.bodyMedium?.copyWith(
                    color: waiting ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// A step of the path: a button up to it, or — the folder on screen — its name.
class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, this.tooltip, this.onTap});

  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final here = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall,
      ),
    );
    if (onTap == null && tooltip == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: here,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240, minHeight: 48),
      child: TextButton(
        onPressed: onTap,
        child: Tooltip(
          message: tooltip ?? label,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
