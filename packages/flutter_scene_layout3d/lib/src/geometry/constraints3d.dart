import 'edge_insets3d.dart';
import 'offset3d.dart';
import 'size3d.dart';

/// Immutable layout constraints for a 3D box, the 3D analogue of
/// [BoxConstraints].
///
/// This is the "constraints go down" half of the protocol: a parent hands
/// these to a child, the child picks a [Size3d] that satisfies them and hands
/// that back up. A child must never look at its position while sizing, and a
/// parent must never expect a size outside the constraints it gave.
class Constraints3d {
  /// Creates constraints from the six bounds.
  const Constraints3d({
    this.minWidth = 0.0,
    this.maxWidth = double.infinity,
    this.minHeight = 0.0,
    this.maxHeight = double.infinity,
    this.minDepth = 0.0,
    this.maxDepth = double.infinity,
  });

  /// Constraints satisfied only by exactly [size].
  Constraints3d.tight(Size3d size)
    : minWidth = size.width,
      maxWidth = size.width,
      minHeight = size.height,
      maxHeight = size.height,
      minDepth = size.depth,
      maxDepth = size.depth;

  /// Constraints that fix the axes given and leave the rest unbounded.
  const Constraints3d.tightFor({double? width, double? height, double? depth})
    : minWidth = width ?? 0.0,
      maxWidth = width ?? double.infinity,
      minHeight = height ?? 0.0,
      maxHeight = height ?? double.infinity,
      minDepth = depth ?? 0.0,
      maxDepth = depth ?? double.infinity;

  /// Constraints allowing anything up to [size] on each axis.
  Constraints3d.loose(Size3d size)
    : minWidth = 0.0,
      maxWidth = size.width,
      minHeight = 0.0,
      maxHeight = size.height,
      minDepth = 0.0,
      maxDepth = size.depth;

  /// Constraints that demand as much room as possible, fixed on the axes
  /// given.
  const Constraints3d.expand({double? width, double? height, double? depth})
    : minWidth = width ?? double.infinity,
      maxWidth = width ?? double.infinity,
      minHeight = height ?? double.infinity,
      maxHeight = height ?? double.infinity,
      minDepth = depth ?? double.infinity,
      maxDepth = depth ?? double.infinity;

  /// The smallest allowed width.
  final double minWidth;

  /// The largest allowed width.
  final double maxWidth;

  /// The smallest allowed height.
  final double minHeight;

  /// The largest allowed height.
  final double maxHeight;

  /// The smallest allowed depth.
  final double minDepth;

  /// The largest allowed depth.
  final double maxDepth;

  /// Constraints that permit any size at all.
  static const Constraints3d unbounded = Constraints3d();

  /// The smallest permitted size.
  Size3d get smallest => Size3d(minWidth, minHeight, minDepth);

  /// The largest permitted size.
  Size3d get biggest => Size3d(maxWidth, maxHeight, maxDepth);

  /// Whether exactly one size satisfies these constraints.
  bool get isTight => hasTightWidth && hasTightHeight && hasTightDepth;

  /// Whether the width is fully determined.
  bool get hasTightWidth => minWidth >= maxWidth;

  /// Whether the height is fully determined.
  bool get hasTightHeight => minHeight >= maxHeight;

  /// Whether the depth is fully determined.
  bool get hasTightDepth => minDepth >= maxDepth;

  /// Whether the width has a finite upper bound.
  bool get hasBoundedWidth => maxWidth < double.infinity;

  /// Whether the height has a finite upper bound.
  bool get hasBoundedHeight => maxHeight < double.infinity;

  /// Whether the depth has a finite upper bound.
  bool get hasBoundedDepth => maxDepth < double.infinity;

  /// Whether every minimum is at or below its maximum, and no bound is NaN.
  bool get isNormalized =>
      minWidth >= 0.0 &&
      minWidth <= maxWidth &&
      minHeight >= 0.0 &&
      minHeight <= maxHeight &&
      minDepth >= 0.0 &&
      minDepth <= maxDepth;

  /// The lower bound along [axis].
  double minAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => minWidth,
    Axis3d.vertical => minHeight,
    Axis3d.depth => minDepth,
  };

  /// The upper bound along [axis].
  double maxAlong(Axis3d axis) => switch (axis) {
    Axis3d.horizontal => maxWidth,
    Axis3d.vertical => maxHeight,
    Axis3d.depth => maxDepth,
  };

  /// Whether the upper bound along [axis] is finite.
  bool hasBoundedAlong(Axis3d axis) => maxAlong(axis) < double.infinity;

  /// The nearest width satisfying these constraints.
  double constrainWidth([double width = double.infinity]) =>
      width.clamp(minWidth, maxWidth);

  /// The nearest height satisfying these constraints.
  double constrainHeight([double height = double.infinity]) =>
      height.clamp(minHeight, maxHeight);

  /// The nearest depth satisfying these constraints.
  double constrainDepth([double depth = double.infinity]) =>
      depth.clamp(minDepth, maxDepth);

  /// The nearest extent along [axis] satisfying these constraints.
  double constrainAlong(Axis3d axis, double extent) =>
      extent.clamp(minAlong(axis), maxAlong(axis));

  /// The size closest to [size] that satisfies these constraints.
  Size3d constrain(Size3d size) => Size3d(
    constrainWidth(size.width),
    constrainHeight(size.height),
    constrainDepth(size.depth),
  );

  /// The size closest to the given extents that satisfies these constraints.
  Size3d constrainDimensions(double width, double height, double depth) =>
      Size3d(
        constrainWidth(width),
        constrainHeight(height),
        constrainDepth(depth),
      );

  /// Whether [size] satisfies these constraints.
  bool isSatisfiedBy(Size3d size) =>
      size.width >= minWidth &&
      size.width <= maxWidth &&
      size.height >= minHeight &&
      size.height <= maxHeight &&
      size.depth >= minDepth &&
      size.depth <= maxDepth;

  /// These constraints with every minimum dropped to zero.
  Constraints3d loosen() => Constraints3d(
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    maxDepth: maxDepth,
  );

  /// These constraints with the maxima reduced by [padding], and the minima
  /// reduced to match (never below zero).
  Constraints3d deflate(EdgeInsets3d padding) {
    final horizontal = padding.horizontal;
    final vertical = padding.vertical;
    final alongDepth = padding.alongDepth;
    final deflatedMinWidth = (minWidth - horizontal).clamp(
      0.0,
      double.infinity,
    );
    final deflatedMinHeight = (minHeight - vertical).clamp(
      0.0,
      double.infinity,
    );
    final deflatedMinDepth = (minDepth - alongDepth).clamp(
      0.0,
      double.infinity,
    );
    return Constraints3d(
      minWidth: deflatedMinWidth,
      maxWidth: maxWidth.isFinite
          ? (maxWidth - horizontal).clamp(deflatedMinWidth, double.infinity)
          : double.infinity,
      minHeight: deflatedMinHeight,
      maxHeight: maxHeight.isFinite
          ? (maxHeight - vertical).clamp(deflatedMinHeight, double.infinity)
          : double.infinity,
      minDepth: deflatedMinDepth,
      maxDepth: maxDepth.isFinite
          ? (maxDepth - alongDepth).clamp(deflatedMinDepth, double.infinity)
          : double.infinity,
    );
  }

  /// These constraints clamped into [constraints].
  ///
  /// The result satisfies [constraints] while staying as close as it can to
  /// these; this is how a `ConstrainedBox3d` combines what it was given with
  /// what it wants.
  Constraints3d enforce(Constraints3d constraints) => Constraints3d(
    minWidth: minWidth.clamp(constraints.minWidth, constraints.maxWidth),
    maxWidth: maxWidth.clamp(constraints.minWidth, constraints.maxWidth),
    minHeight: minHeight.clamp(constraints.minHeight, constraints.maxHeight),
    maxHeight: maxHeight.clamp(constraints.minHeight, constraints.maxHeight),
    minDepth: minDepth.clamp(constraints.minDepth, constraints.maxDepth),
    maxDepth: maxDepth.clamp(constraints.minDepth, constraints.maxDepth),
  );

  /// These constraints tightened toward the given extents, without leaving
  /// the range they already allow.
  Constraints3d tighten({double? width, double? height, double? depth}) {
    final tightWidth = width?.clamp(minWidth, maxWidth);
    final tightHeight = height?.clamp(minHeight, maxHeight);
    final tightDepth = depth?.clamp(minDepth, maxDepth);
    return Constraints3d(
      minWidth: tightWidth ?? minWidth,
      maxWidth: tightWidth ?? maxWidth,
      minHeight: tightHeight ?? minHeight,
      maxHeight: tightHeight ?? maxHeight,
      minDepth: tightDepth ?? minDepth,
      maxDepth: tightDepth ?? maxDepth,
    );
  }

  /// A copy with the bounds along [axis] replaced.
  Constraints3d withAxis(Axis3d axis, {double? min, double? max}) =>
      switch (axis) {
        Axis3d.horizontal => copyWith(minWidth: min, maxWidth: max),
        Axis3d.vertical => copyWith(minHeight: min, maxHeight: max),
        Axis3d.depth => copyWith(minDepth: min, maxDepth: max),
      };

  /// A copy with the given bounds replaced.
  Constraints3d copyWith({
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
    double? minDepth,
    double? maxDepth,
  }) => Constraints3d(
    minWidth: minWidth ?? this.minWidth,
    maxWidth: maxWidth ?? this.maxWidth,
    minHeight: minHeight ?? this.minHeight,
    maxHeight: maxHeight ?? this.maxHeight,
    minDepth: minDepth ?? this.minDepth,
    maxDepth: maxDepth ?? this.maxDepth,
  );

  /// These constraints with each minimum pulled down to its maximum where the
  /// two crossed over.
  Constraints3d normalize() {
    if (isNormalized) return this;
    final normalizedMinWidth = minWidth.clamp(0.0, double.infinity);
    final normalizedMinHeight = minHeight.clamp(0.0, double.infinity);
    final normalizedMinDepth = minDepth.clamp(0.0, double.infinity);
    return Constraints3d(
      minWidth: normalizedMinWidth,
      maxWidth: normalizedMinWidth > maxWidth ? normalizedMinWidth : maxWidth,
      minHeight: normalizedMinHeight,
      maxHeight: normalizedMinHeight > maxHeight
          ? normalizedMinHeight
          : maxHeight,
      minDepth: normalizedMinDepth,
      maxDepth: normalizedMinDepth > maxDepth ? normalizedMinDepth : maxDepth,
    );
  }

  Constraints3d operator *(double factor) => Constraints3d(
    minWidth: minWidth * factor,
    maxWidth: maxWidth * factor,
    minHeight: minHeight * factor,
    maxHeight: maxHeight * factor,
    minDepth: minDepth * factor,
    maxDepth: maxDepth * factor,
  );

  /// Linearly interpolates between two sets of constraints.
  static Constraints3d lerp(Constraints3d a, Constraints3d b, double t) =>
      Constraints3d(
        minWidth: a.minWidth + (b.minWidth - a.minWidth) * t,
        maxWidth: a.maxWidth + (b.maxWidth - a.maxWidth) * t,
        minHeight: a.minHeight + (b.minHeight - a.minHeight) * t,
        maxHeight: a.maxHeight + (b.maxHeight - a.maxHeight) * t,
        minDepth: a.minDepth + (b.minDepth - a.minDepth) * t,
        maxDepth: a.maxDepth + (b.maxDepth - a.maxDepth) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is Constraints3d &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.minHeight == minHeight &&
      other.maxHeight == maxHeight &&
      other.minDepth == minDepth &&
      other.maxDepth == maxDepth;

  @override
  int get hashCode =>
      Object.hash(minWidth, maxWidth, minHeight, maxHeight, minDepth, maxDepth);

  @override
  String toString() =>
      'Constraints3d(w: $minWidth..$maxWidth, h: $minHeight..$maxHeight, '
      'd: $minDepth..$maxDepth)';
}
