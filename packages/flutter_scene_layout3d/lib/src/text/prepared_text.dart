import 'package:flutter/painting.dart' show TextStyle;

import 'break_rules.dart';
import 'line_break.dart';
import 'text_measurement.dart';

/// One atom of line breaking, measured.
///
/// A segment is the run of text between two places a line may end, plus the
/// whitespace that trails it. [width] is what a line pays to take it;
/// [whitespaceWidth] is what it pays only if something follows on the same
/// line, because trailing whitespace hangs past the wrap width rather than
/// forcing a break.
///
/// Every extent here is in **logical pixels**, at the font size the style
/// asked for and with no text scaling applied. That is what makes the handle
/// worth caching: the world-unit size of the same text at a different
/// [Layout3dMetrics] is the same numbers times a different scale, and nothing
/// has to be measured again.
class TextSegment3d {
  /// Creates a measured segment.
  const TextSegment3d({
    required this.start,
    required this.visibleEnd,
    required this.end,
    required this.width,
    required this.whitespaceWidth,
    required this.breakAfter,
  });

  /// Where the segment begins in [PreparedText3d.text].
  final int start;

  /// Where its drawable part ends, before the trailing whitespace.
  final int visibleEnd;

  /// Where it ends, after the trailing whitespace.
  final int end;

  /// The width of the drawable part, in logical pixels.
  final double width;

  /// The width of the trailing whitespace, in logical pixels.
  final double whitespaceWidth;

  /// How a line may end after this segment.
  final TextBreak3d breakAfter;

  /// Whether the segment draws nothing at all.
  bool get isEmpty => visibleEnd == start;

  /// Whether a line that ends here must draw a hyphen.
  bool get hyphenates => breakAfter == TextBreak3d.hyphen;

  @override
  String toString() =>
      'TextSegment3d($start..$end, ${width.toStringAsFixed(1)}px, '
      '$breakAfter)';
}

/// The grapheme clusters of one segment, with their widths.
///
/// What [OverflowWrap3d.breakWord] breaks a too-wide word on. Graphemes
/// rather than code units or runes, because a family emoji, an accented
/// letter written as a base plus a combining mark, and a Devanagari
/// consonant cluster are each one thing a break must not fall inside.
class SegmentGraphemes3d {
  /// Records a segment's graphemes.
  const SegmentGraphemes3d(this.offsets, this.widths);

  /// The boundaries between graphemes, in [PreparedText3d.text] offsets.
  ///
  /// One longer than [widths]: the first entry is where the segment's
  /// drawable part begins and the last is where it ends.
  final List<int> offsets;

  /// Each grapheme's width, in logical pixels.
  final List<double> widths;

  /// How many graphemes the segment has.
  int get length => widths.length;
}

/// A string that has been segmented and measured, ready to be laid out at any
/// width without consulting the font again.
///
/// This is the handle the whole design turns on. Preparing a string is the
/// expensive half — segmentation, then one `ui.Paragraph` per distinct
/// segment — and it depends on the text, the style and the
/// [TextBreakRules3d], none of which change when a box is relaid out. Laying
/// the prepared handle out at a width is arithmetic over [segments], so a
/// scroll offset that changes how much room a label gets, a surface that
/// resizes, an animation that dirties layout every frame, and the two extra
/// walks an [IntrinsicWidth3d] costs all become free of shaping.
///
/// Do not build one directly: [TextMeasurement3d.prepare] does, and a handle
/// only means anything to the measurement that produced it.
///
/// Everything on it is in **logical pixels**. A [Text3d] multiplies by
/// `metrics.unitsPerLogicalPixel * metrics.textScaleFactor` on the way out,
/// which is exactly equivalent to having asked for a bigger font, because
/// font metrics are linear in the size.
class PreparedText3d {
  /// Records a measured string. Called by a [TextMeasurement3d].
  PreparedText3d({
    required this.owner,
    required this.source,
    required this.text,
    required this.style,
    required this.rules,
    required this.segments,
    required this.lineHeight,
    required this.baseline,
    required this.spaceWidth,
    required this.hyphenWidth,
    required this.ellipsisWidth,
    required this.minIntrinsicWidth,
    required this.maxIntrinsicWidth,
    required this.hardLineCount,
  });

  /// The measurement that produced this handle.
  ///
  /// A handle carries the assumptions of the policy that built it — an
  /// exact one has no segments to lay out from — so the two halves of the
  /// split have to be kept together.
  final TextMeasurement3d owner;

  /// The string the caller passed to [TextMeasurement3d.prepare].
  final String source;

  /// The normalized string the offsets in [segments] index into.
  ///
  /// Not [source]: soft hyphens and zero-width spaces have been removed
  /// (they are recorded as break opportunities instead), and under
  /// [TextWhitespace3d.collapse] runs of whitespace have been squeezed to
  /// one space. This is the string a renderer draws and a hit test resolves
  /// against.
  final String text;

  /// The style every segment was measured at.
  final TextStyle style;

  /// The policy the text was segmented under.
  final TextBreakRules3d rules;

  /// The atoms of line breaking, in order, covering [text] end to end.
  ///
  /// Empty for a handle from [ParagraphTextMeasurement3d], which does not
  /// break lines itself.
  final List<TextSegment3d> segments;

  /// The height of one line, in logical pixels.
  final double lineHeight;

  /// How far below the top of a line its alphabetic baseline sits, in logical
  /// pixels.
  final double baseline;

  /// The width of a single space, in logical pixels.
  final double spaceWidth;

  /// The width of the hyphen drawn where a soft-hyphen break is taken.
  final double hyphenWidth;

  /// The width of the ellipsis drawn where the text is truncated.
  final double ellipsisWidth;

  /// The width of the widest thing that cannot be broken, in logical pixels.
  ///
  /// The narrowest a box can be without a word standing outside it, and so
  /// the answer to [Layout3d.getMinIntrinsicExtent] along the horizontal.
  final double minIntrinsicWidth;

  /// The width the text would take on one line per hard break, in logical
  /// pixels.
  ///
  /// The widest a box can usefully be, and so the answer to
  /// [Layout3d.getMaxIntrinsicExtent] along the horizontal.
  final double maxIntrinsicWidth;

  /// How many lines the text has before any wrapping, counting hard breaks.
  final int hardLineCount;

  /// Whether this handle carries segments a greedy line breaker can use.
  bool get isSegmented => segments.isNotEmpty;

  /// Whether the text draws nothing at all.
  bool get isEmpty => text.isEmpty;

  /// The character between [start] and [end] of [text].
  String substring(int start, int end) => text.substring(start, end);

  final Map<int, SegmentGraphemes3d> _graphemes = <int, SegmentGraphemes3d>{};

  /// The grapheme clusters of segment [index] and their widths, measured on
  /// first use and kept afterwards.
  ///
  /// The one thing on this handle that is not resolved by
  /// [TextMeasurement3d.prepare], and deliberately: it is needed only by
  /// [OverflowWrap3d.breakWord], and only for the segments that actually turn
  /// out to be too wide for the room they are given. Measuring every grapheme
  /// of every string up front would cost a `ui.Paragraph` per character for a
  /// policy most text never exercises. The first layout narrow enough to need
  /// one pays for it; every layout after that is arithmetic again.
  SegmentGraphemes3d graphemes(int index) =>
      _graphemes[index] ??= owner.measureGraphemes(this, index);

  @override
  String toString() =>
      'PreparedText3d(${segments.length} segments of '
      '${text.length} code units)';
}
