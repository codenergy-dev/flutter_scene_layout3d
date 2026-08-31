/// A one-dimensional velocity estimate over the last stretch of a drag.
///
/// Shared by everything in the package that has to tell a flick from a slow
/// drag: the scroll drag `_Sequence` runs, and the swipe a [Dismissible3d]
/// decides on. Internal — a caller with real pointer events has Flutter's own
/// `VelocityTracker`.
///
/// Flutter's `VelocityTracker` cannot be used here. It timestamps its own
/// samples from `GestureBinding.instance.samplingClock`, which in a test
/// binding asserts that a widget test is running — and this package's pointer
/// is driven from plain `test` cases, and in an application from whatever
/// clock the host has. Every position this sees already comes with the
/// timestamp the caller handed [Layout3dPointer.move], so the tracker only
/// has to do the arithmetic.
///
/// A straight least-squares fit over the samples inside [_horizon], which is
/// enough for a fling: the curve a finger draws in the last tenth of a second
/// before it lifts is close enough to a line that a quadratic fit buys
/// nothing a scroll position can feel.
class Drag3dVelocityTracker {
  static const Duration _horizon = Duration(milliseconds: 100);

  /// Fewer samples than this is not a gesture with a direction.
  static const int _minSamples = 3;

  /// Samples spanning less time than this cannot be trusted.
  ///
  /// Two positions a few microseconds apart divide into an enormous speed,
  /// and that is exactly what a synthesized drag looks like when the caller
  /// leaves the timestamps to the wall clock — a whole gesture inside one
  /// millisecond. Below this the release is treated as being at rest, so a
  /// test that wants a fling passes real timestamps, which is also what a
  /// real pointer does.
  static const Duration _minSpan = Duration(milliseconds: 2);

  final List<Duration> _times = <Duration>[];
  final List<double> _positions = <double>[];

  void add(Duration time, double position) {
    _times.add(time);
    _positions.add(position);
    while (_times.length > 1 && time - _times.first > _horizon) {
      _times.removeAt(0);
      _positions.removeAt(0);
    }
  }

  /// The speed the pointer was moving at, in layout units per second, or zero
  /// when there is not enough to say.
  double estimate() {
    final count = _times.length;
    if (count < _minSamples) return 0.0;
    final span = _times.last - _times.first;
    if (span < _minSpan) return 0.0;
    final origin = _times.first;
    var sumT = 0.0;
    var sumP = 0.0;
    var sumTT = 0.0;
    var sumTP = 0.0;
    for (var i = 0; i < count; i++) {
      final t =
          (_times[i] - origin).inMicroseconds / Duration.microsecondsPerSecond;
      final p = _positions[i];
      sumT += t;
      sumP += p;
      sumTT += t * t;
      sumTP += t * p;
    }
    final denominator = count * sumTT - sumT * sumT;
    if (denominator == 0.0) return 0.0;
    return (count * sumTP - sumT * sumP) / denominator;
  }
}
