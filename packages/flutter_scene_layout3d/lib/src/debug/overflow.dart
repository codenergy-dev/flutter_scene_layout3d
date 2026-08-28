import 'package:flutter/foundation.dart'
    show
        DiagnosticsNode,
        DiagnosticsTreeStyle,
        ErrorDescription,
        ErrorHint,
        ErrorSummary,
        FlutterError,
        FlutterErrorDetails,
        protected;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// One box reporting that its content did not fit inside it.
///
/// The 3D counterpart of Flutter's yellow-and-black stripes, and it has to be
/// a *report* rather than a stripe because nothing here paints: a box that
/// overflows looks exactly like a box that fits, right up until the geometry
/// inside it is standing through the front of a panel, and by then the
/// symptom reads as a rendering artefact rather than as a layout error.
///
/// The depth axis is why this matters more here than in Flutter. A row that
/// is 40 logical pixels too wide is at least visibly clipped; a card whose
/// content is 2mm too deep is a chip floating out of the front of it, and
/// nothing about that looks like an overflow until someone says so.
class Layout3dOverflow {
  /// Describes an overflow of [overflow] on [box].
  const Layout3dOverflow({
    required this.box,
    required this.overflow,
    this.hint,
  });

  /// The box whose content did not fit.
  final Layout3d box;

  /// How much the content exceeded the box by, per axis.
  ///
  /// Only positive components mean anything: an axis with room to spare
  /// reports zero rather than a negative number, so the value reads directly
  /// as "how much too big".
  final Size3d overflow;

  /// What to do about it, in one sentence, from the box that noticed.
  final String? hint;

  /// The axes that actually overflowed, in canonical order.
  Iterable<Axis3d> get axes =>
      Axis3d.values.where((axis) => overflow.alongAxis(axis) > 0.0);

  /// Whether anything overflowed at all.
  bool get isEmpty => axes.isEmpty;

  /// Which axes overflowed and by how much, in one line.
  ///
  /// Named for the edge the content came out of, the way Flutter names them
  /// ("overflowed by 12 pixels on the right"), with `back` for the third: a
  /// box grows away from the viewer, so depth overflow comes out the back.
  String describe() {
    final parts = <String>[
      for (final axis in axes)
        'the ${_edgeName(axis)} by '
            '${overflow.alongAxis(axis).toStringAsFixed(3)}',
    ];
    return parts.isEmpty ? 'nothing' : parts.join(', ');
  }

  static String _edgeName(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => 'right',
    Axis3d.vertical => 'bottom',
    Axis3d.depth => 'back',
  };

  @override
  String toString() =>
      'Layout3dOverflow(${box.toStringShort()} overflowed ${describe()})';
}

/// What happens when a box reports an overflow.
typedef Layout3dOverflowReporter = void Function(Layout3dOverflow overflow);

/// Where overflow reports go.
///
/// Defaults to [defaultLayout3dOverflowReporter], which routes them through
/// [FlutterError.reportError] so an overflow is as loud as any other layout
/// error and a `flutter_test` run fails on one. Replace it to collect reports
/// instead — a test that means to overflow, a debug HUD that lists what did.
Layout3dOverflowReporter debugLayout3dOverflowReporter =
    defaultLayout3dOverflowReporter;

/// Reports an overflow the way Flutter reports a layout error.
void defaultLayout3dOverflowReporter(Layout3dOverflow overflow) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'A ${overflow.box.runtimeType} overflowed ${overflow.describe()}.',
        ),
        ErrorDescription(
          'The content laid out inside this box does not fit in the extent '
          'the box settled on, so it stands outside it. Nothing clips it '
          'unless a ClipBox3d is in the way, which means it is drawn through '
          'whatever is around it.',
        ),
        if (overflow.hint != null) ErrorHint(overflow.hint!),
        overflow.box.toDiagnosticsNode(
          name: 'The overflowing box was',
          style: DiagnosticsTreeStyle.errorProperty,
        ),
      ]),
      library: 'flutter_scene_layout3d',
      context: ErrorDescription('during layout'),
    ),
  );
}

/// Mixed into a box that can notice its own content overflowing.
///
/// The bookkeeping, not the arithmetic: the box works out how much too big
/// its content was and calls [debugReportOverflow]; this decides whether that
/// is news. Reporting is throttled to changes, because a list being flung
/// past a row that overflows would otherwise report the same overflow on
/// every frame of the fling.
mixin Layout3dOverflowReportingMixin on Layout3d {
  Size3d _debugOverflow = Size3d.zero;
  Size3d? _debugReportedOverflow;

  /// How much this box's content exceeded it by, as of the last layout.
  ///
  /// [Size3d.zero] when it fits, which is the common case. Readable in
  /// release, where it stays zero because nothing computes it: an overflow
  /// check is a debug tool, and a shipped application should not be paying
  /// for one.
  Size3d get debugOverflow => _debugOverflow;

  /// Records that this box's content exceeded it by [overflow], and reports
  /// it if that is new.
  ///
  /// Call from [performLayout], every time, including with [Size3d.zero]:
  /// clearing the overflow is what lets the *next* one be reported.
  @protected
  void debugReportOverflow(Size3d overflow, {String? hint}) {
    assert(() {
      final clamped = Size3d(
        overflow.width > 0.0 ? overflow.width : 0.0,
        overflow.height > 0.0 ? overflow.height : 0.0,
        overflow.depth > 0.0 ? overflow.depth : 0.0,
      );
      _debugOverflow = clamped;
      if (clamped == Size3d.zero) {
        _debugReportedOverflow = null;
        return true;
      }
      if (_debugReportedOverflow == clamped) return true;
      _debugReportedOverflow = clamped;
      debugLayout3dOverflowReporter(
        Layout3dOverflow(box: this, overflow: clamped, hint: hint),
      );
      return true;
    }());
  }
}
