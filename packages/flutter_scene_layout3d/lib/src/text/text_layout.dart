import 'prepared_text.dart';

/// A stretch of drawable text on one line, at a known offset.
///
/// The unit a renderer draws and a hit test resolves against. A greedy layout
/// produces one run per segment placed on the line, which is what makes
/// justification (extra space *between* runs) and a cursor position inside a
/// line expressible without re-measuring anything.
///
/// [left] and [width] are in logical pixels, measured from the left edge of
/// the laid-out block.
class TextRun3d {
  /// Creates a positioned run.
  const TextRun3d({
    required this.start,
    required this.end,
    required this.text,
    required this.left,
    required this.width,
  });

  /// Where the run begins in [PreparedText3d.text].
  ///
  /// Equal to [end] for a run that is not in the source at all: the hyphen a
  /// soft-hyphen break draws, and the ellipsis that marks a truncation.
  final int start;

  /// Where it ends there.
  final int end;

  /// What the run draws.
  final String text;

  /// The run's left edge, in logical pixels from the block's left edge.
  final double left;

  /// The run's width, in logical pixels.
  final double width;

  /// Whether the run draws something that is not in the source text.
  bool get isSynthetic => start == end;

  @override
  String toString() =>
      'TextRun3d("$text" at ${left.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}px)';
}

/// One laid-out line.
///
/// Everything is in logical pixels, measured from the top-left of the block.
class TextLine3d {
  /// Creates a laid-out line.
  const TextLine3d({
    required this.start,
    required this.end,
    required this.runs,
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.baseline,
    required this.hardBreak,
  });

  /// Where the line's text begins in [PreparedText3d.text].
  final int start;

  /// Where it ends, not counting the whitespace hanging past the wrap width.
  final int end;

  /// The runs on this line, left to right.
  final List<TextRun3d> runs;

  /// The line's left edge, which is where alignment put it.
  final double left;

  /// The width of the drawable content, not counting hanging whitespace.
  final double width;

  /// The line's top edge, measured from the top of the block.
  final double top;

  /// The line's height.
  final double height;

  /// How far below [top] the line's alphabetic baseline sits.
  final double baseline;

  /// Whether the line ended because the text said so rather than because it
  /// ran out of room.
  final bool hardBreak;

  /// The baseline's distance from the top of the block.
  double get baselineFromTop => top + baseline;

  @override
  String toString() =>
      'TextLine3d($start..$end, ${width.toStringAsFixed(1)}px at '
      '${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)})';
}

/// A string laid out at a width: the answer the box protocol needs.
///
/// Produced by [TextMeasurement3d.layout], and, for the segmented policy,
/// produced without touching the font at all. Every extent is in logical
/// pixels; a [Text3d] scales the whole thing by
/// `metrics.unitsPerLogicalPixel * metrics.textScaleFactor` on the way into
/// world units.
class TextLayout3d {
  /// Records a laid-out string.
  const TextLayout3d({
    required this.prepared,
    required this.maxWidth,
    required this.lines,
    required this.width,
    required this.longestLine,
    required this.height,
    required this.didExceedMaxLines,
  });

  /// The handle this layout came from.
  final PreparedText3d prepared;

  /// The width the text was broken at, which may be infinite.
  final double maxWidth;

  /// The lines, top to bottom. Never empty: a string with nothing in it lays
  /// out as one empty line, exactly as an empty `Text` is one line tall.
  final List<TextLine3d> lines;

  /// The block's width, in logical pixels.
  ///
  /// The width Flutter's own text reports, and it is not always the longest
  /// line: text that wraps fills the width it was offered, which is why a
  /// wrapping `Text` in a column takes the whole column. It is
  /// [longestLine] only when the text fits without wrapping.
  final double width;

  /// The width of the widest line, in logical pixels.
  final double longestLine;

  /// The block's height, in logical pixels.
  final double height;

  /// Whether lines were dropped to honour a line limit.
  final bool didExceedMaxLines;

  /// How far below the top of the block the first line's baseline sits.
  double get firstBaseline => lines.first.baselineFromTop;

  /// How far below the top of the block the last line's baseline sits.
  double get lastBaseline => lines.last.baselineFromTop;

  /// How many lines the text took.
  int get lineCount => lines.length;

  @override
  String toString() =>
      'TextLayout3d(${lines.length} lines, ${width.toStringAsFixed(1)} x '
      '${height.toStringAsFixed(1)}px)';
}
