import 'package:flutter/material.dart';

/// The width [text] takes on one line in [style] at the phone's text size: the room a number
/// needs so it never wraps, whatever size the phone sets its text to.
double textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// The widest word of [texts], so a layout can give every word a line of its own rather than
/// break one in the middle.
double widestWord(
  BuildContext context,
  Iterable<String> texts,
  TextStyle? style,
) {
  var widest = 0.0;
  for (final text in texts) {
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final w = textWidth(context, word, style);
      if (w > widest) widest = w;
    }
  }
  return widest;
}
