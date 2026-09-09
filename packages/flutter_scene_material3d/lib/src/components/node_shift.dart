import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Offset3d, ProxyLayout3d;
import 'package:vector_math/vector_math.dart' show Matrix4;
import 'package:flutter_scene_layout3d/widgets.dart'
    show SingleChildLayout3dWidget;

/// Moves and stretches what it holds **without laying anything out**.
///
/// The node tier, given a name. `docs/traps.md` lists three tiers of change
/// — repaint only, node only, and a real relayout — and says that picking the
/// wrong one is how a smooth interaction becomes a stutter. A switch's thumb
/// sliding along its track and a slider's thumb tracking a finger are exactly
/// the second tier: the geometry moves and no box changes size, so there is
/// nothing for the layout protocol to redo.
///
/// Two channels, and they compose the way `Layout3d`'s own do — the node
/// carries `T(offset + sceneOffset + shift) * scale`:
///
///  * [shift] is a `nodeOffset`: a translation in the box's own layout axes,
///    in **world units**.
///  * [scaleX] is a `nodeTransform` that stretches the geometry along x.
///    Because a node transform pivots on the box's **origin corner** rather
///    than on its centre, scaling by a half leaves the left edge exactly
///    where layout put it and halves the box toward it — which is what a
///    slider's active track is, and is why filling a track costs no relayout
///    even though the filled part gets longer as the finger moves.
///
/// The price, and it is the same one `Follower3d` pays: **`worldTransform`
/// undoes both**, deliberately, so that hit testing keeps finding a box where
/// layout put it. `screenCenter` and `screenPointOf` on a shifted box report
/// the laid-out position rather than the drawn one, and a render probe of
/// anything moved this way has to take its oracle from a box that did not
/// move — a slider's *track*, not its thumb.
class NodeShift3d extends ProxyLayout3d {
  /// Creates a shift, at rest.
  NodeShift3d({
    Offset3d shift = Offset3d.zero,
    double scaleX = 1.0,
    super.name = 'NodeShift3d',
  }) : _scaleX = scaleX {
    nodeOffset = shift;
    _applyScale();
  }

  double _scaleX;

  /// How far the child's geometry is moved, in world units.
  Offset3d get shift => nodeOffset;

  set shift(Offset3d value) => nodeOffset = value;

  /// How far the child's geometry is stretched along x, about its own left
  /// edge.
  ///
  /// One leaves it alone; zero collapses it to nothing, which is what an
  /// empty slider draws.
  double get scaleX => _scaleX;

  set scaleX(double value) {
    if (_scaleX == value) return;
    _scaleX = value;
    _applyScale();
  }

  void _applyScale() {
    // Null rather than an identity matrix at rest, so a box that never
    // stretches carries no extra multiply at all.
    nodeTransform = _scaleX == 1.0
        ? null
        : Matrix4.diagonal3Values(_scaleX, 1.0, 1.0);
  }
}

/// The declarative form of [NodeShift3d].
///
/// Rebuilding this widget writes a matrix and marks **nothing** dirty for
/// layout, which is the whole point: a switch that is toggled, or a slider
/// dragged from a `setState`, rebuilds its own subtree and lays nothing out.
class SceneNodeShift3d extends SingleChildLayout3dWidget {
  /// Creates a shifted subtree.
  const SceneNodeShift3d({
    super.key,
    this.shift = Offset3d.zero,
    this.scaleX = 1.0,
    super.child,
  });

  /// How far to move the child's geometry, in world units.
  final Offset3d shift;

  /// How far to stretch it along x, about its own left edge.
  final double scaleX;

  @override
  NodeShift3d createLayout(BuildContext context) =>
      NodeShift3d(shift: shift, scaleX: scaleX);

  @override
  void updateLayout(BuildContext context, NodeShift3d layout) {
    layout
      ..shift = shift
      ..scaleX = scaleX;
  }
}
