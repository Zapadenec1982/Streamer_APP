import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'station_card.dart';
import 'writes.dart';

/// Every station of the list; a tap tunes it and goes back to the Player. Editing the list and the
/// catalog stay in the web (plan, §1).
class StationsPage extends ConsumerWidget {
  const StationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(snapshotProvider.select((s) => s.radio.current));
    final list = ref.watch(stationListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.pageStations)),
      body: switch (list) {
        AsyncData(:final value) when value.stations.isEmpty => Center(
          child: Text(l.stNone),
        ),
        AsyncData(:final value) => ListView.builder(
          itemCount: value.stations.length,
          itemBuilder: (context, i) {
            final st = value.stations[i];
            final preset = value.presets.indexOf(i);
            return ListTile(
              leading: StationDisc(name: st.name, size: 40),
              title: Text(
                st.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: preset >= 0 ? Text(l.stPresetN('${preset + 1}')) : null,
              selected: i == current,
              onTap: () {
                act(context, ref, (api) => api.listen(i));
                context.go('/player');
              },
            );
          },
        ),
        AsyncError() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.stLoadFailed),
              TextButton(
                onPressed: () => ref.invalidate(stationListProvider),
                child: Text(l.appRetry),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
