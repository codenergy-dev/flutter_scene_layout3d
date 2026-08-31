import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color, TextStyle;
import 'package:flutter_scene/scene.dart'
    show AlphaMode, GeometryBuilder, Mesh, Node, UnlitMaterial;
import 'package:vector_math/vector_math.dart'
    show Matrix4, Vector2, Vector3, Vector4;

import 'glyph_atlas.dart';
import 'text_geometry.dart';
import 'text_renderer.dart';

/// Draws text as textured quads out of a shared glyph atlas.
///
/// The default renderer, and the one a component library wants: a screen of
/// labels sharing a font shares one texture and pays one mesh per label, so
/// the cost of the hundredth button is a hundred quads rather than a hundred
/// captures.
///
/// ```dart
/// Text3d('Save', style: labelStyle, renderer: AtlasText3dRenderer())
/// ```
///
/// **What it does per layout.** Nothing, when nothing changed: a [Text3d]
/// hands back the same [TextLayout3d] object when it relaid out at the same
/// width, and this compares identities before it does anything else. When
/// the text really did change it walks the lines, asks the atlas for a slot
/// per glyph — reserving and measuring the ones it has never seen — and
/// rebuilds one mesh. The atlas's *pixels* are produced asynchronously,
/// because `dart:ui` will not hand back an image any other way, so a label
/// containing a glyph nothing has drawn before appears a frame late rather
/// than blocking layout on a texture upload.
///
/// **What it does not do.** Ligatures across a grapheme boundary, and any
/// script whose glyphs change shape according to their neighbours, are drawn
/// as separate glyphs and will be wrong: the atlas holds one raster per
/// grapheme cluster, and Arabic, Devanagari and their relatives are exactly
/// the case that cannot be assembled that way. The *positions* do carry the
/// font's kerning, because a run is shaped as a whole before it is cut up
/// (see [TextRunShaper3d]), so Latin, Greek and Cyrillic come out right.
///
/// A style's `foreground` and `background` paints are not honoured either,
/// for the reason the atlas gives: a glyph is rasterized white so that one
/// atlas serves every colour, and the colour is applied by the material.
class AtlasText3dRenderer extends Text3dRenderer {
  /// Creates a renderer drawing at [resolution] times the surface's own
  /// scale.
  AtlasText3dRenderer({
    this.resolution = 2.0,
    this.depthOffset = 0.002,
    GlyphAtlasCache3d? atlases,
    TextRunShaper3d? shaper,
  }) : assert(resolution > 0.0),
       assert(depthOffset >= 0.0),
       _atlases = atlases ?? GlyphAtlasCache3d.shared,
       _shaper = shaper ?? TextRunShaper3d.shared;

  /// Texels per logical pixel, on top of what the metrics ask for.
  ///
  /// The level-of-detail dial, and the reason it is a dial rather than a
  /// derived number: `logicalPixelsPerUnit` is a promise about screen pixels
  /// only for a surface bound to the camera. A panel the viewer can walk
  /// toward covers more screen pixels with every step, and the only thing
  /// standing between that and mush is having rasterized the glyphs bigger
  /// than the panel's authored scale needs. Two is a reasonable default for
  /// a panel at arm's length on a dense display; a wall-sized surface wants
  /// more, a distant one less, and the memory cost is quadratic.
  final double resolution;

  /// How far toward the viewer the glyphs sit, in world units.
  ///
  /// Text drawn exactly on the plane of the panel behind it is text at the
  /// same depth as that panel, and the depth test does not break ties: the
  /// label vanishes into the surface it labels. This is the nudge that stops
  /// that, and it is applied to the glyph mesh alone — layout, hit testing
  /// and the box's own size never see it.
  final double depthOffset;

  final GlyphAtlasCache3d _atlases;
  final TextRunShaper3d _shaper;

  GlyphAtlas3d? _atlas;
  Node? _mesh;
  UnlitMaterial? _material;
  Node? _parent;

  Object? _layout;
  double _scale = 0.0;
  double _units = 0.0;
  TextStyle? _style;
  int _generation = -1;
  int _quadCount = 0;

  /// The atlas this renderer draws out of, or null before the first layout.
  GlyphAtlas3d? get atlas => _atlas;

  /// How many glyph quads the current mesh holds.
  int get quadCount => _quadCount;

  /// The node the glyphs hang from, or null when there is nothing to draw.
  Node? get meshNode => _mesh;

  @override
  void render(Text3dRenderRequest request) {
    final scale = glyphAtlasScaleFor(
      request.unitsPerLogicalPixel * request.logicalPixelsPerUnit * resolution,
    );
    final atlas = _atlases.atlasFor(request.style, scale);
    if (!identical(atlas, _atlas)) {
      _atlas?.removeListener(_onAtlasChanged);
      atlas.addListener(_onAtlasChanged);
      _atlas = atlas;
      _generation = -1;
    }
    if (identical(request.layout, _layout) &&
        _scale == scale &&
        _units == request.unitsPerLogicalPixel &&
        _style == request.style &&
        _generation == atlas.generation &&
        identical(_parent, request.node)) {
      return;
    }
    _layout = request.layout;
    _scale = scale;
    _units = request.unitsPerLogicalPixel;
    _style = request.style;
    _parent = request.node;
    _rebuild(request, atlas);
    // Reserving a glyph can repack the atlas, which invalidates every UV
    // just baked — including the ones baked before the repack happened. Bake
    // them again rather than draw a mesh pointing at the wrong texels.
    if (_generation != atlas.generation) _rebuild(request, atlas);
    atlas.flush();
  }

  void _rebuild(Text3dRenderRequest request, GlyphAtlas3d atlas) {
    _generation = atlas.generation;
    final quads = buildTextGlyphQuads(
      layout: request.layout,
      atlas: atlas,
      shaper: _shaper,
    );
    _quadCount = quads.length;
    _attach(request.node, quads, request.unitsPerLogicalPixel, request.style);
  }

  void _attach(
    Node parent,
    List<TextGlyphQuad3d> quads,
    double units,
    TextStyle style,
  ) {
    _detach();
    if (quads.isEmpty) return;
    final material = _material = UnlitMaterial()
      ..alphaMode = AlphaMode.blend
      ..vertexColorWeight = 0.0
      ..baseColorFactor = linearColor(style.color ?? const Color(0xFFFFFFFF));
    final texture = _atlas?.texture;
    if (texture != null) material.baseColorTexture = texture;
    final node = _mesh =
        Node(mesh: Mesh(buildGlyphGeometry(quads, units).build(), material))
          ..name = 'Text3d glyphs'
          // Layout's z runs away from the viewer, so the nudge that lifts the
          // glyphs off the panel behind them is negative.
          ..localTransform = Matrix4.translationValues(0.0, 0.0, -depthOffset);
    parent.add(node);
  }

  void _detach() {
    final mesh = _mesh;
    if (mesh != null) _parent?.remove(mesh);
    _mesh = null;
    _material = null;
  }

  void _onAtlasChanged() {
    final atlas = _atlas;
    if (atlas == null) return;
    if (atlas.generation != _generation) {
      // The atlas repacked under someone else's glyph: every UV in this mesh
      // is stale. Drop it and let the next layout bake new ones — which the
      // box will do, because a repack only happens while it is laying out.
      _generation = -1;
      _layout = null;
      _detach();
      return;
    }
    final texture = atlas.texture;
    if (texture != null) _material?.baseColorTexture = texture;
  }

  @override
  void dispose() {
    _atlas?.removeListener(_onAtlasChanged);
    _atlas = null;
    _detach();
    _parent = null;
    _layout = null;
  }

  /// Fills a [GeometryBuilder] with one textured quad per glyph, in layout
  /// axes and world units.
  ///
  /// Separated from [render] because everything up to the `build()` call is
  /// arithmetic a headless test can check, and `build()` is a GPU upload no
  /// headless test survives.
  ///
  /// The winding is the engine's: a triangle's vertices run counter-clockwise
  /// around the outward normal, and in layout space — `x` right, `y` down,
  /// `z` away — a glyph's outward normal is `-z`, toward the viewer. The
  /// surface's basis is a mirror and the engine flips the front face for a
  /// mirrored transform on its own, so building in layout axes is both the
  /// easy way and the correct one.
  static GeometryBuilder buildGlyphGeometry(
    List<TextGlyphQuad3d> quads,
    double units,
  ) {
    final builder = GeometryBuilder(deduplicate: false)
      ..normal(Vector3(0.0, 0.0, -1.0));
    for (final quad in quads) {
      final corners = glyphQuadCorners(quad, units);
      final uvs = glyphQuadTexCoords(quad);
      var first = 0;
      for (var i = 0; i < corners.length; i++) {
        builder.texCoord(uvs[i]);
        final index = builder.addVertex(corners[i]);
        if (i == 0) first = index;
      }
      builder
        ..addTriangle(first, first + 1, first + 2)
        ..addTriangle(first, first + 2, first + 3);
    }
    return builder;
  }

  /// A glyph quad's four corners in world units and layout axes, in the
  /// order [buildGlyphGeometry] indexes them: top-left, bottom-left,
  /// bottom-right, top-right.
  ///
  /// Triangles `(0, 1, 2)` and `(0, 2, 3)` over these four run
  /// counter-clockwise around `-z`, which in layout space is the direction
  /// the viewer is in. Reverse them and every label in the scene is culled,
  /// which is a failure with no symptom other than absence — hence a
  /// function that can be checked without a GPU.
  static List<Vector3> glyphQuadCorners(TextGlyphQuad3d quad, double units) {
    final left = quad.left * units;
    final right = quad.right * units;
    final top = quad.top * units;
    final bottom = quad.bottom * units;
    return <Vector3>[
      Vector3(left, top, 0.0),
      Vector3(left, bottom, 0.0),
      Vector3(right, bottom, 0.0),
      Vector3(right, top, 0.0),
    ];
  }

  /// The atlas coordinates of [glyphQuadCorners], in the same order.
  static List<Vector2> glyphQuadTexCoords(TextGlyphQuad3d quad) => <Vector2>[
    Vector2(quad.u0, quad.v0),
    Vector2(quad.u0, quad.v1),
    Vector2(quad.u1, quad.v1),
    Vector2(quad.u1, quad.v0),
  ];

  @override
  String toString() => 'AtlasText3dRenderer(${resolution}x, $_quadCount quads)';
}

/// [color] as the linear RGBA a material's colour factor multiplies in.
///
/// A `Color` is sRGB and `UnlitMaterial.baseColorFactor` is linear, so a
/// label handed a mid grey and drawn without this comes out visibly too
/// light. The engine's own `setColor` does the same decode for a shader
/// parameter tagged `source_color`.
Vector4 linearColor(Color color) => Vector4(
  _srgbToLinear(color.r),
  _srgbToLinear(color.g),
  _srgbToLinear(color.b),
  color.a,
);

double _srgbToLinear(double component) => component <= 0.04045
    ? component / 12.92
    : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
