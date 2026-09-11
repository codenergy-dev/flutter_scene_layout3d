// Tracing a glyph's silhouette out of its raster: the arithmetic that turns
// an alpha mask into the wall around an extruded letter.
//
// Every mask here is written by hand, because the point of the tracer is that
// it never needs a font or a GPU — it needs a bitmap, and a bitmap can be
// spelled out.

import 'dart:typed_data';

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// An atlas image of [size] texels a side, with the rows of [mask] stamped in
/// at [x], [y].
///
/// A `#` is ink at full coverage, a `.` is nothing, and a `-` is coverage just
/// under the threshold, which is how a test says "the soft edge of a glyph".
Uint8List maskImage(List<String> mask, {int size = 16, int x = 0, int y = 0}) {
  final pixels = Uint8List(size * size * 4);
  for (var row = 0; row < mask.length; row++) {
    for (var column = 0; column < mask[row].length; column++) {
      final alpha = switch (mask[row][column]) {
        '#' => 255,
        '-' => 60,
        _ => 0,
      };
      final index = ((y + row) * size + x + column) * 4;
      pixels[index] = 255;
      pixels[index + 1] = 255;
      pixels[index + 2] = 255;
      pixels[index + 3] = alpha;
    }
  }
  return pixels;
}

GlyphOutline3d trace(
  List<String> mask, {
  int size = 16,
  int x = 0,
  int y = 0,
  double scale = 1.0,
  double tolerance = kGlyphOutlineTolerance,
}) => traceGlyphOutline(
  grapheme: 'x',
  pixels: maskImage(mask, size: size, x: x, y: y),
  stride: size,
  x: x,
  y: y,
  width: mask.first.length,
  height: mask.length,
  scale: scale,
  tolerance: tolerance,
);

/// Twice the signed area of a closed loop, positive when it winds one way and
/// negative when it winds the other.
double signedArea(List<Offset> contour) {
  var total = 0.0;
  for (var i = 0; i < contour.length; i++) {
    final a = contour[i];
    final b = contour[(i + 1) % contour.length];
    total += a.dx * b.dy - b.dx * a.dy;
  }
  return total;
}

/// Whether the outward normal of every segment of [contour] points away from
/// [inside] — the arithmetic the wall's winding depends on.
bool facesAwayFrom(List<Offset> contour, Offset inside) {
  for (var i = 0; i < contour.length; i++) {
    final a = contour[i];
    final b = contour[(i + 1) % contour.length];
    final normal = Offset(-(b.dy - a.dy), b.dx - a.dx);
    final midpoint = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final toward = midpoint - inside;
    if (normal.dx * toward.dx + normal.dy * toward.dy <= 0) return false;
  }
  return true;
}

void main() {
  group('tracing', () {
    test('an empty mask has no contour', () {
      expect(trace(const ['....', '....']).isEmpty, isTrue);
    });

    test('a solid block is one rectangle on the texel grid', () {
      final outline = trace(const ['....', '.##.', '.##.', '....']);
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single, hasLength(4));
      expect(outline.contours.single.toSet(), <Offset>{
        const Offset(1, 1),
        const Offset(3, 1),
        const Offset(3, 3),
        const Offset(1, 3),
      });
    });

    test('coverage under the threshold is not ink', () {
      final outline = trace(const ['----', '-##-', '-##-', '----']);
      expect(outline.contours.single.toSet(), <Offset>{
        const Offset(1, 1),
        const Offset(3, 1),
        const Offset(3, 3),
        const Offset(1, 3),
      });
    });

    test('the scale turns texels into logical pixels', () {
      final outline = trace(const ['....', '.##.', '.##.', '....'], scale: 2.0);
      expect(outline.contours.single.toSet(), <Offset>{
        const Offset(0.5, 0.5),
        const Offset(1.5, 0.5),
        const Offset(1.5, 1.5),
        const Offset(0.5, 1.5),
      });
    });

    test('the rectangle is read out of the atlas at its own offset', () {
      final outline = trace(
        const ['....', '.##.', '.##.', '....'],
        size: 32,
        x: 9,
        y: 7,
      );
      expect(outline.contours.single.toSet(), <Offset>{
        const Offset(1, 1),
        const Offset(3, 1),
        const Offset(3, 3),
        const Offset(1, 3),
      });
    });

    test('a ring traces its hole as a second contour', () {
      final outline = trace(const [
        '.....',
        '.###.',
        '.#.#.',
        '.###.',
        '.....',
      ]);
      expect(outline.contours, hasLength(2));
    });

    test('two texels touching at a corner stay one silhouette', () {
      final outline = trace(const ['....', '.#..', '..#.', '....']);
      expect(outline.contours, hasLength(1));
    });

    test('a glyph that misses the cell entirely has nothing to wall', () {
      expect(trace(const ['....', '....']).segmentCount, 0);
    });
  });

  group('winding', () {
    test('an outer contour faces away from the ink', () {
      final outline = trace(const ['....', '.##.', '.##.', '....']);
      expect(
        facesAwayFrom(outline.contours.single, const Offset(2, 2)),
        isTrue,
      );
    });

    test('a hole faces away from the ink too, which is inward', () {
      final outline = trace(const [
        '.....',
        '.###.',
        '.#.#.',
        '.###.',
        '.....',
      ]);
      // The hole is the loop whose area has the opposite sign, and its
      // outward normals point at the middle of the hole rather than away.
      final outer = outline.contours.reduce(
        (a, b) => signedArea(a).abs() > signedArea(b).abs() ? a : b,
      );
      final hole = outline.contours.firstWhere((c) => !identical(c, outer));
      expect(signedArea(outer) * signedArea(hole), lessThan(0.0));
      expect(facesAwayFrom(hole, const Offset(2.5, 2.5)), isFalse);
      // "Away from the ink" for a hole is toward the hole's middle.
      final reversed = hole.reversed.toList();
      expect(facesAwayFrom(reversed, const Offset(2.5, 2.5)), isTrue);
    });
  });

  group('simplification', () {
    test('a staircase collapses to a line and keeps the corners', () {
      // A right triangle: the hypotenuse is eight steps of the raster and
      // should come back as one segment, so the whole loop is a triangle.
      final outline = trace(const [
        '#.......',
        '##......',
        '###.....',
        '####....',
        '#####...',
        '######..',
        '#######.',
        '########',
      ], tolerance: 1.0);
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single.length, lessThanOrEqualTo(5));
      expect(outline.contours.single, contains(const Offset(0, 0)));
      expect(outline.contours.single, contains(const Offset(8, 8)));
    });

    test('a tighter tolerance keeps more of the staircase', () {
      const mask = [
        '#.......',
        '##......',
        '###.....',
        '####....',
        '#####...',
        '######..',
        '#######.',
        '########',
      ];
      final coarse = trace(mask, tolerance: 4.0);
      final fine = trace(mask, scale: 8.0, tolerance: 0.02);
      expect(fine.segmentCount, greaterThan(coarse.segmentCount));
    });

    test('a rectangle is not simplified past its own corners', () {
      final outline = trace(const [
        '########',
        '########',
        '########',
      ], tolerance: 1.0);
      expect(outline.contours.single, hasLength(4));
    });

    test('a tolerance wider than the letter leaves no wall at all', () {
      // Douglas-Peucker deletes a corner it can reach across, and a loop of
      // two points is not a loop. Stated here because it is the failure mode
      // of a badly chosen tolerance and it is silent: the type still draws,
      // flat. The default is a sixth of a logical pixel, which no letter
      // worth reading is small enough to lose.
      final outline = trace(const [
        '########',
        '########',
        '########',
      ], tolerance: 8.0);
      expect(outline.isEmpty, isTrue);
    });
  });
}
