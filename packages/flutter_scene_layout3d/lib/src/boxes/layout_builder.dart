import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, FlagProperty;

import '../built_children.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';
import '../layout_pass.dart';

/// Builds a subtree from the constraints it is given.
///
/// The imperative half of [LayoutBuilder3d]. The declarative half is a
/// widget builder, and goes through the layout's [Layout3dChildManager]
/// instead.
typedef Layout3dBuilder = Layout3d Function(Constraints3d constraints);

/// A box that builds its child from the room it was given, the 3D analogue of
/// [LayoutBuilder].
///
/// Everything else in this package decides how big a subtree is; this decides
/// *which* subtree, from the same information. It is what a component reaches
/// for when the answer changes shape rather than size — show the label only
/// if it fits, put the navigation at the side on a wide panel and along the
/// bottom on a narrow one, drop the third column when the surface is a
/// phone-sized slab:
///
/// ```dart
/// LayoutBuilder3d(
///   builder: (constraints) => constraints.maxWidth > 6
///       ? Row3d(children: [rail, body])
///       : Column3d(children: [body, bar]),
/// )
/// ```
///
/// ## Building inside a layout
///
/// The child is built during [performLayout], which is the one thing that
/// makes this box different from every other. In the declarative layer that
/// means inflating a widget while Flutter is already laying the tree out, and
/// it is legal for exactly the reason it is legal for a lazily built list:
/// the surface's pass runs inside a Flutter layout callback opened by the box
/// at the root of the surface, and inserting render objects below such a box
/// is what that callback permits. So this box takes the same seam the lists
/// take — a [Layout3dChildManager] that is the element — rather than a second
/// mechanism of its own.
///
/// The rule that comes with it is the usual one: **a builder must not have
/// side effects on the tree above it**. Calling `setState` on an ancestor, or
/// marking an ancestor as needing layout, from inside a builder is asking for
/// a pass that is already under way to be redone from a point it has passed.
/// Read the constraints, return a subtree.
///
/// A rebuild does not throw the child away. When the constraints change, the
/// manager reconciles the new widget onto the element that is already there,
/// so state, focus nodes and painters below survive a resize — the same
/// contract Flutter's `LayoutBuilder` keeps.
///
/// ## Intrinsics
///
/// Refused. An intrinsic query asks how big this box would be under
/// constraints it has not been given, and answering would mean building a
/// subtree for constraints nothing is going to lay out — with the side effect
/// of replacing the child that *is* laid out. Flutter refuses for the same
/// reason. Put a [SizedBox3d] or an [AspectRatio3d] around the builder when
/// something above it needs an intrinsic answer.
class LayoutBuilder3d extends MultiChildLayout3d<ParentData3d>
    with Layout3dLayoutPassMixin, Layout3dBuiltChildrenMixin<ParentData3d> {
  /// Creates a box that builds its child from its constraints.
  ///
  /// [builder] is the imperative form; leave it out in the declarative layer,
  /// where `SceneLayoutBuilder3d`'s element is the child manager.
  LayoutBuilder3d({Layout3dBuilder? builder, super.name}) : _builder = builder;

  Layout3dBuilder? _builder;

  /// Builds the child from the constraints, or null when a child manager is
  /// doing that instead.
  Layout3dBuilder? get builder => _builder;

  set builder(Layout3dBuilder? value) {
    if (identical(_builder, value)) return;
    assert(
      value == null || childManager == null,
      'A LayoutBuilder3d builds its child from a function or from a child '
      'manager, not both.',
    );
    _builder = value;
    _builtConstraints = null;
    markNeedsLayout();
  }

  /// Never index-based: this box has one child, and it is a function of the
  /// constraints rather than of an index.
  @override
  Layout3dItemBuilder? get itemBuilder => null;

  @override
  String get itemNoun => 'children';

  Constraints3d? _builtConstraints;

  /// The constraints the child standing now was built from, or null when
  /// nothing has been built.
  ///
  /// Written after a successful build, so a builder that threw is retried
  /// rather than remembered as done.
  Constraints3d? get builtConstraints => _builtConstraints;

  /// The child currently built, or null before the first layout.
  Layout3d? get built => childCount == 0 ? null : childAt(0);

  /// Asks for the child to be built again on the next layout, even though the
  /// constraints have not changed.
  ///
  /// What the declarative layer calls when its widget is rebuilt: the builder
  /// is a new closure and may return anything, and the pass is where a
  /// builder runs. Cheap when nothing comes of it — the manager reconciles
  /// the new widget onto the element already there.
  void markNeedsBuild() {
    _builtConstraints = null;
    markNeedsLayout();
  }

  /// Rebuilds the child on the next layout even if the constraints have not
  /// changed.
  ///
  /// The counterpart of `Layout3dBuiltChildrenMixin.refresh` for a box whose
  /// builder reads something this package cannot see change.
  @override
  void refresh() {
    _builtConstraints = null;
    super.refresh();
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _noIntrinsics(axis);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _noIntrinsics(axis);

  double _noIntrinsics(Axis3d axis) {
    assert(
      false,
      'A LayoutBuilder3d was asked for its intrinsic extent along $axis. It '
      'has no answer: its child is a function of the constraints, and an '
      'intrinsic query is a question about constraints it has not been given, '
      'so answering would mean building a subtree nobody is going to lay out. '
      'Wrap the builder in a SizedBox3d or an AspectRatio3d, or ask the '
      'question of the subtree the builder returns.',
    );
    return 0.0;
  }

  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      defaultComputeDistanceToFirstActualBaseline(axis);

  void _buildIfNeeded(Constraints3d constraints) {
    if (_builtConstraints == constraints && childCount > 0) return;
    final manager = childManager;
    if (manager != null) {
      // The element reconciles: the same child element is updated with a
      // widget built from the new constraints, so what is below it survives.
      rebuildChild(0);
      _builtConstraints = constraints;
      return;
    }
    final builder = _builder;
    if (builder == null) return;
    final replacement = builder(constraints);
    if (childCount > 0) {
      final old = childAt(0);
      if (identical(old, replacement)) {
        _builtConstraints = constraints;
        return;
      }
      remove(old);
      // The builder made it, this box owns it, and nothing else is holding
      // it. The declarative path never gets here: there the element owns the
      // child and disposes it when it is unmounted.
      old.dispose();
    }
    insert(replacement);
    _builtConstraints = constraints;
  }

  @override
  void performLayout() {
    // The whole pass, because building edits this box's child list and
    // adopting a child marks it as needing layout again.
    runLayoutPass(() {
      final constraints = this.constraints;
      _buildIfNeeded(constraints);
      final child = built;
      if (child == null) {
        size = constraints.smallest;
        return;
      }
      child.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child.size);
      child.place(Offset3d.zero);
    });
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Constraints3d>(
        'builtConstraints',
        builtConstraints,
        defaultValue: null,
      ),
    );
    properties.add(
      FlagProperty('lazy', value: itemBuilder != null, ifTrue: 'builds items'),
    );
  }
}
