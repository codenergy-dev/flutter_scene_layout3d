// The renderer's arithmetic: packing glyphs into an atlas, rasterizing it,
// and turning a laid-out block into quads. Everything here runs headless —
// the only part of the atlas renderer that cannot is the mesh upload and the
// texture upload, and both are behind seams this file stands in for.
//
// The test font makes every glyph exactly `fontSize` wide, with a line
// `fontSize` tall and its baseline at 0.75 of that, and it draws each glyph
// as a solid block filling its em box. That last part is what lets a test
// ask which texels a glyph landed on.

import 'dart:typed_data';

import 'package:flutter/painting.dart'
    show Color, TextAlign, TextDecoration, TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const TextStyle style = TextStyle(fontSize: 10);

/// An atlas that never reaches for a GPU: the upload is recorded instead.
class RecordingAtlas {
  RecordingAtlas({
    double scale = 1.0,
    int padding = 2,
    int initialSize = 128,
    int maxSize = 2048,
    TextStyle textStyle = style,
  }) {
    atlas = GlyphAtlas3d(
      style: textStyle,
      scale: scale,
      padding: padding,
      initialSize: initialSize,
      maxSize: maxSize,
      upload: (image) {
        uploads.add(image);
        return null;
      },
      // Explicitly the slow path: there is no GPU here to wrap a picture with.
      uploadPicture: (picture) => null,
    );
  }

  late final GlyphAtlas3d atlas;
  final List<GlyphAtlasImage3d> uploads = <GlyphAtlasImage3d>[];
}

/// The alpha of one texel of a rasterized atlas.
int alphaAt(GlyphAtlasImage3d image, int x, int y) =>
    image.pixels[(y * image.size + x) * 4 + 3];

/// Which glyph of [packing] owns the texel at ([x], [y]), or null where the
/// atlas is empty.
///
/// The test font fills every glyph's em box with the same solid block, so a
/// texel cannot say which letter it belongs to and no amount of reading
/// pixels will answer this. The packing can, exactly: a slot is a rectangle
/// and the rectangles never overlap.
String? graphemeUnder(Iterable<GlyphSlot3d> packing, double x, double y) {
  for (final slot in packing) {
    if (slot.isBlank) continue;
    if (x >= slot.x &&
        x < slot.x + slot.width &&
        y >= slot.y &&
        y < slot.y + slot.height) {
      return slot.grapheme;
    }
  }
  return null;
}

/// The texel a quad built from [slot] samples at its middle, in an atlas image
/// of [size] texels.
///
/// The GPU's own arithmetic, and the reason a mesh and a texture are a pair:
/// a slot's texture coordinates are a *fraction* of the atlas edge, so the
/// same slot addresses a different texel in a picture of a different size.
(double, double) sampleAt(GlyphSlot3d slot, int size) =>
    ((slot.u0 + slot.u1) / 2 * size, (slot.v0 + slot.v1) / 2 * size);

TextLayout3d layoutOf(
  String text, {
  double maxWidth = double.infinity,
  double minWidth = 0.0,
  TextAlign textAlign = TextAlign.start,
  TextStyle textStyle = style,
}) {
  final measurement = SegmentedTextMeasurement3d();
  return measurement.layout(
    measurement.prepare(text, textStyle),
    minWidth: minWidth,
    maxWidth: maxWidth,
    textAlign: textAlign,
  );
}

void main() {
  group('the atlas packs', () {
    test('one slot per distinct grapheme, however often it is asked for', () {
      final atlas = RecordingAtlas().atlas;
      for (final grapheme in 'hello'.split('')) {
        atlas.slotFor(grapheme);
      }
      expect(atlas.glyphCount, 4);
      final first = atlas.slotFor('l');
      expect(identical(atlas.slotFor('l'), first), isTrue);
    });

    test('a glyph carries its own advance and its gutter', () {
      final atlas = RecordingAtlas(padding: 2).atlas;
      final slot = atlas.slotFor('a');
      // A 10pt glyph in the test font: 10 texels of advance, a 15-texel
      // raster box (the atlas rasterizes at 1.5 line heights), two texels of
      // gutter on every side.
      expect(slot.width, 14);
      expect(slot.height, 19);
      expect(slot.advance, closeTo(10.0, 1e-9));
      expect(slot.left, closeTo(-2.0, 1e-9));
      // The baseline of a 1.5-height line sits at 1.125em, so the raster's
      // top edge is that plus the gutter above the baseline.
      expect(slot.top, closeTo(-13.25, 1e-9));
      expect(slot.isBlank, isFalse);
    });

    test('whitespace advances the pen and reserves nothing', () {
      final atlas = RecordingAtlas().atlas;
      final space = atlas.slotFor(' ');
      expect(space.isBlank, isTrue);
      expect(space.advance, closeTo(10.0, 1e-9));
      expect(atlas.needsRaster, isFalse);
    });

    test('a revision counts contents, a generation counts repacks', () async {
      // The distinction the fix above rests on. `generation` answers *are my
      // texture coordinates still valid*, and only a repack moves it;
      // `revision` answers *is my picture of the atlas still complete*, and
      // reserving a glyph moves that too. Conflating them is what lost a
      // screen its letters.
      final recording = RecordingAtlas(initialSize: 1024, maxSize: 1024);
      final atlas = recording.atlas;
      final before = atlas.revision;
      atlas.slotFor('a');
      expect(atlas.revision, greaterThan(before));
      expect(atlas.generation, 0, reason: 'a reservation is not a repack');
      final image = await atlas.rasterize();
      expect(image.revision, atlas.revision);
      atlas.slotFor('b');
      expect(
        image.revision,
        lessThan(atlas.revision),
        reason:
            'the image is a glyph behind and nothing but the revision '
            'says so',
      );
    });

    test('scale is what the raster is measured in', () {
      final atlas = RecordingAtlas(scale: 2.0).atlas;
      final slot = atlas.slotFor('a');
      expect(slot.width, 24); // 20 texels of glyph, four of gutter.
      // The logical figures are unchanged: a glyph is the same size on the
      // panel however finely it was rasterized.
      expect(slot.advance, closeTo(10.0, 1e-9));
      expect(slot.left, closeTo(-1.0, 1e-9));
    });

    test('slots never overlap, and stay inside the atlas', () {
      final atlas = RecordingAtlas(initialSize: 64, maxSize: 512).atlas;
      final slots = <GlyphSlot3d>[];
      for (final grapheme in 'abcdefghijklmnopqrstuvwxyz0123456789'.split('')) {
        atlas.slotFor(grapheme);
      }
      // Ask again: growth repacks, so only the final answers are comparable.
      for (final grapheme in 'abcdefghijklmnopqrstuvwxyz0123456789'.split('')) {
        slots.add(atlas.slotFor(grapheme));
      }
      for (final slot in slots) {
        expect(slot.x + slot.width, lessThanOrEqualTo(atlas.size));
        expect(slot.y + slot.height, lessThanOrEqualTo(atlas.size));
        expect(slot.u0, closeTo(slot.x / atlas.size, 1e-12));
        expect(slot.v1, closeTo((slot.y + slot.height) / atlas.size, 1e-12));
      }
      for (var i = 0; i < slots.length; i++) {
        for (var j = i + 1; j < slots.length; j++) {
          final a = slots[i];
          final b = slots[j];
          final apart =
              a.x + a.width <= b.x ||
              b.x + b.width <= a.x ||
              a.y + a.height <= b.y ||
              b.y + b.height <= a.y;
          expect(apart, isTrue, reason: '$a overlaps $b');
        }
      }
    });

    test('running out of room doubles the atlas and says so', () {
      final atlas = RecordingAtlas(initialSize: 32, maxSize: 512).atlas;
      expect(atlas.size, 32);
      expect(atlas.generation, 0);
      for (final grapheme in 'abcdefgh'.split('')) {
        atlas.slotFor(grapheme);
      }
      expect(atlas.size, greaterThan(32));
      expect(atlas.generation, greaterThan(0));
      expect(atlas.glyphCount, 8);
    });

    test('a glyph too big for the largest atlas draws nothing', () {
      final atlas = RecordingAtlas(initialSize: 8, maxSize: 8).atlas;
      final slot = atlas.slotFor('a');
      expect(slot.isBlank, isTrue);
      // The pen still moves, so the rest of the line stays where it belongs.
      expect(slot.advance, closeTo(10.0, 1e-9));
    });
  });

  group('the atlas rasterizes', () {
    test('every reserved glyph, into its own slot', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final slots = <GlyphSlot3d>[
        for (final grapheme in 'abc'.split('')) atlas.slotFor(grapheme),
      ];
      final image = await atlas.rasterize();
      expect(image.size, atlas.size);
      expect(image.pixels, hasLength(atlas.size * atlas.size * 4));
      for (final slot in slots) {
        // The test font fills its em box, so the middle of a glyph's raster
        // is opaque and the gutter around it is not.
        expect(
          alphaAt(image, slot.x + slot.width ~/ 2, slot.y + 6),
          greaterThan(0),
          reason: 'the middle of "${slot.grapheme}" is empty',
        );
        expect(
          alphaAt(image, slot.x, slot.y),
          0,
          reason: 'the gutter of "${slot.grapheme}" is not clear',
        );
      }
    });

    test('once per flush, and not at all when nothing was added', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      atlas.slotFor('a');
      expect(atlas.needsRaster, isTrue);
      var notified = 0;
      atlas.addListener(() => notified++);
      await atlas.flush();
      expect(recording.uploads, hasLength(1));
      expect(notified, 1);
      expect(atlas.needsRaster, isFalse);
      await atlas.flush();
      expect(recording.uploads, hasLength(1));
      atlas.slotFor('b');
      await atlas.flush();
      expect(recording.uploads, hasLength(2));
      expect(notified, 2);
    });

    test('a glyph reserved while a raster is in flight still reaches the '
        'texture', () async {
      // The defect two surfaces sharing GlyphAtlasCache3d.shared hit: the
      // second surface reserves a letter while the first surface's raster is
      // already awaiting `toImage`, the picture was recorded before that
      // letter existed, and the generation has not moved because a plain
      // reservation is not a repack. The upload therefore lands with the
      // letter missing and `needsRaster` cleared, so nothing ever draws it.
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final a = atlas.slotFor('a');
      final pending = atlas.flush();
      final b = atlas.slotFor('b');
      await pending;
      final image = recording.uploads.last;
      expect(alphaAt(image, a.x + a.width ~/ 2, a.y + a.height ~/ 2), 255);
      expect(
        alphaAt(image, b.x + b.width ~/ 2, b.y + b.height ~/ 2),
        255,
        reason: 'the glyph reserved mid-raster is missing from the texture',
      );
      expect(atlas.needsRaster, isFalse);
    });

    test(
      'the pixels are straight-alpha RGBA, white where the ink is',
      () async {
        final recording = RecordingAtlas();
        final atlas = recording.atlas;
        final slot = atlas.slotFor('a');
        final image = await atlas.rasterize();
        final at = ((slot.y + 6) * image.size + slot.x + slot.width ~/ 2) * 4;
        expect(image.pixels.sublist(at, at + 4), <int>[255, 255, 255, 255]);
        expect(image.pixels, isA<Uint8List>());
      },
    );
  });

  group('the picture the texture holds', () {
    // A letter that comes back wrong. See
    // `plans/2026_09_17_a_letter_that_comes_back_wrong.md`.
    //
    // A mesh's texture coordinates and the texture they sample are a *pair*:
    // coordinates baked at one generation address the picture rasterized at
    // that generation and no other. A repack renumbers every slot the moment
    // it happens and rasterizes the new picture several frames later — reading
    // a 2048-texel atlas back off the raster thread is not free — so between
    // the two there is a window in which every coordinate the atlas hands out
    // describes an image that does not exist. `textureGeneration` is what
    // says so.
    //
    // The atlas here is built to **grow**, which is the opposite of what the
    // `two_surfaces_of_type` family needs: a repack is the whole mechanism
    // rather than the thing that hides it.
    const graphemes = <String>[
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
      'g',
      'h',
      'i',
      'j',
      'k',
      'l',
    ];

    /// An atlas of twelve glyphs, rasterized, one reservation short of a
    /// repack.
    ///
    /// Twelve 14x19 cells is exactly a 64-texel atlas — four to a shelf,
    /// three shelves — so the thirteenth letter is what doubles it.
    Future<RecordingAtlas> settled() async {
      final recording = RecordingAtlas(initialSize: 64, maxSize: 512);
      for (final grapheme in graphemes) {
        recording.atlas.slotFor(grapheme);
      }
      await recording.atlas.flush();
      return recording;
    }

    test('names the packing it was rasterized from', () async {
      final recording = await settled();
      final atlas = recording.atlas;
      expect(atlas.textureGeneration, atlas.generation);
      expect(atlas.textureIsCurrent, isTrue);
      expect(recording.uploads.single.generation, atlas.textureGeneration);
    });

    test('says how complete it is, which the generation cannot', () async {
      // The gap `textureIsCurrent` leaves open on purpose. Reserving a glyph
      // into free space does not repack, so the generation does not move and
      // the picture stays "current" while being a letter short. Only
      // `textureRevision` says so, and a diagnostic that cannot say it reports
      // a healthy atlas at the exact moment a label is drawing a letter the
      // texture does not hold — which is how a round was spent.
      // Room to spare, so the reservation below lands in free space: a
      // repack would move the generation and this is the case the generation
      // cannot see.
      final recording = RecordingAtlas(initialSize: 512, maxSize: 512);
      final atlas = recording.atlas;
      for (final grapheme in 'abc'.split('')) {
        atlas.slotFor(grapheme);
      }
      await atlas.flush();
      expect(atlas.textureRevision, atlas.revision);

      atlas.slotFor('\u00e9');
      expect(
        atlas.generation,
        atlas.textureGeneration,
        reason: 'this case is the one a repack does not cover',
      );
      expect(atlas.textureIsCurrent, isTrue);
      expect(
        atlas.textureRevision,
        lessThan(atlas.revision),
        reason: 'the picture is a letter short and nothing else says so',
      );

      await atlas.flush();
      expect(atlas.textureRevision, atlas.revision);
    });

    test('typesets a letter once, and copies it forward ever after', () async {
      // **The defect this exists to stop is not in this package**, which is
      // why the test is about *how many times* a glyph is typeset rather than
      // about what came out. Drawing a grapheme into one offscreen picture and
      // then into a second one draws nothing the second time on at least one
      // machine — the same glyph set rendered three times running came back
      // with 3021, 0 and 0 ink texels — and a repack used to redraw the whole
      // alphabet, so the letters that had been there longest were the ones
      // that came out hollow. Nothing headless can see that. What it can see
      // is the rule that avoids it: a glyph is handed to the font engine once
      // and blitted from the previous picture every time after.
      final recording = RecordingAtlas(initialSize: 64, maxSize: 2048);
      final atlas = recording.atlas;
      for (final grapheme in 'abc'.split('')) {
        atlas.slotFor(grapheme);
      }
      await atlas.flush();
      final pictured = atlas.generation;

      // Reserve until the packing moves, so every letter above is at a new
      // address in the next picture and a redraw is the *easy* way to get it
      // there.
      final added = <String>[];
      for (final grapheme in 'defghijklmnopqrstuv'.split('')) {
        atlas.slotFor(grapheme);
        added.add(grapheme);
        if (atlas.generation > pictured) break;
      }
      expect(atlas.generation, greaterThan(pictured), reason: 'no repack');

      final before = debugTextParagraphCount;
      await atlas.flush();
      expect(
        debugTextParagraphCount - before,
        added.length,
        reason: 'a, b and c were already drawn and must be copied, not redrawn',
      );

      // And the copy has to be the letter, at the address the packing now
      // hands out — a blit that lands anywhere else is worse than a redraw.
      final image = recording.uploads.last;
      for (final grapheme in 'abc'.split('')) {
        final slot = atlas.slotFor(grapheme);
        final (u, v) = sampleAt(slot, image.size);
        expect(
          alphaAt(image, u.round(), v.round()),
          greaterThan(0),
          reason: 'the cell "$grapheme" was copied into came back empty',
        );
      }
    });

    test('is nothing at all before the first flush', () {
      final atlas = RecordingAtlas().atlas;
      expect(atlas.textureGeneration, -1);
      expect(atlas.textureRevision, -1);
      expect(atlas.textureIsCurrent, isFalse);
      atlas.slotFor('a');
      expect(atlas.textureIsCurrent, isFalse);
    });

    test('falls behind the moment a repack happens', () async {
      final recording = await settled();
      final atlas = recording.atlas;
      final was = atlas.generation;
      atlas.slotFor('m');
      expect(atlas.generation, greaterThan(was), reason: 'no repack happened');
      expect(atlas.textureGeneration, was);
      expect(
        atlas.textureIsCurrent,
        isFalse,
        reason: 'the new packing has not been rasterized yet',
      );
      // And the atlas always owes a raster in that window, which is what
      // makes waiting for it safe rather than a deadlock.
      expect(atlas.needsRaster, isTrue);
      await atlas.flush();
      expect(atlas.textureIsCurrent, isTrue);
      expect(atlas.textureGeneration, atlas.generation);
    });

    test('holds another letter under a coordinate baked after the repack, or '
        'no letter at all', () async {
      // The defect, reproduced: `Notifications` drew as `Noti`, a dark
      // speckled block, then `ications`, and `Ada Lovelace` drew as
      // `Lovel ce`. Both are one mesh sampling the *previous* picture of the
      // atlas with coordinates measured against the new one.
      final recording = await settled();
      final atlas = recording.atlas;
      final picture = recording.uploads.single;
      final before = <GlyphSlot3d>[
        for (final grapheme in graphemes) atlas.slotFor(grapheme),
      ];

      // Every letter is where its own coordinates say, while the pair holds.
      for (final slot in before) {
        final (x, y) = sampleAt(slot, picture.size);
        expect(
          graphemeUnder(before, x, y),
          slot.grapheme,
          reason: '"${slot.grapheme}" does not address its own texels',
        );
      }

      // One more letter doubles the atlas, and nothing has rasterized it.
      atlas.slotFor('m');
      final after = <GlyphSlot3d>[
        for (final grapheme in graphemes) atlas.slotFor(grapheme),
      ];
      expect(atlas.size, greaterThan(picture.size));

      final wrongLetter = <String>[];
      final noLetter = <String>[];
      for (final slot in after) {
        final (x, y) = sampleAt(slot, picture.size);
        final found = graphemeUnder(before, x, y);
        if (found == null) {
          noLetter.add(slot.grapheme);
        } else if (found != slot.grapheme) {
          wrongLetter.add(slot.grapheme);
        }
      }
      expect(
        wrongLetter,
        isNotEmpty,
        reason: 'no glyph lands on a neighbour, so no speckled block',
      );
      expect(
        noLetter,
        isNotEmpty,
        reason: 'no glyph lands on empty atlas, so no missing letter',
      );
      // And the reason it reads as a defect *per glyph* rather than per
      // label: the atlas doubles, so a coordinate is roughly halved, and the
      // letters packed first are the ones that still land on themselves. The
      // first glyph in the atlas comes out right in the same frame the
      // eighth comes out as a block.
      final (x, y) = sampleAt(after.first, picture.size);
      expect(graphemeUnder(before, x, y), after.first.grapheme);
    });
  });

  group('the atlas traces', () {
    test('a silhouette per glyph, with the pixels and not before', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      atlas.slotFor('a');
      // A slot is packing arithmetic and is available at once; an outline is
      // read off the raster, and the raster is asynchronous.
      expect(atlas.outlineFor('a'), isNull);
      expect(atlas.outlineRevision, 0);
      await atlas.flush();
      final outline = atlas.outlineFor('a');
      expect(outline, isNotNull);
      expect(outline!.isEmpty, isFalse);
      expect(atlas.outlineRevision, 1);
    });

    test('the test font\'s solid em box, as one rectangle', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final slot = atlas.slotFor('a');
      await atlas.flush();
      final outline = atlas.outlineFor('a')!;
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single, hasLength(4));
      // In logical pixels from the cell's top-left, which is where the quad's
      // own top-left is, so an outline drops onto a placed quad with an add.
      for (final point in outline.contours.single) {
        expect(point.dx, inInclusiveRange(0.0, slot.width / atlas.scale));
        expect(point.dy, inInclusiveRange(0.0, slot.height / atlas.scale));
      }
    });

    test('a blank glyph gets nothing to trace', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      atlas.slotFor('a');
      atlas.slotFor(' ');
      await atlas.flush();
      expect(atlas.outlineFor(' '), isNull);
    });

    test('once per glyph, so the revision settles', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      atlas.slotFor('a');
      await atlas.flush();
      expect(atlas.outlineRevision, 1);
      atlas.slotFor('b');
      await atlas.flush();
      expect(atlas.outlineRevision, 2);
      // Nothing new: nothing traced.
      atlas.slotFor('a');
      await atlas.flush();
      expect(atlas.outlineRevision, 2);
    });

    test('never from a picture of another packing', () async {
      // The second hypothesis in
      // `plans/2026_09_17_a_letter_that_comes_back_wrong.md`, checked and
      // found not to be the fault: a silhouette is cached by grapheme and is
      // never traced twice, so one traced off the wrong cell would be wrong
      // for the life of the atlas with no path that repairs it. The guard is
      // that `flush` traces only from an image whose generation *and* revision
      // match the atlas's, and this is the case that tests it — a repack
      // arriving while the rasterization is in flight, which moves every cell
      // under the picture being read back.
      const alphabet = 'abcdefghijkl';

      // The control: one atlas that reserves its whole alphabet and then
      // rasterizes it, so nothing moves while the pixels are being read.
      final clean = RecordingAtlas(initialSize: 32, maxSize: 512).atlas;
      for (final grapheme in alphabet.split('')) {
        clean.slotFor(grapheme);
      }
      await clean.flush();

      // And the same atlas built the way an overlay builds one: a letter
      // settled and rasterized, then eleven more arriving while that raster is
      // in flight, which repacks the atlas twice under the picture being read
      // back.
      final atlas = RecordingAtlas(initialSize: 32, maxSize: 512).atlas;
      atlas.slotFor('a');
      final pending = atlas.flush();
      for (final grapheme in alphabet.substring(1).split('')) {
        atlas.slotFor(grapheme);
      }
      await pending;
      expect(atlas.generation, greaterThan(0), reason: 'no repack happened');
      expect(atlas.size, clean.size);

      for (final grapheme in alphabet.split('')) {
        expect(
          atlas.outlineFor(grapheme)!.contours,
          clean.outlineFor(grapheme)!.contours,
          reason: '"$grapheme" was traced off the wrong cell',
        );
      }
    });

    test('an outline survives the repack that invalidates every UV', () async {
      final recording = RecordingAtlas(initialSize: 32);
      final atlas = recording.atlas;
      final before = atlas.slotFor('a');
      await atlas.flush();
      final traced = atlas.outlineFor('a')!;
      final generation = atlas.generation;
      for (final grapheme in 'bcdefghijkl'.split('')) {
        atlas.slotFor(grapheme);
      }
      await atlas.flush();
      expect(
        atlas.generation,
        greaterThan(generation),
        reason: 'the atlas did not repack, so there is nothing to survive',
      );
      expect(atlas.slotFor('a').u1, isNot(before.u1));
      // The texture coordinates are gone and the outline is not: a repack
      // moves a cell and resizes the atlas, and an outline is stated in
      // logical pixels from the cell's own corner.
      expect(atlas.outlineFor('a')!.contours, traced.contours);
      expect(atlas.outlineRevision, 2);
    });
  });

  group('the wall', () {
    test('is one segment per side of a traced silhouette', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      await atlas.flush();
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      await atlas.flush();
      final segments = buildGlyphWallSegments(quads: quads, atlas: atlas);
      expect(segments, hasLength(4));
      expect(segments.every((s) => s.grapheme == 'a'), isTrue);
    });

    test('is empty until the atlas has traced anything', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      expect(buildGlyphWallSegments(quads: quads, atlas: atlas), isEmpty);
    });

    test('sits on the quad that draws the glyph', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      await atlas.flush();
      final quad = quads.single;
      final segments = buildGlyphWallSegments(quads: quads, atlas: atlas);
      for (final segment in segments) {
        expect(segment.x0, inInclusiveRange(quad.left, quad.right));
        expect(segment.y0, inInclusiveRange(quad.top, quad.bottom));
      }
    });

    test('carries a normal pointing away from the ink', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      await atlas.flush();
      final segments = buildGlyphWallSegments(quads: quads, atlas: atlas);
      final middleX =
          segments.map((s) => s.x0).reduce((a, b) => a + b) / segments.length;
      final middleY =
          segments.map((s) => s.y0).reduce((a, b) => a + b) / segments.length;
      for (final segment in segments) {
        final (nx, ny) = segment.outwardNormal;
        final towardX = (segment.x0 + segment.x1) / 2 - middleX;
        final towardY = (segment.y0 + segment.y1) / 2 - middleY;
        expect(
          nx * towardX + ny * towardY,
          greaterThan(0.0),
          reason: '$segment faces into the letter',
        );
      }
    });

    test('is two triangles a segment, wound around that normal', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      await atlas.flush();
      final segments = buildGlyphWallSegments(quads: quads, atlas: atlas);
      final builder = AtlasText3dRenderer.buildGlyphWallGeometry(
        segments,
        0.01,
        0.02,
        const Color(0xFFFFFFFF),
      );
      expect(builder.vertexCount, segments.length * 4);
      expect(builder.triangleCount, segments.length * 2);
      for (final segment in segments) {
        final corners = AtlasText3dRenderer.glyphWallCorners(
          segment,
          0.01,
          0.02,
        );
        final normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
        final (nx, ny) = segment.outwardNormal;
        expect(normal.dot(Vector3(nx, ny, 0.0)), greaterThan(0.0));
      }
    });

    test('runs from the old plane forward to the viewer', () async {
      final recording = RecordingAtlas();
      final atlas = recording.atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a'), atlas: atlas);
      await atlas.flush();
      final segment = buildGlyphWallSegments(quads: quads, atlas: atlas).first;
      final corners = AtlasText3dRenderer.glyphWallCorners(segment, 0.01, 0.02);
      expect(corners[0].z, 0.0);
      expect(corners[1].z, 0.0);
      // Toward the viewer is negative z, and the back face is where the flat
      // quad used to be, so nothing a component lifted has to move.
      expect(corners[2].z, closeTo(-0.02, 1e-9));
      expect(corners[3].z, closeTo(-0.02, 1e-9));
    });

    test('a zero thickness builds nothing', () {
      expect(
        AtlasText3dRenderer.buildGlyphWallGeometry(
          const <GlyphWallSegment3d>[
            GlyphWallSegment3d(grapheme: 'a', x0: 0, y0: 0, x1: 1, y1: 0),
          ],
          0.01,
          0.0,
          const Color(0xFFFFFFFF),
        ).vertexCount,
        0,
      );
    });

    test('is shaded from the letter\'s own upper left', () {
      // Up is -y here, so a wall facing up is the lit one and the wall facing
      // down is the dark one. The floor is not zero: a wall that went to
      // black would read as a hole beside the stroke.
      final up = AtlasText3dRenderer.wallShade(0.0, -1.0);
      final down = AtlasText3dRenderer.wallShade(0.0, 1.0);
      final left = AtlasText3dRenderer.wallShade(-1.0, 0.0);
      expect(up, greaterThan(down));
      expect(left, greaterThan(AtlasText3dRenderer.wallShade(1.0, 0.0)));
      expect(down, greaterThanOrEqualTo(AtlasText3dRenderer.wallShadeFloor));
      expect(up, lessThanOrEqualTo(1.0));
    });
  });

  group('the depth of a glyph', () {
    test('is a tenth of the font size unless one is stated', () {
      final renderer = AtlasText3dRenderer();
      expect(renderer.resolveDepth(const TextStyle(fontSize: 20)), 2.0);
      expect(
        renderer.resolveDepth(const TextStyle(fontSize: 57)),
        closeTo(5.7, 1e-9),
      );
      // Icons are text, so a 24dp icon is thicker than the label beside it,
      // which is what keeps both looking like the same material.
      expect(
        renderer.resolveDepth(const TextStyle(fontSize: 24)),
        closeTo(2.4, 1e-9),
      );
    });

    test('is what was stated, when one was', () {
      final renderer = AtlasText3dRenderer(depth: 1.5);
      expect(renderer.resolveDepth(const TextStyle(fontSize: 20)), 1.5);
      expect(
        AtlasText3dRenderer(depth: 0.0).resolveDepth(const TextStyle()),
        0.0,
      );
    });

    test('falls back to the measurement half\'s own default size', () {
      expect(
        AtlasText3dRenderer(depthFactor: 0.5).resolveDepth(const TextStyle()),
        7.0,
      );
    });
  });

  group('the cache', () {
    test('shares an atlas between styles that differ only in colour', () {
      final cache = GlyphAtlasCache3d(upload: (_) => null);
      final plain = cache.atlasFor(style, 1.0);
      final coloured = cache.atlasFor(
        style.copyWith(color: const Color(0xFFFF0000)),
        1.0,
      );
      expect(identical(plain, coloured), isTrue);
      expect(cache.length, 1);
    });

    test('including the colour a decoration would have been drawn in', () {
      // Material's typography carries `decorationColor` alongside `color` —
      // `TextStyle.apply` sets both — so an atlas keyed by it is an atlas per
      // text colour however carefully the colour itself is stripped. The
      // gallery had twenty-seven of them for nine styles.
      final cache = GlyphAtlasCache3d(upload: (_) => null);
      final plain = cache.atlasFor(
        style.copyWith(
          color: const Color(0xFF101010),
          decorationColor: const Color(0xFF101010),
        ),
        1.0,
      );
      final other = cache.atlasFor(
        style.copyWith(
          color: const Color(0xFFEEEEEE),
          decorationColor: const Color(0xFFEEEEEE),
        ),
        1.0,
      );
      expect(identical(plain, other), isTrue);
      expect(cache.length, 1);
    });

    test('and an underline is rasterized white like the ink', () {
      final atlas = GlyphAtlas3d(
        style: const TextStyle(
          fontSize: 20,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFFF0000),
        ),
        scale: 1.0,
        upload: (_) => null,
      );
      expect(atlas.rasterStyle.decorationColor, const Color(0xFFFFFFFF));
      expect(atlas.rasterStyle.color, const Color(0xFFFFFFFF));
    });

    test('but not between sizes or resolutions', () {
      final cache = GlyphAtlasCache3d(upload: (_) => null);
      cache.atlasFor(style, 1.0);
      cache.atlasFor(style, 2.0);
      cache.atlasFor(const TextStyle(fontSize: 20), 1.0);
      expect(cache.length, 3);
    });

    test('a scale is bucketed up to the next quarter step', () {
      expect(glyphAtlasScaleFor(1.0), 1.0);
      expect(glyphAtlasScaleFor(1.01), 1.25);
      expect(glyphAtlasScaleFor(2.4), 2.5);
      expect(glyphAtlasScaleFor(0.01), 0.25);
      expect(glyphAtlasScaleFor(99.0), 8.0);
    });
  });

  group('quads', () {
    test('one per glyph that draws, at the pen and off the baseline', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('hi'), atlas: atlas);
      expect(quads.map((quad) => quad.grapheme), <String>['h', 'i']);
      // The raster carries a two-texel gutter, so a glyph's quad starts two
      // logical pixels before the pen and is four wider than its advance.
      expect(quads.first.left, closeTo(-2.0, 1e-9));
      expect(quads.first.width, closeTo(14.0, 1e-9));
      expect(quads[1].left, closeTo(8.0, 1e-9));
      // The line's baseline is at 7.5; the raster's top is 13.25 above it.
      expect(quads.first.top, closeTo(7.5 - 13.25, 1e-9));
      expect(quads.first.height, closeTo(19.0, 1e-9));
    });

    test('none for whitespace', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('a b'), atlas: atlas);
      expect(quads.map((quad) => quad.grapheme), <String>['a', 'b']);
      expect(quads.last.left, closeTo(18.0, 1e-9));
    });

    test('a second line is a line lower', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(
        layout: layoutOf('ab cd', maxWidth: 25),
        atlas: atlas,
      );
      expect(quads, hasLength(4));
      expect(quads[2].top - quads[0].top, closeTo(10.0, 1e-9));
      expect(quads[2].left, closeTo(quads[0].left, 1e-9));
    });

    test(
      'alignment moves them, because a run says where it is in the block',
      () {
        final atlas = RecordingAtlas().atlas;
        final centred = buildTextGlyphQuads(
          layout: layoutOf(
            'ab',
            minWidth: 100,
            maxWidth: 100,
            textAlign: TextAlign.center,
          ),
          atlas: atlas,
        );
        // 100 wide, 20 of text: the line starts at 40.
        expect(centred.first.left, closeTo(38.0, 1e-9));
        final right = buildTextGlyphQuads(
          layout: layoutOf(
            'ab',
            minWidth: 100,
            maxWidth: 100,
            textAlign: TextAlign.right,
          ),
          atlas: atlas,
        );
        expect(right.first.left, closeTo(78.0, 1e-9));
      },
    );

    test('the ellipsis a truncated line draws is a glyph like any other', () {
      final atlas = RecordingAtlas().atlas;
      final measurement = SegmentedTextMeasurement3d();
      final layout = measurement.layout(
        measurement.prepare('hello world', style),
        maxWidth: 50,
        maxLines: 1,
        ellipsis: '…',
      );
      final quads = buildTextGlyphQuads(layout: layout, atlas: atlas);
      expect(quads.last.grapheme, '…');
    });

    test('every quad samples the slot its glyph was packed into', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('ab'), atlas: atlas);
      for (final quad in quads) {
        final slot = atlas.slotFor(quad.grapheme);
        expect(quad.u0, slot.u0);
        expect(quad.v0, slot.v0);
        expect(quad.u1, slot.u1);
        expect(quad.v1, slot.v1);
      }
    });
  });

  group('the shaper', () {
    test('places a run\'s graphemes along it', () {
      final shaper = TextRunShaper3d();
      final shaped = shaper.shape('abc', style);
      expect(shaped.graphemes, <String>['a', 'b', 'c']);
      expect(shaped.offsets, <double>[0, 10, 20]);
    });

    test('keeps a grapheme cluster whole', () {
      final shaper = TextRunShaper3d();
      // A base plus a combining acute is one grapheme, and must not be cut
      // in half on the way to becoming two glyphs.
      expect(shaper.shape('e\u0301x', style).graphemes, <String>[
        'e\u0301',
        'x',
      ]);
    });

    test('shapes a run once, however often it is drawn', () {
      final shaper = TextRunShaper3d();
      shaper.shape('again', style);
      final before = debugTextParagraphCount;
      for (var i = 0; i < 20; i++) {
        shaper.shape('again', style);
      }
      expect(debugTextParagraphCount, before);
    });

    test('evicts rather than growing', () {
      final shaper = TextRunShaper3d(capacity: 2);
      shaper
        ..shape('a', style)
        ..shape('b', style)
        ..shape('c', style);
      expect(shaper.length, 2);
      final before = debugTextParagraphCount;
      shaper.shape('a', style);
      expect(debugTextParagraphCount, greaterThan(before));
    });
  });

  group('geometry', () {
    test('is four vertices and two triangles a glyph', () {
      final atlas = RecordingAtlas().atlas;
      final quads = buildTextGlyphQuads(layout: layoutOf('hi'), atlas: atlas);
      final builder = AtlasText3dRenderer.buildGlyphGeometry(quads, 0.01);
      expect(builder.vertexCount, 8);
      expect(builder.triangleCount, 4);
      expect(builder.packVertices(), isNotEmpty);
    });

    test('faces the viewer', () {
      final atlas = RecordingAtlas().atlas;
      final quad = buildTextGlyphQuads(
        layout: layoutOf('a'),
        atlas: atlas,
      ).single;
      final corners = AtlasText3dRenderer.glyphQuadCorners(quad, 0.01);
      // The engine's convention: a triangle is wound counter-clockwise
      // around its outward normal. In layout space the viewer is along -z,
      // so a glyph the viewer can see has a normal pointing that way.
      final normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
      expect(normal.z, lessThan(0.0));
      expect(normal.x, 0.0);
      expect(normal.y, 0.0);
    });

    test('is in world units, and the atlas rectangle is not', () {
      final atlas = RecordingAtlas().atlas;
      final quad = buildTextGlyphQuads(
        layout: layoutOf('a'),
        atlas: atlas,
      ).single;
      final corners = AtlasText3dRenderer.glyphQuadCorners(quad, 0.01);
      // Vector3 holds single-precision floats, so the comparison is one.
      expect(corners.first.x, closeTo(quad.left * 0.01, 1e-7));
      expect(corners[2].y, closeTo(quad.bottom * 0.01, 1e-7));
      final uvs = AtlasText3dRenderer.glyphQuadTexCoords(quad);
      expect(uvs.first.x, quad.u0);
      expect(uvs[2].y, quad.v1);
    });
  });

  group('colour', () {
    test('reaches the material in linear space', () {
      expect(linearColor(const Color(0xFFFFFFFF)).r, closeTo(1.0, 1e-9));
      expect(linearColor(const Color(0xFF000000)).r, closeTo(0.0, 1e-9));
      // Mid grey is not half: that is the whole reason for the conversion.
      expect(linearColor(const Color(0xFF808080)).r, closeTo(0.2158, 1e-3));
      expect(linearColor(const Color(0x80FFFFFF)).a, closeTo(0.5019, 1e-3));
    });
  });
}
