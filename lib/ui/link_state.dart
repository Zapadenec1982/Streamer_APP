import 'dart:async';

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
    // another panel chosen is waited for afresh
    if (!snapshot.known) {
      return _Waiting(key: ValueKey(choice.id), status: snapshot.status);
    }
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
    // TalkBack says it as it appears
    return Semantics(
      liveRegion: true,
      child: Container(
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
      ),
    );
  }
}

/// The panel has not spoken yet. For a while that is «Підключення…»; a panel that still has not
/// answered after [_patience] is said to be out of reach, with the way to try again at once or to
/// choose another — the link keeps trying by itself all the while. A busy panel is not out of
/// reach: it says so, and the link tries again every 5 s.
class _Waiting extends ConsumerStatefulWidget {
  const _Waiting({super.key, required this.status});

  final LinkStatus status;

  @override
  ConsumerState<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends ConsumerState<_Waiting> {
  static const _patience = Duration(seconds: 10);

  Timer? _timer;
  bool _late = false;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _wait() {
    _timer?.cancel();
    _late = false;
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _late = true);
    });
  }

  void _retry() {
    // let go of the panel and take it again: a new attempt now, not at the end of the backoff
    ref.read(deviceApiProvider)
      ..suspend()
      ..resume();
    setState(_wait);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final unreachable = _late && widget.status == LinkStatus.connecting;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: unreachable
                  ? [
                      Icon(
                        Icons.wifi_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.appError,
                        style: text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.mobNoPanelNote,
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: _retry, child: Text(l.appRetry)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.go('/settings/panels'),
                        child: Text(l.mobOtherPanel),
                      ),
                    ]
                  : [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _words(l, widget.status, known: false),
                        textAlign: TextAlign.center,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
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
