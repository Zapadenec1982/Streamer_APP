import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../device/models.dart';
import '../device/panel/panel_link.dart';
import '../device/radio_browser.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'regions.dart';
import 'station_card.dart';
import 'writes.dart';

/// The catalogue's tabs: Ukraine's top, the countries, the genres, a search.
enum CatalogTab { top, countries, genres, search }

/// The Radio Browser catalogue — Top · Countries · Genres · Search — as the web's
/// stations/Catalog.svelte has it. The phone asks Radio Browser itself; the panel gets a station's
/// name, stream and uuid through `radio.web_*`, with the action last: play, keep in the list, keep
/// on preset N. The order, the quality floor and «Лише Україна» are kept between visits.
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key, required this.tab});

  final CatalogTab tab;

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage>
    with AutomaticKeepAliveClientMixin {
  late CatalogSort _sort;
  late CatalogFloor _floor;
  late bool _uaOnly;

  /// What the stations' list is of; null while a tab shows its countries, its genres or the
  /// search's hint.
  CatalogQuery? _query;
  String _where = '';
  int _offset = 0;
  List<CatalogStation> _rows = const [];
  bool _more = false;
  bool _loading = false;
  String? _message;
  bool _error = false;
  int _serial = 0;

  List<({String code, int count})>? _countries;
  Map<String, String> _names = const {};
  List<Genre>? _genres;
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final store = ref.read(settingsStoreProvider);
    _sort =
        CatalogSort.values.elementAtOrNull(
          int.tryParse(store.getString(SettingsKeys.catalogSort) ?? '') ?? 0,
        ) ??
        CatalogSort.popular;
    _floor =
        CatalogFloor.values.elementAtOrNull(
          int.tryParse(store.getString(SettingsKeys.catalogFloor) ?? '') ?? 1,
        ) ??
        CatalogFloor.k128;
    _uaOnly = store.getString(SettingsKeys.catalogUaOnly) == '1';
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _serial++;
    _search.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  void _open() {
    if (!mounted) return;
    switch (widget.tab) {
      case CatalogTab.top:
        _stations(const ByCountry('UA'), null);
      case CatalogTab.countries:
        _showCountries();
      case CatalogTab.genres:
        _showGenres();
      case CatalogTab.search:
        setState(() {
          _query = null;
          _message = null;
        });
    }
  }

  Future<void> _stations(
    CatalogQuery query,
    String? where, {
    int offset = 0,
  }) async {
    final l = AppLocalizations.of(context);
    final mine = ++_serial;
    setState(() {
      _query = query;
      _offset = offset;
      _loading = true;
      _error = false;
      _message = null;
      _rows = const [];
      if (where != null) _where = where;
    });
    if (query case ByCountry(code: 'UA') when where == null) {
      final names = await regionNames(const ['UA'], _language);
      if (mounted && mine == _serial) setState(() => _where = names['UA']!);
    }
    try {
      final page = await ref
          .read(radioBrowserProvider)
          .stations(
            query,
            sort: _sort,
            floor: _floor,
            uaOnly: _uaOnly,
            offset: offset,
          );
      // the rows name their countries in the app's language too
      final codes = {
        for (final r in page.rows)
          if (r.countryCode.isNotEmpty) r.countryCode.toUpperCase(),
      }.difference(_names.keys.toSet());
      final names = codes.isEmpty
          ? const <String, String>{}
          : await regionNames(codes.toList(), _language);
      if (!mounted || mine != _serial) return;
      setState(() {
        _names = {..._names, ...names};
        _rows = page.rows;
        _more = page.more;
        _loading = false;
        _message = page.rows.isNotEmpty
            ? null
            : page.more
            ? l.catNothingPage
            : l.catNothing;
      });
    } on CatalogError catch (e) {
      if (!mounted || mine != _serial) return;
      setState(() {
        _loading = false;
        _error = true;
        _message = l.catUnavailable(e.message);
      });
    }
  }

  Future<void> _showCountries() async {
    final l = AppLocalizations.of(context);
    final mine = ++_serial;
    setState(() {
      _query = null;
      _error = false;
      _message = null;
      _loading = _countries == null;
    });
    if (_countries != null) return;
    try {
      final list = await ref.read(radioBrowserProvider).countries();
      final names = await regionNames([
        for (final c in list) c.code,
      ], _language);
      if (!mounted || mine != _serial) return;
      setState(() {
        _countries = list;
        _names = names;
        _loading = false;
      });
    } on CatalogError catch (e) {
      if (!mounted || mine != _serial) return;
      setState(() {
        _loading = false;
        _error = true;
        _message = l.catUnavailable(e.message);
      });
    }
  }

  Future<void> _showGenres() async {
    final l = AppLocalizations.of(context);
    final mine = ++_serial;
    setState(() {
      _query = null;
      _error = false;
      _message = null;
      _loading = _genres == null;
    });
    if (_genres != null) return;
    try {
      final genres = await ref.read(deviceApiProvider).radioGenres();
      if (!mounted || mine != _serial) return;
      setState(() {
        _genres = genres;
        _loading = false;
        if (genres.isEmpty) _message = l.catNoGenres;
      });
    } on PanelError {
      if (!mounted || mine != _serial) return;
      setState(() {
        _loading = false;
        _error = true;
        _message = l.catNoGenres;
      });
    }
  }

  void _refilter() {
    final store = ref.read(settingsStoreProvider);
    store.setString(SettingsKeys.catalogSort, '${_sort.index}');
    store.setString(SettingsKeys.catalogFloor, '${_floor.index}');
    store.setString(SettingsKeys.catalogUaOnly, _uaOnly ? '1' : '0');
    final query = _query;
    if (query != null) _stations(query, null);
  }

  void _searchNow() {
    final words = _search.text.trim();
    if (words.isEmpty) return;
    _stations(ByName(words), '«$words»');
  }

  /// [action] 0 plays it on the streamer, 1 keeps it in the list, 2…7 keeps it on preset 1…6.
  Future<void> _toPanel(CatalogStation st, int action) async {
    final l = AppLocalizations.of(context);
    final took = await act(
      context,
      ref,
      (api) => api.catalogStation(
        name: st.name,
        url: st.url,
        uuid: st.uuid,
        act: action,
      ),
    );
    if (!took || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            0 => l.catPlayed(st.name),
            1 => l.catKept(st.name),
            _ => l.catInPreset('${action - 1}', st.name),
          }),
        ),
      );
  }

  Future<void> _toPreset(CatalogStation st) async {
    final l = AppLocalizations.of(context);
    final slot = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(st.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.catToPreset),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < StationList.presetCount; i++)
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(i),
                    child: Text('${i + 1}'),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.commonCancel),
          ),
        ],
      ),
    );
    if (slot != null) await _toPanel(st, slot + 2);
  }

  String _subtitle(AppLocalizations l, CatalogStation st) {
    final number = NumberFormat.decimalPattern(_language);
    return [
      if (st.codec == 'FLAC')
        'FLAC · ${l.catLossless}'
      else if (st.bitrate > 0)
        '${st.codec} ${st.bitrate}'
      else
        st.codec,
      if (st.countryCode.isNotEmpty)
        _names[st.countryCode.toUpperCase()] ?? st.countryCode,
      if (_sort == CatalogSort.popular) l.catPerDay(number.format(st.clicks)),
      if (_sort == CatalogSort.votes) l.catVotes(st.votes),
      if (st.tags.isNotEmpty) st.tags.split(',').take(3).join(', '),
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final query = _query;
    final stations = query != null;
    final drilled =
        stations &&
        (widget.tab == CatalogTab.countries || widget.tab == CatalogTab.genres);

    final children = <Widget>[
      if (widget.tab == CatalogTab.search)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchNow(),
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: l.catSearchPh,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _searchNow,
                icon: const Icon(Icons.search),
                label: Text(l.catSearch),
              ),
            ],
          ),
        ),
      if (stations || widget.tab == CatalogTab.search)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in CatalogSort.values)
                ChoiceChip(
                  label: Text(switch (s) {
                    CatalogSort.popular => l.catSortPop,
                    CatalogSort.votes => l.catSortVotes,
                    CatalogSort.quality => l.catSortQuality,
                    CatalogSort.name => l.catSortAz,
                  }),
                  selected: _sort == s,
                  onSelected: (_) {
                    setState(() => _sort = s);
                    _refilter();
                  },
                ),
              DropdownButton<CatalogFloor>(
                value: _floor,
                underline: const SizedBox.shrink(),
                hint: Text(l.catQuality),
                items: [
                  for (final f in CatalogFloor.values)
                    DropdownMenuItem(
                      value: f,
                      child: Text(switch (f) {
                        CatalogFloor.all => l.catQAll,
                        CatalogFloor.k128 => l.catQ128,
                        CatalogFloor.k192 => l.catQ192,
                        CatalogFloor.k320 => l.catQ320,
                        CatalogFloor.flac => l.catQFlac,
                      }),
                    ),
                ],
                onChanged: (f) {
                  if (f == null) return;
                  setState(() => _floor = f);
                  _refilter();
                },
              ),
              if (widget.tab == CatalogTab.genres ||
                  widget.tab == CatalogTab.search)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _uaOnly,
                      onChanged: (on) {
                        setState(() => _uaOnly = on);
                        _refilter();
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(l.catUaOnly),
                  ],
                ),
            ],
          ),
        ),
      if (stations && _where.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(drilled ? 4 : 16, 4, 16, 0),
          child: Row(
            children: [
              if (drilled)
                IconButton(
                  tooltip: widget.tab == CatalogTab.countries
                      ? l.stTabCountries
                      : l.stTabGenres,
                  onPressed: _open,
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Text(
                  _where,
                  style: text.titleSmall?.copyWith(color: colors.primary),
                ),
              ),
            ],
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_message case final message?)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _error ? colors.error : null),
          ),
        ),
      if (!stations &&
          !_loading &&
          widget.tab == CatalogTab.countries &&
          _countries != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l.catCountries(_countries!.length),
            style: text.labelLarge,
          ),
        ),
        for (final c in _countries!)
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(_names[c.code] ?? c.code),
            subtitle: Text(l.catStations(c.count)),
            onTap: () => _stations(ByCountry(c.code), _names[c.code] ?? c.code),
          ),
      ],
      if (!stations &&
          !_loading &&
          widget.tab == CatalogTab.genres &&
          (_genres?.isNotEmpty ?? false)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(l.catGenres(_genres!.length), style: text.labelLarge),
        ),
        for (final g in _genres!)
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(g.nameIn(_language)),
            onTap: () => _stations(ByTag(g.tag), g.nameIn(_language)),
          ),
      ],
      if (stations && !_loading) ...[
        for (final st in _rows)
          ListTile(
            leading: StationLogo(name: st.name, logo: st.favicon, size: 40),
            title: Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _subtitle(l, st),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _toPanel(st, 0),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l.catKeep,
                  onPressed: () => _toPanel(st, 1),
                  icon: const Icon(Icons.favorite_border),
                ),
                IconButton(
                  tooltip: l.catToPreset,
                  onPressed: () => _toPreset(st),
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
        if (_rows.isNotEmpty || _offset > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: l.catPrev,
                  onPressed: _offset == 0
                      ? null
                      : () => _stations(
                          query,
                          null,
                          offset: _offset - RadioBrowser.limit,
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(l.catPage('${_offset ~/ RadioBrowser.limit + 1}')),
                IconButton(
                  tooltip: l.catNext,
                  onPressed: !_more
                      ? null
                      : () => _stations(
                          query,
                          null,
                          offset: _offset + RadioBrowser.limit,
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
      if (widget.tab == CatalogTab.search && !stations && _message == null)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.catSearchHint, textAlign: TextAlign.center),
        ),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}
