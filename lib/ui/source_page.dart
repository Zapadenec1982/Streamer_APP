import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';
import 'writes.dart';

/// The panel's sources as cards, the playing one filled (webui SourcePage, screen_src.cpp).
class SourcePage extends ConsumerWidget {
  const SourcePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final snapshot = ref.watch(snapshotProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSource)),
      body: GridView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: _Card.height(context),
        ),
        children: [for (final card in snapshot.cards) _Card(state: card)],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.state});

  final SourceCardState state;

  /// Tall enough for the icon, the name and two lines of status at the phone's text size, so a
  /// larger text grows the card rather than cutting it.
  static double height(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? s) =>
        scaler.scale(s?.fontSize ?? 14) * (s?.height ?? 1.25);
    return 2 * 14 +
        28 +
        12 +
        line(text.titleMedium) +
        2 +
        2 * line(text.bodySmall) +
        2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = state.active ? colors.onPrimaryContainer : colors.onSurface;
    return Card(
      margin: EdgeInsets.zero,
      color: state.active ? colors.primaryContainer : colors.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      // the card is one stop for TalkBack: its name and status, and whether it is the one playing
      child: Semantics(
        button: true,
        selected: state.active,
        child: InkWell(
          onTap: () => _open(context, ref, l),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(cardIcon(state.card), size: 28, color: fg),
                    const Spacer(),
                    if (state.active)
                      Icon(Icons.check_circle, size: 22, color: fg),
                  ],
                ),
                const Spacer(),
                Text(
                  l.cardName(state.card),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: fg),
                ),
                const SizedBox(height: 2),
                Text(
                  l.label(state.status),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: state.active
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, AppLocalizations l) {
    if (state.card == SourceCard.servers) {
      // the media servers' card opens their browser, as on the glass and the web
      context.go('/source/dlna');
      return;
    }
    // a tap is "listen": the source is set and the Player opens, as on the glass and the web
    if (!state.active) {
      act(context, ref, (api) => api.selectSource(state.card.source));
    }
    context.go('/player');
  }
}
