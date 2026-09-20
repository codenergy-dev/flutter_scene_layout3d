import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show
        ChangeNotifier,
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        debugPrint;
import 'package:flutter/painting.dart'
    show Canvas, Color, FilterQuality, Offset, Paint, Rect, TextStyle;
import 'package:flutter_scene/scene.dart'
    show GpuTextureSource, Texture2D, TextureSampling, TextureSource;
//
// **The engine's own GPU shim, and the import is the workaround.**
// `flutter_scene` exposes no way to make a [TextureSource] out of a `ui.Image`
// without copying it: `Texture2D.fromImage` reads the pixels back, which is the
// thing this file exists to stop doing. `gpu.Texture.fromImage` does exactly
// what is wanted and lives one layer down. Importing the shim rather than
// `package:flutter_gpu` directly is deliberate — the shim is a re-export on
// native and a WebGL2 backend on web, so this keeps working where a direct
// dependency would not. Upstream should expose it; until then, this.
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'glyph_outline.dart';
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
  const GlyphAtlasImage3d(
    this.pixels,
    this.size,
    this.generation,
    this.revision,
  );

  /// The texels, four bytes each.
  final Uint8List pixels;

  /// The atlas is square; this is its edge, in texels.
  final int size;

  /// The [GlyphAtlas3d.generation] these pixels were rasterized from.
  final int generation;

  /// The [GlyphAtlas3d.revision] these pixels were rasterized from.
  ///
  /// [generation] moves only when the atlas *repacks*; this moves whenever
  /// its contents change, which reserving a glyph does. An image whose
  /// revision is behind the atlas's own is a picture of a smaller alphabet,
  /// and uploading it as though it were current loses every glyph reserved
  /// since — see [GlyphAtlas3d.flush].
  final int revision;
}

/// The atlas as an image the GPU already holds, before anything has been
/// copied off it.
///
/// The counterpart of [GlyphAtlasImage3d], and the difference between them is
/// the whole cost of this path: that one is **pixels on the Dart heap**, which
/// means a `toByteData` off the raster thread and 785–973ms for a 512-texel
/// atlas on a real machine; this is the `ui.Image` `toImage` already produced,
/// which a texture can wrap without copying a byte.
class GlyphAtlasPicture3d {
  /// Records a rasterized atlas.
  const GlyphAtlasPicture3d(
    this.image,
    this.size,
    this.generation,
    this.revision, {
    this.slots = const <String, GlyphSlot3d>{},
  });

  /// The rendered atlas.
  ///
  /// **Do not dispose it.** A texture wrapping it shares its storage, and
  /// [GlyphAtlas3d] keeps it alive for as long as the texture it made from it.
  final ui.Image image;

  /// The atlas is square; this is its edge, in texels.
  final int size;

  /// The [GlyphAtlas3d.generation] this picture was rasterized from.
  final int generation;

  /// The [GlyphAtlas3d.revision] this picture was rasterized from.
  final int revision;

  /// Where every glyph this picture holds is in it.
  ///
  /// **What was drawn, not what was reserved.** The two part company across
  /// the `await` inside the rasterization, and the difference is load-bearing:
  /// the next picture blits these cells forward rather than typesetting them
  /// again, so a grapheme listed here that the image does not actually hold
  /// would be copied, empty, for the life of the atlas.
  final Map<String, GlyphSlot3d> slots;
}

/// Wraps a rasterized atlas as a texture without copying it.
///
/// Tried before [GlyphAtlasUpload3d], and returning null is how a backend that
/// cannot do it says so — the atlas then reads the pixels back and takes the
/// slower path. That is not hypothetical: the engine's web backend throws
/// rather than wrapping.
typedef GlyphAtlasPictureUpload3d =
    TextureSource? Function(GlyphAtlasPicture3d picture);

/// The default picture uploader: the image, wrapped, with nothing copied.
///
/// **This is the fix for two things at once.** A `toByteData` readback of the
/// atlas costs 785–973ms on a 512-texel atlas on a real machine, which is the
/// window every text artifact in this package's history lives in — and on that
/// same machine the readback comes back *wrong*, with cells blank that were
/// drawn and stripes where letters should be, permanently, because the bad
/// image is the one that gets kept. See *A picture of the atlas can come back
/// without the letters in it* in `docs/traps.md`. Neither can happen to a
/// texture that was never copied.
///
/// **`clampToEdge`, and it matters here**: the engine's default sampler
/// addressing is `repeat`, so a glyph packed against the atlas's own edge
/// samples the far side of the texture in its outermost texel.
TextureSource? uploadGlyphAtlasPicture(GlyphAtlasPicture3d picture) {
  try {
    return GpuTextureSource(
      gpu.Texture.fromImage(gpu.gpuContext, picture.image),
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        // No mip chain to walk: an atlas packs unrelated letters two texels
        // apart, so a lower level averages one into the next.
        mipFilter: gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  } catch (error) {
    // A backend that will not wrap an image — the web one throws in as many
    // words. The atlas reads the pixels back instead.
    assert(() {
      debugPrint(
        'GlyphAtlas3d could not wrap its picture as a texture ($error); '
        'falling back to reading the pixels back.',
      );
      return true;
    }());
    return null;
  }
}

/// Reports every repack, and how long its picture took to arrive.
///
/// The window this opens is the one a text artifact almost always turns out
/// to be — see *A mesh and an atlas texture are a pair* in `docs/traps.md` —
/// and it is the one thing about it a person running an application can
/// actually observe. A repack renumbers the packing at once and the picture
/// follows a readback later; between the two, a label that has to be baked
/// again — because it relaid out, or because its renderer was rebuilt out from
/// under it — has no picture to draw from and draws nothing.
///
/// Turn this on, use the application, and each line pairs: a repack, then the
/// milliseconds until the picture landed. Artifacts that coincide with a wide
/// window are this; artifacts with no window open near them are not, which is
/// the more useful half of the answer.
///
/// Debug builds only, and off by default.
bool debugReportGlyphAtlasRepacks = false;

/// Checks that every glyph the atlas accepts a picture of actually has ink in
/// it, and remembers the ones that do not.
///
/// The half [GlyphAtlas3d.debugStaleGlyphs] cannot see on its own. That one
/// compares *addresses* — is the slot I hand out the slot the picture has —
/// and is satisfied by a picture whose cell for a letter is empty, because an
/// empty cell is still at the right address. This asks the other question: did
/// the letter actually get drawn.
///
/// It is a flag rather than an assertion because it walks every glyph's cell
/// on every flush, which is the whole atlas. Turn it on from a diagnostic —
/// `examples/render_probe`'s self-driving harness does — and leave it off in a
/// frame.
///
/// Debug builds only, and off by default.
bool debugVerifyGlyphAtlasInk = false;

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
///
/// **The sampling has to be said out loud**, and for a while it was not.
/// `Texture2D.fromPixels` defaults to `TextureSampling()`, which is
/// `mipmaps: true` with no cap on the levels — the right default for a
/// photograph on a wall and the wrong one for an atlas, as the engine's own
/// `TextureSampling.maxMipmapLevels` says in as many words: *a texture atlas
/// uses this so tiles stop shrinking before they merge into their neighbors
/// across the padding gutter*. Two texels of gutter survive one halving and
/// nothing below it, so from the second level down a glyph is averaged with
/// whatever was packed beside it — and `assets/text_glyph3d.fmat` throws away
/// a fragment whose coverage falls under `alpha_cutoff`, which turns that
/// averaging into letters that thin out, break up or disappear according to
/// their own shape while their neighbours stay solid. It also cost a mip
/// chain's worth of CPU on every flush, inside the window a repack opens.
TextureSource? uploadGlyphAtlas(GlyphAtlasImage3d image) =>
    Texture2D.fromPixels(
      image.pixels,
      image.size,
      image.size,
      sampling: const TextureSampling(mipmaps: false),
    );

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
    GlyphAtlasPictureUpload3d uploadPicture = uploadGlyphAtlasPicture,
  }) : assert(scale > 0.0),
       assert(padding >= 0),
       assert(initialSize > 0),
       assert(maxSize >= initialSize),
       _upload = upload,
       _uploadPicture = uploadPicture,
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
  final GlyphAtlasPictureUpload3d _uploadPicture;

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
  int _revision = 0;
  int _shelfTop = 0;
  int _shelfLeft = 0;
  int _shelfHeight = 0;
  bool _needsRaster = false;
  TextureSource? _texture;
  int _textureGeneration = -1;
  int _textureRevision = -1;
  Future<void>? _pending;

  final Map<String, GlyphSlot3d> _slots = <String, GlyphSlot3d>{};
  final Map<String, _GlyphInk> _ink = <String, _GlyphInk>{};
  final Map<String, GlyphOutline3d> _outlines = <String, GlyphOutline3d>{};

  /// Where each glyph was in the picture that is uploaded.
  ///
  /// Not the packing — [_slots] is the packing, and it moves the instant a
  /// repack happens. This is what the *texture* is a picture of, which is the
  /// only thing a baked mesh can actually sample. See [debugStaleGlyphs].
  Map<String, GlyphSlot3d> _pictured = const <String, GlyphSlot3d>{};

  /// The image the texture wraps, kept alive because the texture shares its
  /// storage.
  ui.Image? _textureImage;

  GlyphAtlasImage3d? _debugPicture;

  /// The image the uploaded texture was made from, kept only while
  /// [debugVerifyGlyphAtlasInk] is on.
  ///
  /// **Not a fresh rasterization.** Asking the atlas to draw itself again
  /// answers *what would it look like now*, which is a different question from
  /// *what is on the GPU*, and the two differ by exactly the window every text
  /// artifact here lives in. This is the second one.
  GlyphAtlasImage3d? get debugPicture => _debugPicture;
  int _outlineRevision = 0;

  /// The atlas edge, in texels. Always a power of two times [initialSize].
  int get size => _size;

  /// Bumped every time the atlas repacks, which invalidates every UV in it.
  ///
  /// A renderer that has baked texture coordinates into a mesh compares this
  /// against the generation it baked from, and rebuilds when they differ.
  int get generation => _generation;

  /// Bumped every time the atlas's contents change — a glyph reserved, a
  /// repack — which is strictly more often than [generation] moves.
  ///
  /// [generation] answers *are my texture coordinates still valid*; this
  /// answers *is my picture of the atlas still complete*. They are different
  /// questions and conflating them cost a screen its letters: reserving a
  /// glyph into free space does not repack, so a rasterization already in
  /// flight comes back at the same generation and looks current while being
  /// a letter short.
  int get revision => _revision;

  /// The uploaded texture, or null until the first [flush] has resolved.
  TextureSource? get texture => _texture;

  /// The [generation] [texture] is a picture of, or -1 before the first
  /// [flush] has resolved.
  ///
  /// **Not a fourth counter.** [generation], [revision] and [outlineRevision]
  /// describe the atlas; this describes the *texture*, and it is the one
  /// number that answers the question a baked mesh has to ask before it
  /// samples: *is the picture I am pointing at the packing I was measured
  /// against?* A repack renumbers every slot the moment it happens and the
  /// picture follows only when the rasterization lands, so between the two
  /// this is behind [generation] and every coordinate [slotFor] hands out
  /// describes an image that does not exist yet.
  int get textureGeneration => _textureGeneration;

  /// The [revision] [texture] is a picture of, or -1 before the first [flush]
  /// has resolved.
  ///
  /// [textureGeneration] answers *is the picture of my packing*; this answers
  /// *is the picture as complete as my packing was*. They are the same two
  /// questions [generation] and [revision] ask of the atlas, asked of the
  /// picture — and the second one is needed for the same reason it was needed
  /// there. Reserving a glyph into free space does **not** repack, so the
  /// generation does not move and [textureIsCurrent] stays true while the
  /// uploaded picture is a letter short.
  ///
  /// That gap is deliberate for a glyph's **face**: every glyph the picture
  /// does have is still exactly where the coordinates say, so a label drawn
  /// from it is missing a letter rather than drawing a wrong one, and the
  /// flush that closes the gap is already running. It is not survivable for a
  /// glyph's **wall**, which is geometry with no texture in it and draws
  /// whatever the picture does or does not hold — see
  /// `AtlasText3dRenderer.bakedRevision`.
  int get textureRevision => _textureRevision;

  /// Whether [texture] is a picture of the packing [slotFor] is handing out.
  ///
  /// False in the window a repack opens, and the signal a renderer needs to
  /// stay out of it: texture coordinates baked while this is false address
  /// texels that belong to another letter, or to none. It says nothing about
  /// [revision] on purpose — a picture that is a glyph *short* still puts
  /// every glyph it has where the coordinates say, so a label drawn from it
  /// is missing a letter rather than drawing a wrong one, and [flush] is
  /// already rasterizing again to close that.
  bool get textureIsCurrent => _textureGeneration == _generation;

  /// Whether a glyph has been reserved that the uploaded texture does not
  /// have yet.
  bool get needsRaster => _needsRaster;

  /// How many distinct glyphs the atlas holds.
  int get glyphCount => _slots.length;

  /// Bumped every time a glyph's silhouette is traced.
  ///
  /// The third of the three counters, and it answers the third question. Two
  /// renderers watching this atlas already ask *are my texture coordinates
  /// still valid* ([generation]) and *is my picture of the atlas still
  /// complete* ([revision]); a renderer that extrudes its glyphs also has to
  /// ask *does the atlas know the shape of my letters yet*, because that
  /// answer arrives with the pixels rather than with the packing. A label
  /// laid out before the first flush has slots and no outlines, so it draws
  /// flat and rebuilds when this moves.
  int get outlineRevision => _outlineRevision;

  /// Every glyph [image] was supposed to draw and did not.
  ///
  /// Stops at the first ink texel of a cell, so a healthy atlas pays a few
  /// texels a glyph. Only the cells are walked, never the gutter between them.
  List<String> _glyphsWithoutInk(GlyphAtlasImage3d image) {
    final cutoff = (kGlyphOutlineThreshold * 255.0).round();
    final lost = <String>[];
    for (final slot in _slots.values) {
      if (slot.isBlank) continue;
      var found = false;
      for (var row = 0; row < slot.height && !found; row++) {
        final start = ((slot.y + row) * image.size + slot.x) * 4 + 3;
        for (var column = 0; column < slot.width; column++) {
          final index = start + column * 4;
          if (index >= image.pixels.length || image.pixels[index] >= cutoff) {
            found = true;
            break;
          }
        }
      }
      if (!found) lost.add(slot.grapheme);
    }
    return lost;
  }

  /// Every grapheme whose slot is **not** where the uploaded picture has it.
  ///
  /// The invariant the whole text layer rests on, made askable. A mesh bakes
  /// the coordinates [slotFor] hands out and samples [texture]; if the two
  /// disagree about where a letter is, the mesh draws that letter's neighbour
  /// or draws nothing, and every text artifact this package has shipped has
  /// been one of those two.
  ///
  /// It should always be empty while [textureIsCurrent] is true, and a
  /// grapheme listed here while it is true means one of three statements that
  /// look airtight is false: that a silhouette is only traced from an accepted
  /// image, that an accepted image draws every slot, or that an accepted image
  /// is the one uploaded. A blank glyph is not listed — it has no raster to be
  /// in the wrong place.
  ///
  /// Debug only, and it walks the alphabet, so call it from a diagnostic
  /// rather than from a frame.
  Iterable<String> debugStaleGlyphs() sync* {
    for (final slot in _slots.values) {
      if (slot.isBlank) continue;
      final pictured = _pictured[slot.grapheme];
      if (pictured == null ||
          pictured.x != slot.x ||
          pictured.y != slot.y ||
          pictured.width != slot.width ||
          pictured.height != slot.height) {
        yield slot.grapheme;
      }
    }
  }

  /// Whether the uploaded picture has ink for [grapheme] where [slotFor] says
  /// it is.
  ///
  /// The per-glyph half of [textureIsCurrent], and the one a wall wants: a
  /// glyph's face is stopped by binding no texture, and its wall is geometry
  /// with nothing to stop it.
  bool picturesGlyph(String grapheme) {
    final slot = _slots[grapheme];
    if (slot == null || slot.isBlank) return false;
    final pictured = _pictured[grapheme];
    return pictured != null && pictured.x == slot.x && pictured.y == slot.y;
  }

  /// [grapheme]'s silhouette, or null until the raster it is traced from has
  /// been read back.
  ///
  /// In logical pixels from the top-left of the glyph's padded cell, which is
  /// where its quad's top-left is too — see [GlyphOutline3d]. A blank glyph
  /// never gets one, because there is nothing to trace.
  GlyphOutline3d? outlineFor(String grapheme) => _outlines[grapheme];

  /// The style a glyph is rasterized at: [style] at [scale], white, with
  /// room around it.
  ///
  /// **White includes the decoration.** An underline or a strikethrough is
  /// part of the raster — `drawParagraph` paints it — so a style that kept
  /// its own `decorationColor` here would bake a colour into an atlas that is
  /// supposed to serve every colour, and [glyphAtlasStyleOf] would have to
  /// key by it to stay honest. One rule instead: everything in the raster is
  /// white and the material tints it.
  TextStyle get rasterStyle => style.copyWith(
    color: const Color(0xFFFFFFFF),
    decorationColor: const Color(0xFFFFFFFF),
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
    _revision++;
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
        final picture = await rasterizePicture();
        // A glyph reserved while the rasterization was in flight — or a
        // repack triggered by one — means this picture is already stale.
        //
        // **This compares the revision and not only the generation**, and
        // that is the whole of it: `rasterizePicture` records its picture
        // synchronously and then awaits `toImage`, so every glyph reserved
        // during that await is missing from the image, and a reservation
        // that finds free space does not repack, so the generation has not
        // moved to say so. Clearing `_needsRaster` on such an image lost
        // those glyphs *permanently* — nothing ever asked for them again —
        // and that is what took an app bar's letters away the moment a
        // second surface shared this atlas. A single surface hid it, because
        // one surface reserves its whole alphabet in one layout pass, which
        // grows the atlas, which does move the generation.
        if (picture.generation != _generation ||
            picture.revision != _revision) {
          picture.image.dispose();
          continue;
        }
        // **Wrapped, not copied.** This is where the readback used to be, and
        // taking it out cost 785–973ms on a 512-texel atlas — the window every
        // text artifact here lives in. It is not what made the letters wrong;
        // that was measured, and the artifact was identical either way. See
        // *A letter draws once, and the second time it draws nothing* in
        // `docs/traps.md`.
        var texture = _uploadPicture(picture);
        GlyphAtlasImage3d? pixels;
        if (texture == null) {
          // A backend that will not wrap an image. Read the pixels back and
          // take the old path, which is slower and is still correct.
          pixels = await readBack(picture);
          texture = _upload(pixels);
        }
        _needsRaster = false;
        // **The silhouettes are the one thing that still wants pixels**, and
        // they want them only for a glyph nothing has traced yet. A repack
        // traces nothing — an outline is stated from its own cell's corner, so
        // moving the cell does not change it — which is exactly the case the
        // readback used to be most expensive in.
        if (_slots.values.any(
          (slot) => !slot.isBlank && !_outlines.containsKey(slot.grapheme),
        )) {
          pixels ??= await readBack(picture);
          _traceOutlines(pixels);
        }
        // **The verification, and it is the thing that found this.** It costs
        // a readback, so it is behind a flag and never runs in a frame a
        // person is waiting on. Note the question it asks: whether a cell
        // holds *any* ink. A cell of stripes passes, so silence here is not a
        // clean picture — [debugPicture] is what settles that.
        if (debugVerifyGlyphAtlasInk) {
          pixels ??= await readBack(picture);
          _debugPicture = pixels;
          final lost = _glyphsWithoutInk(pixels);
          if (lost.isNotEmpty) {
            debugPrint(
              'GlyphAtlas3d drew ${lost.join()} into its picture and the '
              'picture came back without '
              '${lost.length == 1 ? 'it' : 'them'}. Those letters will not '
              'draw until the atlas repacks. See *A letter draws once, and '
              'the second time it draws nothing* in docs/traps.md.',
            );
          }
        } else {
          _debugPicture = null;
        }
        // **From the picture, not from `_slots`.** Reading the packing again
        // here would count glyphs reserved during the awaits above, which this
        // image does not hold — and the next picture blits whatever this map
        // names.
        _pictured = picture.slots;
        // The generation goes up with the pixels, and both go up before the
        // notification: a listener is entitled to read `textureIsCurrent` and
        // find the two halves agreeing, because agreeing is the whole reason
        // it was woken.
        _textureGeneration = picture.generation;
        _textureRevision = picture.revision;
        // The image the texture wraps shares storage with it, so the old one
        // is only let go once nothing is pointing at it any more.
        _textureImage?.dispose();
        _textureImage = picture.image;
        _texture = texture;
        assert(() {
          final clock = _repackClock;
          if (clock != null) {
            debugPrint(
              'GlyphAtlas3d picture of generation $_generation landed after '
              '${clock.elapsedMilliseconds}ms.',
            );
            _repackClock = null;
          }
          return true;
        }());
        notifyListeners();
      }
    } finally {
      _pending = null;
    }
  }

  /// Copies [picture]'s pixels back off the GPU.
  ///
  /// The expensive step, kept behind a name so it is obvious where it is paid:
  /// `toByteData` of a 512-texel atlas measures 785–973ms on a real machine.
  /// Nothing on the drawing path calls it any more — only silhouette tracing
  /// does, and only for a glyph nothing has traced yet.
  Future<GlyphAtlasImage3d> readBack(GlyphAtlasPicture3d picture) async {
    final bytes = await picture.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) {
      throw StateError('The glyph atlas could not be read back.');
    }
    return GlyphAtlasImage3d(
      bytes.buffer.asUint8List(),
      picture.size,
      picture.generation,
      picture.revision,
    );
  }

  /// Draws every reserved glyph into one image, and stops there.
  ///
  /// Free of the GPU only in the sense that matters to a test: it needs
  /// `dart:ui`, which `flutter test` has, and nothing from `flutter_scene`.
  /// The image it returns is the one a texture wraps, so **the caller owns it**
  /// and must dispose it or hand it to something that will.
  Future<GlyphAtlasPicture3d> rasterizePicture() async {
    final generation = _generation;
    final revision = _revision;
    final edge = _size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final style = rasterStyle;
    // **A glyph is typeset exactly once, ever.** Every later picture copies
    // its cell out of the previous one, at whatever address the new packing
    // gave it.
    //
    // This is not an optimization, it is the defect. Drawing a grapheme into
    // one offscreen picture and then into a second one draws *nothing* the
    // second time, on the machine this was measured on: the same glyph set
    // rendered three times running came back with 3021, 0 and 0 ink texels,
    // and where it did not vanish outright it came back short — 12248, 9986,
    // 9986 — always losing a contiguous run of the glyphs reserved earliest.
    // Every flush used to typeset the whole atlas, so every repack redrew
    // glyphs an earlier picture had already drawn, and those are exactly the
    // letters that came out hollow. A blit is not typesetting, so it does not
    // trip it. See *A letter draws once and never again* in `docs/traps.md`.
    final previous = _textureImage;
    final held = previous == null ? const <String, GlyphSlot3d>{} : _pictured;
    // **Every paragraph stays alive until the picture has been rasterized.**
    // `drawParagraph` records a reference rather than the ink, and the pixels
    // are produced by `toImage` later. Disposing one in between was measured
    // not to be what loses a glyph here, but the ordering is the one the API
    // asks for and costs nothing to keep.
    final drawn = <ui.Paragraph>[];
    final holds = <String, GlyphSlot3d>{};
    for (final slot in _slots.values) {
      if (slot.isBlank) continue;
      holds[slot.grapheme] = slot;
      final was = held[slot.grapheme];
      if (was != null && was.width == slot.width && was.height == slot.height) {
        // A blit, not a typesetting. The cell is the same size in both
        // pictures — it is the same glyph at the same scale — so this is a
        // texel-for-texel copy and the filter never has anything to do.
        canvas.drawImageRect(
          previous!,
          Rect.fromLTWH(
            was.x.toDouble(),
            was.y.toDouble(),
            was.width.toDouble(),
            was.height.toDouble(),
          ),
          Rect.fromLTWH(
            slot.x.toDouble(),
            slot.y.toDouble(),
            slot.width.toDouble(),
            slot.height.toDouble(),
          ),
          Paint()..filterQuality = FilterQuality.none,
        );
        continue;
      }
      final paragraph = buildParagraph(slot.grapheme, style)
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(
        paragraph,
        Offset((slot.x + padding).toDouble(), (slot.y + padding).toDouble()),
      );
      drawn.add(paragraph);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(edge, edge);
    picture.dispose();
    for (final paragraph in drawn) {
      paragraph.dispose();
    }
    return GlyphAtlasPicture3d(image, edge, generation, revision, slots: holds);
  }

  /// Draws every reserved glyph into one image and reads the pixels back.
  ///
  /// [rasterizePicture] followed by [readBack]. Nothing on the drawing path
  /// calls this any more — the texture wraps the image instead — but it is
  /// what makes the atlas testable, because a headless test can rasterize and
  /// inspect the texels.
  Future<GlyphAtlasImage3d> rasterize() async {
    final picture = await rasterizePicture();
    try {
      return await readBack(picture);
    } finally {
      picture.image.dispose();
    }
  }

  /// Traces every glyph whose silhouette this atlas does not know yet.
  ///
  /// Each glyph is traced once and kept: an outline is stated in logical
  /// pixels from its own cell's corner, so a repack moves the cell without
  /// changing the answer.
  void _traceOutlines(GlyphAtlasImage3d image) {
    var traced = false;
    for (final slot in _slots.values) {
      if (slot.isBlank || _outlines.containsKey(slot.grapheme)) continue;
      _outlines[slot.grapheme] = traceGlyphOutline(
        grapheme: slot.grapheme,
        pixels: image.pixels,
        stride: image.size,
        x: slot.x,
        y: slot.y,
        width: slot.width,
        height: slot.height,
        scale: scale,
      );
      traced = true;
    }
    if (traced) _outlineRevision++;
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
    _revision++;
    _needsRaster = true;
    assert(() {
      if (debugReportGlyphAtlasRepacks) {
        _repackClock = Stopwatch()..start();
        debugPrint(
          'GlyphAtlas3d repacked to ${size}x$size at generation $_generation '
          '(${style.fontSize?.toStringAsFixed(0) ?? '?'}dp, '
          '${_slots.length} glyphs): every label drawn from this atlas has '
          'no picture to sample until the raster lands.',
        );
      }
      return true;
    }());
  }

  Stopwatch? _repackClock;

  @override
  void dispose() {
    _slots.clear();
    _ink.clear();
    _outlines.clear();
    _pictured = const <String, GlyphSlot3d>{};
    _debugPicture = null;
    _textureImage?.dispose();
    _textureImage = null;
    _texture = null;
    // A disposed atlas has no picture of anything, and must not read as
    // though it had one: a renderer still pointing at it compares its bake
    // against this before it samples.
    _textureGeneration = -1;
    _textureRevision = -1;
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

/// The style an atlas is keyed by: [style] with its colours taken out.
///
/// Glyphs are rasterized white and tinted by the material, so two labels
/// that differ only in colour share an atlas. A style carrying a
/// `foreground` paint is returned untouched, because a `TextStyle` refuses
/// to hold both — such a style is not supported by the atlas renderer, and
/// this at least keeps it from crashing on the way to not being drawn.
///
/// **`decorationColor` comes out too, and leaving it in was expensive.**
/// Material's typography carries it alongside `color` — a `TextStyle.apply`
/// sets both — so keying by it meant one atlas per *text colour* after all:
/// the gallery had twenty-seven atlases for nine styles, the same alphabet
/// rasterized once per colour it is drawn in. The raster is white either way
/// (see [GlyphAtlas3d.rasterStyle]), so the key must not carry the colour a
/// decoration would have been drawn in.
TextStyle glyphAtlasStyleOf(TextStyle style) => style.foreground != null
    ? style
    : style.copyWith(
        color: const Color(0xFFFFFFFF),
        decorationColor: const Color(0xFFFFFFFF),
      );

/// The atlases an application has, one per style and resolution.
///
/// Sharing is the whole point of an atlas, and a renderer is owned by one
/// box, so the sharing has to live somewhere neither of them does. Every
/// [AtlasText3dRenderer] reaches for [shared] unless it is handed a cache of
/// its own, which is what a test does when it wants an atlas it can count
/// the glyphs of.
///
/// **Nothing is evicted.** An atlas lives until [clear] drops it, and
/// [shared] is a static, so it lives for the process. That is bounded rather
/// than unbounded — [glyphAtlasScaleFor] admits 32 buckets, so a style can
/// reach at most that many atlases however far the camera travels — but the
/// ceiling is a real one: a screen with many type styles, walked through many
/// distances, accumulates textures and never gives them back. No eviction
/// policy is implemented because none has been needed; a catalogue that
/// settles at one or two scales per style never approaches the bound. If a
/// long-running application does, [clear] is the blunt instrument, and a
/// least-recently-used bound on [_atlases] is the obvious fix.
class GlyphAtlasCache3d {
  /// Creates a cache whose atlases are built with these settings.
  GlyphAtlasCache3d({
    this.padding = 2,
    this.initialSize = 128,
    this.maxSize = 2048,
    this.upload = uploadGlyphAtlas,
    this.uploadPicture = uploadGlyphAtlasPicture,
  });

  /// The cache every renderer shares unless told otherwise.
  static final GlyphAtlasCache3d shared = GlyphAtlasCache3d();

  /// Passed on to every atlas this cache builds. See [GlyphAtlas3d].
  final int padding;
  final int initialSize;
  final int maxSize;
  final GlyphAtlasUpload3d upload;

  /// Tried before [upload], and the one that costs nothing. See
  /// [uploadGlyphAtlasPicture].
  final GlyphAtlasPictureUpload3d uploadPicture;

  final Map<(TextStyle, double), GlyphAtlas3d> _atlases =
      <(TextStyle, double), GlyphAtlas3d>{};

  /// How many atlases are live.
  int get length => _atlases.length;

  /// Every atlas this cache holds, in the order they were first asked for.
  ///
  /// For asking something of the whole set: how many textures an application
  /// has accumulated, or — the reason this exists — whether every one of them
  /// has rasterized the packing it is handing out. A label whose atlas
  /// repacked waits for the new picture before baking again, and an atlas
  /// stuck with [GlyphAtlas3d.textureIsCurrent] false would leave it waiting
  /// for ever.
  Iterable<GlyphAtlas3d> get atlases => _atlases.values;

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
      uploadPicture: uploadPicture,
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
