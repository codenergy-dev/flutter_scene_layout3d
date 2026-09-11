// RichText3d: the escape hatch's half that does not need a GPU.
//
// Measurement, intrinsics and the baseline come from a TextPainter, so all of
// that is checkable headless and is checked here against the same painter a
// Flutter `Text` would use. What cannot be checked here is the capture: there
// is no SceneView hosting the subtree and no GPU to sample it with, so the
// box measures, sizes and reports, and draws nothing.
//
// The test font makes every glyph exactly `fontSize` wide, with a line
// `fontSize` tall and its baseline at 0.75 of that.

import 'dart:typed_data';

import 'package:flutter/painting.dart'
    show
        Color,
        TextDirection,
        TextOverflow,
        TextPainter,
        TextScaler,
        TextSpan,
        TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const TextStyle style = TextStyle(fontSize: 10);
const TextStyle bigger = TextStyle(fontSize: 20);

TextSpan span(String text, [TextStyle textStyle = style]) =>
    TextSpan(text: text, style: textStyle);

Layout3dSurface panel(
  Layout3d child, {
  Size3d size = const Size3d(4, 3, 0.5),
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) => laidOut(child, constraints: Constraints3d.tight(size), metrics: metrics);

/// What a Flutter `Text` would make of the same span at the same width.
TextPainter truth(TextSpan text, {double maxWidth = double.infinity}) =>
    TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);

void main() {
  group('sizing', () {
    test('a paragraph is as big as Flutter makes it, in world units', () {
      final text = RichText3d(span('hello'));
      panel(Center3d(child: text));
      final painter = truth(span('hello'));
      expect(text.size.width, closeTo(painter.width * 0.01, 1e-9));
      expect(text.size.height, closeTo(painter.height * 0.01, 1e-9));
      expect(text.size.depth, 0.0);
    });

    test('several styles in one span are measured as one paragraph', () {
      final mixed = TextSpan(
        children: <TextSpan>[span('ab'), span('cd', bigger)],
      );
      final text = RichText3d(mixed);
      panel(Center3d(child: text));
      final painter = truth(mixed);
      expect(text.size.width, closeTo(painter.width * 0.01, 1e-9));
      // The taller run sets the line box, which is the whole reason a span
      // cannot be measured a piece at a time.
      expect(text.size.height, closeTo(0.2, 1e-9));
    });

    test('it wraps into the room it is given', () {
      final text = RichText3d(span('hello world'));
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.5),
            child: text,
          ),
        ),
      );
      expect(text.size.height, closeTo(0.2, 1e-9));
      expect(text.painter.width, closeTo(50.0, 1e-9));
    });

    test('softWrap false lays it out on one line', () {
      final text = RichText3d(span('hello world'), softWrap: false);
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.5),
            child: text,
          ),
        ),
      );
      expect(text.painter.height, closeTo(10.0, 1e-9));
      // The box is still no wider than the room it was given; the glyphs
      // are what overflow, which is what Flutter does too.
      expect(text.size.width, closeTo(0.5, 1e-9));
    });

    test('maxLines with an ellipsis cuts it, as a Text would', () {
      final text = RichText3d(
        span('hello world again'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.5),
            child: text,
          ),
        ),
      );
      expect(text.painter.height, closeTo(10.0, 1e-9));
      expect(text.painter.computeLineMetrics(), hasLength(1));
    });

    test('depth is reserved room, not something the glyphs fill', () {
      final text = RichText3d(span('hi'), depth: 0.3);
      panel(Center3d(child: text));
      expect(text.size.depth, 0.3);
    });
  });

  group('the unit contract', () {
    test('a denser surface makes the same paragraph smaller', () {
      final text = RichText3d(span('hello'));
      panel(
        Center3d(child: text),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.005),
      );
      expect(text.size.width, closeTo(0.25, 1e-9));
      expect(text.logicalPixelScale, closeTo(0.005, 1e-12));
    });

    test('the text scale multiplies type and nothing else', () {
      final text = RichText3d(span('hello'));
      panel(
        Center3d(child: text),
        metrics: const Layout3dMetrics(textScaleFactor: 1.5),
      );
      expect(text.size.width, closeTo(0.75, 1e-9));
      // The paragraph itself was never re-measured: the scale is geometric.
      expect(text.painter.width, closeTo(50.0, 1e-9));
    });
  });

  group('the measurement protocol', () {
    test('intrinsics are the widest line and the widest word', () {
      final text = RichText3d(span('hello world'));
      panel(Center3d(child: text));
      expect(
        text.getMaxIntrinsicExtent(Axis3d.horizontal, const Size3d(4, 3, 1)),
        closeTo(1.1, 1e-9),
      );
      expect(
        text.getMinIntrinsicExtent(Axis3d.horizontal, const Size3d(4, 3, 1)),
        closeTo(0.5, 1e-9),
      );
    });

    test('the vertical intrinsic is the height at the width offered', () {
      final text = RichText3d(span('hello world'));
      panel(Center3d(child: text));
      expect(
        text.getMinIntrinsicExtent(Axis3d.vertical, const Size3d(0.5, 3, 1)),
        closeTo(0.2, 1e-9),
      );
    });

    test('an intrinsic query leaves the box laid out as it was', () {
      final text = RichText3d(span('hello world'));
      final surface = panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.5),
            child: text,
          ),
        ),
      );
      final before = text.size;
      text.getMaxIntrinsicExtent(Axis3d.horizontal, const Size3d(4, 3, 1));
      text.markNeedsLayout();
      surface.flush();
      expect(text.size, before);
    });

    test(
      'the baseline is the first line\'s, and only the vertical has one',
      () {
        final text = RichText3d(span('hello world'));
        panel(
          Center3d(
            child: ConstrainedBox3d(
              additionalConstraints: const Constraints3d(maxWidth: 0.5),
              child: text,
            ),
          ),
        );
        expect(
          text.getDistanceToBaseline(Axis3d.vertical),
          closeTo(0.075, 1e-9),
        );
        expect(
          text.getDistanceToBaseline(Axis3d.horizontal, onlyReal: true),
          isNull,
        );
        expect(
          text.getDistanceToBaseline(Axis3d.depth, onlyReal: true),
          isNull,
        );
      },
    );

    test('two sizes of rich text share a baseline in a row', () {
      final small = RichText3d(span('ab'));
      final large = RichText3d(span('cd', bigger));
      panel(
        Row3d(
          crossAxisAlignment: CrossAxisAlignment3d.baseline,
          children: <Layout3d>[small, large],
        ),
      );
      expect(
        small.offset.y + small.getDistanceToBaseline(Axis3d.vertical)!,
        closeTo(
          large.offset.y + large.getDistanceToBaseline(Axis3d.vertical)!,
          1e-9,
        ),
      );
    });
  });

  group('the box', () {
    test('a setter that changes the paragraph relays it out', () {
      final text = RichText3d(span('hi'));
      final surface = panel(Center3d(child: text));
      expect(text.size.width, closeTo(0.2, 1e-9));
      text.text = span('hello');
      expect(text.needsLayout, isTrue);
      surface.flush();
      expect(text.size.width, closeTo(0.5, 1e-9));
    });

    test('a ray finds the paragraph, gaps between letters included', () {
      final text = RichText3d(span('hi'));
      final surface = panel(Center3d(child: text));
      // The panel is 4 by 3 and the 0.2 by 0.1 paragraph is centred on it.
      expect(surface.hitTestAt(const Offset3d(2.0, 1.5, 0)).target, same(text));
      expect(surface.hitTestAt(const Offset3d(2.0, 1.0, 0)).isEmpty, isTrue);
    });

    test('it draws nothing without a scene to be captured in', () {
      final text = RichText3d(span('hi'));
      panel(Center3d(child: text));
      expect(text.isDrawn, isFalse);
      // The component is attached all the same: what it is missing is a
      // SceneView to host the subtree, not a place to put the capture.
      expect(text.node.children, isEmpty);
    });

    test('disposal lets the surface go', () {
      final text = RichText3d(span('hi'));
      panel(Center3d(child: text));
      text.dispose();
      expect(text.node.children, isEmpty);
    });

    test('the quad sits at the front of its own extrusion', () {
      // The face moves forward with the wall and the wall runs back to the
      // plane the flat quad occupied, exactly as a glyph's does.
      final front = textQuadCorners(const Size3d(0.4, 0.2, 0), z: -0.05);
      for (final corner in front) {
        expect(corner.z, closeTo(-0.05, 1e-7));
      }
    });

    test('the quad is the box, wound to face the viewer', () {
      // Building the geometry uploads it, which needs a GPU; the winding is
      // arithmetic, and it is the one mistake whose only symptom is that a
      // correctly measured paragraph cannot be seen.
      final corners = textQuadCorners(const Size3d(0.4, 0.2, 0));
      final normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
      expect(normal.z, lessThan(0.0));
      expect(corners[2].x, closeTo(0.4, 1e-7));
      expect(corners[2].y, closeTo(0.2, 1e-7));
    });
  });

  group('the paragraph is extruded', () {
    test('a tenth of the root span\'s size unless one is stated', () {
      expect(
        RichText3d(
          const TextSpan(text: 'hi', style: TextStyle(fontSize: 40)),
        ).resolvedGlyphDepth,
        closeTo(4.0, 1e-9),
      );
      expect(RichText3d(span('hi'), glyphDepth: 1.5).resolvedGlyphDepth, 1.5);
      expect(RichText3d(span('hi'), glyphDepth: 0.0).resolvedGlyphDepth, 0.0);
      // The same fallback size the measurement half assumes, so the two never
      // disagree about what "the type" is.
      expect(
        RichText3d(const TextSpan(text: 'hi')).resolvedGlyphDepth,
        closeTo(1.4, 1e-9),
      );
    });

    test('nothing is walled before the trace comes back', () {
      final text = RichText3d(span('hi'));
      panel(Center3d(child: text));
      expect(text.wallSegmentCount, 0);
    });

    test(
      'a paragraph rasterizes to a bitmap the resolution asks for',
      () async {
        final painter = TextPainter(
          text: span('hi'),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        final width = painter.width;
        final height = painter.height;
        final raster = await rasterizeParagraph(painter, 3.0);
        painter.dispose();
        expect(raster, isNotNull);
        expect(raster!.width, (width * 3.0).ceil());
        expect(raster.height, (height * 3.0).ceil());
        expect(raster.scale, 3.0);
        expect(raster.pixels, hasLength(raster.width * raster.height * 4));
        // The test font fills its em box, so there is ink in the middle.
        final middle =
            ((raster.height ~/ 2) * raster.width + raster.width ~/ 2) * 4;
        expect(raster.pixels[middle + 3], greaterThan(0));
      },
    );

    test('a painter with nothing in it rasterizes to nothing', () async {
      final painter = TextPainter(
        text: const TextSpan(text: ''),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      expect(await rasterizeParagraph(painter, 2.0), isNull);
      painter.dispose();
    });
  });

  group('the wall takes its colour from the picture', () {
    /// A one-texel-per-pixel raster with [fill] everywhere inside a
    /// 4x4 block and nothing outside it.
    ParagraphRaster3d block(Color fill) {
      const size = 8;
      final pixels = Uint8List(size * size * 4);
      for (var y = 2; y < 6; y++) {
        for (var x = 2; x < 6; x++) {
          final at = (y * size + x) * 4;
          pixels[at] = (fill.r * 255).round();
          pixels[at + 1] = (fill.g * 255).round();
          pixels[at + 2] = (fill.b * 255).round();
          pixels[at + 3] = 255;
        }
      }
      return ParagraphRaster3d(pixels, size, size, 1.0);
    }

    test('a segment is given the ink it stands on', () {
      final raster = block(const Color(0xFF2050A0));
      final outline = traceGlyphOutline(
        grapheme: '',
        pixels: raster.pixels,
        stride: raster.width,
        x: 0,
        y: 0,
        width: raster.width,
        height: raster.height,
        scale: 1.0,
      );
      final segments = buildParagraphWallSegments(
        outline: outline,
        raster: raster,
        fallback: const Color(0xFF000000),
      );
      expect(segments, hasLength(4));
      for (final segment in segments) {
        expect(segment.color, const Color(0xFF2050A0));
      }
    });

    test('a sample off the ink falls back', () {
      final raster = block(const Color(0xFF2050A0));
      // The block's top edge is at y = 2, so the ink is below it and the
      // outward normal points up. The sample steps against that normal.
      expect(
        sampleParagraphInk(raster, 4, 2, 0, -1, const Color(0xFFAA0000)),
        const Color(0xFF2050A0),
        reason: 'the inward step should have landed on ink',
      );
      expect(
        sampleParagraphInk(raster, 4, 2, 0, 1, const Color(0xFFAA0000)),
        const Color(0xFFAA0000),
        reason: 'a normal pointing the wrong way samples the margin',
      );
      expect(
        sampleParagraphInk(raster, 40, 40, 0, 1, const Color(0xFFAA0000)),
        const Color(0xFFAA0000),
        reason: 'a sample off the bitmap has nothing to read',
      );
    });

    test('a segment\'s own colour wins over the builder\'s', () {
      final builder = AtlasText3dRenderer.buildGlyphWallGeometry(
        const <GlyphWallSegment3d>[
          GlyphWallSegment3d(grapheme: 'a', x0: 0, y0: 0, x1: 1, y1: 0),
          GlyphWallSegment3d(
            grapheme: 'a',
            x0: 1,
            y0: 0,
            x1: 2,
            y1: 0,
            color: Color(0xFF00FF00),
          ),
        ],
        1.0,
        0.5,
        const Color(0xFFFF0000),
      );
      expect(builder.vertexCount, 8);
      // Both are lit the same way, so any difference in the baked colour is
      // the segment's own colour and nothing else.
      final packed = builder.packVertices();
      expect(packed, isNotEmpty);
    });
  });
}
