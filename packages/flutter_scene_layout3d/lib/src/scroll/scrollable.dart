import 'package:flutter/foundation.dart' show protected;

import '../geometry/offset3d.dart';
import '../layout_pass.dart';
import 'scroll_controller.dart';

/// What every scrolling view in this package has in common: an axis and a
/// position.
///
/// The handle input code reaches for. A hit test returns the layouts a ray
/// passed through, and asking that path for the nearest [Scrollable3d] is how
/// a drag finds the view it should move, whether that is a [Viewport3d] or a
/// [ListView3d]:
///
/// ```dart
/// final scrollable = surface.hitTestRay(ray).firstOf<Scrollable3d>();
/// ```
abstract interface class Scrollable3d {
  /// The axis the content moves along, in the view's own layout space.
  Axis3d get scrollAxis;

  /// The position, and the metrics the view measured for it.
  Scroll3dController get controller;
}

/// The scroll position a view holds, and the ownership rule that goes with it.
///
/// `Viewport3d`, `ListView3d`, `GridView3d` and `CustomScrollView3d` all take
/// an optional [Scroll3dController], relay out when it moves, and have to
/// decide who disposes it. That is the same six members four times over, and
/// the rule underneath them is easy to get subtly wrong, so it lives here
/// once.
///
/// The rule is that **null means the default**, and the default position is
/// one the view owns:
///
///  * a constructor given null makes a controller and owns it;
///  * `controller = other` detaches from the old one, disposes it only if the
///    view owned it, and does not take ownership of `other`;
///  * `controller = null` makes a fresh one and owns that;
///  * [dispose] detaches, and disposes only what the view owned.
///
/// So a declarative caller that stops passing a controller gets a working
/// view with a fresh position, rather than one still driven by the controller
/// it passed two rebuilds ago.
///
/// A view mixes this in, calls [initController] from its constructor body,
/// and supplies [scrollAxis] itself.
mixin Scroll3dHolderMixin on Layout3dLayoutPassMixin implements Scrollable3d {
  Scroll3dController? _held;
  bool _ownsController = true;

  /// The scroll position, and the metrics this view measured for it.
  @override
  Scroll3dController get controller {
    assert(
      _held != null,
      '$runtimeType has no scroll controller yet. A view mixing in '
      'Scroll3dHolderMixin must call initController(controller) from its '
      'constructor body.',
    );
    return _held!;
  }

  /// Sets the position, or hands ownership back with null.
  set controller(Scroll3dController? value) {
    final held = controller;
    if (identical(held, value)) return;
    held.removeListener(_handleScrollChanged);
    if (_ownsController) held.dispose();
    _ownsController = value == null;
    _held = (value ?? Scroll3dController())..addListener(_handleScrollChanged);
    markNeedsLayout();
  }

  /// Installs the controller a constructor was handed, making one when it was
  /// handed null. Constructor bodies only.
  ///
  /// A mixin has no constructor, so this cannot happen in an initializer
  /// list; miss the call and the first read of [controller] says so.
  @protected
  void initController(Scroll3dController? value) {
    assert(
      _held == null,
      '$runtimeType called initController twice. It installs the controller a '
      'constructor was given; assign to controller to change it afterwards.',
    );
    _ownsController = value == null;
    _held = (value ?? Scroll3dController())..addListener(_handleScrollChanged);
  }

  /// A scroll position that moved needs a new layout, unless it moved
  /// *during* one — and [Layout3dLayoutPassMixin.markNeedsLayout] already
  /// ignores that case.
  void _handleScrollChanged() => markNeedsLayout();

  @override
  void dispose() {
    final held = _held;
    if (held != null) {
      held.removeListener(_handleScrollChanged);
      if (_ownsController) held.dispose();
    }
    super.dispose();
  }
}

/// What a scrolling view answers when it is asked how much room it wants.
///
/// Nothing honest, which is the point. A viewport's content is as long as it
/// is, and the view exists precisely so that it need not grow to match, so
/// there is no extent it would like. Flutter throws here; this asserts, and
/// answers zero in release so that a layout degrades rather than dies.
///
/// A scrolling view that has to sit inside an [IntrinsicHeight3d] should be
/// given a size instead, with a [SizedBox3d].
double noIntrinsicExtent(Object view, Axis3d axis) {
  assert(
    false,
    '$view was asked for its intrinsic extent along $axis. A scrolling view '
    'has none: its content is whatever length it is, and the view does not '
    'grow to match it. Give it a size instead.',
  );
  return 0.0;
}
