import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DoubleProperty,
        EnumProperty,
        ErrorDescription,
        FlagProperty,
        FlutterError,
        FlutterErrorDetails,
        IntProperty;
import 'package:flutter/painting.dart'
    show
        Canvas,
        Color,
        InlineSpan,
        Offset,
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
        GeometryBuilder,
        GpuTextureSource,
        Mesh,
        MeshGeometry,
        MeshPrimitive,
        Node,
        WidgetComponent,
        WidgetInput,
        WidgetUpdatePolicy;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector2, Vector3;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'atlas_text_renderer.dart' show AtlasText3dRenderer;
import 'glyph_material.dart' show GlyphMaterial3d;
import 'glyph_outline.dart';
import 'text_geometry.dart' show GlyphWallSegment3d;

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
///
/// **Its letters have a thickness, by a different route than a [Text3d]'s.**
/// There is no atlas here to trace a glyph out of, and the capture is a
/// `gpu.Texture` with no readable copy — so the silhouette comes from a
/// second, *CPU* rasterization of this box's own [painter], traced by the same
/// [traceGlyphOutline]. That mask being on this side of the GPU is also what
/// lets each segment's colour be **sampled out of it**, so one wall carries a
/// span's several colours. [glyphDepth] is the dial; [depth] is a different
/// thing and does not draw.
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
    double? glyphDepth,
    double glyphDepthFactor = 0.10,
    int maxWallSegments = defaultMaxWallSegments,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    double resolution = 2.0,
    double depthOffset = 0.2,
    WidgetUpdatePolicy update = WidgetUpdatePolicy.everyFrame,
    super.name,
  }) : _text = text,
       _textAlign = textAlign,
       _textDirection = textDirection,
       _softWrap = softWrap,
       _overflow = overflow,
       _maxLines = maxLines,
       _depth = depth,
       _glyphDepth = glyphDepth,
       _glyphDepthFactor = glyphDepthFactor,
       _maxWallSegments = maxWallSegments,
       _strutStyle = strutStyle,
       _textWidthBasis = textWidthBasis,
       _resolution = resolution,
       _depthOffset = depthOffset,
       _update = update,
       assert(maxLines == null || maxLines > 0),
       assert(depth >= 0.0),
       assert(glyphDepth == null || glyphDepth >= 0.0),
       assert(glyphDepthFactor >= 0.0),
       assert(maxWallSegments >= 0),
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

  /// How much depth the box **reserves**, in world units. Zero by default.
  ///
  /// A claim on space and not a promise to fill it, the way a `SizedBox3d`'s
  /// is: the paragraph is drawn on one plane at the front of the box, and
  /// whatever is between that plane and `depth` behind it stays empty. State
  /// it when a sibling has to clear the paragraph, or when the paragraph is
  /// about to be given a backing of its own; do not state it expecting a
  /// slab.
  ///
  /// **A slab is not what a thick paragraph is**, and it was tried. A capture
  /// is mostly transparent, so a box built out of two of them is two panes of
  /// glass: the type doubles against its own mirrored back face. The thickness
  /// that does work is [glyphDepth], which extrudes the letters rather than
  /// the box, and it has nothing to do with this figure.
  double get depth => _depth;

  set depth(double value) {
    if (_depth == value) return;
    assert(value >= 0.0);
    _depth = value;
    markParentNeedsLayout();
  }

  double? _glyphDepth;

  /// How thick the paragraph's letters are, in **logical pixels**, or null to
  /// derive it from the root span's font size through [glyphDepthFactor].
  ///
  /// A paragraph here is extruded the way a [Text3d]'s glyphs are, and for the
  /// same reason: a flat one beside a thick one on the same panel reads as a
  /// decal next to a slab. The silhouette comes from a **CPU re-rasterization
  /// of this box's own [painter]** — the capture is a GPU texture with no
  /// readable copy — so it arrives a few frames after the content, and each
  /// segment's colour is sampled out of that bitmap, which is what lets one
  /// wall carry a span's several colours.
  ///
  /// Zero is the flat quad this box drew before it could do this, and it is
  /// the right answer more often than the default is: at body-copy sizes the
  /// wall is barely visible and a full paragraph traces into thousands of
  /// segments. See [maxWallSegments].
  ///
  /// **Two things it does not cover.** A `WidgetSpan`'s content is not painted
  /// by a [TextPainter], so an inline widget gets no wall. And the trace runs
  /// when this box lays out, not when the subtree repaints, so under
  /// [WidgetUpdatePolicy.everyFrame] a wall does not follow a cursor, a
  /// spinner or anything else animating inside the span.
  double? get glyphDepth => _glyphDepth;

  set glyphDepth(double? value) {
    if (_glyphDepth == value) return;
    assert(value == null || value >= 0.0);
    _glyphDepth = value;
    _invalidateWall();
  }

  double _glyphDepthFactor;

  /// How thick the letters are as a fraction of the root span's font size,
  /// when [glyphDepth] says nothing.
  ///
  /// The same tenth `AtlasText3dRenderer.depthFactor` uses, so a paragraph and
  /// a label at the same size come out the same thickness. It is the **root**
  /// span's size because a wall is one depth per box: one that changed
  /// thickness at a style boundary would come apart at the seam.
  double get glyphDepthFactor => _glyphDepthFactor;

  set glyphDepthFactor(double value) {
    if (_glyphDepthFactor == value) return;
    assert(value >= 0.0);
    _glyphDepthFactor = value;
    _invalidateWall();
  }

  /// The most wall segments this box will build before it refuses.
  ///
  /// A guard rather than a budget. A page of body copy traces into tens of
  /// thousands of segments for an edge nobody at reading distance can see, and
  /// silently building that mesh is worse than not building it — so past this
  /// the wall is dropped and, in debug, reported. The cure is `glyphDepth: 0`
  /// on the paragraph that asked for it.
  int get maxWallSegments => _maxWallSegments;

  set maxWallSegments(int value) {
    if (_maxWallSegments == value) return;
    assert(value >= 0);
    _maxWallSegments = value;
    _invalidateWall();
  }

  int _maxWallSegments;

  /// The cap [maxWallSegments] starts at: twenty thousand.
  ///
  /// About two and a half paragraphs of 15dp body copy, measured. High enough
  /// that nothing anyone would want an edge on reaches it, low enough that a
  /// page of text does.
  static const int defaultMaxWallSegments = 20000;

  /// How thick the letters actually are, in logical pixels.
  double get resolvedGlyphDepth =>
      _glyphDepth ?? _glyphDepthFactor * (_text.style?.fontSize ?? 14.0);

  /// How many wall segments the current mesh holds.
  ///
  /// Zero before the trace has come back, zero at a [resolvedGlyphDepth] of
  /// zero, and zero when the paragraph went past [maxWallSegments].
  int get wallSegmentCount => _wallSegments.length;

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

  /// How far toward the viewer the quad sits, in **logical pixels**.
  ///
  /// The same nudge [AtlasText3dRenderer.depthOffset] applies, in the same
  /// units and for the same reason: a paragraph coplanar with the panel behind
  /// it loses the depth test to it.
  double get depthOffset => _depthOffset;

  set depthOffset(double value) {
    if (_depthOffset == value) return;
    assert(value >= 0.0);
    _depthOffset = value;
    _quad?.localTransform = Matrix4.translationValues(0.0, 0.0, -_liftInUnits);
  }

  /// [depthOffset] in world units, through the surface's own unit rate.
  double get _liftInUnits => _depthOffset * metrics.unitsPerLogicalPixel;

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
  GlyphMaterial3d? _material;

  /// Whether a capture has reached the material, which is what [isDrawn]
  /// answers: a [GlyphMaterial3d] deliberately hides what it is bound to, so
  /// the one bit a caller needs is kept here.
  bool _hasCapture = false;
  WidgetComponent? _component;
  Size3d _quadSize = Size3d.zero;
  Size3d? _builtSize;
  int _builtWall = -1;
  List<GlyphWallSegment3d> _wallSegments = const <GlyphWallSegment3d>[];
  int _wallToken = 0;
  Object? _wallKey;

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
  bool get isDrawn => _hasCapture;

  void _invalidateContent() {
    _releaseSurface();
    markParentNeedsLayout();
  }

  /// Throws the traced wall away and asks for another one.
  ///
  /// Cheaper than [_invalidateContent]: the paragraph is the same paragraph
  /// and the capture is the same capture, so nothing is laid out again and
  /// the face keeps drawing while the new wall is traced.
  void _invalidateWall() {
    _wallKey = null;
    _wallSegments = const <GlyphWallSegment3d>[];
    _builtWall = -1;
    _wallToken++;
    _traceWall();
    _syncQuad();
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
    _traceWall();
    _syncQuad();
  }

  /// Rasterizes the paragraph and traces its silhouette, once per distinct
  /// picture of it.
  ///
  /// Called from layout rather than from the capture, which is the whole of
  /// the timing story: the capture is a GPU texture this side cannot read, so
  /// the wall is traced off a **second, CPU** rasterization of the same
  /// painter. The two agree because they are the same [TextPainter] at the
  /// same width; they are not the same event, so a subtree that repaints
  /// without this box laying out — a cursor, a spinner — moves the face and
  /// not the wall.
  ///
  /// [_wallKey] is what makes it once-per-picture: a paragraph that lays out
  /// again at the same width, which is every scroll and every frame of an
  /// animation moving it, traces nothing.
  void _traceWall() {
    final thickness = resolvedGlyphDepth;
    if (thickness <= 0.0 || _painter.width <= 0.0 || _painter.height <= 0.0) {
      if (_wallSegments.isNotEmpty) {
        _wallSegments = const <GlyphWallSegment3d>[];
        _builtWall = -1;
      }
      return;
    }
    final key = Object.hash(
      _text,
      _painter.width,
      _painter.height,
      _resolution,
      _textAlign,
      _textDirection,
    );
    if (_wallKey == key) return;
    _wallKey = key;
    final token = ++_wallToken;
    _traceWallAsync(token);
  }

  Future<void> _traceWallAsync(int token) async {
    final raster = await rasterizeParagraph(_painter, _resolution);
    // Anything that moved while `toImage` was in flight — a new paragraph, a
    // relayout at another width, disposal — has already bumped the token, and
    // this raster is a picture of a paragraph that no longer exists.
    if (raster == null || token != _wallToken) return;
    final outline = traceGlyphOutline(
      grapheme: '',
      pixels: raster.pixels,
      stride: raster.width,
      x: 0,
      y: 0,
      width: raster.width,
      height: raster.height,
      scale: raster.scale,
    );
    final segments = buildParagraphWallSegments(
      outline: outline,
      raster: raster,
      fallback: _text.style?.color ?? const Color(0xFF808080),
    );
    if (token != _wallToken) return;
    if (segments.length > _maxWallSegments) {
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError(
              'A RichText3d traced into ${segments.length} wall segments, '
              'past its maxWallSegments of $_maxWallSegments, so its letters '
              'will be drawn flat. A paragraph this large has an edge no '
              'reader at this size can see and a mesh nobody wants: state '
              'glyphDepth: 0 on it, or raise maxWallSegments if the edge is '
              'the point.',
            ),
            library: 'flutter_scene_layout3d',
            context: ErrorDescription('while extruding a paragraph'),
          ),
        );
        return true;
      }());
      _wallSegments = const <GlyphWallSegment3d>[];
      return;
    }
    _wallSegments = segments;
    _builtWall = -1;
    _syncQuad();
  }

  /// Builds or resizes the quad and its wall, once there is a capture to
  /// sample.
  void _syncQuad() {
    if (_material == null) return;
    final wall = _wallSegments.length;
    if (_quad != null && _builtSize == _quadSize && _builtWall == wall) return;
    final existing = _quad;
    if (existing != null) node.remove(existing);
    final units = logicalPixelScale;
    final thickness = _wallSegments.isEmpty ? 0.0 : resolvedGlyphDepth * units;
    // The face moves forward with the extrusion and the wall runs back to the
    // plane the flat quad occupied, exactly as a glyph's does — which is what
    // keeps a paragraph and a label beside it looking like one material, and
    // what keeps every lift computed against that plane valid.
    final primitives = <MeshPrimitive>[
      MeshPrimitive(
        buildTextQuadGeometry(_quadSize, z: -thickness),
        _material!.material,
      ),
    ];
    if (thickness > 0.0) {
      primitives.add(
        MeshPrimitive(
          AtlasText3dRenderer.buildGlyphWallGeometry(
            _wallSegments,
            units,
            thickness,
            // Every segment states its own colour, sampled off the bitmap it
            // was traced from, so this is only ever reached by one that could
            // not be sampled.
            _text.style?.color ?? const Color(0xFF808080),
          ).build(),
          AtlasText3dRenderer.buildWallMaterial(),
        ),
      );
    }
    _quad = Node(mesh: Mesh.primitives(primitives: primitives))
      ..name = 'RichText3d surface'
      ..localTransform = Matrix4.translationValues(0.0, 0.0, -_liftInUnits);
    node.add(_quad!);
    _builtSize = _quadSize;
    _builtWall = wall;
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
    // The same material a `Text3d`'s glyphs are drawn with, and for the same
    // reason: it writes depth, so a panel the paragraph is written on cannot
    // erase it by being drawn afterwards. The capture already carries the
    // colours the span asked for, so the tint is white and the material
    // multiplies by one.
    final material = _material ??= GlyphMaterial3d.factory()
      ..tint(const Color(0xFFFFFFFF));
    material.bindAtlas(GpuTextureSource(texture));
    _hasCapture = true;
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
    _hasCapture = false;
    _quadSize = Size3d.zero;
    _builtSize = null;
    _builtWall = -1;
    _wallSegments = const <GlyphWallSegment3d>[];
    _wallKey = null;
    // Anything still rasterizing is a picture of a paragraph this box has
    // stopped drawing.
    _wallToken++;
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
    properties.add(DoubleProperty('glyphDepth', resolvedGlyphDepth));
    properties.add(IntProperty('wallSegments', wallSegmentCount));
  }
}

/// A quad from the box's origin to `(size.width, size.height)`, in layout
/// axes.
///
/// Textured `(0, 0)` at the top-left corner and `(1, 1)` at the bottom
/// right, which is the frame a captured image arrives in. Building it
/// uploads it, so this needs a GPU; [textQuadCorners] is the arithmetic
/// under it, which does not.
MeshGeometry buildTextQuadGeometry(Size3d size, {double z = 0.0}) {
  final corners = textQuadCorners(size, z: z);
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
List<Vector3> textQuadCorners(Size3d size, {double z = 0.0}) => <Vector3>[
  Vector3(0.0, 0.0, z),
  Vector3(0.0, size.height, z),
  Vector3(size.width, size.height, z),
  Vector3(size.width, 0.0, z),
];

/// A paragraph rasterized to a bitmap, on the way to being traced.
///
/// RGBA8888, straight alpha, row-major, which is what [traceGlyphOutline]
/// takes and what [GlyphAtlasImage3d] is. The atlas's counterpart, and
/// deliberately the same shape.
class ParagraphRaster3d {
  /// Records a rasterized paragraph.
  const ParagraphRaster3d(this.pixels, this.width, this.height, this.scale);

  /// The texels, four bytes each.
  final Uint8List pixels;

  /// The bitmap's edges, in texels.
  final int width;
  final int height;

  /// Texels per logical pixel.
  final double scale;
}

/// Paints [painter] into a bitmap at [resolution] texels per logical pixel.
///
/// The whole reason a paragraph can have a wall at all. A [RichText3d]'s
/// *capture* is a `gpu.Texture` and there is no CPU copy of it anywhere, so
/// the ink's shape has to come from somewhere else — and the box is already
/// holding a laid-out [TextPainter], which will paint into any canvas it is
/// given. Three steps, no GPU, no capture: record, `toImage`, `toByteData`.
/// `GlyphAtlas3d.rasterize` does the same three for the same reason.
///
/// Asynchronous because `dart:ui` will not hand back an image any other way,
/// which is what puts the wall a few frames behind the content it belongs to.
///
/// Returns null when the painter has nothing to paint, or when the image
/// cannot be read back.
Future<ParagraphRaster3d?> rasterizeParagraph(
  TextPainter painter,
  double resolution,
) async {
  assert(resolution > 0.0);
  final width = (painter.width * resolution).ceil();
  final height = (painter.height * resolution).ceil();
  if (width <= 0 || height <= 0) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(resolution);
  painter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
  try {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return ParagraphRaster3d(
      data.buffer.asUint8List(),
      width,
      height,
      resolution,
    );
  } finally {
    image.dispose();
  }
}

/// How far inside the ink a segment's colour is read, in texels.
///
/// Far enough to clear the antialiased rim, which is a blend of the ink and
/// whatever is behind it and would wash every wall out toward the background;
/// near enough to stay inside a hairline stroke at a small size. A texel and
/// a half is inside the stem of 12dp type at any resolution worth tracing at.
const double kParagraphWallSampleDepth = 1.5;

/// Turns a traced paragraph into wall segments, each carrying the colour of
/// the ink it stands on.
///
/// The step that has no counterpart in the atlas path, and the one that makes
/// this worth doing. A glyph out of an atlas is white and tinted by the label,
/// because a label is one colour; a rich span is several, and a wall painted
/// in one of them would be wrong everywhere else. Since the mask is on this
/// side of the GPU, the colour can simply be **read off it**: step
/// [kParagraphWallSampleDepth] texels along the inward normal and take what is
/// there.
///
/// [fallback] is what a segment takes when the sample lands on nothing — off
/// the edge of the bitmap, or on a texel too faint to trust. In practice that
/// is a hairline thinner than the sample depth, and the root span's colour is
/// the right answer for it.
///
/// Pure arithmetic over a bitmap and an outline: no GPU, no `dart:ui`.
List<GlyphWallSegment3d> buildParagraphWallSegments({
  required GlyphOutline3d outline,
  required ParagraphRaster3d raster,
  required Color fallback,
}) {
  final segments = <GlyphWallSegment3d>[];
  for (final contour in outline.contours) {
    for (var i = 0; i < contour.length; i++) {
      final from = contour[i];
      final to = contour[(i + 1) % contour.length];
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final run = math.sqrt(dx * dx + dy * dy);
      if (run == 0.0) continue;
      final nx = -dy / run;
      final ny = dx / run;
      segments.add(
        GlyphWallSegment3d(
          grapheme: outline.grapheme,
          x0: from.dx,
          y0: from.dy,
          x1: to.dx,
          y1: to.dy,
          color: sampleParagraphInk(
            raster,
            (from.dx + to.dx) / 2,
            (from.dy + to.dy) / 2,
            nx,
            ny,
            fallback,
          ),
        ),
      );
    }
  }
  return segments;
}

/// The colour of the ink just inside a boundary point, or [fallback].
///
/// [x] and [y] are on the boundary, in logical pixels from the paragraph's
/// top-left; `(nx, ny)` points **away** from the ink, so the sample steps the
/// other way.
Color sampleParagraphInk(
  ParagraphRaster3d raster,
  double x,
  double y,
  double nx,
  double ny,
  Color fallback,
) {
  final px = (x * raster.scale - nx * kParagraphWallSampleDepth).round();
  final py = (y * raster.scale - ny * kParagraphWallSampleDepth).round();
  if (px < 0 || py < 0 || px >= raster.width || py >= raster.height) {
    return fallback;
  }
  final at = (py * raster.width + px) * 4;
  if (at + 3 >= raster.pixels.length) return fallback;
  // Below the tracer's own threshold this is a rim texel rather than ink, and
  // its colour is a blend with whatever is behind the paragraph.
  if (raster.pixels[at + 3] < kGlyphOutlineThreshold * 255) return fallback;
  return Color.fromARGB(
    255,
    raster.pixels[at],
    raster.pixels[at + 1],
    raster.pixels[at + 2],
  );
}
