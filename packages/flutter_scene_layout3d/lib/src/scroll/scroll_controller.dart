import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ChangeNotifier;

/// The scroll offset of a [Viewport3d] or [ListView3d], and the metrics the
/// view reports back.
///
/// Deliberately thin: it holds a position and clamps it to what the content
/// allows. There is no physics, no fling, and no animation in this release,
/// because in a 3D scene the gesture that drives scrolling is the
/// application's to choose (a drag on the `SceneView`, a raycast, a
/// controller stick). Drive [offset] from whatever input you have.
class Scroll3dController extends ChangeNotifier {
  /// Creates a controller starting at [initialOffset].
  Scroll3dController({double initialOffset = 0.0}) : _offset = initialOffset;

  double _offset;

  /// How far the content is scrolled, in layout units along the view's axis.
  ///
  /// Zero shows the start of the content; larger values move the content
  /// toward the low face (up, for a vertical list), the same sense as
  /// Flutter's scroll offsets.
  double get offset => _offset;

  set offset(double value) {
    final clamped = value.clamp(0.0, _maxScrollExtent);
    if (clamped == _offset) return;
    _offset = clamped;
    notifyListeners();
  }

  double _maxScrollExtent = 0.0;

  /// The largest useful [offset], set by the view during layout.
  double get maxScrollExtent => _maxScrollExtent;

  double _viewportExtent = 0.0;

  /// The extent of the scrolling window along its axis, set by the view.
  double get viewportExtent => _viewportExtent;

  /// The extent of the content along the view's axis.
  double get contentExtent => _maxScrollExtent + _viewportExtent;

  /// Whether the content is longer than the window.
  bool get canScroll => _maxScrollExtent > 0.0;

  /// Jumps to [value], clamped to the scrollable range.
  void jumpTo(double value) => offset = value;

  /// Moves by [delta], clamped to the scrollable range.
  void jumpBy(double delta) => offset = _offset + delta;

  /// Records the metrics measured during layout, clamping [offset] into the
  /// new range.
  ///
  /// Called by the view; a change here notifies listeners so a host can
  /// react, but the view has already used the clamped value for this pass.
  void applyViewportMetrics({
    required double maxScrollExtent,
    required double viewportExtent,
  }) {
    final clampedMax = math.max(0.0, maxScrollExtent);
    final clampedOffset = _offset.clamp(0.0, clampedMax);
    final offsetChanged = clampedOffset != _offset;
    _maxScrollExtent = clampedMax;
    _viewportExtent = viewportExtent;
    _offset = clampedOffset;
    // Only a moved position is worth waking listeners for; the metrics
    // themselves are recorded silently, because this runs during layout.
    if (offsetChanged) notifyListeners();
  }
}
