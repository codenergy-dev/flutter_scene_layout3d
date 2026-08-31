import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DoubleProperty,
        EnumProperty,
        FlagProperty,
        IntProperty;
import 'package:flutter/painting.dart'
    show
        Color,
        InlineSpan,
        Size,
        StrutStyle,
        TextAlign,
        TextBaseline,
        TextDirection,
        TextOverflow,
        TextPainter,
        TextScaler,
        TextWidthBasis;
import 'package:flutter/widgets.dart'
    show Directionality, RichText, SizedBox, Widget;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart'
    show
        AlphaMode,
        GeometryBuilder,
        GpuTextureSource,
        Mesh,
        MeshGeometry,
        Node,
        UnlitMaterial,
        WidgetComponent,
        WidgetInput,
        WidgetUpdatePolicy;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector2, Vector3;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'atlas_text_renderer.dart' show AtlasText3dRenderer, linearColor;

/// A span of rich text, drawn by Flutter itself onto a quad.
///
/// The escape hatch, and the other half of [Text3d]. Where a `Text3d` is
/// measured and drawn by this package — arithmetic over prepared segments,
/// glyphs assembled out of an atlas — a `RichText3d` hands the whole problem
/// back to the framework: a live `RichText` subtree is laid out and
/// rasterized by Flutter and the result is sampled as a texture. Everything
/// Flutter can draw, it draws. Several styles in one paragraph, inline
/// widgets, emoji, Arabic and Devanagari with their joining and reordering
/// intact, `TextStyle.foreground` and its shaders.
///
/// ```dart
/// RichText3d(
///   TextSpan(
///     style: const TextStyle(fontSize: 14, color: Color(0xFF202020)),
///     children: [
///       const TextSpan(text: 'Signed in as '),
///       TextSpan(text: user.name, style: bold),
///     ],
///   ),
/// )
/// ```
///
/// **What it costs.** A texture per box, a widget subtree per box, and — at
/// the default [update] policy — a rasterization per frame per box. That is
/// the trade the plan for this package names outright: correct immediately,
/// but not the thing to build a catalogue's every label out of. A screen of
/// buttons wants [Text3d] and a shared glyph atlas; the one paragraph with a
/// link in it wants this.
///
/// **Measurement is exact and headless.** The size, the intrinsics and the
/// baseline come from a [TextPainter] — the same object a Flutter `Text`
/// measures with — so a `RichText3d` participates in the layout protocol
/// fully whether or not there is a GPU to draw it on, and reports the same
/// numbers a 2D `RichText` would at the same width.
///
/// **It needs a `SceneView`.** The hosted subtree lives inside the widget
/// that displays the scene, which is where its tickers run and where the
/// capture happens. A box in a scene nobody is displaying measures correctly
/// and draws nothing.
///
/// Pointer input is not forwarded into the subtree: this package dispatches
/// its own pointers against the layout tree, and a hit on a `RichText3d`
/// stops at the box, exactly as it stops at a [Text3d].
class RichText3d extends Layout3d {
  /// Creates a box over [text].
  RichText3d(
    InlineSpan text, {
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    double depth = 0.0,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    double resolution = 2.0,
    double depthOffset = 0.002,
    WidgetUpdatePolicy update = WidgetUpdatePolicy.everyFrame,
    super.name,
  }) : _text = text,
       _textAlign = textAlign,
       _textDirection = textDirection,
       _softWrap = softWrap,
       _overflow = overflow,
       _maxLines = maxLines,
       _depth = depth,
       _strutStyle = strutStyle,
       _textWidthBasis = textWidthBasis,
       _resolution = resolution,
       _depthOffset = depthOffset,
       _update = update,
       assert(maxLines == null || maxLines > 0),
       assert(depth >= 0.0),
       assert(resolution > 0.0),
       assert(depthOffset >= 0.0);

  /// What a truncated line ends with.
  static const String ellipsis = '…';

  final TextPainter _painter = TextPainter(
    // The accessibility scale is applied as a geometric scale on the way to
    // world units, exactly as [Text3d] applies it, so the painter measures
    // at the style's own size and a change of metrics costs no relayout of
    // the paragraph itself.
    textScaler: TextScaler.noScaling,
  );

  InlineSpan _text;

  /// The span this box lays out.
  InlineSpan get text => _text;

  set text(InlineSpan value) {
    if (_text == value) return;
    _text = value;
    _invalidateContent();
  }

  TextAlign _textAlign;

  /// How lines sit inside the box's width.
  TextAlign get textAlign => _textAlign;

  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    _invalidateContent();
  }

  TextDirection _textDirection;

  /// Which way the text runs, and so what [TextAlign.start] means.
  TextDirection get textDirection => _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _invalidateContent();
  }

  bool _softWrap;

  /// Whether a line may end because it ran out of room.
  bool get softWrap => _softWrap;

  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    _invalidateContent();
  }

  TextOverflow _overflow;

  /// What text that does not fit does.
  TextOverflow get overflow => _overflow;

  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    _invalidateContent();
  }

  int? _maxLines;

  /// The most lines the text may take, or null for as many as it needs.
  int? get maxLines => _maxLines;

  set maxLines(int? value) {
    if (_maxLines == value) return;
    assert(value == null || value > 0);
    _maxLines = value;
    _invalidateContent();
  }

  double _depth;

  /// How thick the box is, in world units. Zero by default: a captured
  /// paragraph is flat.
  double get depth => _depth;

  set depth(double value) {
    if (_depth == value) return;
    assert(value >= 0.0);
    _depth = value;
    markParentNeedsLayout();
  }

  StrutStyle? _strutStyle;

  /// The strut that sets the minimum line box, as on a Flutter `Text`.
  StrutStyle? get strutStyle => _strutStyle;

  set strutStyle(StrutStyle? value) {
    if (_strutStyle == value) return;
    _strutStyle = value;
    _invalidateContent();
  }

  TextWidthBasis _textWidthBasis;

  /// Whether the block shrink-wraps its longest line or fills the width it
  /// was offered.
  TextWidthBasis get textWidthBasis => _textWidthBasis;

  set textWidthBasis(TextWidthBasis value) {
    if (_textWidthBasis == value) return;
    _textWidthBasis = value;
    _invalidateContent();
  }

  double _resolution;

  /// Texels per logical pixel in the capture.
  ///
  /// The same dial [AtlasText3dRenderer.resolution] is, and it costs the
  /// same way: the texture is this squared. Two is right for a panel at
  /// arm's length on a dense display.
  double get resolution => _resolution;

  set resolution(double value) {
    if (_resolution == value) return;
    assert(value > 0.0);
    _resolution = value;
    _releaseSurface();
    markNeedsLayout();
  }

  double _depthOffset;

  /// How far toward the viewer the quad sits, in world units.
  ///
  /// The same nudge [AtlasText3dRenderer.depthOffset] applies, for the same
  /// reason: a paragraph coplanar with the panel behind it loses the depth
  /// test to it.
  double get depthOffset => _depthOffset;

  set depthOffset(double value) {
    if (_depthOffset == value) return;
    assert(value >= 0.0);
    _depthOffset = value;
    _quad?.localTransform = Matrix4.translationValues(0.0, 0.0, -value);
  }

  WidgetUpdatePolicy _update;

  /// When the hosted subtree is re-rasterized.
  ///
  /// [WidgetUpdatePolicy.everyFrame] by default, because that is the only
  /// policy that catches a repaint inside the subtree — a cursor, a spinner
  /// in a `WidgetSpan`, a shader-painted style. Text that is only ever
  /// changed by this box's own setters can afford
  /// [WidgetUpdatePolicy.manual], which captures once per change and nothing
  /// in between.
  WidgetUpdatePolicy get update => _update;

  set update(WidgetUpdatePolicy value) {
    if (_update == value) return;
    _update = value;
    _releaseSurface();
    markNeedsLayout();
  }

  Node? _quad;
  UnlitMaterial? _material;
  WidgetComponent? _component;
  Size3d _quadSize = Size3d.zero;
  Size3d? _builtSize;

  /// The painter the size, the intrinsics and the baseline come from.
  ///
  /// Laid out at the width of the last pass. Useful for the questions the
  /// box protocol has no room for — where a line starts, which character a
  /// point is over.
  TextPainter get painter => _painter;

  /// What one logical pixel of the paragraph is worth in world units.
  double get logicalPixelScale =>
      metrics.unitsPerLogicalPixel * metrics.textScaleFactor;

  /// Whether the hosted subtree has produced a texture yet.
  bool get isDrawn => _material?.baseColorTexture != null;

  void _invalidateContent() {
    _releaseSurface();
    markParentNeedsLayout();
  }

  void _layoutPainter(double minWidth, double maxWidth) {
    _painter
      ..text = _text
      ..textAlign = _textAlign
      ..textDirection = _textDirection
      ..maxLines = _maxLines
      ..strutStyle = _strutStyle
      ..textWidthBasis = _textWidthBasis
      ..ellipsis = _overflow == TextOverflow.ellipsis ? ellipsis : null
      ..layout(minWidth: minWidth, maxWidth: maxWidth);
  }

  void _layoutFor(Constraints3d constraints) {
    final scale = logicalPixelScale;
    final available = constraints.maxWidth.isFinite
        ? constraints.maxWidth / scale
        : double.infinity;
    final minWidth = _softWrap
        ? constraints.minWidth / scale
        : constraints.minWidth / scale > available
        ? available
        : constraints.minWidth / scale;
    _layoutPainter(minWidth, _softWrap ? available : double.infinity);
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) {
    final scale = logicalPixelScale;
    switch (axis) {
      case Axis3d.horizontal:
        _layoutPainter(0.0, double.infinity);
        return _painter.minIntrinsicWidth * scale;
      case Axis3d.vertical:
        return _heightAt(limits.width);
      case Axis3d.depth:
        return _depth;
    }
  }

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) {
    final scale = logicalPixelScale;
    switch (axis) {
      case Axis3d.horizontal:
        _layoutPainter(0.0, double.infinity);
        return _painter.maxIntrinsicWidth * scale;
      case Axis3d.vertical:
        return _heightAt(limits.width);
      case Axis3d.depth:
        return _depth;
    }
  }

  double _heightAt(double width) {
    final scale = logicalPixelScale;
    final available = width.isFinite ? width / scale : double.infinity;
    _layoutPainter(0.0, _softWrap ? available : double.infinity);
    return _painter.height * scale;
  }

  /// The first line's alphabetic baseline, and only along the vertical.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) {
    if (axis != Axis3d.vertical) return null;
    _layoutFor(constraints);
    final baseline = _painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return baseline * logicalPixelScale;
  }

  @override
  void performLayout() {
    _layoutFor(constraints);
    final scale = logicalPixelScale;
    size = constraints.constrain(
      Size3d(_painter.width * scale, _painter.height * scale, _depth),
    );
    _updateSurface();
  }

  /// Rebuilds the hosted subtree and the quad it lands on, when the size or
  /// the content has moved.
  ///
  /// Nothing here touches the GPU. The quad is built the first time a
  /// capture arrives, which is also the first moment there is anything to
  /// put on it: a box in a scene nobody is displaying, or in a test, lays
  /// out and reports its size with no mesh and no material at all.
  void _updateSurface() {
    final width = _painter.width;
    final height = _painter.height;
    if (width <= 0.0 || height <= 0.0) {
      _releaseSurface();
      return;
    }
    final scale = logicalPixelScale;
    _quadSize = Size3d(width * scale, height * scale, 0.0);
    if (_component == null) {
      final component = _component = WidgetComponent.bindOnly(
        child: _buildChild(width, height),
        size: Size(width, height),
        pixelRatio: _resolution,
        update: _update,
        // This package dispatches its own pointers against the layout tree;
        // the engine's raycast has no mesh of ours to find, and two
        // dispatchers would fight over the same tap.
        input: WidgetInput.manual,
        bind: _bind,
      );
      node.addComponent(component);
      if (_update == WidgetUpdatePolicy.manual) {
        component.controller.requestCapture();
      }
    }
    _syncQuad();
  }

  /// Builds or resizes the quad, once there is a capture to sample.
  void _syncQuad() {
    if (_material == null) return;
    if (_quad != null && _builtSize == _quadSize) return;
    final existing = _quad;
    if (existing != null) node.remove(existing);
    _quad = Node(mesh: Mesh(buildTextQuadGeometry(_quadSize), _material!))
      ..name = 'RichText3d surface'
      ..localTransform = Matrix4.translationValues(0.0, 0.0, -_depthOffset);
    node.add(_quad!);
    _builtSize = _quadSize;
  }

  Widget _buildChild(double width, double height) => Directionality(
    textDirection: _textDirection,
    child: SizedBox(
      width: width,
      height: height,
      child: RichText(
        text: _text,
        textAlign: _textAlign,
        textDirection: _textDirection,
        softWrap: _softWrap,
        overflow: _overflow,
        maxLines: _maxLines,
        strutStyle: _strutStyle,
        textWidthBasis: _textWidthBasis,
        textScaler: TextScaler.noScaling,
      ),
    ),
  );

  void _bind(gpu.Texture texture) {
    final material = _material ??= UnlitMaterial()
      ..alphaMode = AlphaMode.blend
      ..vertexColorWeight = 0.0
      // The capture already carries the colours the span asked for; the
      // factor is here only so the material multiplies by one.
      ..baseColorFactor = linearColor(const Color(0xFFFFFFFF));
    material.baseColorTexture = GpuTextureSource(texture);
    _syncQuad();
  }

  void _releaseSurface() {
    final component = _component;
    if (component != null && component.isAttached) {
      node.removeComponent(component);
    }
    _component = null;
    final quad = _quad;
    if (quad != null) node.remove(quad);
    _quad = null;
    _material = null;
    _quadSize = Size3d.zero;
    _builtSize = null;
  }

  /// A label answers a ray on its own account, exactly as a [Text3d] does.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  void dispose() {
    _releaseSurface();
    _painter.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<TextAlign>('textAlign', textAlign));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
    properties.add(EnumProperty<TextOverflow>('overflow', overflow));
    properties.add(
      FlagProperty('softWrap', value: softWrap, ifFalse: 'no wrap'),
    );
    properties.add(IntProperty('maxLines', maxLines, defaultValue: null));
    properties.add(DoubleProperty('resolution', resolution));
    properties.add(
      FlagProperty('drawn', value: isDrawn, ifFalse: 'not captured yet'),
    );
  }
}

/// A quad from the box's origin to `(size.width, size.height)`, in layout
/// axes.
///
/// Textured `(0, 0)` at the top-left corner and `(1, 1)` at the bottom
/// right, which is the frame a captured image arrives in. Building it
/// uploads it, so this needs a GPU; [textQuadCorners] is the arithmetic
/// under it, which does not.
MeshGeometry buildTextQuadGeometry(Size3d size) {
  final corners = textQuadCorners(size);
  final uvs = <Vector2>[
    Vector2(0.0, 0.0),
    Vector2(0.0, 1.0),
    Vector2(1.0, 1.0),
    Vector2(1.0, 0.0),
  ];
  final builder = GeometryBuilder(deduplicate: false)
    ..normal(Vector3(0.0, 0.0, -1.0));
  for (var i = 0; i < corners.length; i++) {
    builder
      ..texCoord(uvs[i])
      ..addVertex(corners[i]);
  }
  builder
    ..addTriangle(0, 1, 2)
    ..addTriangle(0, 2, 3);
  return builder.build();
}

/// The quad's four corners in world units: top-left, bottom-left,
/// bottom-right, top-right.
///
/// Triangles `(0, 1, 2)` and `(0, 2, 3)` over them run counter-clockwise
/// around `-z`, which in layout space is the direction the viewer is in —
/// the same winding [AtlasText3dRenderer.glyphQuadCorners] produces, and
/// the same failure if it is reversed: a paragraph that measures correctly
/// and cannot be seen.
List<Vector3> textQuadCorners(Size3d size) => <Vector3>[
  Vector3(0.0, 0.0, 0.0),
  Vector3(0.0, size.height, 0.0),
  Vector3(size.width, size.height, 0.0),
  Vector3(size.width, 0.0, 0.0),
];
