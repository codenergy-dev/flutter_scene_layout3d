import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter_test/flutter_test.dart'
    show FinderBase, MatchFinderMixin, Plurality;

import '../input/focus.dart';
import '../layout3d.dart';
import '../semantics.dart';
import '../text/rich_text3d.dart';
import '../text/text3d.dart';
import 'scene.dart';

/// Finds boxes in the layout trees of every surface in the widget tree.
///
/// The counterpart of `find` for a 3D screen, and read the same way:
///
/// ```dart
/// expect(find3d.bySemanticsLabel('Compose'), findsOne);
/// await tester.tap3d(find3d.bySemanticsLabel('Settings'));
/// ```
const CommonLayout3dFinders find3d = CommonLayout3dFinders._();

/// The finders [find3d] offers.
///
/// Every one of them searches **every box on every surface mounted in the
/// widget tree**, in tree order, with each overlay's detached entries straight
/// after the surface the overlay is on — so a dialog on a surface of its own
/// is found without the test knowing where it is. The surfaces themselves are
/// candidates too.
class CommonLayout3dFinders {
  const CommonLayout3dFinders._();

  /// The [Semantics3d] boxes whose label matches [label].
  ///
  /// A [String] matches a label equal to it and a [RegExp] one it matches
  /// anywhere in. This is the finder to reach for first: a component in a
  /// catalogue publishes its label here, and it is what a person reads, so a
  /// test written with it survives a change to how the component is built.
  Layout3dFinder bySemanticsLabel(Pattern label) => _PredicateFinder(
    (box) =>
        box is Semantics3d &&
        switch (box.properties.label) {
          final String value => _matches(label, value),
          _ => false,
        },
    'semantics label ${_describePattern(label)}',
  );

  /// The [Text3d] and [RichText3d] boxes whose whole text is [text].
  Layout3dFinder text(String text) =>
      _PredicateFinder((box) => _textOf(box) == text, 'text "$text"');

  /// The [Text3d] and [RichText3d] boxes whose text contains [pattern].
  Layout3dFinder textContaining(Pattern pattern) => _PredicateFinder((box) {
    final text = _textOf(box);
    return text != null && _contains(pattern, text);
  }, 'text containing ${_describePattern(pattern)}');

  /// The boxes whose runtime type is exactly [type].
  Layout3dFinder byType(Type type) =>
      _PredicateFinder((box) => box.runtimeType == type, 'type "$type"');

  /// The boxes that are a [T], subtypes included.
  Layout3dFinder bySubtype<T extends Layout3d>() =>
      _PredicateFinder((box) => box is T, 'type "$T" or a subtype');

  /// The boxes whose scene node is named [name].
  ///
  /// A box built imperatively takes a `name`; one built by a widget is named
  /// after its runtime type.
  Layout3dFinder byName(String name) =>
      _PredicateFinder((box) => box.node.name == name, 'node name "$name"');

  /// [layout] itself, when it is mounted.
  Layout3dFinder byLayout(Layout3d layout) => _PredicateFinder(
    (box) => identical(box, layout),
    'the given box (${describeBox3d(layout)})',
  );

  /// The boxes [predicate] accepts.
  Layout3dFinder byPredicate(
    bool Function(Layout3d box) predicate, {
    String? description,
  }) => _PredicateFinder(predicate, description ?? 'box matching predicate');

  /// The box holding the keyboard focus, when one does.
  ///
  /// A focus scope that holds the focus itself — a dialog that has just
  /// opened with nothing inside it asking — is found as the box the scope
  /// stands for.
  Layout3dFinder focused() => _PredicateFinder((box) {
    final primary = FocusManager.instance.primaryFocus;
    return primary != null && identical(Focus3d.layoutFor(primary), box);
  }, 'keyboard focus');

  /// The boxes [matching] finds below a box [of] finds.
  ///
  /// Below means in the layout tree: a dialog opened from a button is not
  /// below the button, because it is on a surface of its own. With
  /// [matchRoot] the boxes [of] finds are candidates too.
  Layout3dFinder descendant({
    required FinderBase<Layout3d> of,
    required FinderBase<Layout3d> matching,
    bool matchRoot = false,
  }) => _DescendantFinder(of, matching, matchRoot: matchRoot);

  /// The boxes [matching] finds above a box [of] finds, nearest first.
  ///
  /// With [matchRoot] the boxes [of] finds are candidates too.
  Layout3dFinder ancestor({
    required FinderBase<Layout3d> of,
    required FinderBase<Layout3d> matching,
    bool matchRoot = false,
  }) => _AncestorFinder(of, matching, matchRoot: matchRoot);
}

/// A finder over the layout trees of the surfaces in the widget tree.
///
/// Built on `flutter_test`'s own [FinderBase], so `findsOne`, `findsNothing`,
/// `findsExactly`, `first`, `last` and `at` all work, and a failure describes
/// what was searched for the way a widget finder's does.
abstract class Layout3dFinder extends FinderBase<Layout3d> {
  /// Every box on every surface in the widget tree, in tree order.
  @override
  Iterable<Layout3d> get allCandidates => _everyBox();

  /// What a matching box is, as a noun phrase, for [describeMatch].
  String get description;

  @override
  String describeMatch(Plurality plurality) => switch (plurality) {
    Plurality.one => 'box with $description',
    Plurality.zero || Plurality.many => 'boxes with $description',
  };
}

class _PredicateFinder extends Layout3dFinder with MatchFinderMixin<Layout3d> {
  _PredicateFinder(this._predicate, this.description);

  final bool Function(Layout3d box) _predicate;

  @override
  final String description;

  @override
  bool matches(Layout3d candidate) => _predicate(candidate);
}

class _DescendantFinder extends Layout3dFinder {
  _DescendantFinder(this.of, this.matching, {required this.matchRoot});

  final FinderBase<Layout3d> of;
  final FinderBase<Layout3d> matching;
  final bool matchRoot;

  @override
  String get description =>
      '${matching.describeMatch(Plurality.many)} below '
      '${of.describeMatch(Plurality.one)}';

  @override
  String describeMatch(Plurality plurality) =>
      '${matching.describeMatch(plurality)} below '
      '${of.describeMatch(Plurality.one)}';

  @override
  Iterable<Layout3d> get allCandidates {
    final seen = <Layout3d>{};
    final boxes = <Layout3d>[];
    for (final root in of.evaluate()) {
      void walk(Layout3d box) {
        if ((matchRoot || !identical(box, root)) && seen.add(box)) {
          boxes.add(box);
        }
        box.visitChildren(walk);
      }

      walk(root);
    }
    return boxes;
  }

  @override
  Iterable<Layout3d> findInCandidates(Iterable<Layout3d> candidates) =>
      matching.findInCandidates(candidates);
}

class _AncestorFinder extends Layout3dFinder {
  _AncestorFinder(this.of, this.matching, {required this.matchRoot});

  final FinderBase<Layout3d> of;
  final FinderBase<Layout3d> matching;
  final bool matchRoot;

  @override
  String get description =>
      '${matching.describeMatch(Plurality.many)} above '
      '${of.describeMatch(Plurality.one)}';

  @override
  String describeMatch(Plurality plurality) =>
      '${matching.describeMatch(plurality)} above '
      '${of.describeMatch(Plurality.one)}';

  @override
  Iterable<Layout3d> get allCandidates {
    final seen = <Layout3d>{};
    final boxes = <Layout3d>[];
    for (final leaf in of.evaluate()) {
      Layout3d? box = matchRoot ? leaf : leaf.parent;
      while (box != null) {
        if (seen.add(box)) boxes.add(box);
        box = box.parent;
      }
    }
    return boxes;
  }

  @override
  Iterable<Layout3d> findInCandidates(Iterable<Layout3d> candidates) =>
      matching.findInCandidates(candidates);
}

Iterable<Layout3d> _everyBox() sync* {
  for (final record in sceneSurfaces3d()) {
    final boxes = <Layout3d>[];
    void walk(Layout3d box) {
      boxes.add(box);
      box.visitChildren(walk);
    }

    walk(record.surface);
    yield* boxes;
  }
}

String? _textOf(Layout3d box) => switch (box) {
  Text3d() => box.data,
  RichText3d() => box.text.toPlainText(),
  _ => null,
};

bool _matches(Pattern pattern, String value) => switch (pattern) {
  String() => pattern == value,
  RegExp() => pattern.hasMatch(value),
  _ => pattern.allMatches(value).isNotEmpty,
};

bool _contains(Pattern pattern, String value) => switch (pattern) {
  String() => value.contains(pattern),
  _ => pattern.allMatches(value).isNotEmpty,
};

String _describePattern(Pattern pattern) => switch (pattern) {
  String() => '"$pattern"',
  RegExp() => '/${pattern.pattern}/',
  _ => '$pattern',
};
