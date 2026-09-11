import 'package:flutter/painting.dart' show Color, TextStyle;
import 'package:flutter_scene/scene.dart'
    show
        AlphaMode,
        GeometryBuilder,
        Mesh,
        MeshPrimitive,
        Node,
        TextureSource,
        UnlitMaterial;
import 'package:vector_math/vector_math.dart'
    show Matrix4, Vector2, Vector3, Vector4;

import 'glyph_atlas.dart';
import 'glyph_material.dart';
import 'text_geometry.dart';
import 'text_layout.dart';
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
///
/// **Type here has a thickness.** A glyph is not one quad but a slab: a front
/// face, a back face, and a wall around the letter's silhouette, so a label on
/// a panel that turns shows an edge rather than reading as a decal. The
/// silhouette is traced off the atlas raster — see [GlyphOutline3d] — which
/// means it arrives with the *texture* rather than with the layout, so the
/// first frame of a label is flat and the wall appears when the atlas says it
/// has one. [depth] and [depthFactor] are the dials, and a zero depth gets the
/// single quad this renderer drew before there was a wall.
class AtlasText3dRenderer extends Text3dRenderer {
  /// Creates a renderer drawing at [resolution] times the surface's own
  /// scale.
  AtlasText3dRenderer({
    this.resolution = 2.0,
    this.depthOffset = 0.2,
    this.depth,
    this.depthFactor = 0.10,
    GlyphAtlasCache3d? atlases,
    TextRunShaper3d? shaper,
  }) : assert(resolution > 0.0),
       assert(depthOffset >= 0.0),
       assert(depth == null || depth >= 0.0),
       assert(depthFactor >= 0.0),
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

  /// How far toward the viewer the glyphs sit, in **logical pixels**.
  ///
  /// Text drawn exactly on the plane of the panel behind it is text at the
  /// same depth as that panel, and the depth test does not break ties: the
  /// label vanishes into the surface it labels. This is the nudge that stops
  /// that, and it is applied to the glyph mesh alone — layout, hit testing
  /// and the box's own size never see it.
  ///
  /// A fifth of a logical pixel, which is a hair against the type it lifts and
  /// several hundred depth-buffer steps at any distance a panel is legible
  /// from. It is in logical pixels rather than world units because everything
  /// else a caller states here is — the lift has to clear the *face* of a
  /// slab whose own thickness is a dp figure, so it scales with the surface's
  /// unit rate and a panel authored small does not get a label floating a
  /// centimetre off it.
  ///
  /// **It is not what keeps a label on a turning panel.** That is
  /// [GlyphMaterial3d]: no lift small enough to be invisible can win the
  /// translucent pass's back-to-front sort, because that sort is one number
  /// per draw and turning the plane swings a label near an edge much further
  /// through it than any nudge. See
  /// `plans/2026_09_10_a_letter_on_a_slab.md`.
  final double depthOffset;

  /// How thick a glyph is, in **logical pixels**, or null to derive it from
  /// the font size through [depthFactor].
  ///
  /// The extrusion grows **toward the viewer**: the back face stays on the
  /// plane the flat quad used to occupy, so [depthOffset] and every
  /// `contentLift` a component computed to clear the surface underneath still
  /// clear it. Only the front of the letter moves.
  ///
  /// Zero is the old picture — one quad, no wall — and is the thing to state
  /// when type is being drawn flat against something on purpose.
  final double? depth;

  /// How thick a glyph is as a fraction of its font size, when [depth] says
  /// nothing.
  ///
  /// Relative by default because one figure cannot serve a 12dp caption, a
  /// 24dp icon and a 57dp display headline: a wall thick enough to read on the
  /// headline swallows the caption, and one that suits the caption is
  /// invisible on the headline. A tenth of the em is about where a letter
  /// stops looking like a sticker and before it starts looking like masonry.
  ///
  /// It is a *fraction of the type*, not of the surface, so a component that
  /// wants its labels to agree with `Thickness3d` states [depth] instead.
  final double depthFactor;

  final GlyphAtlasCache3d _atlases;
  final TextRunShaper3d _shaper;

  GlyphAtlas3d? _atlas;
  Node? _mesh;
  GlyphMaterial3d? _material;
  Node? _parent;

  TextLayout3d? _layout;
  double _scale = 0.0;
  double _units = 0.0;
  TextStyle? _style;
  int _generation = -1;
  int _outlineRevision = -1;
  int _quadCount = 0;
  int _wallSegmentCount = 0;

  /// The atlas this renderer draws out of, or null before the first layout.
  GlyphAtlas3d? get atlas => _atlas;

  /// How many glyph quads the current mesh holds.
  ///
  /// One per glyph that draws, whatever the thickness: a slab's two faces are
  /// built from the same quad and counted once.
  int get quadCount => _quadCount;

  /// How many wall segments the current mesh holds.
  ///
  /// Zero until the atlas has traced the silhouettes, and zero for good when
  /// the resolved depth is zero.
  int get wallSegmentCount => _wallSegmentCount;

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
        _outlineRevision == atlas.outlineRevision &&
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
    _outlineRevision = atlas.outlineRevision;
    final quads = buildTextGlyphQuads(
      layout: request.layout,
      atlas: atlas,
      shaper: _shaper,
    );
    _quadCount = quads.length;
    _attach(
      request.node,
      quads,
      buildGlyphWallSegments(quads: quads, atlas: atlas),
      request.unitsPerLogicalPixel,
      request.style,
    );
  }

  /// How thick a glyph of [style] is, in logical pixels.
  ///
  /// [depth] when it says something, and [depthFactor] of the font size
  /// otherwise. A style with no font size at all falls back to the same 14
  /// logical pixels the measurement half assumes, so the two never disagree
  /// about what "the type" is.
  double resolveDepth(TextStyle style) =>
      depth ?? depthFactor * (style.fontSize ?? 14.0);

  void _attach(
    Node parent,
    List<TextGlyphQuad3d> quads,
    List<GlyphWallSegment3d> walls,
    double units,
    TextStyle style,
  ) {
    _detach();
    if (quads.isEmpty) return;
    final color = style.color ?? const Color(0xFFFFFFFF);
    final material = _material = GlyphMaterial3d.factory()..tint(color);
    _bindTexture(_atlas?.texture);
    final thickness = resolveDepth(style) * units;
    _wallSegmentCount = thickness > 0.0 ? walls.length : 0;

    // Layout's z runs away from the viewer, so a glyph's front face is at
    // negative z and its back face is at zero — on the plane the flat quad
    // used to occupy. Growing the letter forward rather than backward is what
    // keeps every `contentLift` already computed against that plane valid.
    final primitives = <MeshPrimitive>[
      MeshPrimitive(
        buildGlyphGeometry(quads, units, z: -thickness).build(),
        material.material,
      ),
    ];
    if (thickness > 0.0) {
      primitives.add(
        MeshPrimitive(
          // The back face, reversed so it faces away from the viewer. The
          // compiled glyph material culls nothing and would not care; the
          // `UnlitMaterial` fallback blends, and a blending material culls
          // back faces, so a back face wound like the front one is invisible
          // in exactly the application that installed no shader.
          buildGlyphGeometry(quads, units, reversed: true).build(),
          material.material,
        ),
      );
      if (walls.isNotEmpty) {
        primitives.add(
          MeshPrimitive(
            buildGlyphWallGeometry(walls, units, thickness, color).build(),
            buildWallMaterial(),
          ),
        );
      }
    }

    final node = _mesh = Node(mesh: Mesh.primitives(primitives: primitives))
      ..name = 'Text3d glyphs'
      // The nudge that lifts the glyphs off the panel behind them. In dp,
      // so it goes through the surface's unit rate like every other
      // figure, and negative because toward the viewer is negative z.
      ..localTransform = Matrix4.translationValues(
        0.0,
        0.0,
        -depthOffset * units,
      );
    parent.add(node);
  }

  /// Points the material at the atlas, or at nothing when there is no atlas
  /// texture yet.
  ///
  /// The second half is not a nicety: a material with no texture samples a
  /// **1x1 white placeholder**, so a glyph mesh attached before the atlas has
  /// uploaded anything draws its quads as solid rectangles in the label's own
  /// colour — which is what a black slab where a navigation label belongs
  /// actually is, rather than a quad sampling empty atlas. Drawing nothing
  /// until the pixels arrive is [GlyphMaterial3d.bindAtlas]'s contract.
  void _bindTexture(TextureSource? texture) => _material?.bindAtlas(texture);

  void _detach() {
    final mesh = _mesh;
    if (mesh != null) _parent?.remove(mesh);
    _mesh = null;
    _material = null;
    _wallSegmentCount = 0;
  }

  bool _rebuilding = false;

  void _onAtlasChanged() {
    final atlas = _atlas;
    if (atlas == null || _rebuilding) return;
    // The outlines are the *second* reason to bake again, and they are the
    // ordinary one: a silhouette is traced off the raster, so a label laid
    // out before the first flush has quads and no wall. That is not a repack,
    // so the generation has not moved to say so, and a panel that has settled
    // would otherwise stay flat for good.
    if (atlas.generation != _generation ||
        atlas.outlineRevision != _outlineRevision) {
      // The atlas repacked under someone else's glyph, so every UV in this
      // mesh is stale. **Bake them again here rather than waiting for a
      // layout.** This used to drop the mesh and rely on the box laying out
      // again, on the reasoning that a repack only happens while something is
      // laying out — which is true, but the something is not necessarily
      // *this* box. A second surface added to the scene shares
      // `GlyphAtlasCache3d.shared`, and the glyph that overflows the atlas is
      // usually its, not ours: a panel whose labels were laid out once and
      // then only turned lost every one of them the moment another surface
      // drew a letter it did not have. The gallery is where that showed up —
      // an app bar reading "nb" where it should have read "Inbox" — because
      // it is the first thing in this repository to put two lots of type in
      // one scene.
      final layout = _layout;
      final parent = _parent;
      final style = _style;
      if (layout == null || parent == null || style == null) {
        _generation = -1;
        _outlineRevision = -1;
        _layout = null;
        _detach();
        return;
      }
      // Baking our glyphs can reserve one the atlas does not have, which
      // repacks it again and invalidates what we have just baked — the same
      // re-entrancy `render` guards against, and the reason this is a loop
      // with a stop rather than one pass. `_rebuilding` keeps the repack our
      // own reservation causes from re-entering here.
      _rebuilding = true;
      try {
        var guard = 0;
        do {
          _generation = atlas.generation;
          _outlineRevision = atlas.outlineRevision;
          final quads = buildTextGlyphQuads(
            layout: layout,
            atlas: atlas,
            shaper: _shaper,
          );
          _quadCount = quads.length;
          _attach(
            parent,
            quads,
            buildGlyphWallSegments(quads: quads, atlas: atlas),
            _units,
            style,
          );
        } while (_generation != atlas.generation && ++guard < 4);
      } finally {
        _rebuilding = false;
      }
      _bindTexture(atlas.texture);
      // Baking outside `render` is the common case now, and `render` used to
      // be the only caller of `flush`. A panel that has settled has nothing
      // left to call it, so a glyph this rebuild reserved would wait for
      // some other renderer to upload it. `flush` is a no-op when the
      // texture is current and returns the in-flight future otherwise, so
      // saying it here costs nothing and makes the invariant local.
      atlas.flush();
      return;
    }
    _bindTexture(atlas.texture);
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
    double units, {
    double z = 0.0,
    bool reversed = false,
  }) {
    final builder = GeometryBuilder(deduplicate: false)
      ..normal(Vector3(0.0, 0.0, reversed ? 1.0 : -1.0));
    for (final quad in quads) {
      final corners = glyphQuadCorners(quad, units, z: z);
      final uvs = glyphQuadTexCoords(quad);
      var first = 0;
      for (var i = 0; i < corners.length; i++) {
        builder.texCoord(uvs[i]);
        final index = builder.addVertex(corners[i]);
        if (i == 0) first = index;
      }
      if (reversed) {
        builder
          ..addTriangle(first, first + 2, first + 1)
          ..addTriangle(first, first + 3, first + 2);
      } else {
        builder
          ..addTriangle(first, first + 1, first + 2)
          ..addTriangle(first, first + 2, first + 3);
      }
    }
    return builder;
  }

  /// The direction the wall shading is lit from, in layout axes.
  ///
  /// Up and to the left, because `y` runs downward — the same place a reader
  /// expects light to come from in every other piece of Material, and the
  /// same place the elevation shadows in this catalogue imply.
  ///
  /// It is a **baked** direction rather than a scene light on purpose. Type
  /// here is drawn unlit so that a label does not dim as the panel it is
  /// written on turns away, and a wall that answered to the scene's lighting
  /// would put exactly that back: the edge of a letter would go dark at the
  /// angle where it is most visible. Baking it means a glyph's edge is lit
  /// from the letter's own upper left however the panel is turned, which is
  /// what an extruded sign looks like and what stays legible.
  static final Vector3 wallKeyDirection = Vector3(-0.55, -0.84, 0.0)
    ..normalize();

  /// How dark the wall gets where it faces away from [wallKeyDirection], as a
  /// fraction of the label's own colour.
  ///
  /// Not zero. A wall that goes to black reads as a hole punched next to the
  /// letter on a dark surface, and the point of the wall is to say *this is
  /// thick*, which a silhouette does on its own. Just over half is enough
  /// separation to see an edge and little enough to keep small type from
  /// looking soot-edged.
  static const double wallShadeFloor = 0.55;

  /// Fills a [GeometryBuilder] with the wall around a set of glyphs, in
  /// layout axes and world units.
  ///
  /// [thickness] is in **world units** and the wall runs from `z = 0` — the
  /// back face, on the plane the flat quad occupied — forward to
  /// `z = -thickness`, which is toward the viewer.
  ///
  /// The shading is baked into the vertex colours rather than computed by a
  /// shader, which is what lets the wall be drawn with the engine's own
  /// `UnlitMaterial` and adds no second `.fmat` to the package. Vertex
  /// colours are multiplied in linearly by that shader, so the colour is
  /// decoded here.
  ///
  /// [color] is the wall's colour for every segment that does not state one.
  /// A glyph out of an atlas never does — a label is one colour — and a
  /// paragraph's segments always do, because a [RichText3d] samples each
  /// one's colour out of the bitmap it traced.
  ///
  /// Separated from [render] for the same reason [buildGlyphGeometry] is:
  /// everything up to `build()` is arithmetic a headless test can check.
  static GeometryBuilder buildGlyphWallGeometry(
    List<GlyphWallSegment3d> segments,
    double units,
    double thickness,
    Color color,
  ) {
    final builder = GeometryBuilder(deduplicate: false);
    if (thickness <= 0.0) return builder;
    final fallback = linearColor(color);
    for (final segment in segments) {
      final (nx, ny) = segment.outwardNormal;
      if (nx == 0.0 && ny == 0.0) continue;
      final shade = wallShade(nx, ny);
      final own = segment.color;
      final tint = own == null ? fallback : linearColor(own);
      builder
        ..normal(Vector3(nx, ny, 0.0))
        ..color(
          Vector4(tint.x * shade, tint.y * shade, tint.z * shade, tint.w),
        );
      final corners = glyphWallCorners(segment, units, thickness);
      final first = builder.addVertex(corners[0]);
      for (var i = 1; i < corners.length; i++) {
        builder.addVertex(corners[i]);
      }
      builder
        ..addTriangle(first, first + 1, first + 2)
        ..addTriangle(first, first + 2, first + 3);
    }
    return builder;
  }

  /// How bright a wall facing `(nx, ny)` is, between [wallShadeFloor] and 1.
  ///
  /// A half-Lambert against [wallKeyDirection] rather than a clamped dot
  /// product: a real Lambert leaves every wall in the far hemisphere at the
  /// same flat floor, which is half of every letter, and the whole job of the
  /// shading is to tell one side of a stroke from the other.
  static double wallShade(double nx, double ny) {
    final facing =
        0.5 + 0.5 * (nx * wallKeyDirection.x + ny * wallKeyDirection.y);
    return wallShadeFloor + (1.0 - wallShadeFloor) * facing.clamp(0.0, 1.0);
  }

  /// One wall segment's four corners in world units and layout axes, in the
  /// order [buildGlyphWallGeometry] indexes them: the segment's start and end
  /// on the back face, then its end and start on the front one.
  ///
  /// Triangles `(0, 1, 2)` and `(0, 2, 3)` over these four run
  /// counter-clockwise around the segment's outward normal, which is what
  /// keeps the wall visible from outside the letter and culled from inside
  /// it.
  static List<Vector3> glyphWallCorners(
    GlyphWallSegment3d segment,
    double units,
    double thickness,
  ) => <Vector3>[
    Vector3(segment.x0 * units, segment.y0 * units, 0.0),
    Vector3(segment.x1 * units, segment.y1 * units, 0.0),
    Vector3(segment.x1 * units, segment.y1 * units, -thickness),
    Vector3(segment.x0 * units, segment.y0 * units, -thickness),
  ];

  /// The material a glyph's wall is drawn with.
  ///
  /// Opaque, so it goes through the opaque pass and writes depth there rather
  /// than joining the back-to-front sort the *faces* have to survive — the
  /// wall has no soft edge and nothing to blend, so there is no reason to put
  /// it at the mercy of one number per draw. The colour comes entirely from
  /// the vertex colours [buildGlyphWallGeometry] baked, which is why the base
  /// factor is left white.
  static UnlitMaterial buildWallMaterial() => UnlitMaterial()
    ..alphaMode = AlphaMode.opaque
    ..vertexColorWeight = 1.0
    ..baseColorFactor = Vector4(1.0, 1.0, 1.0, 1.0);

  /// A glyph quad's four corners in world units and layout axes, in the
  /// order [buildGlyphGeometry] indexes them: top-left, bottom-left,
  /// bottom-right, top-right.
  ///
  /// Triangles `(0, 1, 2)` and `(0, 2, 3)` over these four run
  /// counter-clockwise around `-z`, which in layout space is the direction
  /// the viewer is in. Reverse them and every label in the scene is culled,
  /// which is a failure with no symptom other than absence — hence a
  /// function that can be checked without a GPU.
  static List<Vector3> glyphQuadCorners(
    TextGlyphQuad3d quad,
    double units, {
    double z = 0.0,
  }) {
    final left = quad.left * units;
    final right = quad.right * units;
    final top = quad.top * units;
    final bottom = quad.bottom * units;
    return <Vector3>[
      Vector3(left, top, z),
      Vector3(left, bottom, z),
      Vector3(right, bottom, z),
      Vector3(right, top, z),
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
  String toString() =>
      'AtlasText3dRenderer(${resolution}x, $_quadCount quads, '
      '$_wallSegmentCount wall segments)';
}
