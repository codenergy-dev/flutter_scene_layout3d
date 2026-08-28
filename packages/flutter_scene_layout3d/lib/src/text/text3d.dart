import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DoubleProperty,
        EnumProperty,
        FlagProperty,
        IntProperty,
        StringProperty;
import 'package:flutter/painting.dart'
    show TextAlign, TextDirection, TextOverflow, TextStyle;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'break_rules.dart';
import 'prepared_text.dart';
import 'text_layout.dart';
import 'text_measurement.dart';
import 'text_renderer.dart';

/// A string, laid out as a box.
///
/// The leaf every label in a component library is built out of, and the first
/// thing in this package that answers the measurement protocol with something
/// real: a `Text3d` reports intrinsic extents that mean what they say, and it
/// states an alphabetic baseline, which until now only [Baseline3d] could do
/// and only by being told the number.
///
/// ```dart
/// Row3d(
///   crossAxisAlignment: CrossAxisAlignment3d.baseline,
///   children: [
///     Text3d('Save', style: const TextStyle(fontSize: 14)),
///     Text3d('⌘S', style: const TextStyle(fontSize: 11)),
///   ],
/// )
/// ```
///
/// **Sizes are in logical pixels, twice over.** [TextStyle.fontSize] is a
/// logical-pixel figure, as it is everywhere else in Flutter, and the whole
/// measurement is done in that frame; the box then multiplies by
/// `metrics.unitsPerLogicalPixel * metrics.textScaleFactor` to reach world
/// units. That is what makes a 14sp label 14sp on a surface bound to a camera
/// and still 14sp on a panel whose scale the author picked. Because font
/// metrics are linear in the size, applying the accessibility scale as a
/// multiplier is exactly the same as having asked for a bigger font, and it
/// costs no re-measurement — which matters, because changing the metrics
/// relayouts the whole tree.
///
/// **The box has no thickness.** Glyphs are flat, and the slab behind a label
/// belongs to whatever draws the label's background. [depth] is there for the
/// day letterforms are extruded, and for a caller who wants the box to
/// reserve room in front of a panel.
///
/// **It draws nothing without a [renderer].** Measurement and rasterization
/// are separated on purpose (see [Text3dRenderer]); a `Text3d` on its own
/// lays out, sizes, answers intrinsics and states a baseline, which is
/// everything the layout protocol needs and everything this package's tests
/// exercise.
class Text3d extends Layout3d {
  /// Creates a text box over [data].
  Text3d(
    String data, {
    TextStyle style = defaultStyle,
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    double depth = 0.0,
    TextBreakRules3d rules = TextBreakRules3d.standard,
    TextMeasurement3d? measurement,
    Text3dRenderer? renderer,
    super.name,
  }) : _data = data,
       _style = style,
       _textAlign = textAlign,
       _textDirection = textDirection,
       _softWrap = softWrap,
       _overflow = overflow,
       _maxLines = maxLines,
       _depth = depth,
       _rules = rules,
       _measurement = measurement ?? SegmentedTextMeasurement3d.shared,
       _renderer = renderer,
       assert(maxLines == null || maxLines > 0),
       assert(depth >= 0.0);

  /// The style a box uses when the caller does not state one.
  ///
  /// Material's body size, in logical pixels, and nothing else: there is no
  /// `DefaultTextStyle` to inherit from here, because there is no
  /// `BuildContext` in the imperative layer. A component library states its
  /// own styles and passes them down; this is only so that a `Text3d` written
  /// in a test or a sketch has a size at all.
  static const TextStyle defaultStyle = TextStyle(fontSize: 14.0);

  /// What a truncated line ends with.
  static const String ellipsis = '…';

  String _data;

  /// The string this box lays out.
  String get data => _data;

  set data(String value) {
    if (_data == value) return;
    _data = value;
    _invalidatePrepared();
  }

  TextStyle _style;

  /// The style the text is measured and drawn at.
  ///
  /// [TextStyle.fontSize] is in logical pixels; the metrics turn it into
  /// world units. A style with no size falls back to the platform's, which is
  /// almost certainly not what a component wants — state one.
  TextStyle get style => _style;

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _invalidatePrepared();
  }

  TextAlign _textAlign;

  /// How lines sit inside the box's width.
  TextAlign get textAlign => _textAlign;

  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    _invalidateLayout();
  }

  TextDirection _textDirection;

  /// Which way the text runs, and so what [TextAlign.start] means.
  TextDirection get textDirection => _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _invalidateLayout();
  }

  bool _softWrap;

  /// Whether a line may end because it ran out of room.
  ///
  /// False lays every paragraph out on one line however wide it comes out;
  /// hard breaks in the string still break.
  bool get softWrap => _softWrap;

  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    _invalidateLayout();
  }

  TextOverflow _overflow;

  /// What text that does not fit does.
  ///
  /// [TextOverflow.ellipsis] cuts a line that exceeds the box's width, and
  /// cuts the last line when [maxLines] drops the rest. The other values are
  /// the same thing as far as *layout* is concerned — the box's size does not
  /// depend on them — and differ only in what a renderer draws, which is why
  /// [TextOverflow.clip] and [TextOverflow.visible] behave alike here: this
  /// package has no clipping yet.
  TextOverflow get overflow => _overflow;

  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    _invalidateLayout();
  }

  int? _maxLines;

  /// The most lines the text may take, or null for as many as it needs.
  int? get maxLines => _maxLines;

  set maxLines(int? value) {
    if (_maxLines == value) return;
    assert(value == null || value > 0);
    _maxLines = value;
    _invalidateLayout();
  }

  double _depth;

  /// How thick the box is, in world units.
  ///
  /// Zero by default. Glyphs are flat, so this is room reserved rather than
  /// anything the text fills.
  double get depth => _depth;

  set depth(double value) {
    if (_depth == value) return;
    assert(value >= 0.0);
    _depth = value;
    markParentNeedsLayout();
  }

  TextBreakRules3d _rules;

  /// Where a line is allowed to end.
  TextBreakRules3d get rules => _rules;

  set rules(TextBreakRules3d value) {
    if (_rules == value) return;
    _rules = value;
    _invalidatePrepared();
  }

  TextMeasurement3d _measurement;

  /// The measurement policy: fast and segmented, or exact and shaped.
  TextMeasurement3d get measurement => _measurement;

  set measurement(TextMeasurement3d value) {
    if (identical(_measurement, value)) return;
    _measurement = value;
    _invalidatePrepared();
  }

  Text3dRenderer? _renderer;

  /// What turns the layout into geometry, or null to draw nothing.
  ///
  /// Owned by this box: the old one is disposed when a new one is set, and
  /// the current one when the box is.
  Text3dRenderer? get renderer => _renderer;

  set renderer(Text3dRenderer? value) {
    if (identical(_renderer, value)) return;
    _renderer?.dispose();
    _renderer = value;
    markNeedsLayout();
  }

  PreparedText3d? _prepared;
  TextLayout3d? _layout;
  double _layoutScale = 0.0;
  double _layoutMinWidth = double.nan;
  double _layoutWidth = double.nan;
  double _truncateWidth = double.nan;

  /// The measured handle for the current text, style and rules.
  ///
  /// Built on first use and kept until one of those three changes. Reading it
  /// is what a caller does to ask a question about the text that layout does
  /// not answer.
  PreparedText3d get prepared =>
      _prepared ??= _measurement.prepare(_data, _style, rules: _rules);

  /// The most recent layout, in logical pixels, or null before the first one.
  ///
  /// The lines, their runs and their baselines. Multiply by
  /// [logicalPixelScale] for world units.
  TextLayout3d? get textLayout => _layout;

  /// What one logical pixel of the layout is worth in world units.
  ///
  /// `metrics.unitsPerLogicalPixel * metrics.textScaleFactor`: the whole of
  /// the conversion, in one number, so a caller reading [textLayout] does not
  /// have to reassemble it.
  double get logicalPixelScale =>
      metrics.unitsPerLogicalPixel * metrics.textScaleFactor;

  void _invalidatePrepared() {
    _prepared = null;
    _layout = null;
    markParentNeedsLayout();
  }

  void _invalidateLayout() {
    _layout = null;
    markParentNeedsLayout();
  }

  /// Lays the text out for [constraints], reusing the last result when
  /// nothing about the question changed.
  ///
  /// The cheap path this whole design exists for. A box relaid out at the
  /// same width with the same metrics does no work at all; one relaid out at
  /// a different width does arithmetic over the prepared segments and still
  /// touches no font.
  TextLayout3d _layoutFor(Constraints3d constraints) {
    final scale = logicalPixelScale;
    final available = constraints.maxWidth.isFinite
        ? constraints.maxWidth / scale
        : double.infinity;
    // A parent that insists on a width is what makes [textAlign] mean
    // anything: on its own the block shrink-wraps to its longest line and
    // there is nothing to align it inside of.
    final minWidth = _softWrap
        ? constraints.minWidth / scale
        : math.min(constraints.minWidth / scale, available);
    final wrapWidth = _softWrap ? available : double.infinity;
    final cached = _layout;
    if (cached != null &&
        _layoutScale == scale &&
        _sameWidth(_layoutMinWidth, minWidth) &&
        _sameWidth(_layoutWidth, wrapWidth) &&
        _sameWidth(_truncateWidth, available)) {
      return cached;
    }
    final result = _layoutAt(minWidth, wrapWidth, available);
    _layout = result;
    _layoutScale = scale;
    _layoutMinWidth = minWidth;
    _layoutWidth = wrapWidth;
    _truncateWidth = available;
    return result;
  }

  TextLayout3d _layoutAt(
    double minWidth,
    double wrapWidth,
    double truncateWidth,
  ) => _measurement.layout(
    prepared,
    minWidth: minWidth,
    maxWidth: wrapWidth,
    truncateWidth: truncateWidth,
    textAlign: _textAlign,
    textDirection: _textDirection,
    maxLines: _maxLines,
    ellipsis: _overflow == TextOverflow.ellipsis ? ellipsis : null,
  );

  static bool _sameWidth(double a, double b) =>
      a == b || (a.isInfinite && b.isInfinite);

  /// The widest unbreakable piece of the text: the narrowest the box can be
  /// without a word standing outside it.
  ///
  /// Answered from the prepared handle, with no line breaking and no layout
  /// pass, which is what makes an [IntrinsicWidth3d] over a column of labels
  /// affordable. The vertical answer is not free in the same way — a height
  /// depends on a width, so it has to break lines — but it breaks them
  /// arithmetically.
  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      switch (axis) {
        Axis3d.horizontal => prepared.minIntrinsicWidth * logicalPixelScale,
        Axis3d.vertical => _heightAt(limits.width),
        Axis3d.depth => _depth,
      };

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      switch (axis) {
        Axis3d.horizontal => prepared.maxIntrinsicWidth * logicalPixelScale,
        Axis3d.vertical => _heightAt(limits.width),
        Axis3d.depth => _depth,
      };

  double _heightAt(double width) {
    final scale = logicalPixelScale;
    final available = width.isFinite ? width / scale : double.infinity;
    return _layoutAt(
          0.0,
          _softWrap ? available : double.infinity,
          available,
        ).height *
        scale;
  }

  /// The first line's alphabetic baseline, and only along the vertical.
  ///
  /// The first real baseline in the package: everything else either has none
  /// or has to be told one. The other two axes return null, because a line of
  /// type has one baseline and it runs across the text, not through it.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) {
    if (axis != Axis3d.vertical) return null;
    return _layoutFor(constraints).firstBaseline * logicalPixelScale;
  }

  @override
  void performLayout() {
    final layout = _layoutFor(constraints);
    final scale = logicalPixelScale;
    size = constraints.constrain(
      Size3d(layout.width * scale, layout.height * scale, _depth),
    );
    _renderer?.render(
      Text3dRenderRequest(
        node: node,
        layout: layout,
        style: _style,
        size: size,
        basis: basis,
        unitsPerLogicalPixel: scale,
        logicalPixelsPerUnit: metrics.logicalPixelsPerUnit,
      ),
    );
  }

  /// A label is something the reader points at, the same way the content of a
  /// [NodeBox3d] is.
  ///
  /// The hit is against the box, not the glyphs: a ray through the gap
  /// between two letters still finds the label, which is what makes a word
  /// easy to click. Wrap it in an [IgnorePointer3d] for a label that should
  /// let a ray through to whatever is behind it — which is what a label
  /// inside a button wants, so that the button answers rather than the text.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  void dispose() {
    _renderer?.dispose();
    _renderer = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('data', data, quoted: true));
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
    properties.add(EnumProperty<TextOverflow>('overflow', overflow));
    properties.add(
      FlagProperty('softWrap', value: softWrap, ifFalse: 'no wrap'),
    );
    properties.add(IntProperty('maxLines', maxLines, defaultValue: null));
    properties.add(
      IntProperty('lines', textLayout?.lines.length, defaultValue: null),
    );
    properties.add(DoubleProperty('logicalPixelScale', logicalPixelScale));
  }
}
