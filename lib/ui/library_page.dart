import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/media.dart';
import '../device/models.dart';
import '../device/panel/panel_link.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'writes.dart';

/// The index as last read, kept while the app is open: a second visit asks only whether the card
/// changed (its generation and count) and shows the list at once.
({int gen, int count, String root, List<String> rows})? _kept;

/// The card's library: every track on the card, as the glass's Library page lists them
/// (screen_library.cpp) and the web's LibraryPage — the file's name without its extension, its
/// folder under it, the track the queue is on marked. A filter narrows it by name or folder; a
/// tap plays the track (`player.track` and `player.cmd` 1) and the Player opens, as on the glass.
///
/// `GET /api/library` gives the index a page at a time; the page reads all of it, then filters on
/// the phone.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  static const _page = 200;

  final _scroll = ScrollController();
  final _filter = TextEditingController();
  var _lib = _kept;
  int _loaded = 0;
  int _total = 0;

  /// The panel is still reading the card.
  bool _busy = false;
  String? _error;
  int _serial = 0;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _loaded = _total = _lib?.count ?? 0;
    _filter.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _serial++;
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  /// The whole index, page after page; starts over when the card changed under it.
  Future<void> _load() async {
    final mine = ++_serial;
    setState(() => _error = null);
    final api = ref.read(deviceApiProvider);
    for (var attempt = 0; attempt < 40 && mine == _serial; attempt++) {
      try {
        final kept = _kept;
        // with a copy kept, only "has it changed": one row
        final first = await api.library(count: kept != null ? 1 : _page);
        if (mine != _serial || !mounted) return;
        if (first.busy) {
          setState(() => _busy = true);
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          continue;
        }
        _busy = false;
        if (kept != null &&
            kept.gen == first.gen &&
            kept.count == first.count) {
          setState(() {
            _lib = kept;
            _loaded = _total = kept.count;
          });
          _reveal();
          return;
        }
        var rows = kept != null ? <String>[] : first.rows;
        var moved = false;
        setState(() {
          _total = first.count;
          _loaded = rows.length;
        });
        while (rows.length < first.count && mine == _serial) {
          final p = await api.library(from: rows.length, count: _page);
          if (p.busy || p.gen != first.gen || p.rows.isEmpty) {
            moved = true;
            break;
          }
          rows = [...rows, ...p.rows];
          if (mounted) setState(() => _loaded = rows.length);
        }
        if (mine != _serial || !mounted) return;
        if (moved) {
          _kept = null;
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        final lib = (
          gen: first.gen,
          count: first.count,
          root: first.root,
          rows: rows,
        );
        _kept = lib;
        setState(() => _lib = lib);
        _reveal();
        return;
      } on PanelError catch (e) {
        if (mine == _serial && mounted && !e.unauthorized) {
          setState(() => _error = e.code ?? '${e.status}');
        }
        return;
      }
    }
  }

  /// Opens on the track the queue is on, once, as the glass does.
  void _reveal() {
    if (_revealed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cursor = ref.read(snapshotProvider).cardIndex;
      final lib = _lib;
      if (!mounted || !_scroll.hasClients || lib == null) return;
      if (cursor < 0 || cursor >= lib.rows.length || _filter.text.isNotEmpty) {
        return;
      }
      _revealed = true;
      final position = _scroll.position;
      // every row is as tall as the prototype, so the row's place is its index times that
      final row =
          (position.maxScrollExtent + position.viewportDimension) /
          lib.rows.length;
      _scroll.jumpTo(
        (cursor * row - (position.viewportDimension - row) / 2).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _play(String rel) async {
    final lib = _lib!;
    final took = await act(
      context,
      ref,
      (api) => api.playTrack(trackPath(lib.root, rel)),
    );
    if (took && mounted) context.go('/player');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    // a new count is a new card: the panel builds the index again
    ref.listen(snapshotProvider.select((s) => s.cardCount), (before, now) {
      if (before != null && before != now) _load();
    });
    final cursor = ref.watch(snapshotProvider.select((s) => s.cardIndex));
    final now = ref.watch(snapshotProvider.select((s) => s.now));
    final playing = now.kind == NowKind.card && now.playing;
    final lib = _lib;
    final query = _filter.text;
    final found = [
      if (lib != null)
        for (var i = 0; i < lib.rows.length; i++)
          if (matchesFilter(lib.rows[i], query)) i,
    ];
    final count = _busy
        ? l.libBusy
        : lib != null && query.isNotEmpty
        ? l.libFound('${found.length}', '${lib.rows.length}')
        : lib != null
        ? l.srcsubTracks(lib.rows.length)
        : _total > 0
        ? l.libReading('$_loaded', '$_total')
        : '';

    Widget centre(Widget child) => Center(
      child: Padding(padding: const EdgeInsets.all(32), child: child),
    );
    final Widget body;
    if (_error case final error?) {
      body = centre(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.libUnavailable(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(l.appRetry),
            ),
          ],
        ),
      );
    } else if (lib == null) {
      body = centre(
        _busy || _total > 0
            ? const CircularProgressIndicator()
            : Text(l.appLoading),
      );
    } else if (lib.rows.isEmpty) {
      body = centre(Text(l.libEmpty, textAlign: TextAlign.center));
    } else if (found.isEmpty) {
      body = centre(Text(l.libNothing, textAlign: TextAlign.center));
    } else {
      ListTile row(int i) {
        final rel = lib.rows[i];
        final folder = trackFolder(rel);
        final name = trackName(rel);
        return ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(
            name.isEmpty ? '—' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: i == cursor,
          trailing: i == cursor && playing
              ? Icon(Icons.graphic_eq, semanticLabel: l.libPlaying)
              : null,
          onTap: () => _play(rel),
        );
      }

      body = ListView.builder(
        controller: _scroll,
        itemCount: found.length,
        prototypeItem: row(found.first),
        itemBuilder: (context, i) => row(found[i]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.pageLibrary)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                labelText: l.libFilter,
                hintText: l.libFilterPh,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Semantics(
              liveRegion: true,
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  count,
                  style: text.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
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
