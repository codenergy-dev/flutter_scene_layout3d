// The measurement half of text: preparing a string once, then fitting it to a
// width without consulting the font again.
//
// Everything here is in logical pixels, which is the frame the measurement
// layer works in. The test font ("FlutterTest") makes every glyph exactly
// `fontSize` wide with a line `fontSize` tall and its baseline at 0.75 of
// that, so an expected number is a character count times a size rather than a
// magic constant.

import 'package:flutter/painting.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle style = TextStyle(fontSize: 10);

/// The text of each line, with whatever synthetic run (a hyphen, an
/// ellipsis) the break added at the end of it.
List<String> linesOf(TextLayout3d layout) => <String>[
  for (final line in layout.lines)
    layout.prepared.text.substring(line.start, line.end) +
        line.runs.where((run) => run.isSynthetic).map((run) => run.text).join(),
];

/// Flutter's own answer for the same string at the same width.
TextPainter ground(String text, {double maxWidth = double.infinity}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

void main() {
  late SegmentedTextMeasurement3d measurement;

  setUp(() => measurement = SegmentedTextMeasurement3d());

  group('prepare', () {
    test('splits at the places a line may end, and measures each', () {
      final prepared = measurement.prepare('hello world', style);
      expect(prepared.segments, hasLength(2));
      expect(prepared.segments.first.width, 50);
      expect(prepared.segments.first.whitespaceWidth, 10);
      expect(prepared.segments.first.breakAfter, TextBreak3d.opportunity);
      expect(prepared.segments.last.width, 50);
      expect(prepared.segments.last.whitespaceWidth, 0);
      expect(prepared.segments.last.breakAfter, TextBreak3d.none);
    });

    test('reports the line box, which does not depend on the content', () {
      final full = measurement.prepare('Hgjq', style);
      final empty = measurement.prepare('', style);
      expect(full.lineHeight, 10);
      expect(full.baseline, 7.5);
      expect(empty.lineHeight, full.lineHeight);
      expect(empty.baseline, full.baseline);
    });

    test('intrinsics are the widest word and the whole thing on a line', () {
      final prepared = measurement.prepare('hello world foo bar', style);
      expect(prepared.minIntrinsicWidth, 50);
      expect(prepared.maxIntrinsicWidth, 190);
      // Which is what Flutter says too.
      final truth = ground('hello world foo bar');
      expect(prepared.minIntrinsicWidth, truth.minIntrinsicWidth);
      expect(prepared.maxIntrinsicWidth, truth.maxIntrinsicWidth);
    });

    test('a hard break is a paragraph, and the widest one wins', () {
      final prepared = measurement.prepare('a\nlonger line', style);
      expect(prepared.hardLineCount, 2);
      expect(prepared.maxIntrinsicWidth, 110);
    });

    test('a trailing newline leaves an empty line behind it', () {
      final prepared = measurement.prepare('a\n', style);
      expect(prepared.hardLineCount, 2);
      expect(measurement.layout(prepared).lineCount, 2);
    });

    test('an empty string is one empty line, not nothing', () {
      final layout = measurement.layout(measurement.prepare('', style));
      expect(layout.lineCount, 1);
      expect(layout.width, 0);
      expect(layout.height, 10);
      expect(layout.firstBaseline, 7.5);
    });

    test('whitespace-only text has width but nothing to draw', () {
      final layout = measurement.layout(measurement.prepare('   ', style));
      expect(layout.lineCount, 1);
      expect(layout.lines.single.runs, isEmpty);
      expect(layout.width, ground('   ').size.width);
    });

    test('whitespace is preserved by default, as Flutter preserves it', () {
      final prepared = measurement.prepare('a   b', style);
      expect(prepared.text, 'a   b');
      expect(prepared.maxIntrinsicWidth, 50);
    });

    test('collapse squeezes runs and clears them off a hard break', () {
      final prepared = measurement.prepare(
        'a   b\n   c',
        style,
        rules: const TextBreakRules3d(whitespace: TextWhitespace3d.collapse),
      );
      expect(prepared.text, 'a b\nc');
      expect(prepared.maxIntrinsicWidth, 30);
    });

    test('a tab is a fixed advance of tabSize spaces', () {
      expect(measurement.prepare('a\tb', style).maxIntrinsicWidth, 100);
      expect(
        measurement
            .prepare('a\tb', style, rules: const TextBreakRules3d(tabSize: 2))
            .maxIntrinsicWidth,
        40,
      );
    });

    test('a non-breaking space is whitespace a line may not end at', () {
      final prepared = measurement.prepare('a b c', style);
      expect(prepared.segments, hasLength(2));
      expect(prepared.minIntrinsicWidth, 30);
    });

    test('a soft hyphen leaves the string and becomes a break', () {
      final prepared = measurement.prepare('hy­phen', style);
      expect(prepared.text, 'hyphen');
      expect(prepared.segments, hasLength(2));
      expect(prepared.segments.first.breakAfter, TextBreak3d.hyphen);
      // It is not a break the intrinsic width pays for: on one line the word
      // is whole.
      expect(prepared.maxIntrinsicWidth, 60);
      expect(prepared.minIntrinsicWidth, 40);
    });

    test('softHyphens off drops the character outright', () {
      final prepared = measurement.prepare(
        'hy­phen',
        style,
        rules: const TextBreakRules3d(softHyphens: false),
      );
      expect(prepared.text, 'hyphen');
      expect(prepared.segments, hasLength(1));
    });

    test('a zero-width space is a break that draws nothing', () {
      final prepared = measurement.prepare('ab​cd', style);
      expect(prepared.text, 'abcd');
      expect(prepared.segments, hasLength(2));
      expect(prepared.segments.first.breakAfter, TextBreak3d.opportunity);
    });
  });

  group('line breaking against Flutter', () {
    // The tolerance *is* the accuracy claim: for Latin text the greedy
    // breaker over prepared segments agrees with `TextPainter` exactly, at
    // every width down to a single glyph. Below one glyph the platform stops
    // being self-consistent (it drops the empty line after a trailing
    // newline), so that is where the comparison stops.
    const texts = <String>[
      'hello world foo bar',
      'a b c',
      '',
      '   ',
      'one\ntwo',
      'a\n',
      'supercalifragilisticexpialidocious',
      'trailing space ',
    ];
    for (final text in texts) {
      final label = text.replaceAll('\n', r'\n');
      test('"$label" wraps where Flutter wraps it', () {
        final prepared = measurement.prepare(text, style);
        for (final width in <double>[1000, 100, 70, 42, 30, 20, 10]) {
          final layout = measurement.layout(prepared, maxWidth: width);
          final truth = ground(text, maxWidth: width);
          expect(
            layout.height,
            truth.size.height,
            reason: '"$label" at $width: height',
          );
          expect(
            layout.width,
            truth.size.width,
            reason: '"$label" at $width: width',
          );
        }
      });
    }

    test('and at every width in between, not only the ones chosen', () {
      // The sweep, because the interesting failures are off by one line at
      // one width. Whole logical pixels only: a fractional wrap width is a
      // place where two different floating-point sums are compared, and the
      // claim being made here is about line breaking, not about how the
      // platform rounds.
      for (final text in texts) {
        final prepared = measurement.prepare(text, style);
        for (var width = 10.0; width <= 210.0; width += 1.0) {
          expect(
            measurement.layout(prepared, maxWidth: width).height,
            ground(text, maxWidth: width).size.height,
            reason: 'at width $width',
          );
        }
      }
    });

    test('the runs are the words, at the offsets Flutter puts them at', () {
      final prepared = measurement.prepare('hello world foo bar', style);
      final layout = measurement.layout(prepared, maxWidth: 100);
      expect(linesOf(layout), <String>['hello', 'world foo', 'bar']);
      expect(layout.lines[1].runs.map((run) => run.left), <double>[0, 60]);
      expect(layout.lines.map((line) => line.top), <double>[0, 10, 20]);
      expect(layout.lines.map((line) => line.baselineFromTop), <double>[
        7.5,
        17.5,
        27.5,
      ]);
    });

    test('trailing whitespace hangs rather than forcing a break', () {
      // "ab " is 30 wide with its space and 20 without; at 20 it still fits,
      // because the space at the end of a line costs nothing.
      final prepared = measurement.prepare('ab cd', style);
      final layout = measurement.layout(prepared, maxWidth: 20);
      expect(linesOf(layout), <String>['ab', 'cd']);
      expect(layout.lines.first.width, 20);
    });
  });

  group('break rules', () {
    test('an over-wide word is broken at a grapheme, as Flutter breaks it', () {
      final prepared = measurement.prepare('abcdef', style);
      expect(linesOf(measurement.layout(prepared, maxWidth: 25)), <String>[
        'ab',
        'cd',
        'ef',
      ]);
    });

    test('the overflow rule lets it stand outside the box instead', () {
      final prepared = measurement.prepare(
        'abcdef',
        style,
        rules: TextBreakRules3d.overflow,
      );
      final layout = measurement.layout(prepared, maxWidth: 25);
      expect(linesOf(layout), <String>['abcdef']);
      expect(layout.longestLine, 60);
      // The block still reports the width it was offered; the glyphs are what
      // overflow, exactly as in Flutter.
      expect(layout.width, 25);
    });

    test('a grapheme cluster is never split down the middle', () {
      // A base plus a combining acute is one thing to break around.
      final prepared = measurement.prepare('aéi', style);
      final layout = measurement.layout(prepared, maxWidth: 10);
      expect(linesOf(layout), <String>['a', 'é', 'i']);
    });

    test('ideographs break between characters', () {
      final prepared = measurement.prepare('日本語のテキスト', style);
      expect(prepared.segments, hasLength(8));
      expect(prepared.minIntrinsicWidth, 10);
      expect(linesOf(measurement.layout(prepared, maxWidth: 40)), <String>[
        '日本語の',
        'テキスト',
      ]);
    });

    test('keep-all refuses those breaks', () {
      final prepared = measurement.prepare(
        '日本語のテキスト',
        style,
        rules: const TextBreakRules3d(
          wordBreak: WordBreak3d.keepAll,
          overflowWrap: OverflowWrap3d.overflow,
        ),
      );
      expect(prepared.segments, hasLength(1));
      expect(prepared.minIntrinsicWidth, 80);
      expect(linesOf(measurement.layout(prepared, maxWidth: 40)), <String>[
        '日本語のテキスト',
      ]);
    });

    test('closing punctuation may not start a line', () {
      final prepared = measurement.prepare('本。書', style);
      // Two segments, not three: the break between 本 and 。is refused.
      expect(prepared.segments, hasLength(2));
      expect(prepared.segments.first.width, 20);
    });

    test('a line may end after a hyphen', () {
      final prepared = measurement.prepare('well-known word', style);
      expect(prepared.minIntrinsicWidth, 50);
      expect(linesOf(measurement.layout(prepared, maxWidth: 60)), <String>[
        'well-',
        'known',
        'word',
      ]);
    });

    test('a soft-hyphen break draws a hyphen, and only when taken', () {
      final prepared = measurement.prepare('hy­phen and', style);
      expect(linesOf(measurement.layout(prepared, maxWidth: 100)), <String>[
        'hyphen and',
      ]);
      final broken = measurement.layout(prepared, maxWidth: 45);
      expect(linesOf(broken), <String>['hy-', 'phen', 'and']);
      expect(broken.lines.first.runs.last.isSynthetic, isTrue);
      expect(broken.lines.first.width, 30);
    });
  });

  group('alignment', () {
    // Alignment needs a block wider than the text, and a block is only wider
    // than its text when a parent insisted: on its own it shrink-wraps.
    TextLayout3d align(TextAlign textAlign, {TextDirection? direction}) =>
        measurement.layout(
          measurement.prepare('ab cd', style),
          minWidth: 100,
          maxWidth: 100,
          textAlign: textAlign,
          textDirection: direction ?? TextDirection.ltr,
        );

    test('left, right and centre put the line where they say', () {
      expect(align(TextAlign.left).lines.single.left, 0);
      expect(align(TextAlign.right).lines.single.left, 50);
      expect(align(TextAlign.center).lines.single.left, 25);
    });

    test('start and end follow the direction', () {
      expect(align(TextAlign.start).lines.single.left, 0);
      expect(align(TextAlign.end).lines.single.left, 50);
      expect(
        align(TextAlign.start, direction: TextDirection.rtl).lines.single.left,
        50,
      );
      expect(
        align(TextAlign.end, direction: TextDirection.rtl).lines.single.left,
        0,
      );
    });

    test('justify spreads the gaps, and leaves the last line alone', () {
      final prepared = measurement.prepare('ab cd ef gh', style);
      final layout = measurement.layout(
        prepared,
        minWidth: 60,
        maxWidth: 60,
        textAlign: TextAlign.justify,
      );
      expect(linesOf(layout), <String>['ab cd', 'ef gh']);
      // 20 of slack over one gap on the first line, nothing on the last.
      expect(layout.lines.first.runs.map((run) => run.left), <double>[0, 40]);
      expect(layout.lines.first.width, 60);
      expect(layout.lines.last.runs.map((run) => run.left), <double>[0, 30]);
    });

    test('a shrink-wrapped block has no room to align inside', () {
      final layout = measurement.layout(
        measurement.prepare('ab cd', style),
        maxWidth: 100,
        textAlign: TextAlign.center,
      );
      expect(layout.width, 50);
      expect(layout.lines.single.left, 0);
    });
  });

  group('maxLines and ellipsis', () {
    test('maxLines drops the rest and says so', () {
      final prepared = measurement.prepare('hello world foo bar', style);
      final layout = measurement.layout(prepared, maxWidth: 60, maxLines: 2);
      expect(linesOf(layout), <String>['hello', 'world']);
      expect(layout.didExceedMaxLines, isTrue);
      expect(layout.height, 20);
    });

    test('a limit the text does not reach is not exceeded', () {
      final prepared = measurement.prepare('hello', style);
      final layout = measurement.layout(prepared, maxWidth: 60, maxLines: 2);
      expect(layout.didExceedMaxLines, isFalse);
    });

    test('the ellipsis marks the last line kept', () {
      final prepared = measurement.prepare('hello world foo bar', style);
      final layout = measurement.layout(
        prepared,
        maxWidth: 60,
        maxLines: 2,
        ellipsis: '…',
      );
      expect(linesOf(layout), <String>['hello', 'world…']);
      expect(layout.lines.last.width, 60);
    });

    test('it eats into the line when there is no room beside it', () {
      final prepared = measurement.prepare('abcdefgh ij', style);
      final layout = measurement.layout(
        prepared,
        maxWidth: 60,
        maxLines: 1,
        ellipsis: '…',
      );
      expect(linesOf(layout), <String>['abcde…']);
      expect(layout.lines.single.width, 60);
    });

    test('with no width to cut against, the mark is all there is', () {
      final prepared = measurement.prepare('one\ntwo\nthree', style);
      final layout = measurement.layout(prepared, maxLines: 2, ellipsis: '…');
      expect(linesOf(layout), <String>['one', 'two…']);
      expect(layout.didExceedMaxLines, isTrue);
    });

    test('an unwrapped line is cut to the room the box has', () {
      // What `softWrap: false` with `TextOverflow.ellipsis` asks for: break
      // nowhere, but do not draw past the box.
      final prepared = measurement.prepare('hello world', style);
      final layout = measurement.layout(
        prepared,
        truncateWidth: 60,
        ellipsis: '…',
      );
      expect(linesOf(layout), <String>['hello…']);
    });
  });

  group('the hot path', () {
    test('laying prepared text out consults the font zero times', () {
      final prepared = measurement.prepare('hello world foo bar baz', style);
      // One pass first, so the grapheme widths the narrow end needs are
      // already measured; that one-time cost has a test of its own below.
      measurement.layout(prepared, maxWidth: 20);
      final before = debugTextParagraphCount;
      for (var width = 20.0; width < 220.0; width += 1.0) {
        final layout = measurement.layout(
          prepared,
          maxWidth: width,
          textAlign: TextAlign.center,
          maxLines: 4,
        );
        expect(layout.lines, isNotEmpty);
      }
      expect(debugTextParagraphCount, before);
    });

    test('and neither does an intrinsic query', () {
      final prepared = measurement.prepare('hello world', style);
      final before = debugTextParagraphCount;
      expect(prepared.minIntrinsicWidth, 50);
      expect(prepared.maxIntrinsicWidth, 110);
      expect(debugTextParagraphCount, before);
    });

    test('breaking inside a word costs the font once, then never again', () {
      final prepared = measurement.prepare('abcdefgh', style);
      final before = debugTextParagraphCount;
      measurement.layout(prepared, maxWidth: 30);
      final afterFirst = debugTextParagraphCount;
      expect(afterFirst, greaterThan(before));
      for (var width = 10.0; width < 80.0; width += 1.0) {
        measurement.layout(prepared, maxWidth: width);
      }
      expect(debugTextParagraphCount, afterFirst);
    });
  });

  group('the cache', () {
    test('the same string at the same style is measured once', () {
      measurement.prepare('hello world', style);
      final before = debugTextParagraphCount;
      measurement.prepare('hello world', style);
      measurement.prepare('world hello', style);
      expect(debugTextParagraphCount, before);
    });

    test('a different style is a different measurement', () {
      measurement.prepare('hello', style);
      final before = debugTextParagraphCount;
      measurement.prepare('hello', const TextStyle(fontSize: 20));
      expect(debugTextParagraphCount, greaterThan(before));
    });

    test('it forgets the oldest entry rather than growing', () {
      final small = SegmentedTextMeasurement3d(
        cache: TextMeasurementCache3d(maximumEntries: 4),
      );
      small.prepare('one two three four five six', style);
      expect(small.cache.length, 4);
    });
  });

  group('the exact policy', () {
    const exact = ParagraphTextMeasurement3d();

    test('agrees with the fast one on Latin text', () {
      const text = 'hello world foo bar';
      final approximate = measurement.prepare(text, style);
      final precise = exact.prepare(text, style);
      expect(precise.minIntrinsicWidth, approximate.minIntrinsicWidth);
      expect(precise.maxIntrinsicWidth, approximate.maxIntrinsicWidth);
      expect(precise.lineHeight, approximate.lineHeight);
      expect(precise.baseline, approximate.baseline);
      for (final width in <double>[1000, 100, 60, 30]) {
        final a = measurement.layout(approximate, maxWidth: width);
        final b = exact.layout(precise, maxWidth: width);
        expect(b.height, a.height, reason: 'height at $width');
        expect(b.width, a.width, reason: 'width at $width');
        expect(
          b.lines.map((line) => line.width),
          a.lines.map((line) => line.width),
          reason: 'line widths at $width',
        );
      }
    });

    test('and on where a run sits, which is what a renderer draws from', () {
      // A run's `left` is measured from the block, alignment included — the
      // contract TextRun3d has always stated. It has to hold for *both*
      // policies or a glyph's place on the panel would depend on which one
      // measured it, and the segmented policy used to report it relative to
      // its own line. Every other assertion here is left-aligned, where the
      // two readings coincide and the bug was invisible.
      const text = 'ab';
      for (final align in <TextAlign>[
        TextAlign.center,
        TextAlign.right,
        TextAlign.left,
      ]) {
        final a = measurement.layout(
          measurement.prepare(text, style),
          minWidth: 100,
          maxWidth: 100,
          textAlign: align,
        );
        final b = exact.layout(
          exact.prepare(text, style),
          minWidth: 100,
          maxWidth: 100,
          textAlign: align,
        );
        expect(
          a.lines.single.runs.map((run) => run.left),
          b.lines.single.runs.map((run) => run.left),
          reason: 'run offsets disagree under $align',
        );
        // And they are absolute, not relative to the line: a centred line
        // starts at 40 of the 100 it was given, and so does its first run.
        expect(
          a.lines.single.runs.first.left,
          a.lines.single.left,
          reason: 'the first run should start where its line does under $align',
        );
      }
    });

    test('and with Flutter, which is the point of it', () {
      final precise = exact.prepare('hello world foo bar', style);
      final layout = exact.layout(precise, maxWidth: 100);
      final truth = ground('hello world foo bar', maxWidth: 100);
      expect(layout.height, truth.size.height);
      expect(layout.width, truth.size.width);
      expect(layout.lineCount, truth.computeLineMetrics().length);
    });

    test('it carries the alignment the platform applied', () {
      final precise = exact.prepare('ab cd', style);
      final layout = exact.layout(
        precise,
        minWidth: 100,
        maxWidth: 100,
        textAlign: TextAlign.right,
      );
      expect(layout.width, 100);
      expect(layout.lines.single.left, 50);
    });

    test('a handle belongs to the measurement that made it', () {
      final precise = exact.prepare('hello', style);
      expect(precise.isSegmented, isFalse);
      expect(() => measurement.layout(precise), throwsA(isA<AssertionError>()));
    });
  });
}
