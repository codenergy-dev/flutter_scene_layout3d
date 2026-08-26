/// What happens to the whitespace in a string before it is measured.
///
/// CSS calls these `white-space: pre-wrap` and `white-space: normal`; the
/// names here say what they do rather than what they were called first.
enum TextWhitespace3d {
  /// Every space, tab and non-breaking space is kept exactly as written.
  ///
  /// The default, because it is Flutter's: a `Text` widget draws two spaces
  /// as two spaces. Line breaking still hangs the whitespace at the end of a
  /// line past the wrap width, which is the part of the CSS rule that is not
  /// about collapsing.
  preserve,

  /// Runs of whitespace collapse to a single space, and a run that would
  /// land against a hard break disappears.
  ///
  /// The rule a browser applies to ordinary markup, and what a label built
  /// from concatenated strings usually wants. Hard breaks (`\n`) survive
  /// either way; that is a deliberate difference from CSS, where a newline is
  /// just more whitespace, and it is Flutter's behaviour that wins here.
  collapse,
}

/// Whether a break may fall inside a word, the analogue of CSS `word-break`.
enum WordBreak3d {
  /// Break where the script says a break is allowed: after spaces and
  /// hyphens, and between ideographs.
  normal,

  /// Never break between two ideographs.
  ///
  /// CSS `word-break: keep-all`. Korean text set this way breaks at spaces
  /// only, which is what a Korean reader expects; Chinese and Japanese set
  /// this way stop wrapping altogether inside a run, so use it deliberately.
  keepAll,
}

/// What a word too wide for its line is allowed to do, the analogue of CSS
/// `overflow-wrap`.
enum OverflowWrap3d {
  /// Let it overflow. The line is wider than the wrap width and the glyphs
  /// stand outside the box.
  ///
  /// CSS's default, and *not* this package's: Flutter's text engine breaks an
  /// over-wide word rather than let it hang, and a box here reports the same
  /// size Flutter's would.
  overflow,

  /// Break it at a grapheme boundary rather than let it overflow.
  ///
  /// The default, because it is what Flutter does. It is measured lazily —
  /// the first layout narrow enough to need it consults the font once per
  /// over-wide segment, and every layout after that is arithmetic again — so
  /// a policy that most text never exercises costs nothing until it does.
  breakWord,
}

/// The line-breaking policy a string is prepared under.
///
/// These belong to [TextMeasurement3d.prepare] rather than to a layout call
/// because they decide the *segmentation*: where a line is allowed to end at
/// all. Changing one invalidates the prepared handle; changing the width a
/// line is laid out in does not, which is the whole point of the split.
class TextBreakRules3d {
  /// Creates a break policy.
  const TextBreakRules3d({
    this.whitespace = TextWhitespace3d.preserve,
    this.wordBreak = WordBreak3d.normal,
    this.overflowWrap = OverflowWrap3d.breakWord,
    this.tabSize = 8,
    this.softHyphens = true,
  }) : assert(tabSize > 0);

  /// Flutter's rules: whitespace preserved, breaks where the script allows,
  /// an over-wide word broken rather than left hanging.
  static const TextBreakRules3d standard = TextBreakRules3d();

  /// Lets a word too wide for its line stand outside the box, as CSS does by
  /// default and Flutter does not.
  static const TextBreakRules3d overflow = TextBreakRules3d(
    overflowWrap: OverflowWrap3d.overflow,
  );

  /// What happens to runs of whitespace.
  final TextWhitespace3d whitespace;

  /// Whether a break may fall between two ideographs.
  final WordBreak3d wordBreak;

  /// What a word too wide for its line does.
  final OverflowWrap3d overflowWrap;

  /// How many spaces wide a tab is.
  ///
  /// Eight, as everywhere else. A tab here is a *fixed* advance of this many
  /// space widths rather than a jump to the next tab stop: a stop depends on
  /// where the tab sits on the line, and a line's position is not known until
  /// after it has been broken and aligned. Text that needs real tab stops
  /// wants a table, and this package has boxes for that.
  final int tabSize;

  /// Whether U+00AD SOFT HYPHEN is honoured as a break opportunity.
  ///
  /// When it is, the character never draws unless a line actually ends there,
  /// and then a hyphen does. When it is not, it is dropped outright.
  final bool softHyphens;

  /// A copy with the given fields replaced.
  TextBreakRules3d copyWith({
    TextWhitespace3d? whitespace,
    WordBreak3d? wordBreak,
    OverflowWrap3d? overflowWrap,
    int? tabSize,
    bool? softHyphens,
  }) => TextBreakRules3d(
    whitespace: whitespace ?? this.whitespace,
    wordBreak: wordBreak ?? this.wordBreak,
    overflowWrap: overflowWrap ?? this.overflowWrap,
    tabSize: tabSize ?? this.tabSize,
    softHyphens: softHyphens ?? this.softHyphens,
  );

  @override
  bool operator ==(Object other) =>
      other is TextBreakRules3d &&
      other.whitespace == whitespace &&
      other.wordBreak == wordBreak &&
      other.overflowWrap == overflowWrap &&
      other.tabSize == tabSize &&
      other.softHyphens == softHyphens;

  @override
  int get hashCode =>
      Object.hash(whitespace, wordBreak, overflowWrap, tabSize, softHyphens);

  @override
  String toString() =>
      'TextBreakRules3d($whitespace, $wordBreak, $overflowWrap, '
      'tabSize: $tabSize)';
}
