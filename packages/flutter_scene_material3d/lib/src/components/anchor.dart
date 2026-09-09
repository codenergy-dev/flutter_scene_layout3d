import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, Widget, WidgetsBinding;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, Layout3dAnchoring, Offset3d, ProxyLayout3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show SingleChildLayout3dWidget;

// Anchoring one overlay to a box somewhere else in the tree.
//
// Two components need it — a menu at its button, a tooltip under the control
// it describes — and neither could have it before phase 6, because an overlay
// entry is placed by the overlay's own alignment and nothing in the stack
// anchored anything. `Layout3d.anchorOffsetTo` in the layout package is the
// arithmetic; these two boxes are what drive it.

/// The box an overlay is anchored to: whatever a `PopupMenuButton3d` or a
/// `Tooltip3d` wraps.
///
/// A proxy that reports when it has been **placed**, which is one of the two
/// hooks a follower needs. A scrolling view places its rows rather than
/// relaying them out, so a follower watching only for a relayout would never
/// hear about a scroll.
class Anchor3d extends ProxyLayout3d {
  /// Creates an anchor.
  Anchor3d({super.name = 'Anchor3d'});

  /// Called after this box has been positioned, every pass.
  VoidCallback? onPlaced;

  @override
  void place(Offset3d offset) {
    super.place(offset);
    onPlaced?.call();
  }
}

/// Hands the [Anchor3d] it creates back to whoever asked for it.
class Anchor3dWidget extends SingleChildLayout3dWidget {
  /// Creates an anchor around [child].
  const Anchor3dWidget({
    super.key,
    required this.onCreated,
    required super.child,
  });

  /// Called once, with the anchor this widget owns.
  final ValueChanged<Anchor3d> onCreated;

  @override
  Anchor3d createLayout(BuildContext context) {
    final anchor = Anchor3d();
    onCreated(anchor);
    return anchor;
  }

  @override
  void updateLayout(BuildContext context, Anchor3d layout) {}
}

/// Keeps its child over [anchor], on the node tier.
///
/// The follower half of the anchoring. It re-anchors on two occasions and
/// both are inside the layout pass, so the menu is never a frame behind its
/// button: when the follower itself is placed, and when the anchor is.
class Follower3d extends ProxyLayout3d {
  /// Creates a follower for [anchor].
  Follower3d({
    required Anchor3d anchor,
    this.self = Alignment3d.topLeft,
    this.target = Alignment3d.bottomLeft,
    super.name = 'Follower3d',
  }) : _anchor = anchor {
    anchor.onPlaced = reanchor;
  }

  Anchor3d _anchor;

  /// Which point of this box sits on the anchor's [target] point.
  final Alignment3d self;

  /// Which point of the anchor it sits on.
  final Alignment3d target;

  /// The box being followed.
  Anchor3d get anchor => _anchor;

  set anchor(Anchor3d value) {
    if (identical(_anchor, value)) return;
    if (identical(_anchor.onPlaced, reanchor)) _anchor.onPlaced = null;
    _anchor = value..onPlaced = reanchor;
    reanchor();
  }

  /// Puts this box back over its anchor.
  ///
  /// A no-op until both boxes have been laid out, which is the frame the
  /// menu was inserted on.
  void reanchor() {
    final placed = anchorOffsetTo(_anchor, self: self, target: target);
    if (placed == null || placed == nodeOffset) return;
    nodeOffset = placed;
  }

  @override
  void place(Offset3d offset) {
    super.place(offset);
    reanchor();
  }

  @override
  void dispose() {
    if (identical(_anchor.onPlaced, reanchor)) _anchor.onPlaced = null;
    super.dispose();
  }
}

/// The declarative form of [Follower3d]: keeps [child] over [anchor].
///
/// Stateful, because following an anchor is not something a build method can
/// do: the anchor moves without anything in the widget tree changing. The
/// state re-anchors after every frame, which is two matrix operations on the
/// node tier and lays nothing out.
class Follower3dWidget extends StatefulWidget {
  /// Creates a follower around [child].
  const Follower3dWidget({
    super.key,
    required this.anchor,
    this.self = Alignment3d.topLeft,
    this.target = Alignment3d.bottomLeft,
    required this.child,
  });

  /// The box to follow.
  final Anchor3d anchor;

  /// Which point of the child sits on the anchor's [target] point.
  final Alignment3d self;

  /// Which point of the anchor it sits on.
  final Alignment3d target;

  /// What follows the anchor.
  final Widget child;

  @override
  State<Follower3dWidget> createState() => _Follower3dWidgetState();
}

class _Follower3dWidgetState extends State<Follower3dWidget> {
  Follower3d? _follower;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _follower = null;
    super.dispose();
  }

  /// Re-anchors at the end of every frame, and asks for the next one.
  ///
  /// A post-frame callback does not *schedule* a frame, so a menu over a
  /// screen where nothing moves costs nothing at all: the callback is pending
  /// and never runs. When something does move there is a frame, and the menu
  /// is back over its button by the end of it.
  ///
  /// The two `place` hooks inside [Follower3d] are what keep the common
  /// cases from being a frame behind — the frame the menu opens on, and any
  /// move that relays the overlay out. This is the backstop for the rest: an
  /// ancestor of the button that moves without the boxes below it being
  /// placed again, which is exactly what a scroll does.
  void _watch() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _follower?.reanchor();
      _watch();
    });
  }

  @override
  Widget build(BuildContext context) => _Follower3dHost(
    anchor: widget.anchor,
    self: widget.self,
    target: widget.target,
    onCreated: (follower) => _follower = follower,
    child: widget.child,
  );
}

class _Follower3dHost extends SingleChildLayout3dWidget {
  const _Follower3dHost({
    required this.anchor,
    required this.self,
    required this.target,
    required this.onCreated,
    required super.child,
  });

  final Anchor3d anchor;
  final Alignment3d self;
  final Alignment3d target;
  final ValueChanged<Follower3d> onCreated;

  @override
  Follower3d createLayout(BuildContext context) {
    final follower = Follower3d(anchor: anchor, self: self, target: target);
    onCreated(follower);
    return follower;
  }

  @override
  void updateLayout(BuildContext context, Follower3d layout) {
    layout.anchor = anchor;
  }
}
