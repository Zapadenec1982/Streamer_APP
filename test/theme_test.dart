import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer/theme/app_theme.dart';
import 'package:streamer/theme/m3_schemes.g.dart';

void main() {
  test('the panel has four schemes, in ui.theme order', () {
    expect(panelSchemes.map((s) => s.id), ['amber', 'blue', 'green', 'red']);
    // The swatches the web draws for them (webui/src/lib/schemes.js).
    expect(panelSchemes.map((s) => s.colors.primary), const [
      Color(0xFFFFB95F),
      Color(0xFF7A82C0),
      Color(0xFF9A9973),
      Color(0xFFC45D4A),
    ]);
  });

  test('an unknown ui.theme falls back to the first scheme', () {
    expect(panelColors(9), panelSchemes.first.colors);
    expect(panelColors(-1), panelSchemes.first.colors);
  });

  test('the app theme carries the panel roles', () {
    for (final s in panelSchemes) {
      final scheme = panelTheme(s.colors).colorScheme;
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, s.colors.primary);
      expect(scheme.surface, s.colors.surface);
      expect(scheme.surfaceContainer, s.colors.surfaceContainer);
      expect(scheme.onSurfaceVariant, s.colors.onSurfaceVar);
      expect(scheme.error, s.colors.error);
    }
  });
}
