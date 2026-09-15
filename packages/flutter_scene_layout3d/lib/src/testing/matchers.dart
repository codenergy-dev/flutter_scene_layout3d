import 'package:flutter_test/flutter_test.dart'
    show
        Description,
        FinderBase,
        Matcher,
        Plurality,
        StringDescription,
        closeTo,
        wrapMatcher;

import '../decoration/decorated_box.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import 'scene.dart';

/// Matches when a press at the centre of every box found would reach it.
///
/// The box is projected through the camera of the [SceneInput3d] above it,
/// and the host is asked what a press at that point of the view would be
/// dispatched to — the same question `tester.tap3d` asks before it presses.
/// It fails for a box covered by another surface, by a sibling in front of
/// it, by a barrier, for one outside every hit-testable region, and for one
/// that is off the screen or not under a host at all.
///
/// The actual value is a finder over layout boxes, or a box.
const Matcher isReachable3d = _EveryBoxMatcher(
  _reachable,
  'reachable by a press at its centre',
);

/// Matches when every box found is [size] across, in world units, to within
/// [epsilon] on each axis.
Matcher hasSize3d(Size3d size, {double epsilon = 1e-6}) => _hasSizeWhere(
  width: closeTo(size.width, epsilon),
  height: closeTo(size.height, epsilon),
  depth: closeTo(size.depth, epsilon),
  unit: 'world units',
  toUnit: (box, units) => units,
);

/// Matches when every box found measures [width], [height] and [depth] in
/// logical pixels, each converted through the box's own metrics.
///
/// Each figure is a number, matched to within a hundredth of a logical pixel,
/// or a [Matcher] — `greaterThan(1)` is how "a screen more than one logical
/// pixel deep" is spelled. A null figure is not checked.
///
/// This is the matcher a component's author wants, because a component is
/// specified in dp and a box is measured in world units — the trap
/// `docs/traps.md` opens with.
Matcher hasSizeDp({Object? width, Object? height, Object? depth}) =>
    _hasSizeWhere(
      width: _dp(width),
      height: _dp(height),
      depth: _dp(depth),
      unit: 'dp',
      toUnit: (box, units) => box.metrics.toLogicalPixels(units),
    );

Matcher? _dp(Object? figure) => switch (figure) {
  null => null,
  final num value => closeTo(value, 0.01),
  _ => wrapMatcher(figure),
};

/// The matcher behind [hasSize3d] and [hasSizeDp].
Matcher _hasSizeWhere({
  Matcher? width,
  Matcher? height,
  Matcher? depth,
  required String unit,
  required double Function(Layout3d box, double units) toUnit,
}) {
  final axes = <(String, Matcher, double Function(Size3d))>[
    if (width != null) ('width', width, (size) => size.width),
    if (height != null) ('height', height, (size) => size.height),
    if (depth != null) ('depth', depth, (size) => size.depth),
  ];
  final described = StringDescription();
  for (final (name, matcher, _) in axes) {
    if (described.length > 0) described.add(', ');
    described.add('$name ');
    matcher.describe(described);
  }
  return _EveryBoxMatcher((box, _) {
    if (!box.hasSize) return 'it is not laid out';
    final problems = <String>[];
    for (final (name, matcher, extent) in axes) {
      final value = toUnit(box, extent(box.size));
      if (!matcher.matches(value, <Object?, Object?>{})) {
        problems.add('its $name is ${_figure(value)} $unit');
      }
    }
    return problems.isEmpty ? null : problems.join(' and ');
  }, 'sized, in $unit, $described');
}

/// Matches when no box found is laid out behind the front face of the panel
/// it is on.
///
/// The panel is the nearest [DecoratedBox3d] above the box. Both are measured
/// where they are *drawn*, in the surface's frame, and the box's front has to
/// be no further from the viewer than the panel's front face — because a slab
/// is opaque, and content inside one is hidden by it however correct its
/// layout is. A box on no panel passes: there is nothing to be sunk into.
///
/// It is the check for the defect a `EdgeInsets3d.all` padding makes inside a
/// card: `all` insets the front too, and the content ends up behind a face
/// that hides it while every test that asks whether it is *there* passes.
/// Over a whole screen it asks every label at once:
///
/// ```dart
/// expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
/// ```
const Matcher standsOnItsPanel3d = _EveryBoxMatcher(
  _standsOnItsPanel,
  'not laid out behind the front face of its panel',
);

String? _reachable(Layout3d box, List<SceneSurface3d> surfaces) {
  final reach = Reach3d.of(box, surfaces);
  return reach.reaches ? null : reach.describeMiss();
}

String? _standsOnItsPanel(Layout3d box, List<SceneSurface3d> surfaces) {
  final surface = rootSurfaceOf(box);
  if (surface == null || !box.hasSize) return 'it is not laid out';
  Layout3d? panel = box.parent;
  while (panel != null && panel is! DecoratedBox3d) {
    panel = panel.parent;
  }
  if (panel == null) return null;
  final front = drawnCornerIn(surface, box).z;
  final face = drawnCornerIn(surface, panel).z;
  // Layout's z runs away from the viewer, so "behind the face" is larger.
  const tolerance = 1e-9;
  if (front <= face + tolerance) return null;
  final units = front - face;
  return 'its front is ${_figure(box.metrics.toLogicalPixels(units))} dp '
      'behind the front face of ${describeBox3d(panel)}, which hides it. Is something between '
      'them insetting the front — an EdgeInsets3d.all where '
      'EdgeInsets3d.symmetric was meant?';
}

String _figure(double value) {
  final rounded = value.toStringAsFixed(2);
  return rounded.endsWith('.00')
      ? rounded.substring(0, rounded.length - 3)
      : rounded;
}

/// Applies a check to every box a finder finds, and fails on none.
///
/// [_check] returns null when a box passes and says why when it does not.
class _EveryBoxMatcher extends Matcher {
  const _EveryBoxMatcher(this._check, this._description);

  final String? Function(Layout3d box, List<SceneSurface3d> surfaces) _check;
  final String _description;

  static const _failuresKey = 'layout3d.failures';

  @override
  Description describe(Description description) =>
      description.add('every box found $_description');

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final List<Layout3d> boxes;
    if (item is Layout3d) {
      boxes = <Layout3d>[item];
    } else if (item is FinderBase<Layout3d>) {
      boxes = item.evaluate().toList();
    } else {
      matchState[_failuresKey] = <String>[
        'is not a Layout3d or a finder over them',
      ];
      return false;
    }
    if (boxes.isEmpty) {
      matchState[_failuresKey] = <String>['found no box at all'];
      return false;
    }
    final surfaces = sceneSurfaces3d();
    final failures = <String>[
      for (final box in boxes)
        if (_check(box, surfaces) case final String why)
          '${describeBox3d(box)}: $why',
    ];
    matchState[_failuresKey] = failures;
    return failures.isEmpty;
  }

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    final failures = matchState[_failuresKey] as List<String>? ?? const [];
    if (item is FinderBase<Layout3d>) {
      mismatchDescription.add(
        'searched for ${item.describeMatch(Plurality.many)}, and ',
      );
    }
    if (failures.length == 1) return mismatchDescription.add(failures.single);
    mismatchDescription.add('${failures.length} of them failed:');
    for (final failure in failures) {
      mismatchDescription.add('\n  $failure');
    }
    return mismatchDescription;
  }
}
