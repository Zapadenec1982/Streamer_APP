import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../device/eq.dart';
import '../device/eq_math.dart';

/// The equalizer's plot, as the web's dsp/EqPlot.svelte and the glass's screen_eq.cpp draw it:
/// 20 Hz – 20 kHz on a log axis, ±12 dB — ±24 once a pass or a notch is on, or the whole system
/// goes past ±12 — the summed curve from the firmware's own design (eq_math.dart), and a point
/// per band at the band's own response at its own frequency, which is where a shelf or a pass
/// actually is. A band that is off is a hollow point on 0 dB. With [stages] the whole system's
/// curve is over it, dashed.
///
/// A band is taken by its point only: a finger anywhere else on the plot scrolls the page. On a
/// point it picks the band ([onSelect]) and the point moves once it has been held [hold] or the
/// finger went [slop] away; a mouse takes it at once. x is frequency, y is gain — twice the
/// target for a shelf, whose corner carries half of it; nothing for a pass or a notch.
/// [onGrab] fires when a band starts to move, [onRelease] when it is let go.
class EqPlot extends StatefulWidget {
  const EqPlot({
    super.key,
    required this.bands,
    required this.fs,
    required this.selected,
    required this.on,
    required this.label,
    this.stages,
    required this.onSelect,
    required this.onEdit,
    required this.onGrab,
    required this.onRelease,
  });

  final List<EqBand> bands;
  final double fs;
  final int selected;

  /// The EQ is on: the curve is what is heard. Off, it is what switching on would do — grey.
  final bool on;

  /// What TalkBack calls the plot.
  final String label;

  /// The stages around the EQ (systemStages): the whole system is drawn too; null: not.
  final List<Stage>? stages;
  final ValueChanged<int> onSelect;
  final void Function(int band, EqBand edited) onEdit;
  final ValueChanged<int> onGrab;
  final ValueChanged<int> onRelease;

  static const height = 240.0;

  /// How far a finger goes before a press on a point is a drag.
  static const slop = 8.0;

  /// How long a still finger holds a point before it is picked up.
  static const hold = Duration(milliseconds: 300);

  @override
  State<EqPlot> createState() => _EqPlotState();
}

/// The plot's geometry at a size and a range.
class _Frame {
  _Frame(this.size, this.range);

  static const fLo = 20.0;
  static const decades = 3.0;
  static const left = 34.0;
  static const right = 10.0;
  static const top = 12.0;
  static const bottom = 24.0;

  final Size size;
  final double range;

  double get pw => math.max(10, size.width - left - right);
  double get ph => math.max(10, size.height - top - bottom);

  static double fx(double f) => math.log(f / fLo) / math.ln10 / decades;
  static double xf(double x) => fLo * math.pow(10, x * decades);

  double x(double fraction) => left + fraction * pw;
  double y(double db) =>
      top + (0.5 - db.clamp(-range, range) / (2 * range)) * ph;
}

class _EqPlotState extends State<EqPlot> {
  /// The panel's 97 points and one between each pair.
  static const _n = 193;
  static const _gridF = [50, 100, 200, 500, 1000, 2000, 5000, 10000];
  static const _gridL = ['50', '100', '200', '500', '1k', '2k', '5k', '10k'];

  /// A point's radius, and how far from its centre a finger takes it.
  static const _r = 13.0;
  static const _hit = 24.0;

  static final _freqs = [for (var i = 0; i < _n; i++) _Frame.xf(i / (_n - 1))];

  /// What the last frame drew: the hit test and a drag go by it.
  _Frame? _frame;
  List<Offset> _points = const [];

  /// The band that moves, and the one picked up by a hold — drawn larger.
  int _drag = -1;
  int _lifted = -1;

  // one press on a point
  int _band = -1;
  Offset _start = Offset.zero;
  Duration _t0 = Duration.zero;
  _Press _state = _Press.idle;

  /// The finger from the point's centre, kept while it moves.
  Offset _off = Offset.zero;
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  /// The band whose point is under [p]: the selected one on top, then the later over the earlier,
  /// as they are drawn.
  int _bandAt(Offset p) {
    bool near(int i) => (_points[i] - p).distance <= _hit;
    final sel = widget.selected;
    if (sel >= 0 && sel < _points.length && near(sel)) return sel;
    for (var i = _points.length - 1; i >= 0; i--) {
      if (near(i)) return i;
    }
    return -1;
  }

  void _down(int band, PointerDownEvent e) {
    // a press starts afresh — also when the end of the one before never came
    _holdTimer?.cancel();
    _band = band;
    _start = e.localPosition;
    _t0 = e.timeStamp;
    _off = e.localPosition - _points[band];
    if (band != widget.selected) widget.onSelect(band);
    if (e.kind == PointerDeviceKind.mouse) {
      _state = _Press.drag;
      _begin();
      return;
    }
    _state = _Press.press;
    _holdTimer = Timer(EqPlot.hold, () {
      if (_state == _Press.press && mounted) {
        _state = _Press.lift;
        setState(() => _lifted = _band);
      }
    });
  }

  void _begin() {
    setState(() => _drag = _lifted = _band);
    widget.onGrab(_band);
  }

  void _move(PointerMoveEvent e) {
    final was = _state;
    if (_state == _Press.press && e.timeStamp - _t0 >= EqPlot.hold) {
      _state = _Press.lift;
    }
    if (_state == _Press.press &&
        (e.localPosition - _start).distance >= EqPlot.slop) {
      _state = _Press.drag;
    } else if (_state == _Press.lift && e.localPosition != _start) {
      _state = _Press.drag;
    }
    if (_state == _Press.lift && _lifted != _band) {
      setState(() => _lifted = _band);
    }
    if (_state != _Press.drag) return;
    if (was != _Press.drag) _begin();
    final frame = _frame;
    if (frame == null || _drag < 0 || _drag >= widget.bands.length) return;
    final p = e.localPosition - _off;
    final nx = ((p.dx - _Frame.left) / frame.pw).clamp(0.0, 1.0);
    final ny = ((p.dy - _Frame.top) / frame.ph).clamp(0.0, 1.0);
    final b = widget.bands[_drag];
    final target = (0.5 - ny) * 2 * frame.range;
    var gain = b.gain;
    if (b.type.hasGain) {
      gain = (b.type == EqType.peak ? target : target * 2).clamp(
        -EqLimits.gainMax,
        EqLimits.gainMax,
      );
    }
    // a tenth of a dB and three significant figures of Hz: what the band's sheet shows
    final f = double.parse(_Frame.xf(nx).toStringAsPrecision(3));
    widget.onEdit(
      _drag,
      b.copyWith(f: f, gain: (gain * 10 + 0.5).floorToDouble() / 10, on: true),
    );
  }

  void _up() {
    _holdTimer?.cancel();
    _state = _Press.idle;
    final dragged = _drag;
    setState(() {
      _drag = -1;
      _lifted = -1;
    });
    if (dragged >= 0) widget.onRelease(dragged);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bands = widget.bands;
    final fs = widget.fs;
    final curve = curveDb(bands, fs, _freqs);
    final system = widget.stages == null
        ? null
        : systemCurveDb(bands, widget.stages!, fs, _freqs, eqOn: widget.on);
    final range =
        bands.any((b) => b.on && !b.type.hasGain) ||
            (system?.any((v) => v.abs() > 12) ?? false)
        ? 24.0
        : 12.0;
    return Semantics(
      label: widget.label,
      image: true,
      child: SizedBox(
        height: EqPlot.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final frame = _Frame(Size(box.maxWidth, EqPlot.height), range);
            _frame = frame;
            _points = [
              for (final b in bands)
                Offset(
                  frame.x(_Frame.fx(b.f).clamp(0.0, 1.0)),
                  frame.y(bandMagnitudeDb(b, fs, b.f)),
                ),
            ];
            return RawGestureDetector(
              gestures: {
                _PointRecognizer:
                    GestureRecognizerFactoryWithHandlers<_PointRecognizer>(
                      _PointRecognizer.new,
                      (r) => r
                        ..bandAt = _bandAt
                        ..onDown = _down
                        ..onMove = _move
                        ..onUp = _up,
                    ),
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(
                  size: Size(box.maxWidth, EqPlot.height),
                  painter: _PlotPainter(
                    frame: frame,
                    curve: curve,
                    system: system,
                    points: _points,
                    bands: bands,
                    selected: widget.selected,
                    lifted: _lifted,
                    on: widget.on,
                    colors: colors,
                    font: Theme.of(context).textTheme.labelSmall!
                        .copyWith(height: 1, letterSpacing: 0),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _Press { idle, press, lift, drag }

/// A finger on a point is the band's, not the page's: the recogniser takes it the moment it lands
/// — the page's scroll never gets it — and only there; a press anywhere else is left to the page.
class _PointRecognizer extends OneSequenceGestureRecognizer {
  int Function(Offset local)? bandAt;
  void Function(int band, PointerDownEvent event)? onDown;
  void Function(PointerMoveEvent event)? onMove;
  VoidCallback? onUp;
  int? _pointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null &&
      (bandAt?.call(event.localPosition) ?? -1) >= 0 &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    resolve(GestureDisposition.accepted);
    onDown?.call(bandAt!(event.localPosition), event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onMove?.call(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onUp?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _pointer = null;

  @override
  String get debugDescription => 'equalizer point';
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.frame,
    required this.curve,
    required this.system,
    required this.points,
    required this.bands,
    required this.selected,
    required this.lifted,
    required this.on,
    required this.colors,
    required this.font,
  });

  final _Frame frame;
  final List<double> curve;
  final List<double>? system;
  final List<Offset> points;
  final List<EqBand> bands;
  final int selected;
  final int lifted;
  final bool on;
  final ColorScheme colors;

  /// The app's own type, for the axis and the points' numbers; not scaled with the phone's text
  /// size — the plot's frame is fixed.
  final TextStyle font;

  void _label(Canvas canvas, String s, Offset at, {required TextAlign align}) {
    final painter = TextPainter(
      text: TextSpan(
        text: s,
        style: font.copyWith(color: colors.outline, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => -painter.width / 2,
      TextAlign.right => -painter.width,
      _ => 0.0,
    };
    // [at] is the text's baseline, as the web's SVG places it
    painter.paint(
      canvas,
      at +
          Offset(
            dx,
            -painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
    );
    painter.dispose();
  }

  Path _line(List<double> dbs) {
    final path = Path();
    for (var i = 0; i < dbs.length; i++) {
      final p = Offset(frame.x(i / (dbs.length - 1)), frame.y(dbs[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainerLow,
    );
    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    final r = frame.range;
    for (var k = 0; k < _EqPlotState._gridF.length; k++) {
      final x = frame.x(_Frame.fx(_EqPlotState._gridF[k].toDouble()));
      canvas.drawLine(
        Offset(x, _Frame.top),
        Offset(x, _Frame.top + frame.ph),
        grid,
      );
      _label(
        canvas,
        _EqPlotState._gridL[k],
        Offset(x, size.height - 6),
        align: TextAlign.center,
      );
    }
    for (final db in [r, r / 2, 0.0, -r / 2, -r]) {
      final y = frame.y(db);
      canvas.drawLine(
        Offset(_Frame.left, y),
        Offset(_Frame.left + frame.pw, y),
        db == 0 ? (Paint()..color = colors.outline) : grid,
      );
      final n = db.round();
      _label(
        canvas,
        n > 0
            ? '+$n'
            : n < 0
            ? '−${-n}'
            : '0',
        Offset(_Frame.left - 6, y + 4),
        align: TextAlign.right,
      );
    }

    final line = _line(curve);
    final area = Path.from(line)
      ..lineTo(frame.x(1), frame.y(0))
      ..lineTo(frame.x(0), frame.y(0))
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..color = on
            ? colors.primary.withValues(alpha: 0.12)
            : colors.outline.withValues(alpha: 0.08),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = on ? colors.primary : colors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (system case final dbs?) {
      final dashed = Path();
      for (final metric in _line(dbs).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 10) {
          dashed.addPath(
            metric.extractPath(d, math.min(d + 6, metric.length)),
            Offset.zero,
          );
        }
      }
      canvas.drawPath(
        dashed,
        Paint()
          ..color = colors.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // the selected point on top, as the glass moves it to the foreground
    final order = [
      for (var i = 0; i < points.length; i++)
        if (i != selected) i,
      if (selected >= 0 && selected < points.length) selected,
    ];
    for (final i in order) {
      final b = bands[i];
      final sel = i == selected;
      final radius = i == lifted ? _EqPlotState._r + 4 : _EqPlotState._r;
      final Color ink;
      if (sel) {
        canvas.drawCircle(points[i], radius, Paint()..color = colors.primary);
        ink = colors.onPrimary;
      } else if (b.on) {
        canvas.drawCircle(
          points[i],
          radius,
          Paint()..color = colors.secondaryContainer,
        );
        ink = colors.onSecondaryContainer;
      } else {
        canvas.drawCircle(
          points[i],
          radius - 1,
          Paint()
            ..color = colors.outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        ink = colors.outline;
      }
      final number = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: font.copyWith(
            color: ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      number.paint(
        canvas,
        points[i] - Offset(number.width / 2, number.height / 2),
      );
      number.dispose();
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.curve != curve ||
      old.system != system ||
      old.points != points ||
      old.selected != selected ||
      old.lifted != lifted ||
      old.on != on ||
      old.colors != colors ||
      old.font != font ||
      old.frame.range != frame.range ||
      old.frame.size != frame.size;
}

// kept for the tests: where a band's point is drawn on a plot of [width]
@visibleForTesting
Offset eqPointAt(List<EqBand> bands, int i, double fs, double width) {
  final range = bands.any((b) => b.on && !b.type.hasGain) ? 24.0 : 12.0;
  final frame = _Frame(Size(width, EqPlot.height), range);
  final b = bands[i];
  return Offset(
    frame.x(_Frame.fx(b.f).clamp(0.0, 1.0)),
    frame.y(bandMagnitudeDb(b, fs, b.f)),
  );
}
