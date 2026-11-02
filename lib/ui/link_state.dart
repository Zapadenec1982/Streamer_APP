import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../device/models.dart';
import '../device/panels.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// A page that shows the panel: the page itself once the panel has spoken; until then — or with no
/// panel chosen — what is going on, in words. While the panel is away the last state stays, under a
/// line saying so (plan, §1: no command waits for it).
class PanelPage extends ConsumerWidget {
  const PanelPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(activePanelProvider);
    if (choice is NoPanel) return const _ConnectPrompt();
    final snapshot = ref.watch(snapshotProvider);
    if (!snapshot.known) return _Waiting(status: snapshot.status);
    return Column(
      children: [
        if (snapshot.status != LinkStatus.ready)
          SafeArea(bottom: false, child: _Strip(status: snapshot.status)),
        Expanded(child: child),
      ],
    );
  }
}

String _words(AppLocalizations l, LinkStatus status, {required bool known}) =>
    switch (status) {
      LinkStatus.busy => l.mobBusy,
      _ => known ? l.connLost : l.nowConnecting,
    };

class _Strip extends StatelessWidget {
  const _Strip({required this.status});

  final LinkStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _words(AppLocalizations.of(context), status, known: true),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.status});

  final LinkStatus status;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          _words(AppLocalizations.of(context), status, known: false),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ConnectPrompt extends ConsumerWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speaker,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l.mobNoPanel,
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l.mobNoPanelNote,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/settings/panels/add'),
                icon: const Icon(Icons.search),
                label: Text(l.mobFind),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(activeIdProvider.notifier).set(PanelChoice.demoId),
                child: Text(l.mobTryDemo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
