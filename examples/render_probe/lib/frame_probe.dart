import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'probe_scene.dart' show kProbeClear;

/// A captured frame, and the questions worth asking of one.
///
/// Every answer here is a *fraction* or a *mean*, never the value of a single
/// pixel. Anti-aliasing, perspective and a sphere's silhouette all mean the
/// exact pixel a projection names may sit on an edge; a test that reads one
/// pixel is a test that fails on a driver update for no reason. Sampling a
/// small disc and asserting a proportion is both more honest and more stable.
class FrameProbe {
  FrameProbe(this.rgba, this.width, this.height, {this.clear = kProbeClear});

  /// Raw RGBA, four bytes per pixel, row-major from the top left.
  final ByteData rgba;
  final int width;
  final int height;

  /// The colour the scene cleared to. Anything close to it counts as empty.
  final ui.Color clear;

  /// How far a channel may drift from [clear] and still read as empty.
  ///
  /// Generous, because tone mapping and the display transform both move the
  /// clear colour a little on the way to the framebuffer.
  static const int clearTolerance = 12;

  static Future<FrameProbe> fromImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return FrameProbe(data!, image.width, image.height);
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// The pixel at [x], [y], or null when it is off the frame.
  ui.Color? colorAt(int x, int y) {
    if (!_inBounds(x, y)) return null;
    final offset = (y * width + x) * 4;
    return ui.Color.fromARGB(
      rgba.getUint8(offset + 3),
      rgba.getUint8(offset),
      rgba.getUint8(offset + 1),
      rgba.getUint8(offset + 2),
    );
  }

  bool _isClear(ui.Color color) =>
      (color.r * 255 - clear.r * 255).abs() <= clearTolerance &&
      (color.g * 255 - clear.g * 255).abs() <= clearTolerance &&
      (color.b * 255 - clear.b * 255).abs() <= clearTolerance;

  /// The fraction of pixels within [radius] of [center] that are not the
  /// clear colour — that is, how much geometry covers that spot.
  ///
  /// A point off the frame contributes nothing and is not counted, so a disc
  /// half outside the view still reports the coverage of the half inside it.
  /// Returns 0 when the whole disc is off-frame.
  double coverageAt(ui.Offset center, {double radius = 6}) {
    var covered = 0;
    var total = 0;
    final cx = center.dx.round();
    final cy = center.dy.round();
    final r = radius.ceil();
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final color = colorAt(cx + dx, cy + dy);
        if (color == null) continue;
        total++;
        if (!_isClear(color)) covered++;
      }
    }
    return total == 0 ? 0 : covered / total;
  }

  /// Whether the disc at [center] is empty, within [slack].
  ///
  /// [slack] is not zero because an anti-aliased edge bleeds a pixel or two
  /// into what layout considers a gap.
  bool isClearAt(ui.Offset center, {double radius = 6, double slack = 0.05}) =>
      coverageAt(center, radius: radius) <= slack;

  /// The fraction of the whole frame covered by geometry.
  double get coverage {
    var covered = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!_isClear(colorAt(x, y)!)) covered++;
      }
    }
    return covered / (width * height);
  }

  /// Whether all four corners are the clear colour.
  ///
  /// The cheapest "did the surface clear at all" check there is: a scene that
  /// fills the frame edge to edge is usually a scene that did not clear.
  bool get cornersClear {
    const inset = 4.0;
    for (final point in <ui.Offset>[
      const ui.Offset(inset, inset),
      ui.Offset(width - inset - 1, inset),
      ui.Offset(inset, height - inset - 1),
      ui.Offset(width - inset - 1, height - inset - 1),
    ]) {
      if (!isClearAt(point, radius: 2, slack: 0)) return false;
    }
    return true;
  }

  /// Mean luminance of the non-clear pixels: how lit the geometry is.
  ///
  /// Zero when nothing drew. Near zero when something drew and no light
  /// reached it, which looks identical to "nothing drew" in a coverage check
  /// and is a genuinely different bug.
  double get foregroundMeanLuma {
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final color = colorAt(x, y)!;
        if (_isClear(color)) continue;
        sum +=
            0.2126 * color.r * 255 +
            0.7152 * color.g * 255 +
            0.0722 * color.b * 255;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  /// How many distinct colours the frame holds, quantized to [bucket] steps
  /// per channel.
  ///
  /// A loose backstop against a flat fill. Kept loose on purpose: a software
  /// rasterizer produces far fewer distinct values than a real GPU, and a
  /// flat-shaded cuboid legitimately covers only a handful.
  int distinctColors({int bucket = 8}) {
    final seen = <int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = colorAt(x, y)!;
        seen.add(
          ((c.r * 255) ~/ bucket) << 16 |
              ((c.g * 255) ~/ bucket) << 8 |
              ((c.b * 255) ~/ bucket),
        );
      }
    }
    return seen.length;
  }

  /// The mean colour of the non-clear pixels within [radius] of [center].
  ///
  /// Null when nothing is covered there. Averaging over a disc rather than
  /// reading one pixel is the difference between a stable assertion and one
  /// that fails on an anti-aliased edge or a lighting gradient.
  ui.Color? meanColorAt(ui.Offset center, {double radius = 4}) {
    var r = 0.0, g = 0.0, b = 0.0;
    var count = 0;
    final cx = center.dx.round();
    final cy = center.dy.round();
    final span = radius.ceil();
    for (var dy = -span; dy <= span; dy++) {
      for (var dx = -span; dx <= span; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final color = colorAt(cx + dx, cy + dy);
        if (color == null || _isClear(color)) continue;
        r += color.r;
        g += color.g;
        b += color.b;
        count++;
      }
    }
    if (count == 0) return null;
    return ui.Color.from(
      alpha: 1,
      red: r / count,
      green: g / count,
      blue: b / count,
    );
  }

  /// How far apart two colours are, as the largest per-channel difference in
  /// 0..1. Zero for identical colours, one for black against white.
  static double colorDistance(ui.Color a, ui.Color b) => math.max(
    (a.r - b.r).abs(),
    math.max((a.g - b.g).abs(), (a.b - b.b).abs()),
  );

  /// The horizontal centre of mass of the covered pixels in a band of rows,
  /// or null when the band is empty.
  ///
  /// Useful for "the three cubes are in this left-to-right order" without
  /// caring exactly where each one landed.
  double? centroidXIn(ui.Rect region) {
    var sum = 0.0;
    var count = 0;
    final left = math.max(0, region.left.floor());
    final right = math.min(width, region.right.ceil());
    final top = math.max(0, region.top.floor());
    final bottom = math.min(height, region.bottom.ceil());
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (_isClear(colorAt(x, y)!)) continue;
        sum += x;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }
}
