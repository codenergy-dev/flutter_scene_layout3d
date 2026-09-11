import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;

/// The coverage a texel needs before it counts as ink.
///
/// The same figure `assets/text_glyph3d.fmat` discards below, and it has to
/// be: the wall around a glyph meets the face of it exactly where the face's
/// fragments stop being thrown away. Trace at a lower threshold and the wall
/// stands outside the letter, leaving a rim of side colour around every
/// stroke; trace at a higher one and the letter's face overhangs its own
/// edge.
const double kGlyphOutlineThreshold = 0.35;

/// How far a traced contour may be moved to lose a step of the staircase, in
/// **logical pixels**.
///
/// Stated in logical pixels rather than texels on purpose. A raster's
/// staircase is one texel tall whatever the resolution, so a tolerance in
/// texels would hold the segment count fixed while the letter got bigger —
/// and raising [AtlasText3dRenderer.resolution] would silently multiply the
/// wall geometry of every label in the scene. In logical pixels the wall
/// costs what the *letter* is worth, and a sharper raster spends its detail
/// on the face where it can be seen.
const double kGlyphOutlineTolerance = 0.30;

/// One glyph's silhouette, traced off its raster.
///
/// The outline of the ink, not of the cell: [contours] are closed loops in
/// **logical pixels from the top-left of the glyph's padded cell**, which is
/// the same origin [TextGlyphQuad3d.left] and [TextGlyphQuad3d.top] are
/// measured to. A placed quad and an outline therefore compose with an add,
/// and an outline survives a repack — the atlas moves a cell, it does not
/// resize one.
///
/// A loop's first point is not repeated at the end. Every loop is wound so
/// that, walking it, the **outward normal of a segment from `p` to `q` is
/// `(-(q.y - p.y), q.x - p.x)`** — with `y` downward, that points away from
/// the ink for an outer contour and into the hole for an inner one, which is
/// the same statement and is why an `o` needs no special case.
class GlyphOutline3d {
  /// Records a traced silhouette.
  const GlyphOutline3d(this.grapheme, this.contours);

  /// A glyph with no ink at all: a space, a control character, a cell the
  /// atlas had no room for.
  static const GlyphOutline3d blank = GlyphOutline3d('', <List<Offset>>[]);

  /// The grapheme cluster this outlines.
  final String grapheme;

  /// The closed loops, in logical pixels from the cell's top-left.
  final List<List<Offset>> contours;

  /// Whether there is nothing to draw a wall around.
  bool get isEmpty => contours.isEmpty;

  /// How many segments the whole silhouette has, over every contour.
  int get segmentCount =>
      contours.fold(0, (total, contour) => total + contour.length);

  @override
  String toString() =>
      'GlyphOutline3d("$grapheme", ${contours.length} contours, '
      '$segmentCount segments)';
}

/// Traces the ink inside one rectangle of an atlas image.
///
/// [pixels] is straight-alpha RGBA, row-major, [stride] texels to a row —
/// [GlyphAtlasImage3d] exactly. The rectangle is the glyph's **padded cell**,
/// so the coordinates that come back line up with the quad that samples it,
/// and [scale] is the atlas's texels per logical pixel, which is what turns
/// them into logical pixels.
///
/// Pure arithmetic over a bitmap: no GPU, no font engine, no `dart:ui`. That
/// is the point — the silhouette of a letter is the one part of drawing type
/// that a headless test can check.
GlyphOutline3d traceGlyphOutline({
  required String grapheme,
  required Uint8List pixels,
  required int stride,
  required int x,
  required int y,
  required int width,
  required int height,
  required double scale,
  double threshold = kGlyphOutlineThreshold,
  double tolerance = kGlyphOutlineTolerance,
}) {
  assert(scale > 0.0);
  if (width <= 0 || height <= 0) return GlyphOutline3d(grapheme, const []);
  final cutoff = (threshold.clamp(0.0, 1.0) * 255.0).round();
  final ink = Uint8List(width * height);
  var any = false;
  for (var row = 0; row < height; row++) {
    final sourceRow = (y + row) * stride;
    for (var column = 0; column < width; column++) {
      final index = (sourceRow + x + column) * 4 + 3;
      if (index >= pixels.length) continue;
      if (pixels[index] >= cutoff) {
        ink[row * width + column] = 1;
        any = true;
      }
    }
  }
  if (!any) return GlyphOutline3d(grapheme, const []);

  // A tolerance under half a texel cannot remove a step of the staircase,
  // which is the whole job, so a coarse raster gets a floor rather than a
  // faithful reproduction of its own jaggies.
  final texels = math.max(tolerance * scale, 0.6);
  final contours = <List<Offset>>[];
  for (final loop in _traceLoops(ink, width, height)) {
    final simplified = _simplifyLoop(loop, texels);
    if (simplified.length < 3) continue;
    contours.add(<Offset>[
      for (final point in simplified)
        Offset(point.dx / scale, point.dy / scale),
    ]);
  }
  return GlyphOutline3d(grapheme, contours);
}

/// Every closed boundary loop of a binary mask, in grid coordinates.
///
/// Grid coordinates are the *corners* of the texels, so a mask `width` texels
/// across has `width + 1` of them, and a loop runs along texel edges.
List<List<Offset>> _traceLoops(Uint8List ink, int width, int height) {
  final pitch = width + 1;
  bool at(int column, int row) =>
      column >= 0 &&
      row >= 0 &&
      column < width &&
      row < height &&
      ink[row * width + column] != 0;

  // A directed edge per boundary side, keyed by the point it leaves. Wound so
  // that `(-dy, dx)` points away from the ink: the top side runs right to
  // left, the left side downward, the bottom side left to right, the right
  // side upward.
  final outgoing = <int, List<int>>{};
  void edge(int x0, int y0, int x1, int y1) =>
      (outgoing[y0 * pitch + x0] ??= <int>[]).add(y1 * pitch + x1);
  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      if (!at(column, row)) continue;
      if (!at(column, row - 1)) edge(column + 1, row, column, row);
      if (!at(column - 1, row)) edge(column, row, column, row + 1);
      if (!at(column, row + 1)) edge(column, row + 1, column + 1, row + 1);
      if (!at(column + 1, row)) edge(column + 1, row + 1, column + 1, row);
    }
  }

  final loops = <List<Offset>>[];
  // Sorted so the same mask always traces to the same loops in the same
  // order, which is what lets a test name one of them.
  final starts = outgoing.keys.toList()..sort();
  for (final start in starts) {
    while ((outgoing[start] ?? const <int>[]).isNotEmpty) {
      final points = <int>[start];
      var current = start;
      var next = outgoing[start]!.removeLast();
      var direction = _delta(current, next, pitch);
      // Every grid point has as many boundary edges leaving it as arriving,
      // so a walk that consumes each edge once always comes back to where it
      // started; the guard is against a corrupt mask, not against the
      // arithmetic.
      var guard = width * height * 4 + 8;
      while (next != start && guard-- > 0) {
        points.add(next);
        current = next;
        final candidates = outgoing[current];
        if (candidates == null || candidates.isEmpty) break;
        final chosen = _pickTurn(candidates, current, direction, pitch);
        candidates.remove(chosen);
        direction = _delta(current, chosen, pitch);
        next = chosen;
      }
      if (points.length < 4) continue;
      loops.add(<Offset>[
        for (final point in points)
          Offset((point % pitch).toDouble(), (point ~/ pitch).toDouble()),
      ]);
    }
  }
  return loops;
}

Offset _delta(int from, int to, int pitch) => Offset(
  ((to % pitch) - (from % pitch)).toDouble(),
  ((to ~/ pitch) - (from ~/ pitch)).toDouble(),
);

/// The outgoing edge to take at a junction.
///
/// A junction is two ink texels meeting at a corner and nothing else, so
/// there are at most two candidates and the choice is which way the ink is
/// considered connected. Taking the largest `cross(in, out)` keeps the loop
/// on the far side of the corner, which makes the ink **8-connected** — a
/// hairline diagonal stroke stays one silhouette instead of falling apart
/// into a row of separate diamonds.
int _pickTurn(List<int> candidates, int from, Offset direction, int pitch) {
  if (candidates.length == 1) return candidates.first;
  var best = candidates.first;
  var bestCross = double.negativeInfinity;
  for (final candidate in candidates) {
    final out = _delta(from, candidate, pitch);
    final cross = direction.dx * out.dy - direction.dy * out.dx;
    if (cross > bestCross) {
      bestCross = cross;
      best = candidate;
    }
  }
  return best;
}

/// Douglas–Peucker over a closed loop.
///
/// Closed rather than open, so there is no end to anchor to: the two anchors
/// are the loop's first point and whichever point is furthest from it, which
/// splits the loop into two chains that can be simplified the ordinary way.
/// Picking the furthest point rather than the halfway one is what keeps a
/// rectangle's opposite corner from being simplified away.
List<Offset> _simplifyLoop(List<Offset> loop, double tolerance) {
  if (loop.length < 4) return loop;
  final first = loop.first;
  var split = 0;
  var furthest = -1.0;
  for (var i = 1; i < loop.length; i++) {
    final distance = (loop[i] - first).distanceSquared;
    if (distance > furthest) {
      furthest = distance;
      split = i;
    }
  }
  final head = _simplifyChain(loop.sublist(0, split + 1), tolerance);
  final tail = _simplifyChain(<Offset>[
    ...loop.sublist(split),
    loop.first,
  ], tolerance);
  // Both chains carry the anchors they share, so drop the duplicates.
  return <Offset>[
    ...head.sublist(0, head.length - 1),
    ...tail.sublist(0, tail.length - 1),
  ];
}

List<Offset> _simplifyChain(List<Offset> chain, double tolerance) {
  if (chain.length < 3) return chain;
  var worst = 0.0;
  var index = 0;
  for (var i = 1; i < chain.length - 1; i++) {
    final distance = _distanceToSegment(chain[i], chain.first, chain.last);
    if (distance > worst) {
      worst = distance;
      index = i;
    }
  }
  if (worst <= tolerance) return <Offset>[chain.first, chain.last];
  final head = _simplifyChain(chain.sublist(0, index + 1), tolerance);
  final tail = _simplifyChain(chain.sublist(index), tolerance);
  return <Offset>[...head.sublist(0, head.length - 1), ...tail];
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0.0) return (point - a).distance;
  final t = (((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (point - Offset(a.dx + t * dx, a.dy + t * dy)).distance;
}
