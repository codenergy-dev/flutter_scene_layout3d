import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show Cubic, Curve;

/// Material 3's durations and easing curves: how long a thing takes, and on
/// what curve.
///
/// The seventh token family, and the last of the transcribed ones. Sixteen
/// durations from 50ms to a full second, and nine curves — and both sets are
/// **exactly** Flutter's own [Durations] and [Easing], which are generated
/// straight from the Material token database.
///
/// That makes this the strongest drift lane in the package.
/// `ColorScheme3d` compares against public constants and `DialogStyle3d` has
/// to render a real `Dialog` and read the `Material` out of it, because the
/// defaults it wants are private. Here there is nothing to render and nothing
/// to reflect over: `test/motion_test.dart` compares value to value, and a
/// figure that moves upstream fails on the next `flutter upgrade`.
///
/// ```dart
/// final motion = Theme3d.of(context).motion;
/// final route = WidgetPageRoute3d<void>(
///   transition: TimedRoute3dTransition(
///     duration: motion.short3,               // 150ms
///     curve: motion.emphasizedDecelerate,    // arriving
///     reverseCurve: motion.emphasizedAccelerate,
///   ),
///   builder: ...,
/// );
/// ```
///
/// ## What this family is for, and what it is not
///
/// It is a **vocabulary, not a cage.** A component style may hold any
/// duration it can defend: `InkRipple3dStyle` carries 75ms, 225ms and 375ms,
/// which are Flutter's own `InkRipple` figures and not tokens at all, and the
/// tooltip's 75ms fade-out is the same story. The family exists so that the
/// figures which *do* agree say so in one place — which is what makes a theme
/// able to slow every arrival down at once.
///
/// ## Two curves are equal when they are the same curve
///
/// `Curve` has no value equality in Flutter — `Cubic` does not override `==`
/// — so two easings compare by identity, and a [MotionScheme3d] therefore
/// does too. That is exactly right for the way this family is used: the
/// baseline's curves are `const`, Dart canonicalizes them, and
/// `MotionScheme3d.baseline.standard == Easing.standard` is true because
/// they are the same object. A theme that builds a curve at runtime with
/// `Cubic(...)` gets a scheme that is not equal to one built the same way a
/// second time, which is a reason to hold such a curve in a `static const`
/// rather than a reason to invent an equality Flutter does not have.
///
/// It was deliberately closed until there were enough customers to know which
/// tokens get used. The catalogue plan refused it three times, and the
/// sentence it refused with was *one animation is not a scale*. Six overlays
/// arriving is.
///
/// [Durations]: https://api.flutter.dev/flutter/material/Durations-class.html
/// [Easing]: https://api.flutter.dev/flutter/material/Easing-class.html
class MotionScheme3d {
  /// Creates a motion scheme. Every token defaults to Material's own figure.
  const MotionScheme3d({
    this.short1 = const Duration(milliseconds: 50),
    this.short2 = const Duration(milliseconds: 100),
    this.short3 = const Duration(milliseconds: 150),
    this.short4 = const Duration(milliseconds: 200),
    this.medium1 = const Duration(milliseconds: 250),
    this.medium2 = const Duration(milliseconds: 300),
    this.medium3 = const Duration(milliseconds: 350),
    this.medium4 = const Duration(milliseconds: 400),
    this.long1 = const Duration(milliseconds: 450),
    this.long2 = const Duration(milliseconds: 500),
    this.long3 = const Duration(milliseconds: 550),
    this.long4 = const Duration(milliseconds: 600),
    this.extraLong1 = const Duration(milliseconds: 700),
    this.extraLong2 = const Duration(milliseconds: 800),
    this.extraLong3 = const Duration(milliseconds: 900),
    this.extraLong4 = const Duration(milliseconds: 1000),
    this.emphasizedAccelerate = const Cubic(0.3, 0.0, 0.8, 0.15),
    this.emphasizedDecelerate = const Cubic(0.05, 0.7, 0.1, 1.0),
    this.standard = const Cubic(0.2, 0.0, 0.0, 1.0),
    this.standardAccelerate = const Cubic(0.3, 0.0, 1.0, 1.0),
    this.standardDecelerate = const Cubic(0.0, 0.0, 0.0, 1.0),
    this.legacy = const Cubic(0.4, 0.0, 0.2, 1.0),
    this.legacyAccelerate = const Cubic(0.4, 0.0, 1.0, 1.0),
    this.legacyDecelerate = const Cubic(0.0, 0.0, 0.2, 1.0),
    this.linear = const Cubic(0.0, 0.0, 1.0, 1.0),
  });

  /// Material 3's published figures, which are the ones in every constructor
  /// default above.
  static const MotionScheme3d baseline = MotionScheme3d();

  /// 50ms. The shortest thing a person can be said to have seen move.
  final Duration short1;

  /// 100ms.
  final Duration short2;

  /// 150ms. A dialog arriving, and a tooltip fading in.
  final Duration short3;

  /// 200ms. A bottom sheet leaving.
  final Duration short4;

  /// 250ms. A bottom sheet arriving, and a snack bar either way.
  final Duration medium1;

  /// 300ms. A menu, both ways.
  final Duration medium2;

  /// 350ms.
  final Duration medium3;

  /// 400ms.
  final Duration medium4;

  /// 450ms.
  final Duration long1;

  /// 500ms.
  final Duration long2;

  /// 550ms.
  final Duration long3;

  /// 600ms.
  final Duration long4;

  /// 700ms.
  final Duration extraLong1;

  /// 800ms.
  final Duration extraLong2;

  /// 900ms.
  final Duration extraLong3;

  /// 1000ms. A second, which in motion terms is a very long time.
  final Duration extraLong4;

  /// Leaving, with emphasis: starts slowly and is gone.
  ///
  /// The curve every overlay in this catalogue departs on. It is the shape of
  /// something getting out of the way — most of the distance is covered at
  /// the end, so the eye is not asked to follow it out.
  final Curve emphasizedAccelerate;

  /// Arriving, with emphasis: covers most of the distance at once and settles.
  ///
  /// The curve every overlay in this catalogue arrives on, and M3's worked
  /// example of an enter transition. **This is a deliberate divergence from
  /// Flutter**, whose `showDialog` opens on `Curves.easeOut` and whose modal
  /// sheet opens on [legacyDecelerate] — both of which predate the motion
  /// tokens, as the second one says in its own name.
  final Curve emphasizedDecelerate;

  /// The everyday curve: for a thing that moves within the screen rather than
  /// on or off it.
  final Curve standard;

  /// The everyday curve for something leaving.
  final Curve standardAccelerate;

  /// The everyday curve for something arriving.
  final Curve standardDecelerate;

  /// Material 2's curve, kept because M3 keeps it.
  final Curve legacy;

  /// Material 2's accelerating curve.
  final Curve legacyAccelerate;

  /// Material 2's decelerating curve, which Flutter's modal bottom sheet
  /// still uses.
  final Curve legacyDecelerate;

  /// No easing at all. A straight line, expressed as a cubic so that it is
  /// the same kind of thing as its neighbours.
  final Curve linear;

  /// A copy with the given tokens replaced.
  MotionScheme3d copyWith({
    Duration? short1,
    Duration? short2,
    Duration? short3,
    Duration? short4,
    Duration? medium1,
    Duration? medium2,
    Duration? medium3,
    Duration? medium4,
    Duration? long1,
    Duration? long2,
    Duration? long3,
    Duration? long4,
    Duration? extraLong1,
    Duration? extraLong2,
    Duration? extraLong3,
    Duration? extraLong4,
    Curve? emphasizedAccelerate,
    Curve? emphasizedDecelerate,
    Curve? standard,
    Curve? standardAccelerate,
    Curve? standardDecelerate,
    Curve? legacy,
    Curve? legacyAccelerate,
    Curve? legacyDecelerate,
    Curve? linear,
  }) => MotionScheme3d(
    short1: short1 ?? this.short1,
    short2: short2 ?? this.short2,
    short3: short3 ?? this.short3,
    short4: short4 ?? this.short4,
    medium1: medium1 ?? this.medium1,
    medium2: medium2 ?? this.medium2,
    medium3: medium3 ?? this.medium3,
    medium4: medium4 ?? this.medium4,
    long1: long1 ?? this.long1,
    long2: long2 ?? this.long2,
    long3: long3 ?? this.long3,
    long4: long4 ?? this.long4,
    extraLong1: extraLong1 ?? this.extraLong1,
    extraLong2: extraLong2 ?? this.extraLong2,
    extraLong3: extraLong3 ?? this.extraLong3,
    extraLong4: extraLong4 ?? this.extraLong4,
    emphasizedAccelerate: emphasizedAccelerate ?? this.emphasizedAccelerate,
    emphasizedDecelerate: emphasizedDecelerate ?? this.emphasizedDecelerate,
    standard: standard ?? this.standard,
    standardAccelerate: standardAccelerate ?? this.standardAccelerate,
    standardDecelerate: standardDecelerate ?? this.standardDecelerate,
    legacy: legacy ?? this.legacy,
    legacyAccelerate: legacyAccelerate ?? this.legacyAccelerate,
    legacyDecelerate: legacyDecelerate ?? this.legacyDecelerate,
    linear: linear ?? this.linear,
  );

  /// Linearly interpolates between two schemes.
  ///
  /// **The durations interpolate and the curves do not.** A [Curve] is a
  /// function, and there is no value half way between [standard] and
  /// [emphasizedDecelerate] that is itself a curve — so the easings snap at
  /// the midpoint, taking `a`'s below `t` of 0.5 and `b`'s at or above it.
  /// That is what `TextStyle.lerp` does with every discrete field it carries,
  /// and for the same reason.
  ///
  /// It is worth knowing rather than hiding: a theme cross-fade changes its
  /// curves once, half way through, while the durations underneath move
  /// continuously — so nothing visibly jumps, and the one frame it happens on
  /// is a frame where both curves are producing nearly the same number
  /// anyway.
  static MotionScheme3d lerp(MotionScheme3d a, MotionScheme3d b, double t) {
    final easings = t < 0.5 ? a : b;
    return MotionScheme3d(
      short1: _lerp(a.short1, b.short1, t),
      short2: _lerp(a.short2, b.short2, t),
      short3: _lerp(a.short3, b.short3, t),
      short4: _lerp(a.short4, b.short4, t),
      medium1: _lerp(a.medium1, b.medium1, t),
      medium2: _lerp(a.medium2, b.medium2, t),
      medium3: _lerp(a.medium3, b.medium3, t),
      medium4: _lerp(a.medium4, b.medium4, t),
      long1: _lerp(a.long1, b.long1, t),
      long2: _lerp(a.long2, b.long2, t),
      long3: _lerp(a.long3, b.long3, t),
      long4: _lerp(a.long4, b.long4, t),
      extraLong1: _lerp(a.extraLong1, b.extraLong1, t),
      extraLong2: _lerp(a.extraLong2, b.extraLong2, t),
      extraLong3: _lerp(a.extraLong3, b.extraLong3, t),
      extraLong4: _lerp(a.extraLong4, b.extraLong4, t),
      emphasizedAccelerate: easings.emphasizedAccelerate,
      emphasizedDecelerate: easings.emphasizedDecelerate,
      standard: easings.standard,
      standardAccelerate: easings.standardAccelerate,
      standardDecelerate: easings.standardDecelerate,
      legacy: easings.legacy,
      legacyAccelerate: easings.legacyAccelerate,
      legacyDecelerate: easings.legacyDecelerate,
      linear: easings.linear,
    );
  }

  /// Interpolates one duration, held at zero or above.
  ///
  /// Clamped for the reason `Elevation3d.lerp` and `StateLayerOpacity3d.lerp`
  /// are: an overshooting curve produces a negative by construction, and a
  /// negative duration drives an `AnimationController` backwards through
  /// time.
  static Duration _lerp(Duration a, Duration b, double t) {
    final micros = lerpDouble(a.inMicroseconds, b.inMicroseconds, t)!.round();
    return Duration(microseconds: micros < 0 ? 0 : micros);
  }

  List<Object?> get _fields => <Object?>[
    short1,
    short2,
    short3,
    short4,
    medium1,
    medium2,
    medium3,
    medium4,
    long1,
    long2,
    long3,
    long4,
    extraLong1,
    extraLong2,
    extraLong3,
    extraLong4,
    emphasizedAccelerate,
    emphasizedDecelerate,
    standard,
    standardAccelerate,
    standardDecelerate,
    legacy,
    legacyAccelerate,
    legacyDecelerate,
    linear,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MotionScheme3d) return false;
    final mine = _fields;
    final theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() =>
      'MotionScheme3d(short3: ${short3.inMilliseconds}ms, '
      'medium1: ${medium1.inMilliseconds}ms)';
}
