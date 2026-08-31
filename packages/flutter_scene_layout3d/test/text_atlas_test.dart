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

import 'package:flutter/painting.dart' show Color, TextAlign, TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

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
    );
  }

  late final GlyphAtlas3d atlas;
  final List<GlyphAtlasImage3d> uploads = <GlyphAtlasImage3d>[];
}

/// The alpha of one texel of a rasterized atlas.
int alphaAt(GlyphAtlasImage3d image, int x, int y) =>
    image.pixels[(y * image.size + x) * 4 + 3];

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

    test('but not between sizes or resolutions', () {
      final cache = GlyphAtlasCache3d(upload: (_) => null);
      cache.atlasFor(style, 1.0);
      cache.atlasFor(style, 2.0);
      cache.atlasFor(const TextStyle(fontSize: 20), 1.0);
      expect(cache.length, 3);
    });

    test('a scale is bucketed up to the next half step', () {
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
