import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, FlutterError, FlutterErrorDetails, ErrorDescription;
import 'package:flutter/painting.dart' show Canvas, Color, Offset, TextStyle;
import 'package:flutter_scene/scene.dart' show Texture2D, TextureSource;

import 'text_measurement.dart' show buildParagraph;

/// One glyph's place in a [GlyphAtlas3d], and where it sits against the pen.
///
/// Two frames meet here. [x], [y], [width] and [height] are texels in the
/// atlas image, and [u0] through [v1] are the same rectangle as texture
/// coordinates. [left], [top] and [advance] are **logical pixels**, measured
/// the way the rest of the text layer measures: [left] and [top] are where
/// the raster's top-left corner goes relative to the pen position and the
/// baseline, so a renderer that knows where a glyph starts on a line knows
/// where its quad goes without consulting the font again.
class GlyphSlot3d {
  /// Records a packed glyph.
  const GlyphSlot3d({
    required this.grapheme,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.u0,
    required this.v0,
    required this.u1,
    required this.v1,
    required this.left,
    required this.top,
    required this.advance,
  });

  /// The grapheme cluster this raster draws.
  final String grapheme;

  /// The raster's rectangle in the atlas image, in texels.
  final int x;
  final int y;
  final int width;
  final int height;

  /// The same rectangle in texture coordinates.
  final double u0;
  final double v0;
  final double u1;
  final double v1;

  /// Where the raster's left edge sits relative to the pen, in logical
  /// pixels. Negative: the raster carries a gutter the glyph does not.
  final double left;

  /// Where the raster's top edge sits relative to the baseline, in logical
  /// pixels. Negative, because a glyph is drawn above its baseline.
  final double top;

  /// How far the pen moves after this glyph, in logical pixels.
  final double advance;

  /// Whether this glyph has no raster at all: a space, a control character.
  ///
  /// It still has an [advance], and a renderer still skips it.
  bool get isBlank => width == 0 || height == 0;

  @override
  String toString() =>
      'GlyphSlot3d("$grapheme" at $x,$y ${width}x$height, '
      'advance ${advance.toStringAsFixed(1)}px)';
}

/// The atlas as pixels, before anything GPU-shaped has happened to it.
///
/// RGBA8888, straight alpha, row-major from the top-left, which is what
/// [Texture2D.fromPixels] takes.
class GlyphAtlasImage3d {
  /// Records a rasterized atlas.
  const GlyphAtlasImage3d(this.pixels, this.size, this.generation);

  /// The texels, four bytes each.
  final Uint8List pixels;

  /// The atlas is square; this is its edge, in texels.
  final int size;

  /// The [GlyphAtlas3d.generation] these pixels were rasterized from.
  final int generation;
}

/// Uploads a rasterized atlas to the GPU.
///
/// The one GPU-shaped step in the whole atlas, kept behind a function so the
/// rest of it — packing, measuring, rasterizing — runs in `flutter test`,
/// where there is no GPU context to upload to.
typedef GlyphAtlasUpload3d = TextureSource? Function(GlyphAtlasImage3d image);

/// The default uploader: a straight-alpha [Texture2D] with no mipmaps.
///
/// Mipmaps are deliberately off. A glyph atlas packs unrelated rasters next
/// to each other, so a lower mip level averages one letter into its
/// neighbour; the way to keep type sharp as a panel recedes is a bigger
/// [GlyphAtlas3d.scale] or a distance field, not a mip chain.
TextureSource? uploadGlyphAtlas(GlyphAtlasImage3d image) =>
    Texture2D.fromPixels(image.pixels, image.size, image.size);

/// A square texture holding every glyph one style has been asked to draw at
/// one resolution.
///
/// The renderer's half of the two-phase design. Measurement asks the font
/// engine for widths once and then does arithmetic; this asks it for
/// *pixels* once per distinct glyph and then does arithmetic, so a screen of
/// labels sharing a font pays for the alphabet rather than for the text.
///
/// **`dart:ui` exposes no glyph rasters**, so a glyph is obtained the only
/// way there is: a single-grapheme `ui.Paragraph` painted into a
/// `PictureRecorder`. That is why [rasterize] is asynchronous and why the
/// whole atlas is redrawn at once — one recorder, one `toImage`, one
/// `toByteData` for every glyph added since the last time, rather than a
/// round trip per letter.
///
/// **Glyphs are rasterized white and tinted by the material.** One atlas
/// therefore serves every colour the same font is drawn in, which is what
/// makes the "one atlas per font and size" claim true in an application
/// rather than only in a demo. A style's `foreground` or `background` paint
/// is not honoured for the same reason.
///
/// The atlas packs onto shelves and never moves a glyph inside a generation,
/// so a mesh may bake its texture coordinates. When it runs out of room it
/// doubles and repacks, which invalidates every UV in it; [generation]
/// changes, listeners are notified, and a renderer rebuilds. Beyond
/// [maxSize] it starts over empty instead of growing, on the theory that an
/// application drawing more distinct glyphs than a 2048-texel atlas holds
/// wants a bigger atlas or a smaller [scale], and should not silently leak
/// texture memory while it finds out.
class GlyphAtlas3d extends ChangeNotifier {
  /// Creates an empty atlas for [style] at [scale] texels per logical pixel.
  GlyphAtlas3d({
    required this.style,
    required this.scale,
    this.padding = 2,
    this.initialSize = 128,
    this.maxSize = 2048,
    GlyphAtlasUpload3d upload = uploadGlyphAtlas,
  }) : assert(scale > 0.0),
       assert(padding >= 0),
       assert(initialSize > 0),
       assert(maxSize >= initialSize),
       _upload = upload,
       _size = initialSize;

  /// The style glyphs are measured and drawn at, in logical pixels.
  ///
  /// Colour is not part of it: see the class comment.
  final TextStyle style;

  /// Texels per logical pixel.
  ///
  /// The rasterization resolution, and the only defence against soft type:
  /// a glyph is drawn once at this scale and then stretched onto whatever
  /// the panel's size and the camera's distance make of it.
  final double scale;

  /// The gutter around each glyph, in texels.
  ///
  /// Two jobs: it keeps bilinear sampling from bleeding one glyph into the
  /// next, and it gives ink that overhangs its own advance — an italic `f`,
  /// a swash — somewhere to go. Raise it for a face with long overhangs.
  final int padding;

  /// The atlas edge it starts at, in texels.
  final int initialSize;

  /// The atlas edge it refuses to grow past, in texels.
  final int maxSize;

  final GlyphAtlasUpload3d _upload;

  /// The line box glyphs are rasterized inside, as a multiple of the font
  /// size.
  ///
  /// Deliberately taller than any face's natural line height and deliberately
  /// not the style's own: a caller who compresses [TextStyle.height] to fit
  /// more lines on a panel is asking for tighter *layout*, not for clipped
  /// letters. Layout still uses the real style; only the raster is given
  /// room, and the baseline read back from it puts the glyph where it
  /// belongs.
  static const double rasterLineHeight = 1.5;

  int _size;
  int _generation = 0;
  int _shelfTop = 0;
  int _shelfLeft = 0;
  int _shelfHeight = 0;
  bool _needsRaster = false;
  TextureSource? _texture;
  Future<void>? _pending;

  final Map<String, GlyphSlot3d> _slots = <String, GlyphSlot3d>{};
  final Map<String, _GlyphInk> _ink = <String, _GlyphInk>{};

  /// The atlas edge, in texels. Always a power of two times [initialSize].
  int get size => _size;

  /// Bumped every time the atlas repacks, which invalidates every UV in it.
  ///
  /// A renderer that has baked texture coordinates into a mesh compares this
  /// against the generation it baked from, and rebuilds when they differ.
  int get generation => _generation;

  /// The uploaded texture, or null until the first [flush] has resolved.
  TextureSource? get texture => _texture;

  /// Whether a glyph has been reserved that the uploaded texture does not
  /// have yet.
  bool get needsRaster => _needsRaster;

  /// How many distinct glyphs the atlas holds.
  int get glyphCount => _slots.length;

  /// The style a glyph is rasterized at: [style] at [scale], white, with
  /// room around it.
  TextStyle get rasterStyle => style.copyWith(
    color: const Color(0xFFFFFFFF),
    fontSize: (style.fontSize ?? 14.0) * scale,
    height: rasterLineHeight,
  );

  /// The slot for [grapheme], reserving one if this is the first time.
  ///
  /// Synchronous, and it never touches the GPU: the packing is arithmetic
  /// over metrics the font engine is asked for once per glyph. The pixels
  /// follow later, through [flush].
  GlyphSlot3d slotFor(String grapheme) {
    final existing = _slots[grapheme];
    if (existing != null) return existing;
    final ink = _ink[grapheme] ??= _measureGlyph(grapheme);
    final slot = _pack(grapheme, ink);
    _slots[grapheme] = slot;
    if (!slot.isBlank) _needsRaster = true;
    return slot;
  }

  /// Rasterizes and uploads everything reserved so far, once.
  ///
  /// Safe to call after every layout: it returns the in-flight future when
  /// one is running and does nothing at all when the texture is current.
  /// Listeners are notified when the texture changes.
  Future<void> flush() {
    if (!_needsRaster) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final future = _flush();
    _pending = future;
    return future;
  }

  Future<void> _flush() async {
    try {
      while (_needsRaster) {
        final image = await rasterize();
        // A glyph reserved while the rasterization was in flight — or a
        // repack triggered by one — means these pixels are already stale.
        if (image.generation != _generation) continue;
        _needsRaster = false;
        _texture = _upload(image);
        notifyListeners();
      }
    } finally {
      _pending = null;
    }
  }

  /// Draws every reserved glyph into one image.
  ///
  /// Free of the GPU and of `flutter_scene`, which is what makes the atlas
  /// testable: a headless test rasterizes and reads the texels back.
  Future<GlyphAtlasImage3d> rasterize() async {
    final generation = _generation;
    final edge = _size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final style = rasterStyle;
    for (final slot in _slots.values) {
      if (slot.isBlank) continue;
      final paragraph = buildParagraph(slot.grapheme, style)
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(
        paragraph,
        Offset((slot.x + padding).toDouble(), (slot.y + padding).toDouble()),
      );
      paragraph.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(edge, edge);
    picture.dispose();
    try {
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (bytes == null) {
        throw StateError('The glyph atlas could not be read back.');
      }
      return GlyphAtlasImage3d(bytes.buffer.asUint8List(), edge, generation);
    } finally {
      image.dispose();
    }
  }

  _GlyphInk _measureGlyph(String grapheme) {
    if (grapheme.trim().isEmpty) {
      // Whitespace advances the pen and draws nothing. Measuring its box
      // would reserve atlas space for an empty rectangle.
      final metrics = _measure(grapheme);
      return _GlyphInk(0, 0, 0.0, metrics.width);
    }
    final metrics = _measure(grapheme);
    return _GlyphInk(
      metrics.width.ceil(),
      metrics.height.ceil(),
      metrics.baseline,
      metrics.width,
    );
  }

  ({double width, double height, double baseline}) _measure(String grapheme) {
    final paragraph = buildParagraph(grapheme, rasterStyle)
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final metrics = (
      width: paragraph.maxIntrinsicWidth,
      height: paragraph.height,
      baseline: paragraph.alphabeticBaseline,
    );
    paragraph.dispose();
    return metrics;
  }

  GlyphSlot3d _pack(String grapheme, _GlyphInk ink) {
    final cellWidth = ink.width + padding * 2;
    final cellHeight = ink.height + padding * 2;
    if (ink.width == 0 ||
        ink.height == 0 ||
        cellWidth > maxSize ||
        cellHeight > maxSize) {
      // Nothing to draw, or a glyph no atlas this size could ever hold. The
      // pen still advances: a missing raster costs the letter, not the line.
      return _blank(grapheme, ink);
    }
    var at = _place(cellWidth, cellHeight);
    while (at == null) {
      if (!_grow()) return _blank(grapheme, ink);
      at = _place(cellWidth, cellHeight);
    }
    final (x, y) = at;
    _shelfLeft = x + cellWidth;
    _shelfTop = y;
    _shelfHeight = math.max(_shelfHeight, cellHeight);
    final edge = _size.toDouble();
    return GlyphSlot3d(
      grapheme: grapheme,
      x: x,
      y: y,
      width: cellWidth,
      height: cellHeight,
      u0: x / edge,
      v0: y / edge,
      u1: (x + cellWidth) / edge,
      v1: (y + cellHeight) / edge,
      left: -padding / scale,
      top: -(padding + ink.baseline) / scale,
      advance: ink.advance / scale,
    );
  }

  GlyphSlot3d _blank(String grapheme, _GlyphInk ink) => GlyphSlot3d(
    grapheme: grapheme,
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    u0: 0,
    v0: 0,
    u1: 0,
    v1: 0,
    left: 0,
    top: 0,
    advance: ink.advance / scale,
  );

  /// Where a cell of this size goes on the current shelf, or null when the
  /// atlas has no room for it.
  (int, int)? _place(int cellWidth, int cellHeight) {
    var left = _shelfLeft;
    var top = _shelfTop;
    if (left + cellWidth > _size) {
      left = 0;
      top = _shelfTop + _shelfHeight;
    }
    if (left + cellWidth > _size || top + cellHeight > _size) return null;
    return (left, top);
  }

  /// Doubles the atlas and lays every glyph out again.
  ///
  /// Returns false at [maxSize], where there is nothing left to try: the
  /// atlas keeps the glyphs it has and the caller draws the new one blank.
  /// An application in that state wants a bigger atlas or a smaller
  /// resolution, so it is reported rather than absorbed.
  bool _grow() {
    if (_size >= maxSize) {
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError(
              'A $maxSize-texel glyph atlas is full at ${_slots.length} '
              'glyphs of ${style.fontFamily ?? 'the default font'}, '
              '${scale.toStringAsFixed(1)} texels per logical pixel. Further '
              'glyphs will not draw. Raise maxSize, lower the renderer '
              'resolution, or split the text across styles.',
            ),
            library: 'flutter_scene_layout3d',
            context: ErrorDescription('while packing a glyph atlas'),
          ),
        );
        return true;
      }());
      return false;
    }
    final keep = _slots.keys.toList();
    _reset(math.min(maxSize, _size * 2));
    _slots.clear();
    for (final grapheme in keep) {
      _slots[grapheme] = _pack(grapheme, _ink[grapheme]!);
    }
    return true;
  }

  void _reset(int size) {
    _size = size;
    _shelfTop = 0;
    _shelfLeft = 0;
    _shelfHeight = 0;
    _generation++;
    _needsRaster = true;
  }

  @override
  void dispose() {
    _slots.clear();
    _ink.clear();
    _texture = null;
    super.dispose();
  }

  @override
  String toString() =>
      'GlyphAtlas3d(${_slots.length} glyphs, ${_size}x$_size, '
      'generation $_generation)';
}

/// A glyph's raster box, in texels at the atlas's own scale.
class _GlyphInk {
  const _GlyphInk(this.width, this.height, this.baseline, this.advance);

  final int width;
  final int height;
  final double baseline;
  final double advance;
}

/// The rasterization scale [scale] belongs to.
///
/// Buckets exist so that a surface animating its scale, or two panels a
/// hair apart, share one atlas rather than accumulating a texture each. It
/// rounds **up** to the next quarter step, so a bucket is never coarser than
/// asked for, and clamps to something a texture can hold: below a quarter
/// there is nothing left of a glyph, and past eight one label would fill a
/// 2048-texel atlas on its own.
double glyphAtlasScaleFor(double scale) =>
    (scale.clamp(0.25, 8.0) * 4.0).ceilToDouble() / 4.0;

/// The style an atlas is keyed by: [style] with its colour taken out.
///
/// Glyphs are rasterized white and tinted by the material, so two labels
/// that differ only in colour share an atlas. A style carrying a
/// `foreground` paint is returned untouched, because a `TextStyle` refuses
/// to hold both — such a style is not supported by the atlas renderer, and
/// this at least keeps it from crashing on the way to not being drawn.
TextStyle glyphAtlasStyleOf(TextStyle style) => style.foreground != null
    ? style
    : style.copyWith(color: const Color(0xFFFFFFFF));

/// The atlases an application has, one per style and resolution.
///
/// Sharing is the whole point of an atlas, and a renderer is owned by one
/// box, so the sharing has to live somewhere neither of them does. Every
/// [AtlasText3dRenderer] reaches for [shared] unless it is handed a cache of
/// its own, which is what a test does when it wants an atlas it can count
/// the glyphs of.
class GlyphAtlasCache3d {
  /// Creates a cache whose atlases are built with these settings.
  GlyphAtlasCache3d({
    this.padding = 2,
    this.initialSize = 128,
    this.maxSize = 2048,
    this.upload = uploadGlyphAtlas,
  });

  /// The cache every renderer shares unless told otherwise.
  static final GlyphAtlasCache3d shared = GlyphAtlasCache3d();

  /// Passed on to every atlas this cache builds. See [GlyphAtlas3d].
  final int padding;
  final int initialSize;
  final int maxSize;
  final GlyphAtlasUpload3d upload;

  final Map<(TextStyle, double), GlyphAtlas3d> _atlases =
      <(TextStyle, double), GlyphAtlas3d>{};

  /// How many atlases are live.
  int get length => _atlases.length;

  /// The atlas for [style] at [scale] texels per logical pixel, building one
  /// the first time it is asked for.
  GlyphAtlas3d atlasFor(TextStyle style, double scale) {
    final key = (glyphAtlasStyleOf(style), scale);
    return _atlases[key] ??= GlyphAtlas3d(
      style: key.$1,
      scale: scale,
      padding: padding,
      initialSize: initialSize,
      maxSize: maxSize,
      upload: upload,
    );
  }

  /// Drops every atlas, and the textures they hold.
  ///
  /// A renderer still pointing at one keeps drawing from it until its next
  /// layout, which is the same thing that happens when an atlas repacks.
  void clear() {
    for (final atlas in _atlases.values) {
      atlas.dispose();
    }
    _atlases.clear();
  }
}
