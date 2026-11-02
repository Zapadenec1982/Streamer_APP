import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The Player's column: [top] and [bottom] at their own heights, and between them a square
/// [cover] as large as the rest of [height] leaves it — no wider than the column, no smaller than
/// [smallest]. The column is [height] tall unless even the smallest cover leaves no room; then it
/// is as tall as it needs and the page scrolls. However large the phone sets its text and however
/// many rows the presets take, the page fits whenever it can.
class CoverColumn extends MultiChildRenderObjectWidget {
  CoverColumn({
    super.key,
    required this.height,
    required this.smallest,
    required Widget top,
    required Widget cover,
    required Widget bottom,
  }) : super(children: [top, cover, bottom]);

  final double height;
  final double smallest;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCoverColumn(height, smallest);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCoverColumn renderObject,
  ) => renderObject
    ..height = height
    ..smallest = smallest;
}

class _Slot extends ContainerBoxParentData<RenderBox> {}

/// [CoverColumn]'s layout.
class RenderCoverColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _Slot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _Slot> {
  RenderCoverColumn(this._height, this._smallest);

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double _smallest;
  set smallest(double value) {
    if (value == _smallest) return;
    _smallest = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Slot) child.parentData = _Slot();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final top = firstChild!;
    final cover = childAfter(top)!;
    final bottom = childAfter(cover)!;
    final loose = BoxConstraints(maxWidth: width);
    top.layout(loose, parentUsesSize: true);
    bottom.layout(loose, parentUsesSize: true);
    final room = _height - top.size.height - bottom.size.height;
    final side = math.max(math.min(_smallest, width), math.min(room, width));
    cover.layout(BoxConstraints.tight(Size.square(side)), parentUsesSize: true);
    var y = 0.0;
    for (final child in [top, cover, bottom]) {
      (child.parentData! as _Slot).offset = Offset(
        (width - child.size.width) / 2,
        y,
      );
      y += child.size.height;
    }
    size = constraints.constrain(Size(width, math.max(_height, y)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

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
