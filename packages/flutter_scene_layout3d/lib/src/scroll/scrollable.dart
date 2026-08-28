import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DoubleProperty, FlagProperty, protected;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '../geometry/offset3d.dart';
import '../layout3d.dart';
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

  /// The nearest scrolling view at or above [descendant], or null.
  ///
  /// The tree walk behind [ensureVisible3d]: focus traversal and a menu both
  /// have a box in hand and need the view it lives in, and neither has any
  /// other way to find it. Every view here is a [Layout3d] as well as a
  /// [Scrollable3d], so the walk is an ordinary parent chain.
  static Scrollable3d? of(Layout3d descendant) {
    Layout3d? node = descendant;
    while (node != null) {
      if (node is Scrollable3d) return node as Scrollable3d;
      node = node.parent;
    }
    return null;
  }
}

/// The scroll offset that would put [target] inside [view]'s window, or null
/// when [target] is not inside [view] or either has yet to be laid out.
///
/// [alignment] says where in the window the target should land: `0.0` puts
/// its leading edge on the window's leading edge, `1.0` its trailing edge on
/// the window's trailing edge, `0.5` centres it. **Null, the default, is the
/// minimal scroll**: a target already fully visible does not move at all, and
/// one that is not is brought just inside the nearer edge. That is what focus
/// traversal wants — arrowing down a list should slide it by one row, not
/// jump the focused row to the top — and it is why the default here differs
/// from Flutter's `RenderAbstractViewport.getOffsetToReveal`, which has no
/// such mode and takes 0.0.
///
/// The walk sums the layout offsets between the two, so a
/// [Layout3d.localTransform] in between (a `Transform3d`, a rotated
/// container) is not accounted for: the answer is where the target is on the
/// scroll axis before any such turn. Scene-only nudges
/// ([ParentData3d.sceneOffset], [Layout3d.nodeOffset]) are ignored by
/// construction, which is right — a box being animated toward the viewer has
/// not moved down the list.
double? offsetToReveal3d(
  Scrollable3d view,
  Layout3d target, {
  double? alignment,
}) {
  final axis = view.scrollAxis;
  final controller = view.controller;
  var along = 0.0;
  Layout3d? node = target;
  while (node != null && !identical(node, view)) {
    along += node.offset.alongAxis(axis);
    node = node.parent;
  }
  if (node == null || !target.hasSize) return null;
  // The view places its content at minus the scroll offset, however many
  // boxes deep, so undoing that turns a position in the window into a
  // position in the content.
  final leading = along + controller.offset;
  final extent = target.size.alongAxis(axis);
  final window = controller.viewportExtent;
  if (alignment != null) return leading - alignment * (window - extent);
  final trailing = leading + extent;
  if (leading < controller.offset) return leading;
  if (trailing > controller.offset + window) return trailing - window;
  return controller.offset;
}

/// Scrolls the view [target] lives in until [target] is inside its window.
///
/// The hard requirement behind focus traversal and menus: something has been
/// focused, or chosen, and it may be off-screen. Finds the nearest enclosing
/// [Scrollable3d] — pass [within] to name one further up — works out where it
/// would have to be scrolled to (see [offsetToReveal3d] for [alignment]), and
/// animates there over [duration], which defaults to jumping.
///
/// Answers a future that completes when the motion stops, and completes at
/// once when there is nothing to do: no enclosing view, a target that is
/// already visible, or a view with nothing to scroll.
Future<void> ensureVisible3d(
  Layout3d target, {
  double? alignment,
  Duration duration = Duration.zero,
  Curve curve = Curves.easeInOut,
  TickerProvider? vsync,
  Scrollable3d? within,
}) {
  final view = within ?? Scrollable3d.of(target.parent ?? target);
  if (view == null) return Future<void>.value();
  final to = offsetToReveal3d(view, target, alignment: alignment);
  if (to == null) return Future<void>.value();
  return view.controller.animateTo(
    to,
    duration: duration,
    curve: curve,
    vsync: vsync,
  );
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('offset', controller.offset));
    properties.add(
      DoubleProperty('minScrollExtent', controller.minScrollExtent),
    );
    properties.add(
      DoubleProperty('maxScrollExtent', controller.maxScrollExtent),
    );
    properties.add(DoubleProperty('viewportExtent', controller.viewportExtent));
    properties.add(
      FlagProperty(
        'outOfRange',
        value: controller.outOfRange,
        ifTrue: 'OUT-OF-RANGE',
      ),
    );
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
