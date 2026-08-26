import 'break_rules.dart';

/// How a line may end after a segment.
enum TextBreak3d {
  /// It may not: this is the last segment of the text.
  none,

  /// A line may end here, and nothing is drawn to say so.
  opportunity,

  /// A line may end here, and a hyphen is drawn when one does.
  ///
  /// Where a U+00AD SOFT HYPHEN was written.
  hyphen,

  /// A line *must* end here: a newline was written.
  mandatory,
}

/// One atom of line breaking: the run of text between two break
/// opportunities, plus the whitespace that trails it.
///
/// Produced by [segmentText] with offsets only; [TextMeasurement3d] fills in
/// the widths. The three offsets index [SegmentedText3d.text], which is the
/// *normalized* string — soft hyphens and zero-width spaces have been taken
/// out of it, and under [TextWhitespace3d.collapse] its whitespace runs have
/// been squeezed — not the string the caller passed in.
class RawSegment3d {
  /// Creates a raw segment.
  const RawSegment3d({
    required this.start,
    required this.visibleEnd,
    required this.end,
    required this.breakAfter,
    required this.tabCount,
  });

  /// Where the segment begins.
  final int start;

  /// Where its drawable part ends, before any trailing whitespace.
  final int visibleEnd;

  /// Where it ends, after the trailing whitespace.
  final int end;

  /// How a line may end here.
  final TextBreak3d breakAfter;

  /// How many tabs are in the trailing whitespace run.
  final int tabCount;

  /// Whether the segment has no drawable content at all.
  bool get isEmpty => visibleEnd == start;

  @override
  String toString() => 'RawSegment3d($start..$visibleEnd..$end, $breakAfter)';
}

/// A normalized string and the segments it breaks into.
class SegmentedText3d {
  /// Creates a segmentation result.
  const SegmentedText3d(this.text, this.segments);

  /// The normalized text the segment offsets index into.
  final String text;

  /// The segments, in order, covering [text] end to end.
  final List<RawSegment3d> segments;
}

/// Normalizes [source] under [rules] and splits it at every place a line is
/// allowed to end.
///
/// This is the half of `prepare` that does not touch the font, and it is
/// where the break policy is spent: after this, laying text out at a width is
/// arithmetic over segment widths and nothing consults the rules again.
///
/// The rules implemented are a working subset of UAX #14, chosen for the text
/// a component library actually sets: break after a run of whitespace, break
/// after a hyphen, break between ideographs (unless [WordBreak3d.keepAll]),
/// break at a soft hyphen or a zero-width space. Not implemented, and worth
/// knowing about before setting prose in a scene: the numeric context rules
/// that stop `1-2` from breaking, the Korean and Thai dictionary rules, and
/// bidi reordering. [ParagraphTextMeasurement3d] hands all of that back to
/// the platform.
SegmentedText3d segmentText(String source, TextBreakRules3d rules) {
  final (text, explicit) = _normalize(source, rules);
  return SegmentedText3d(text, _segment(text, explicit, rules));
}

/// Strips the invisible break markers out of [source], collapses its
/// whitespace if asked, and records where the markers were.
///
/// The markers have to leave the string because everything downstream — run
/// text, hit testing, the renderer — takes substrings of it, and a soft
/// hyphen that survives into a substring draws as a hyphen in the middle of a
/// word on most platforms. The map they leave behind is keyed by the offset
/// they *would* have occupied.
(String, Map<int, TextBreak3d>) _normalize(
  String source,
  TextBreakRules3d rules,
) {
  final collapse = rules.whitespace == TextWhitespace3d.collapse;
  final breaks = <int, TextBreak3d>{};
  final buffer = StringBuffer();
  var pendingSpace = false;
  var atLineStart = true;
  for (var i = 0; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == _softHyphen) {
      if (rules.softHyphens) breaks[buffer.length] = TextBreak3d.hyphen;
      continue;
    }
    if (code == _zeroWidthSpace) {
      breaks[buffer.length] = TextBreak3d.opportunity;
      continue;
    }
    if (isMandatoryBreak(code)) {
      pendingSpace = false;
      atLineStart = true;
      buffer.writeCharCode(code);
      continue;
    }
    if (collapse && isBreakingWhitespace(code)) {
      pendingSpace = !atLineStart;
      continue;
    }
    if (pendingSpace) {
      buffer.writeCharCode(_space);
      pendingSpace = false;
    }
    atLineStart = false;
    buffer.writeCharCode(code);
  }
  return (buffer.toString(), breaks);
}

List<RawSegment3d> _segment(
  String text,
  Map<int, TextBreak3d> explicit,
  TextBreakRules3d rules,
) {
  final segments = <RawSegment3d>[];
  final length = text.length;
  var cursor = 0;
  while (true) {
    final start = cursor;
    var index = cursor;
    var kind = TextBreak3d.none;
    // The drawable run: characters up to the first place a line may end.
    while (index < length) {
      final code = text.codeUnitAt(index);
      if (isBreakingWhitespace(code) || isMandatoryBreak(code)) break;
      final next = _nextRune(text, index);
      if (next < length) {
        final marker = explicit[next];
        if (marker != null) {
          index = next;
          kind = marker;
          break;
        }
        if (_breaksBetween(text, start, index, next, rules)) {
          index = next;
          kind = TextBreak3d.opportunity;
          break;
        }
      }
      index = next;
    }
    final visibleEnd = index;
    // The whitespace that trails it, which hangs past the wrap width rather
    // than pushing the segment onto the next line.
    var tabs = 0;
    while (index < length && isBreakingWhitespace(text.codeUnitAt(index))) {
      if (text.codeUnitAt(index) == _tab) tabs++;
      index++;
    }
    final end = index;
    if (end > visibleEnd) kind = TextBreak3d.opportunity;
    if (index < length && isMandatoryBreak(text.codeUnitAt(index))) {
      kind = TextBreak3d.mandatory;
      index += _mandatoryBreakLength(text, index);
    } else if (index >= length) {
      kind = TextBreak3d.none;
    }
    segments.add(
      RawSegment3d(
        start: start,
        visibleEnd: visibleEnd,
        end: end,
        breakAfter: kind,
        tabCount: tabs,
      ),
    );
    cursor = index;
    if (cursor >= length) {
      // A string that ends in a newline ends with an empty line, the same way
      // a `Text('a\n')` in Flutter is two lines tall.
      if (kind == TextBreak3d.mandatory) {
        segments.add(
          RawSegment3d(
            start: length,
            visibleEnd: length,
            end: length,
            breakAfter: TextBreak3d.none,
            tabCount: 0,
          ),
        );
      }
      return segments;
    }
  }
}

/// Whether a line may end between the runes at [index] and [next].
///
/// [segmentStart] is where the segment being built began, which the hyphen
/// rule needs: a hyphen is only a break opportunity when there is something
/// in front of it to leave behind.
bool _breaksBetween(
  String text,
  int segmentStart,
  int index,
  int next,
  TextBreakRules3d rules,
) {
  final before = _runeAt(text, index);
  final after = _runeAt(text, next);
  if (isBreakingWhitespace(after) || isMandatoryBreak(after)) return false;
  if (_isHyphen(before)) {
    return index > segmentStart && !_isHyphen(after);
  }
  if (rules.wordBreak == WordBreak3d.keepAll) return false;
  if (!_isIdeographic(before) && !_isIdeographic(after)) return false;
  if (_noBreakBefore(after) || _noBreakAfter(before)) return false;
  return true;
}

// ------------------------------------------------------------- characters

const int _tab = 0x09;
const int _lineFeed = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _softHyphen = 0x00AD;
const int _zeroWidthSpace = 0x200B;

/// Whether [code] ends a line whether or not the text has run out of room.
bool isMandatoryBreak(int code) =>
    code == _lineFeed ||
    code == _carriageReturn ||
    code == 0x0B ||
    code == 0x0C ||
    code == 0x85 ||
    code == 0x2028 ||
    code == 0x2029;

/// How many code units the mandatory break at [index] occupies, so that CRLF
/// counts as one break rather than two.
int _mandatoryBreakLength(String text, int index) {
  if (text.codeUnitAt(index) == _carriageReturn &&
      index + 1 < text.length &&
      text.codeUnitAt(index + 1) == _lineFeed) {
    return 2;
  }
  return 1;
}

/// Whether [code] is whitespace a line may end after.
///
/// U+00A0 NO-BREAK SPACE is deliberately absent: it is whitespace that exists
/// precisely so that a line does not end there.
bool isBreakingWhitespace(int code) =>
    code == _space ||
    code == _tab ||
    code == 0x1680 ||
    (code >= 0x2000 && code <= 0x200A) ||
    code == 0x205F ||
    code == 0x3000;

bool _isHyphen(int rune) =>
    rune == 0x2D || rune == 0x2010 || rune == 0x2012 || rune == 0x2013;

/// Whether [rune] is set in a script that breaks between characters rather
/// than between words.
///
/// Han, kana, Hangul, Yi, and the fullwidth forms. The ideographic space at
/// U+3000 falls inside one of these ranges and is claimed by
/// [isBreakingWhitespace] first, which is checked before this ever is.
bool _isIdeographic(int rune) =>
    (rune >= 0x1100 && rune <= 0x11FF) ||
    (rune >= 0x2E80 && rune <= 0x303F) ||
    (rune >= 0x3041 && rune <= 0x33FF) ||
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xA000 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE4F) ||
    (rune >= 0xFF00 && rune <= 0xFF9F) ||
    (rune >= 0x20000 && rune <= 0x2FA1F);

/// Closing punctuation and the small kana, which may not start a line.
bool _noBreakBefore(int rune) => _closing.contains(rune);

/// Opening punctuation, which may not end one.
bool _noBreakAfter(int rune) => _opening.contains(rune);

final Set<int> _closing = Set<int>.unmodifiable(
  '、。，．！？：；」』）〕｝】〉》・ーぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ々〻'.codeUnits,
);

final Set<int> _opening = Set<int>.unmodifiable('「『（〔｛【〈《‘“'.codeUnits);

/// The offset just past the rune starting at [index].
int _nextRune(String text, int index) {
  final code = text.codeUnitAt(index);
  if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
    final low = text.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) return index + 2;
  }
  return index + 1;
}

/// The rune starting at [index].
int _runeAt(String text, int index) {
  final code = text.codeUnitAt(index);
  if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
    final low = text.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return code;
}
