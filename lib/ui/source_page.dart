import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/models.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'labels.dart';

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
    );
  }

  void _open(BuildContext context, WidgetRef ref, AppLocalizations l) {
    if (state.card == SourceCard.servers) {
      // The media server browser stays in the panel's web interface (plan, §1).
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.mobInWeb)));
      return;
    }
    ref.read(deviceApiProvider).selectSource(state.card.source);
  }
}
