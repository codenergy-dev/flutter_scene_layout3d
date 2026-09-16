import 'dart:ui' show Color, Offset, Rect, TileMode;

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, ErrorDescription;
import 'package:flutter/painting.dart'
    show Gradient, LinearGradient, RadialGradient, SweepGradient, TextDirection;

import '../geometry/size3d.dart';

/// Which shape a gradient's `t` is measured along.
///
/// The three Flutter has, and the three the panel shader knows how to
/// evaluate. The numbers are the ones the shader's `gradient.x` carries, so
/// they are part of the seam rather than an implementation detail.
enum GradientKind3d {
  /// [LinearGradient]: `t` along the line from `begin` to `end`.
  linear(1),

  /// [RadialGradient]: `t` is the distance from the centre over the radius.
  radial(2),

  /// [SweepGradient]: `t` is the angle round the centre.
  sweep(3);

  const GradientKind3d(this.shaderValue);

  /// What the shader's `gradient.x` holds for this kind.
  final int shaderValue;
}

/// A gradient resolved against a box: its geometry in world units, and its
/// ramp as a fixed number of stops.
///
/// The arithmetic half of a gradient, and it is uniforms rather than a
/// texture on purpose. A ramp baked into a texture would hold any number of
/// stops and would cost a GPU upload every time a colour changed — which is
/// every frame of a decoration animating between two gradients, on the one
/// tier this package promises is a parameter write. Uniforms keep that
/// promise, and pay for it with a ceiling: [maxStops].
///
/// The geometry is Skia's, one kind at a time, measured in the box's own
/// frame with the origin at its corner: [LinearGradient]'s `begin` and `end`
/// resolved within the box, [RadialGradient]'s centre and its radius times
/// the box's shorter side, [SweepGradient]'s centre and its two angles.
class GradientUniforms3d {
  /// Records a resolved gradient.
  const GradientUniforms3d({
    required this.kind,
    required this.tileMode,
    required this.geometry,
    required this.stops,
    required this.colors,
  }) : assert(stops.length == colors.length);

  /// How many stops the shader has room for.
  ///
  /// Eight, which covers every gradient in the Material guidance and nearly
  /// every brand one. A gradient with more is **resampled** to eight evenly
  /// spaced colours off its own ramp rather than refused, and says so once in
  /// a debug build: a banner drawn slightly wrong is a better failure than an
  /// application that will not start.
  static const int maxStops = 8;

  /// Which shape `t` is measured along.
  final GradientKind3d kind;

  /// What happens outside `[0, 1]`.
  final TileMode tileMode;

  /// Four numbers whose meaning depends on [kind]: a linear gradient's start
  /// and end points, a radial one's centre and radius, or a sweep's centre
  /// and its start and end angles in radians. Points are in world units in
  /// the box's own frame.
  final List<double> geometry;

  /// The stop positions, ascending, at most [maxStops] of them.
  final List<double> stops;

  /// The colour at each stop, in **sRGB**.
  ///
  /// Not decoded to linear, and the shader does not decode them either until
  /// it has interpolated between two of them. Skia interpolates a gradient in
  /// sRGB with straight alpha, so a red-to-green gradient's midpoint is a
  /// particular muddy brown — and one interpolated in linear light is
  /// visibly a different colour. A gradient that did not match the one the
  /// same application draws in two dimensions would be a bug nobody could
  /// name.
  final List<Color> colors;

  /// Resolves [gradient] against a box of [size], or null when nothing can be
  /// drawn for it.
  ///
  /// Null for a gradient type this package does not know, and for the two
  /// features the shader has no arithmetic for — a [Gradient.transform] and a
  /// [RadialGradient.focal] — each reported once in a debug build.
  static GradientUniforms3d? resolve({
    required Gradient gradient,
    required Size3d size,
    TextDirection? textDirection,
  }) {
    if (gradient.transform != null) {
      _report(gradient, 'carries a GradientTransform');
      return null;
    }
    final rect = Rect.fromLTWH(0.0, 0.0, size.width, size.height);
    final GradientKind3d kind;
    final List<double> geometry;
    final TileMode tileMode;
    switch (gradient) {
      case LinearGradient():
        final begin = gradient.begin.resolve(textDirection).withinRect(rect);
        final end = gradient.end.resolve(textDirection).withinRect(rect);
        kind = GradientKind3d.linear;
        geometry = <double>[begin.dx, begin.dy, end.dx, end.dy];
        tileMode = gradient.tileMode;
      case RadialGradient():
        if (gradient.focal != null) {
          _report(gradient, 'has a focal point');
          return null;
        }
        final centre = gradient.center.resolve(textDirection).withinRect(rect);
        kind = GradientKind3d.radial;
        geometry = <double>[
          centre.dx,
          centre.dy,
          gradient.radius * rect.shortestSide,
          0.0,
        ];
        tileMode = gradient.tileMode;
      case SweepGradient():
        final centre = gradient.center.resolve(textDirection).withinRect(rect);
        kind = GradientKind3d.sweep;
        geometry = <double>[
          centre.dx,
          centre.dy,
          gradient.startAngle,
          gradient.endAngle,
        ];
        tileMode = gradient.tileMode;
      default:
        _report(gradient, 'is not a kind the panel shader can evaluate');
        return null;
    }

    final colors = gradient.colors;
    if (colors.isEmpty) return null;
    final stops = stopsOf(colors, gradient.stops);
    if (colors.length <= maxStops) {
      return GradientUniforms3d(
        kind: kind,
        tileMode: tileMode,
        geometry: geometry,
        stops: stops,
        colors: colors,
      );
    }
    _report(gradient, 'has more than $maxStops stops and was resampled');
    return GradientUniforms3d(
      kind: kind,
      tileMode: tileMode,
      geometry: geometry,
      stops: <double>[for (var i = 0; i < maxStops; i++) i / (maxStops - 1)],
      colors: <Color>[
        for (var i = 0; i < maxStops; i++)
          colorAt(colors, stops, i / (maxStops - 1)),
      ],
    );
  }

  /// The stop positions for [colors], filling in Flutter's own evenly spaced
  /// defaults when [stops] says nothing.
  static List<double> stopsOf(List<Color> colors, List<double>? stops) {
    if (stops != null) return stops;
    if (colors.length == 1) return const <double>[0.0];
    return <double>[
      for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
    ];
  }

  /// The colour a ramp of [colors] at [stops] holds at [t].
  ///
  /// Skia's rule, and the shader's: below the first stop is the first colour,
  /// past the last is the last, and two stops at one position are a hard
  /// edge. Interpolated in sRGB, for the reason [colors] gives.
  static Color colorAt(List<Color> colors, List<double> stops, double t) {
    if (t <= stops.first) return colors.first;
    for (var i = 1; i < colors.length; i++) {
      if (t > stops[i]) continue;
      final span = stops[i] - stops[i - 1];
      final f = span > 0.0 ? (t - stops[i - 1]) / span : 1.0;
      return Color.lerp(colors[i - 1], colors[i], f)!;
    }
    return colors.last;
  }

  /// [geometry] as the shader's `gradient` vector: the kind, the tile mode
  /// and how many stops are in use.
  List<double> get descriptor => <double>[
    kind.shaderValue.toDouble(),
    tileMode.index.toDouble(),
    stops.length.toDouble(),
    0.0,
  ];

  /// The stops packed into two vectors of four, unused slots trailing.
  List<double> stopVector(int index) => <double>[
    for (var i = index * 4; i < index * 4 + 4; i++)
      i < stops.length ? stops[i] : 0.0,
  ];

  /// The point on the face [kind] measures `t` from, for a caller reasoning
  /// about the geometry without unpacking it.
  Offset get origin => Offset(geometry[0], geometry[1]);

  static final Set<Gradient> _reported = <Gradient>{};

  static void _report(Gradient gradient, String what) {
    assert(() {
      if (_reported.add(gradient)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: UnsupportedError(
              'A gradient on a BoxDecoration3d $what, which the panel shader '
              'cannot draw. See BoxDecoration3d.gradient for what is '
              'supported: $gradient',
            ),
            library: 'flutter_scene_layout3d',
            context: ErrorDescription('while resolving a decoration'),
          ),
        );
      }
      return true;
    }());
  }

  /// Forgets which gradients have been reported, so a test can provoke the
  /// same report twice.
  static void debugResetReports() {
    assert(() {
      _reported.clear();
      return true;
    }());
  }

  @override
  String toString() =>
      'GradientUniforms3d($kind, ${colors.length} stops, $tileMode)';
}
