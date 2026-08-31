import 'dart:collection' show LinkedHashMap;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:characters/characters.dart' show CharacterRange;
import 'package:flutter/painting.dart' show TextAlign, TextDirection, TextStyle;

import 'break_rules.dart';
import 'line_break.dart';
import 'prepared_text.dart';
import 'text_layout.dart';

/// How many `ui.Paragraph` objects this library has built, in debug builds.
///
/// The whole design of this layer is a claim — that laying prepared text out
/// at a width consults the font zero times — and this is the instrument that
/// holds it to it. A test prepares a string, notes the count, lays the handle
/// out at a hundred different widths, and asserts the count has not moved. If
/// a change ever puts shaping back on the layout path, that test is where it
/// fails, loudly, instead of showing up as a frame-time regression a year
/// later.
///
/// Not kept in release builds, where the counter is never incremented.
int debugTextParagraphCount = 0;

/// What one measured string costs: its width, and the line box it sits in.
typedef TextMetrics3d = ({double width, double height, double baseline});

/// A bounded cache of measured strings, keyed by the text and the style.
///
/// The reason this pays is that UI text repeats. A list of labels shares its
/// words, a column of numbers shares its digits, and the single space between
/// two words is measured once for a whole application. The key is the pair
/// because a resolved [TextStyle] compares by value, so two boxes that ask
/// for the same 14sp body style hit the same entry.
///
/// Eviction is least-recently-used at [maximumEntries]. It is a cache, not a
/// registry: dropping an entry costs one `ui.Paragraph` to rebuild, never a
/// wrong answer.
class TextMeasurementCache3d {
  /// Creates a cache holding at most [maximumEntries] measurements.
  TextMeasurementCache3d({this.maximumEntries = 2048})
    : assert(maximumEntries > 0);

  /// How many measurements are kept before the oldest is dropped.
  final int maximumEntries;

  final LinkedHashMap<(String, TextStyle), TextMetrics3d> _entries =
      LinkedHashMap<(String, TextStyle), TextMetrics3d>();

  /// How many measurements are held.
  int get length => _entries.length;

  /// The measurement of [text] at [style], or null.
  ///
  /// A hit moves the entry to the front of the eviction order.
  TextMetrics3d? get(String text, TextStyle style) {
    final key = (text, style);
    final hit = _entries.remove(key);
    if (hit == null) return null;
    _entries[key] = hit;
    return hit;
  }

  /// Records the measurement of [text] at [style].
  void put(String text, TextStyle style, TextMetrics3d metrics) {
    _entries[(text, style)] = metrics;
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Forgets everything, for a test or a font change.
  void clear() => _entries.clear();
}

/// Turns a string into something the box protocol can size, in two phases.
///
/// **Prepare** is the expensive half and runs once per string: normalize the
/// whitespace, split the text where a line is allowed to end, and measure
/// each of those pieces with the platform's own font engine. **Layout** is
/// the cheap half and runs whenever the room changes: it fits the measured
/// pieces into a width, which for [SegmentedTextMeasurement3d] is arithmetic
/// and nothing else.
///
/// The split is not an optimization, it is what makes text usable in this
/// package at all. A box here is relaid out far more often than a Flutter
/// `RenderParagraph` is — whenever a scroll offset changes the room an item
/// gets, whenever the surface resizes, on every frame of an animation, and
/// *twice more* whenever an [IntrinsicWidth3d] above it asks its question,
/// because answering an intrinsic walks the whole subtree and then the
/// subtree is laid out again for real. Shaping on each of those would make
/// this package's own intrinsics unusable over labels.
///
/// The trade the fast policy makes is stated openly on
/// [SegmentedTextMeasurement3d]; [ParagraphTextMeasurement3d] is the exact
/// one to swap in where the trade does not hold.
abstract class TextMeasurement3d {
  /// Allows subclasses to be const.
  const TextMeasurement3d();

  /// Measures [text] at [style] under [rules], once.
  ///
  /// The returned handle belongs to this measurement and may only be laid out
  /// by it. Keep it for as long as the string, the style and the rules are
  /// unchanged; that is the whole point of it.
  PreparedText3d prepare(
    String text,
    TextStyle style, {
    TextBreakRules3d rules = TextBreakRules3d.standard,
  });

  /// Fits [prepared] into [maxWidth], in logical pixels.
  ///
  /// [minWidth] is the width the block is padded out to when the text is
  /// narrower, and it is what makes alignment mean anything: a centred label
  /// in a box 200 wide has to know the box is 200 wide, because on its own it
  /// shrink-wraps to the width of its longest line. It is the same pair
  /// `TextPainter.layout` takes, for the same reason.
  ///
  /// [truncateWidth] is the width an ellipsis is measured against, and
  /// defaults to [maxWidth]; they differ only when the text does not wrap
  /// (an infinite [maxWidth]) but still has to be cut to fit a box.
  /// [ellipsis] is what a truncated line ends with, or null to let it
  /// overflow.
  TextLayout3d layout(
    PreparedText3d prepared, {
    double minWidth = 0.0,
    double maxWidth = double.infinity,
    double? truncateWidth,
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
    int? maxLines,
    String? ellipsis,
  });

  /// Measures the graphemes of one segment of [prepared].
  ///
  /// Called by [PreparedText3d.graphemes] the first time a break has to fall
  /// inside a word. Not for general use.
  SegmentGraphemes3d measureGraphemes(PreparedText3d prepared, int segment);
}

/// The default measurement: measure each break-delimited piece once, then do
/// arithmetic.
///
/// **The trade, stated up front.** Adding per-segment widths is not the same
/// as shaping a whole line. Kerning and ligatures *across* a segment boundary
/// are not modelled, and neither is the joining behaviour of Arabic and
/// Indic scripts, where a letter's width depends on its neighbours. Segments
/// are word-like — they are exactly the places a line may end — so for Latin,
/// Greek, Cyrillic and CJK the error is nil or a fraction of a pixel, which
/// is why this is the default. For a connected script, or where the answer
/// has to agree with what Flutter's own text would do to the pixel, use
/// [ParagraphTextMeasurement3d].
///
/// A single instance can be shared by every box in an application, and
/// [shared] is that instance: the [cache] is the thing worth sharing, since
/// its hit rate is a function of how much text goes through it.
class SegmentedTextMeasurement3d extends TextMeasurement3d {
  /// Creates a measurement over its own [cache].
  SegmentedTextMeasurement3d({TextMeasurementCache3d? cache})
    : cache = cache ?? TextMeasurementCache3d();

  /// The instance every [Text3d] uses unless told otherwise.
  static final SegmentedTextMeasurement3d shared = SegmentedTextMeasurement3d();

  /// Where measured strings are kept.
  final TextMeasurementCache3d cache;

  /// Widths within this much of each other are the same width.
  ///
  /// A segment is measured on its own and a line is a sum of segments, so the
  /// comparison "does this still fit" accumulates floating-point error in
  /// proportion to the number of words on the line. Without a tolerance a
  /// line that fits exactly — which is the case a test writes, and the case
  /// a designer sets up on purpose — wraps one word early about half the
  /// time.
  static const double tolerance = 1e-6;

  @override
  PreparedText3d prepare(
    String text,
    TextStyle style, {
    TextBreakRules3d rules = TextBreakRules3d.standard,
  }) {
    final segmented = segmentText(text, rules);
    final source = segmented.text;
    final space = _measure(' ', style);
    // The line box comes from a probe rather than from the content, the same
    // way `TextPainter.preferredLineHeight` does, so that an empty label and
    // a full one are the same height. A run whose fallback font is taller
    // than the primary one widens the box, which the loop below picks up.
    var line = space;
    final segments = <TextSegment3d>[];
    var minIntrinsic = 0.0;
    var maxIntrinsic = 0.0;
    var run = 0.0;
    var hardLines = 1;
    for (final raw in segmented.segments) {
      final visible = source.substring(raw.start, raw.visibleEnd);
      final metrics = _measure(visible, style);
      if (metrics.height > line.height) line = metrics;
      // A tab is a fixed advance of `tabSize` spaces, so the measured width
      // of the whitespace run has the tabs' own glyph widths taken back out.
      final whitespace =
          _measure(source.substring(raw.visibleEnd, raw.end), style).width +
          raw.tabCount * (rules.tabSize - 1) * space.width;
      segments.add(
        TextSegment3d(
          start: raw.start,
          visibleEnd: raw.visibleEnd,
          end: raw.end,
          width: metrics.width,
          whitespaceWidth: whitespace,
          breakAfter: raw.breakAfter,
        ),
      );
      minIntrinsic = math.max(minIntrinsic, metrics.width);
      run += metrics.width;
      if (raw.breakAfter == TextBreak3d.mandatory) {
        maxIntrinsic = math.max(maxIntrinsic, run);
        run = 0.0;
        hardLines++;
      } else {
        run += whitespace;
      }
    }
    maxIntrinsic = math.max(maxIntrinsic, run);
    return PreparedText3d(
      owner: this,
      source: text,
      text: source,
      style: style,
      rules: rules,
      segments: segments,
      lineHeight: line.height,
      baseline: line.baseline,
      spaceWidth: space.width,
      hyphenWidth: _measure('-', style).width,
      ellipsisWidth: _measure('…', style).width,
      minIntrinsicWidth: minIntrinsic,
      maxIntrinsicWidth: maxIntrinsic,
      hardLineCount: hardLines,
    );
  }

  @override
  SegmentGraphemes3d measureGraphemes(PreparedText3d prepared, int segment) {
    final piece = prepared.segments[segment];
    final text = prepared.text.substring(piece.start, piece.visibleEnd);
    final offsets = <int>[piece.start];
    final widths = <double>[];
    final range = CharacterRange(text);
    while (range.moveNext()) {
      widths.add(_measure(range.current, prepared.style).width);
      offsets.add(
        piece.start + range.stringBeforeLength + range.current.length,
      );
    }
    return SegmentGraphemes3d(offsets, widths);
  }

  @override
  TextLayout3d layout(
    PreparedText3d prepared, {
    double minWidth = 0.0,
    double maxWidth = double.infinity,
    double? truncateWidth,
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
    int? maxLines,
    String? ellipsis,
  }) {
    assert(
      identical(prepared.owner, this),
      'A PreparedText3d may only be laid out by the measurement that '
      'prepared it.',
    );
    assert(maxWidth >= 0.0 && minWidth >= 0.0 && minWidth <= maxWidth);
    assert(maxLines == null || maxLines > 0);
    final lines = _breakLines(prepared, maxWidth, maxLines);
    final exceeded = maxLines != null && lines.length > maxLines;
    if (exceeded) lines.removeRange(maxLines, lines.length);
    if (ellipsis != null) {
      _applyEllipsis(
        prepared,
        lines,
        ellipsis,
        truncateWidth ?? maxWidth,
        truncated: exceeded,
      );
    }
    var longest = 0.0;
    for (final line in lines) {
      longest = math.max(longest, line.width);
    }
    return _assemble(
      prepared: prepared,
      lines: lines,
      maxWidth: maxWidth,
      blockWidth: blockWidth(
        prepared,
        minWidth,
        math.min(maxWidth, truncateWidth ?? maxWidth),
      ),
      longestLine: longest,
      textAlign: textAlign,
      textDirection: textDirection,
      didExceedMaxLines: exceeded,
    );
  }

  /// Greedy line breaking over the prepared segments.
  ///
  /// One pass, no backtracking: take segments until the next one does not
  /// fit, then start a line. Knuth–Plass would be a second strategy over the
  /// same handle — the prepared widths are all it needs — and is not here
  /// because nothing in a component catalogue has asked for it.
  ///
  /// The one rule that is not obvious is what happens to a word wider than
  /// the whole line. Under [OverflowWrap3d.breakWord] it is packed into
  /// whatever room is left *on the current line*, not pushed to a line of its
  /// own first — so a line that begins mid-word carries on into the next word
  /// by graphemes as well. That is what Flutter's own text engine does, and
  /// it is the difference between agreeing with a `TextPainter` at narrow
  /// widths and being one line out.
  ///
  /// [lineBudget] stops the walk one line past the limit, which is all a
  /// caller needs to know that it was exceeded.
  List<_PendingLine> _breakLines(
    PreparedText3d prepared,
    double maxWidth,
    int? lineBudget,
  ) {
    final segments = prepared.segments;
    final breakWord = prepared.rules.overflowWrap == OverflowWrap3d.breakWord;
    final lines = <_PendingLine>[];
    var index = 0;
    // How far into segment [index] the last line got, for a word being
    // carried across lines a grapheme at a time.
    var grapheme = 0;
    while (index < segments.length) {
      final runs = <TextRun3d>[];
      var lineStart = grapheme > 0
          ? prepared.graphemes(index).offsets[grapheme]
          : segments[index].start;
      var cursor = 0.0;
      var content = 0.0;
      var end = lineStart;
      var hard = false;
      var hyphenate = false;
      while (index < segments.length) {
        final segment = segments[index];
        final pieces = grapheme > 0 ? prepared.graphemes(index) : null;
        final remaining = pieces == null
            ? segment.width
            : _sumFrom(pieces.widths, grapheme);
        // A segment a line may end after has to leave room for the hyphen
        // that ending there would draw.
        final cost =
            remaining + (segment.hyphenates ? prepared.hyphenWidth : 0.0);
        final fitsHere = cursor + cost <= maxWidth + tolerance;
        final fitsAlone = remaining <= maxWidth + tolerance;
        if (!fitsHere && breakWord && !fitsAlone && !segment.isEmpty) {
          final graphemes = prepared.graphemes(index);
          var taken = 0;
          var width = 0.0;
          while (grapheme + taken < graphemes.length) {
            final next = width + graphemes.widths[grapheme + taken];
            if (next > maxWidth - cursor + tolerance &&
                (taken > 0 || runs.isNotEmpty)) {
              break;
            }
            width = next;
            taken++;
          }
          if (taken == 0) break;
          final from = graphemes.offsets[grapheme];
          final to = graphemes.offsets[grapheme + taken];
          runs.add(
            TextRun3d(
              start: from,
              end: to,
              text: prepared.text.substring(from, to),
              left: cursor,
              width: width,
            ),
          );
          if (runs.length == 1) lineStart = from;
          content = cursor + width;
          end = to;
          grapheme += taken;
          if (grapheme < graphemes.length) break;
          // The word ran out exactly here, so the segment is finished and the
          // line may still take what follows it.
          cursor = content + segment.whitespaceWidth;
          index++;
          grapheme = 0;
          if (segment.breakAfter == TextBreak3d.mandatory) {
            hard = true;
            break;
          }
          if (segment.breakAfter == TextBreak3d.none) break;
          continue;
        }
        if (!fitsHere && runs.isNotEmpty) {
          hyphenate = index > 0 && segments[index - 1].hyphenates;
          break;
        }
        final from = pieces == null ? segment.start : pieces.offsets[grapheme];
        if (from < segment.visibleEnd) {
          runs.add(
            TextRun3d(
              start: from,
              end: segment.visibleEnd,
              text: prepared.text.substring(from, segment.visibleEnd),
              left: cursor,
              width: remaining,
            ),
          );
        }
        content = cursor + remaining;
        end = segment.visibleEnd;
        cursor = content + segment.whitespaceWidth;
        index++;
        grapheme = 0;
        if (segment.breakAfter == TextBreak3d.mandatory) {
          hard = true;
          break;
        }
        if (segment.breakAfter == TextBreak3d.none) break;
      }
      if (hyphenate && prepared.hyphenWidth > 0.0) {
        runs.add(
          TextRun3d(
            start: end,
            end: end,
            text: '-',
            left: content,
            width: prepared.hyphenWidth,
          ),
        );
        content += prepared.hyphenWidth;
      }
      lines.add(
        _PendingLine(
          start: lineStart,
          end: end,
          runs: runs,
          width: content,
          hardBreak: hard,
        ),
      );
      if (lineBudget != null && lines.length > lineBudget) return lines;
    }
    if (lines.isEmpty) {
      lines.add(
        const _PendingLine(
          start: 0,
          end: 0,
          runs: <TextRun3d>[],
          width: 0.0,
          hardBreak: false,
        ),
      );
    }
    return lines;
  }

  /// Cuts every line that does not fit [limit] and marks it with [ellipsis].
  ///
  /// Runs are dropped from the end of the line, and the last one that
  /// survives is cut at a grapheme boundary if it still does not fit. This is
  /// the one path in the layout half that can reach the font, and only the
  /// first time a given word has to be cut.
  void _applyEllipsis(
    PreparedText3d prepared,
    List<_PendingLine> lines,
    String ellipsis,
    double limit, {
    required bool truncated,
  }) {
    final ellipsisWidth = ellipsis == '…'
        ? prepared.ellipsisWidth
        : _measure(ellipsis, prepared.style).width;
    if (!limit.isFinite) {
      // Nothing to cut against, but a line limit still dropped text and the
      // reader has to be told. Mark the last line and leave its width alone.
      if (truncated) {
        lines.last = lines.last.withEllipsis(
          ellipsis,
          ellipsisWidth,
          lines.last.width,
        );
      }
      return;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final last = i == lines.length - 1;
      final overflows = line.width > limit + tolerance;
      if (!overflows && !(last && truncated)) continue;
      if (!overflows && line.width + ellipsisWidth <= limit + tolerance) {
        lines[i] = line.withEllipsis(ellipsis, ellipsisWidth, line.width);
        continue;
      }
      final target = limit - ellipsisWidth;
      final runs = <TextRun3d>[];
      var width = 0.0;
      for (final run in line.runs) {
        if (run.isSynthetic) continue;
        if (run.left + run.width <= target + tolerance) {
          runs.add(run);
          width = run.left + run.width;
          continue;
        }
        // The run straddles the cut: keep the graphemes that fit.
        final kept = _cutRun(prepared, run, target - run.left);
        if (kept != null) {
          runs.add(kept);
          width = kept.left + kept.width;
        }
        break;
      }
      lines[i] = _PendingLine(
        start: line.start,
        end: runs.isEmpty ? line.start : runs.last.end,
        runs: runs,
        width: width,
        hardBreak: line.hardBreak,
      ).withEllipsis(ellipsis, ellipsisWidth, width);
    }
  }

  /// [run], shortened to at most [width], or null if not one grapheme fits.
  TextRun3d? _cutRun(PreparedText3d prepared, TextRun3d run, double width) {
    if (width <= 0.0) return null;
    var kept = 0;
    var taken = 0.0;
    final range = CharacterRange(run.text);
    while (range.moveNext()) {
      final piece = _measure(range.current, prepared.style).width;
      if (taken + piece > width + tolerance) break;
      taken += piece;
      kept = range.stringBeforeLength + range.current.length;
    }
    if (kept == 0) return null;
    return TextRun3d(
      start: run.start,
      end: run.start + kept,
      text: run.text.substring(0, kept),
      left: run.left,
      width: taken,
    );
  }

  /// Positions the broken lines: alignment across, line height down.
  TextLayout3d _assemble({
    required PreparedText3d prepared,
    required List<_PendingLine> lines,
    required double maxWidth,
    required double blockWidth,
    required double longestLine,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required bool didExceedMaxLines,
  }) {
    final height = prepared.lineHeight;
    final resolved = _resolveAlign(textAlign, textDirection);
    final placed = <TextLine3d>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final slack = math.max(0.0, blockWidth - line.width);
      final lastOfParagraph = line.hardBreak || i == lines.length - 1;
      var left = 0.0;
      var runs = line.runs;
      var width = line.width;
      switch (resolved) {
        case TextAlign.right:
          left = slack;
        case TextAlign.center:
          left = slack / 2.0;
        case TextAlign.justify:
          if (!lastOfParagraph && line.runs.length > 1 && slack > 0.0) {
            final gap = slack / (line.runs.length - 1);
            runs = <TextRun3d>[
              for (var r = 0; r < line.runs.length; r++)
                _shifted(line.runs[r], r * gap),
            ];
            width = blockWidth;
          }
        case TextAlign.left:
        case TextAlign.start:
        case TextAlign.end:
          break;
      }
      // A run's left is measured from the block, not from its line, which is
      // the contract a renderer needs: a glyph's place on the panel cannot
      // depend on which of the two measurement policies produced it, and the
      // exact one reports platform line boxes that are already absolute.
      if (left != 0.0) {
        runs = <TextRun3d>[for (final run in runs) _shifted(run, left)];
      }
      placed.add(
        TextLine3d(
          start: line.start,
          end: line.end,
          runs: runs,
          left: left,
          width: width,
          top: i * height,
          height: height,
          baseline: prepared.baseline,
          hardBreak: line.hardBreak,
        ),
      );
    }
    return TextLayout3d(
      prepared: prepared,
      maxWidth: maxWidth,
      lines: placed,
      width: blockWidth,
      longestLine: longestLine,
      height: placed.length * height,
      didExceedMaxLines: didExceedMaxLines,
    );
  }

  TextMetrics3d _measure(String text, TextStyle style) {
    if (text.isEmpty) {
      final blank = cache.get(' ', style);
      if (blank != null) {
        return (width: 0.0, height: blank.height, baseline: blank.baseline);
      }
    }
    final hit = cache.get(text, style);
    if (hit != null) return hit;
    final metrics = measureString(text, style);
    cache.put(text, style, metrics);
    return metrics;
  }
}

/// The exact measurement: hand every layout back to the platform.
///
/// One `ui.Paragraph` per layout call, with the platform's own line breaking,
/// shaping and bidi. It is what [SegmentedTextMeasurement3d] approximates,
/// and it is here for the two cases where the approximation does not hold: a
/// connected script (Arabic, Devanagari, Thai), and text whose measurements
/// have to agree with a Flutter `Text` to the pixel.
///
/// The cost is the thing the two-phase design exists to avoid, so reach for
/// it per box rather than globally: a `Text3d` on a scrolling list re-lays out
/// whenever its room changes, and each of those is a shaping pass. The
/// handle from [prepare] still caches the intrinsics and the line box, so
/// [Layout3d.getMinIntrinsicExtent] and the baseline stay free either way.
class ParagraphTextMeasurement3d extends TextMeasurement3d {
  /// Creates an exact measurement.
  const ParagraphTextMeasurement3d();

  @override
  PreparedText3d prepare(
    String text,
    TextStyle style, {
    TextBreakRules3d rules = TextBreakRules3d.standard,
  }) {
    // The rules still decide normalization — the platform does not collapse
    // whitespace — but the segmentation is thrown away, because the platform
    // breaks its own lines.
    final segmented = segmentText(text, rules);
    var hardLines = 1;
    for (final raw in segmented.segments) {
      if (raw.breakAfter == TextBreak3d.mandatory) hardLines++;
    }
    final paragraph = buildParagraph(segmented.text, style)
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final prepared = PreparedText3d(
      owner: this,
      source: text,
      text: segmented.text,
      style: style,
      rules: rules,
      segments: const <TextSegment3d>[],
      lineHeight: paragraph.height / hardLines,
      baseline: paragraph.alphabeticBaseline,
      spaceWidth: measureString(' ', style).width,
      hyphenWidth: measureString('-', style).width,
      ellipsisWidth: measureString('…', style).width,
      minIntrinsicWidth: paragraph.minIntrinsicWidth,
      maxIntrinsicWidth: paragraph.maxIntrinsicWidth,
      hardLineCount: hardLines,
    );
    paragraph.dispose();
    return prepared;
  }

  @override
  SegmentGraphemes3d measureGraphemes(PreparedText3d prepared, int segment) =>
      const SegmentGraphemes3d(<int>[], <double>[]);

  @override
  TextLayout3d layout(
    PreparedText3d prepared, {
    double minWidth = 0.0,
    double maxWidth = double.infinity,
    double? truncateWidth,
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
    int? maxLines,
    String? ellipsis,
  }) {
    assert(identical(prepared.owner, this));
    assert(maxWidth >= 0.0 && minWidth >= 0.0 && minWidth <= maxWidth);
    // The block's width decides where alignment puts a line, so the paragraph
    // is laid out at that width rather than at the offered maximum. Breaking
    // is unaffected: the two differ only when the text already fits.
    final target = maxWidth.isFinite
        ? blockWidth(prepared, minWidth, maxWidth)
        : double.infinity;
    final paragraph = buildParagraph(
      prepared.text,
      prepared.style,
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      ellipsis: ellipsis,
    )..layout(ui.ParagraphConstraints(width: target));
    final metrics = paragraph.computeLineMetrics();
    final lines = <TextLine3d>[];
    var longest = 0.0;
    var cursor = 0;
    for (final line in metrics) {
      final boundary = paragraph.getLineBoundary(
        ui.TextPosition(offset: math.min(cursor, prepared.text.length)),
      );
      final start = boundary.start < 0 ? cursor : boundary.start;
      final end = boundary.end < 0 ? prepared.text.length : boundary.end;
      final text = prepared.text.substring(start, end).trimRight();
      lines.add(
        TextLine3d(
          start: start,
          end: start + text.length,
          runs: <TextRun3d>[
            if (text.isNotEmpty)
              TextRun3d(
                start: start,
                end: start + text.length,
                text: text,
                left: line.left,
                width: line.width,
              ),
          ],
          left: line.left,
          width: line.width,
          top: line.baseline - line.ascent,
          height: line.height,
          baseline: line.ascent,
          hardBreak: end < prepared.text.length || line.hardBreak,
        ),
      );
      longest = math.max(longest, line.width);
      cursor = end > cursor ? end : cursor + 1;
    }
    final height = paragraph.height;
    final exceeded = paragraph.didExceedMaxLines;
    final width = maxWidth.isFinite ? target : longest;
    paragraph.dispose();
    if (lines.isEmpty) {
      lines.add(
        TextLine3d(
          start: 0,
          end: 0,
          runs: const <TextRun3d>[],
          left: 0.0,
          width: 0.0,
          top: 0.0,
          height: prepared.lineHeight,
          baseline: prepared.baseline,
          hardBreak: false,
        ),
      );
    }
    return TextLayout3d(
      prepared: prepared,
      maxWidth: maxWidth,
      lines: lines,
      width: width,
      longestLine: longest,
      height: height,
      didExceedMaxLines: exceeded,
    );
  }
}

/// Measures [text] at [style] with the platform's font engine.
///
/// The single-segment paragraph laid out at infinite width that the whole
/// prepare phase is built out of. [ui.Paragraph.maxIntrinsicWidth] rather
/// than the laid-out width, because the latter is the constraint it was given
/// and this one asked for no constraint at all.
TextMetrics3d measureString(String text, TextStyle style) {
  final paragraph = buildParagraph(text, style)
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
  final metrics = (
    width: paragraph.maxIntrinsicWidth,
    height: paragraph.height,
    baseline: paragraph.alphabeticBaseline,
  );
  paragraph.dispose();
  return metrics;
}

/// Builds a single-style paragraph over [text].
///
/// The text scale is deliberately left at 1: everything in this layer is
/// measured in logical pixels at the style's own font size, and
/// [Layout3dMetrics.textScaleFactor] is applied once, as a scale, when the
/// layout reaches world units. Font metrics are linear in the size, so the
/// two are the same thing, and doing it this way keeps a prepared handle
/// valid across a change of accessibility scale.
ui.Paragraph buildParagraph(
  String text,
  TextStyle style, {
  TextAlign? textAlign,
  TextDirection textDirection = TextDirection.ltr,
  int? maxLines,
  String? ellipsis,
}) {
  assert(() {
    debugTextParagraphCount++;
    return true;
  }());
  final builder = ui.ParagraphBuilder(
    style.getParagraphStyle(
      textAlign: textAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      ellipsis: ellipsis,
    ),
  )..pushStyle(style.getTextStyle());
  if (text.isNotEmpty) builder.addText(text);
  return builder.build();
}

/// The width the block reports, which is not always its longest line.
///
/// Text that wraps fills the width it was offered — which is why a wrapping
/// `Text` in a column takes the whole column — and text that does not wrap
/// shrinks to what it needs, but never below a minimum the parent insisted
/// on. A word too wide to break is the case where the two part company: the
/// block reports the width it was given and the glyphs are what overflow,
/// which is Flutter's answer as well.
///
/// [limit] is the narrower of the wrap width and the width an ellipsis cuts
/// to, so that a single unwrapped line that has been truncated reports the
/// room it was truncated into rather than the width it would have wanted.
double blockWidth(PreparedText3d prepared, double minWidth, double limit) =>
    math.max(minWidth, math.min(prepared.maxIntrinsicWidth, limit));

TextAlign _resolveAlign(TextAlign align, TextDirection direction) =>
    switch (align) {
      TextAlign.start =>
        direction == TextDirection.rtl ? TextAlign.right : TextAlign.left,
      TextAlign.end =>
        direction == TextDirection.rtl ? TextAlign.left : TextAlign.right,
      _ => align,
    };

TextRun3d _shifted(TextRun3d run, double by) => TextRun3d(
  start: run.start,
  end: run.end,
  text: run.text,
  left: run.left + by,
  width: run.width,
);

double _sumFrom(List<double> values, int start) {
  var total = 0.0;
  for (var i = start; i < values.length; i++) {
    total += values[i];
  }
  return total;
}

/// A line while it is still being built: no vertical position, no alignment.
class _PendingLine {
  const _PendingLine({
    required this.start,
    required this.end,
    required this.runs,
    required this.width,
    required this.hardBreak,
  });

  final int start;
  final int end;
  final List<TextRun3d> runs;
  final double width;
  final bool hardBreak;

  _PendingLine withEllipsis(String text, double width, double at) =>
      _PendingLine(
        start: start,
        end: end,
        runs: <TextRun3d>[
          ...runs,
          TextRun3d(start: end, end: end, text: text, left: at, width: width),
        ],
        width: at + width,
        hardBreak: hardBreak,
      );
}
