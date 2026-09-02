import 'dart:ui' show lerpDouble;

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BoxDecoration3d;

/// Material 3's six elevation levels, in logical pixels.
///
/// In Flutter an elevation is a published shadow recipe standing in for a
/// height. Here the height is real: `BoxDecoration3d.elevation` moves the
/// panel's geometry toward the viewer by `metrics.dp(elevation)`, and a
/// raised card reads as raised because it moves under the camera and occludes
/// what is behind it.
///
/// **It casts no shadow, and no amount of lighting will make it.** The panel
/// shader declares `blending: alpha` — its antialiased outline *is* an alpha
/// — and `flutter_scene` drops every non-opaque material before the shadow
/// pass reaches a shadow map. Grounding a card on a surface is the
/// application's job; the engine's `ShadowCatcherMaterial` on a plane beneath
/// it is the shape of that.
///
/// So of Material's two-part elevation model, the height transfers literally
/// and the shadow does not — which leaves the **surface tint** carrying more
/// weight here than it does in Flutter. It is what distinguishes a level-3
/// surface from a level-1 one when the camera is head-on and parallax gives
/// nothing at all. [tintOpacityFor] is Material's own table, and the panel
/// shader applies it whenever a decoration names a `surfaceTint`.
class Elevation3d {
  /// Creates an elevation scale, in logical pixels.
  const Elevation3d({
    this.level0 = 0.0,
    this.level1 = 1.0,
    this.level2 = 3.0,
    this.level3 = 6.0,
    this.level4 = 8.0,
    this.level5 = 12.0,
  }) : assert(level0 >= 0.0),
       assert(level1 >= 0.0),
       assert(level2 >= 0.0),
       assert(level3 >= 0.0),
       assert(level4 >= 0.0),
       assert(level5 >= 0.0);

  /// Material 3's published levels: 0, 1, 3, 6, 8 and 12dp.
  ///
  /// The same figures the tint table in [tintOpacityFor] is keyed on, which
  /// is not a coincidence: the two halves of Material's elevation model are
  /// specified against one ladder.
  static const Elevation3d baseline = Elevation3d();

  /// 0dp. A surface resting on its parent: most of a screen.
  final double level0;

  /// 1dp. A card at rest, a filled button.
  final double level1;

  /// 3dp. A menu, a raised card, a floating action button.
  final double level2;

  /// 6dp. A dialog, a navigation drawer.
  final double level3;

  /// 8dp. A navigation bar, a bottom sheet at rest.
  final double level4;

  /// 12dp. The top of the scale: a search view, a dragged component.
  final double level5;

  /// The six levels in order, for a component resolving a level by index.
  List<double> get levels => <double>[
    level0,
    level1,
    level2,
    level3,
    level4,
    level5,
  ];

  /// Material 3's surface-tint opacity for an elevation in logical pixels.
  ///
  /// Delegates to `BoxDecoration3d.surfaceTintOpacityFor`, which is where the
  /// table lives, so a component and the shader agree by construction rather
  /// than by two transcriptions matching.
  double tintOpacityFor(double elevation) =>
      BoxDecoration3d.surfaceTintOpacityFor(elevation);

  /// A copy with the given levels replaced.
  Elevation3d copyWith({
    double? level0,
    double? level1,
    double? level2,
    double? level3,
    double? level4,
    double? level5,
  }) => Elevation3d(
    level0: level0 ?? this.level0,
    level1: level1 ?? this.level1,
    level2: level2 ?? this.level2,
    level3: level3 ?? this.level3,
    level4: level4 ?? this.level4,
    level5: level5 ?? this.level5,
  );

  /// Linearly interpolates between two elevation scales.
  static Elevation3d lerp(Elevation3d a, Elevation3d b, double t) =>
      Elevation3d(
        level0: _lerp(a.level0, b.level0, t),
        level1: _lerp(a.level1, b.level1, t),
        level2: _lerp(a.level2, b.level2, t),
        level3: _lerp(a.level3, b.level3, t),
        level4: _lerp(a.level4, b.level4, t),
        level5: _lerp(a.level5, b.level5, t),
      );

  @override
  bool operator ==(Object other) =>
      other is Elevation3d &&
      other.level0 == level0 &&
      other.level1 == level1 &&
      other.level2 == level2 &&
      other.level3 == level3 &&
      other.level4 == level4 &&
      other.level5 == level5;

  @override
  int get hashCode =>
      Object.hash(level0, level1, level2, level3, level4, level5);

  @override
  String toString() =>
      'Elevation3d($level0, $level1, $level2, $level3, '
      '$level4, $level5)';
}

/// How deep a component is, in logical pixels — the token Material does not
/// have.
///
/// Material 3 publishes a shape scale, a type scale and elevation levels, and
/// nothing at all about thickness, because on a screen a component has none.
/// Here every component is a slab and something has to say how deep. This is
/// that scale, invented once in the theme rather than component by component
/// so that the whole catalogue agrees.
///
/// The four steps are deliberately small. A component is a *card*, not a
/// brick: the depth is there to make an edge catch the light and to let one
/// surface occlude another, and a catalogue whose components are as deep as
/// they are tall looks like a box of soap.
///
/// ## The two rules that come with it
///
/// **A thickness fights the depth ordering.** `Stack3d.depthStep` pulls each
/// successive child toward the viewer by a fixed amount, but a child reaches
/// half its own thickness forward of its plane — so two stacked children are
/// only genuinely separated when the step exceeds the *mean* of their
/// thicknesses. Under that, the back child's front face pokes through the
/// front child, wins the depth test where they overlap, and the stack looks
/// inverted. Worse, a drop target inherits it: `Drag3dSession` picks the
/// nearest acceptor along the ray, so a slab that reaches too far forward
/// takes a drop that visibly belonged to the card in front of it.
///
/// That is what [depthStep] and [separates] are for. The scale carries the
/// step it was designed against, so the two numbers can be read together:
///
/// ```dart
/// assert(theme.thickness.separates(
///   theme.thickness.structural,
///   theme.thickness.raised,
/// ));
/// ```
///
/// **[depthStep] is in logical pixels and `Stack3d.depthStep` is in world
/// units.** Convert at the point of use — `metrics.dp(theme.thickness
/// .depthStep)` — the same way every other Material figure crosses that
/// boundary.
///
/// **A thickness is not free at the edges.** A slab wants its rim rounded in
/// proportion to how deep it is; that half of the rule lives on
/// `ShapeScale3d.bevelFor`, because a component reaches for the corner radius
/// and the bevel in the same breath.
class Thickness3d {
  /// Creates a thickness scale, in logical pixels.
  const Thickness3d({
    this.thin = 1.0,
    this.standard = 2.0,
    this.raised = 4.0,
    this.structural = 8.0,
    this.depthStep = 12.0,
  }) : assert(thin >= 0.0),
       assert(standard >= 0.0),
       assert(raised >= 0.0),
       assert(structural >= 0.0),
       assert(depthStep >= 0.0);

  /// The scale this package proposes: 1, 2, 4 and 8dp, on a 12dp step.
  ///
  /// Twelve is not arbitrary. The deepest pair the scale can produce is two
  /// [structural] slabs, whose mean is 8dp, so a 12dp step separates
  /// *anything* built from these tokens with half again to spare. A theme
  /// that thickens the scale has to raise the step with it, and
  /// [separates] is how a component says so out loud.
  static const Thickness3d baseline = Thickness3d();

  /// 1dp. A divider, an outline, a chip.
  final double thin;

  /// 2dp. A button, a text field, a list tile.
  final double standard;

  /// 4dp. A card, a dialog, a menu surface.
  final double raised;

  /// 8dp. An app bar, a navigation bar, a sheet.
  final double structural;

  /// The `Stack3d.depthStep` this scale is meant to be stacked on, in logical
  /// pixels.
  ///
  /// Not applied by anything automatically — a stack takes its step in world
  /// units and knows nothing about themes. It is here so that the number a
  /// layout uses and the numbers the components are built from can be
  /// checked against each other instead of drifting apart silently.
  final double depthStep;

  /// The smallest step that genuinely separates a [back] slab from a [front]
  /// one, in the same unit both are stated in.
  ///
  /// Each slab is centred on its own plane and reaches half its thickness
  /// either side, so the gap the step has to clear is the mean of the two.
  static double minimumStepFor(double back, double front) =>
      (back + front) / 2.0;

  /// Whether [depthStep] (or an explicit [step]) keeps a [back] slab behind a
  /// [front] one everywhere they overlap.
  ///
  /// Strict: equal is coplanar at the touching faces, which is exactly the
  /// z-fight the step exists to prevent.
  bool separates(double back, double front, {double? step}) =>
      (step ?? depthStep) > minimumStepFor(back, front);

  /// A copy with the given steps replaced.
  Thickness3d copyWith({
    double? thin,
    double? standard,
    double? raised,
    double? structural,
    double? depthStep,
  }) => Thickness3d(
    thin: thin ?? this.thin,
    standard: standard ?? this.standard,
    raised: raised ?? this.raised,
    structural: structural ?? this.structural,
    depthStep: depthStep ?? this.depthStep,
  );

  /// Linearly interpolates between two thickness scales.
  static Thickness3d lerp(Thickness3d a, Thickness3d b, double t) =>
      Thickness3d(
        thin: _lerp(a.thin, b.thin, t),
        standard: _lerp(a.standard, b.standard, t),
        raised: _lerp(a.raised, b.raised, t),
        structural: _lerp(a.structural, b.structural, t),
        depthStep: _lerp(a.depthStep, b.depthStep, t),
      );

  @override
  bool operator ==(Object other) =>
      other is Thickness3d &&
      other.thin == thin &&
      other.standard == standard &&
      other.raised == raised &&
      other.structural == structural &&
      other.depthStep == depthStep;

  @override
  int get hashCode =>
      Object.hash(thin, standard, raised, structural, depthStep);

  @override
  String toString() =>
      'Thickness3d($thin, $standard, $raised, $structural on $depthStep)';
}

/// Interpolates two dp figures and holds the result at or above zero.
///
/// A negative thickness or elevation is meaningless, and an overshooting
/// curve — `Curves.easeInBack`, a spring — will produce one if nothing stops
/// it. `BoxDecoration3d` asserts on a negative elevation, so this is the
/// difference between an animation that eases and one that crashes.
double _lerp(double a, double b, double t) =>
    lerpDouble(a, b, t)!.clamp(0.0, double.infinity);
