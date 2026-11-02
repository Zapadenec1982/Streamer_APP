import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'ui/dlna_page.dart';
import 'ui/library_page.dart';
import 'ui/link_state.dart';
import 'ui/panels_page.dart';
import 'ui/phone_keys.dart';
import 'ui/player_page.dart';
import 'ui/settings_page.dart';
import 'ui/shell.dart';
import 'ui/source_page.dart';
import 'ui/stations_page.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/player',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Shell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/player',
                builder: (context, state) =>
                    const PanelPage(child: PlayerPage()),
                routes: [
                  GoRoute(
                    path: 'stations',
                    builder: (context, state) => const StationsPage(),
                  ),
                  GoRoute(
                    path: 'library',
                    builder: (context, state) => const LibraryPage(),
                  ),
                  GoRoute(
                    path: 'dlna',
                    builder: (context, state) => const DlnaPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/source',
                builder: (context, state) =>
                    const PanelPage(child: SourcePage()),
                routes: [
                  GoRoute(
                    path: 'dlna',
                    builder: (context, state) => const DlnaPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'panels',
                    builder: (context, state) => const PanelsPage(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        builder: (context, state) => const AddPanelPage(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);

/// The app wears the panel's colour scheme and speaks the chosen language — the phone's when it is
/// one of the four, English otherwise.
class StreamerApp extends ConsumerWidget {
  const StreamerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ref.watch(snapshotProvider.select((s) => s.scheme));
    return MaterialApp.router(
      builder: (context, child) => PhoneBinding(child: child!),
      onGenerateTitle: (context) => AppLocalizations.of(context).mobAppName,
      theme: panelTheme(panelColors(scheme)),
      routerConfig: ref.watch(routerProvider),
      locale: ref.watch(appLanguageProvider).locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, supported) {
        for (final locale in locales ?? const <Locale>[]) {
          for (final candidate in supported) {
            if (candidate.languageCode == locale.languageCode) return candidate;
          }
        }
        return const Locale('en');
      },
    );
  }
}
