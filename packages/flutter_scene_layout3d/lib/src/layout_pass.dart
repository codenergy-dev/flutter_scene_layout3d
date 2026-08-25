import 'package:flutter/foundation.dart' show protected;

import 'layout3d.dart';

/// A layout that edits its own tree while it is being laid out, and ignores
/// the dirt that raises.
///
/// A view that builds children as its window reaches them, or that reads a
/// scroll position it also writes to, changes state during `performLayout`
/// that would ordinarily mark it as needing layout again. Left alone that is
/// either a wasted second pass or an infinite one. Wrapping the pass in
/// [runLayoutPass] makes [markNeedsLayout] a no-op for its duration, which is
/// what Flutter's `RenderObject` gets from `_doingThisLayoutWithCallback`.
///
/// Kept apart from [Layout3dBuiltChildrenMixin] because the two needs do not
/// travel together: `CustomScrollView3d` holds a scroll position without
/// building children, and `Viewport3d` holds one with a single child.
mixin Layout3dLayoutPassMixin on Layout3d {
  bool _layingOut = false;

  /// Whether a layout pass is running on this layout.
  @protected
  bool get layingOut => _layingOut;

  /// Runs [body] as this layout's pass, ignoring dirt it raises here.
  ///
  /// Wrap the whole of `performLayout` (or `performSliverLayout`) in this
  /// rather than setting a flag by hand, so that an exception thrown from the
  /// middle of a pass does not leave the layout permanently deaf.
  @protected
  void runLayoutPass(void Function() body) {
    _layingOut = true;
    try {
      body();
    } finally {
      _layingOut = false;
    }
  }

  @override
  void markNeedsLayout() {
    if (_layingOut) return;
    super.markNeedsLayout();
  }
}
