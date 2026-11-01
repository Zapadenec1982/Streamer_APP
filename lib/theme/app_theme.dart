import 'package:flutter/material.dart';

import 'm3_schemes.g.dart';

/// The panel's scheme `index` (`ui.theme`), or the first one for an index this build does not know.
PanelColors panelColors(int index) =>
    panelSchemes[index >= 0 && index < panelSchemes.length ? index : 0].colors;

/// The app in the panel's colours. The panel names 22 roles; Material wants a few more, and those
/// are the nearest of the panel's own (secondary is the light end of its secondary container
/// pair, as Material's tone 80 is to 90), or Material's standard dark error tones, which the
/// panel's `error` already is.
ThemeData panelTheme(PanelColors c) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    inversePrimary: c.primaryContainer,
    secondary: c.onSecondaryContainer,
    onSecondary: c.secondaryContainer,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.tertiary,
    onTertiary: c.tertiaryContainer,
    tertiaryContainer: c.tertiaryContainer,
    onTertiaryContainer: c.onTertiaryContainer,
    error: c.error,
    onError: const Color(0xFF690005),
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceVar,
    surfaceContainerLowest: c.surfaceLowest,
    surfaceContainerLow: c.surfaceLow,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceHigh,
    surfaceContainerHighest: c.surfaceHighest,
    outline: c.outline,
    outlineVariant: c.outlineVar,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.inverseOnSurface,
    shadow: Colors.black,
    scrim: Colors.black,
    // The panel draws flat surfaces; no primary tint on raised ones.
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surfaceLow,
      indicatorColor: c.secondaryContainer,
    ),
    sliderTheme: SliderThemeData(inactiveTrackColor: c.surfaceHighest),
  );
}
