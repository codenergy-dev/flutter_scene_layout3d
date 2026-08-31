import 'dart:collection';
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart' show TextStyle;

import 'glyph_atlas.dart';
import 'text_layout.dart';
import 'text_measurement.dart' show buildParagraph;

/// One glyph, placed: a rectangle in the text block and a rectangle in the
/// atlas.
///
/// The whole output of the geometry half, and deliberately nothing more than
/// eight numbers. Positions are **logical pixels** from the top-left of the
/// laid-out block, `y` downward, so a renderer multiplies by one scale and
/// has world units. Nothing here has touched the GPU, which is why the quad
/// builder can be tested headless while the mesh it feeds cannot.
class TextGlyphQuad3d {
  /// Records a placed glyph.
  const TextGlyphQuad3d({
    required this.grapheme,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.u0,
    required this.v0,
    required this.u1,
    required this.v1,
  });

  /// The grapheme cluster this quad draws.
  final String grapheme;

  /// The quad's edges, in logical pixels from the block's top-left.
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// The atlas rectangle it samples.
  final double u0;
  final double v0;
  final double u1;
  final double v1;

  /// The quad's width, in logical pixels.
  double get width => right - left;

  /// The quad's height, in logical pixels.
  double get height => bottom - top;

  @override
  String toString() =>
      'TextGlyphQuad3d("$grapheme" at ${left.toStringAsFixed(1)}, '
      '${top.toStringAsFixed(1)})';
}

/// Where each grapheme of one run sits along its line.
///
/// The layout knows where a *run* starts, because that is what it placed;
/// it does not know where the third letter of it starts, because it never
/// asked. This does, and it asks the font engine the accurate way — one
/// shaped paragraph per run, queried per grapheme — so the letters inside a
/// word carry the kerning the font specifies rather than the sum of their
/// isolated widths.
class ShapedRun3d {
  /// Records a shaped run.
  const ShapedRun3d(this.graphemes, this.offsets);

  /// The run's grapheme clusters, in order.
  final List<String> graphemes;

  /// Each grapheme's pen position, in logical pixels from the run's left
  /// edge.
  final List<double> offsets;

  /// How many graphemes the run has.
  int get length => graphemes.length;
}

/// Shapes runs, and remembers the ones it has shaped.
///
/// A run is a word, and words repeat: down a list, across a screen, between
/// frames. The cache is what keeps a scrolling list of labels from shaping
/// the same word once per frame; it is bounded the same way
/// [TextMeasurementCache3d] is, and for the same reason — dropping an entry
/// costs one paragraph to rebuild, never a wrong answer.
class TextRunShaper3d {
  /// Creates a shaper holding at most [capacity] runs.
  TextRunShaper3d({this.capacity = 512}) : assert(capacity > 0);

  /// The shaper every renderer shares unless it is given one of its own.
  static final TextRunShaper3d shared = TextRunShaper3d();

  /// How many shaped runs are kept before the least recently used goes.
  final int capacity;

  final LinkedHashMap<(String, TextStyle), ShapedRun3d> _entries =
      LinkedHashMap<(String, TextStyle), ShapedRun3d>();

  /// How many runs are cached.
  int get length => _entries.length;

  /// Forgets everything.
  void clear() => _entries.clear();

  /// [text] shaped at [style], from the cache when it has been seen before.
  ShapedRun3d shape(String text, TextStyle style) {
    final key = (text, style);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final shaped = _shape(text, style);
    _entries[key] = shaped;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return shaped;
  }

  ShapedRun3d _shape(String text, TextStyle style) {
    final graphemes = <String>[];
    final offsets = <double>[];
    if (text.isEmpty) return ShapedRun3d(graphemes, offsets);
    final paragraph = buildParagraph(text, style)
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    var start = 0;
    for (final grapheme in text.characters) {
      final end = start + grapheme.length;
      final boxes = paragraph.getBoxesForRange(start, end);
      graphemes.add(grapheme);
      // An empty box list is a grapheme the shaper folded into its
      // neighbour — a combining mark, half of a ligature. It draws at the
      // pen position the previous glyph left, which is where its base sits.
      offsets.add(
        boxes.isEmpty
            ? (offsets.isEmpty ? 0.0 : offsets.last)
            : boxes.first.left,
      );
      start = end;
    }
    paragraph.dispose();
    return ShapedRun3d(graphemes, offsets);
  }
}

/// Turns a laid-out block into one quad per glyph, reserving atlas space as
/// it goes.
///
/// Pure arithmetic over the layout, the shaper's answers and the atlas's
/// packing — no GPU, no mesh, no material. Everything is in logical pixels;
/// the caller applies [Text3dRenderRequest.unitsPerLogicalPixel] once.
///
/// Blank glyphs (spaces, and anything the atlas had no room for) are left
/// out rather than emitted as empty quads, so the count of quads is the
/// count of things that draw.
List<TextGlyphQuad3d> buildTextGlyphQuads({
  required TextLayout3d layout,
  required GlyphAtlas3d atlas,
  TextRunShaper3d? shaper,
}) {
  final runShaper = shaper ?? TextRunShaper3d.shared;
  final style = layout.prepared.style;
  final quads = <TextGlyphQuad3d>[];
  for (final line in layout.lines) {
    final baseline = line.baselineFromTop;
    for (final run in line.runs) {
      if (run.text.isEmpty) continue;
      final shaped = runShaper.shape(run.text, style);
      // A run's left is measured from the block, alignment included, so
      // there is nothing to add to it.
      final origin = run.left;
      for (var i = 0; i < shaped.length; i++) {
        final grapheme = shaped.graphemes[i];
        final slot = atlas.slotFor(grapheme);
        if (slot.isBlank) continue;
        final left = origin + shaped.offsets[i] + slot.left;
        final top = baseline + slot.top;
        quads.add(
          TextGlyphQuad3d(
            grapheme: grapheme,
            left: left,
            top: top,
            right: left + slot.width / atlas.scale,
            bottom: top + slot.height / atlas.scale,
            u0: slot.u0,
            v0: slot.v0,
            u1: slot.u1,
            v1: slot.v1,
          ),
        );
      }
    }
  }
  return quads;
}
