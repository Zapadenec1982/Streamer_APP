import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../device/models.dart';

/// A cover drawn by the app: the scheme's colours at an angle the cover's key picks, and the
/// source's icon. It stands in for a picture until the panel sends one (plan, stage 2), and it is
/// the demo's only artwork — nobody else's album covers.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.coverKey,
    required this.source,
    required this.size,
  });

  final String? coverKey;
  final SourceId source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final turn = (coverKey?.hashCode ?? 0) % 360 / 360 * 2 * math.pi;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 16),
        gradient: coverKey == null
            ? null
            : LinearGradient(
                colors: [
                  colors.primaryContainer,
                  colors.tertiaryContainer,
                  colors.surfaceContainerHigh,
                ],
                transform: GradientRotation(turn),
              ),
        color: coverKey == null ? colors.surfaceContainerLow : null,
      ),
      child: Icon(
        _icon(source),
        size: size * 0.36,
        color: colors.onPrimaryContainer.withValues(
          alpha: coverKey == null ? 0.25 : 0.4,
        ),
      ),
    );
  }

  static IconData _icon(SourceId source) => switch (source) {
    SourceId.radio => Icons.radio,
    SourceId.airplay => Icons.airplay,
    SourceId.usb => Icons.usb,
    SourceId.bt || SourceId.card => Icons.music_note,
    SourceId.off || SourceId.tone || SourceId.aux => Icons.power_settings_new,
  };
}
