import 'package:flutter/foundation.dart' show protected;
import 'package:flutter/rendering.dart'
    show
        BoxConstraints,
        PipelineOwner,
        ContainerBoxParentData,
        ContainerRenderObjectMixin,
        Offset,
        PaintingContext,
        RenderBox,
        RenderObject,
        Size;
import 'package:flutter/widgets.dart'
    show BuildContext, MultiChildRenderObjectWidget, Widget;

import '../layout3d.dart';
import '../surface.dart';

/// Hosts one [Layout3d] inside the Flutter element tree.
///
/// The layout tree is not a widget tree, but reconciling one by hand (which
/// child moved, which was removed, what order they are in now) is exactly the
/// problem Flutter's element machinery already solves. So each layout widget
/// creates a zero-sized [RenderBox] that carries its [Layout3d], and the
/// render tree's own child list, reconciled by
/// [MultiChildRenderObjectWidget], is mirrored onto the layout tree during
/// [performLayout]. The boxes take no space and paint nothing; the real
/// output is the scene node transforms the layout writes.
class Layout3dRenderBox extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, Layout3dHostParentData> {
  /// Creates a host for [layout3d].
  Layout3dRenderBox(this.layout3d);

  /// The layout this box owns.
  final Layout3d layout3d;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! Layout3dHostParentData) {
      child.parentData = Layout3dHostParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void performResize() {
    size = constraints.smallest;
  }

  @override
  void performLayout() {
    final root = findRoot();
    // Mirroring the child list dirties the layout tree, and the surface
    // reports that back by asking its host to relayout. That must not reach
    // Flutter while Flutter is laying this very box out, so the whole pass
    // runs with the surface's callback held.
    root?._enterPass();
    try {
      final layouts = <Layout3d>[];
      var child = firstChild;
      while (child != null) {
        child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
        if (child is Layout3dRenderBox) {
          layouts.add(child.layout3d);
        }
        child = childAfter(child);
      }
      adoptLayoutChildren(layout3d, layouts);
    } finally {
      root?._exitPass();
    }
    // The outermost box of this pass lays the surface out, once, with the
    // whole tree reconciled. A box relaid out on its own is that box.
    if (root != null && root._passDepth == 0) {
      root.flushSurface();
    }
  }

  /// The root box of the surface this box belongs to, if it is in a tree.
  @protected
  Layout3dRootRenderBox? findRoot() {
    RenderObject? node = this;
    while (node != null) {
      if (node is Layout3dRootRenderBox) return node;
      node = node.parent;
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTestSelf(Offset position) => false;
}

/// Parent data for the zero-sized hosting boxes.
class Layout3dHostParentData extends ContainerBoxParentData<RenderBox> {}

/// The hosting box of a [Layout3dSurface], which lays the surface out once
/// the tree below it has been reconciled.
class Layout3dRootRenderBox extends Layout3dRenderBox {
  /// Creates the root host for [surface].
  Layout3dRootRenderBox(Layout3dSurface surface) : super(surface) {
    surface.onNeedVisualUpdate = _handleNeedVisualUpdate;
  }

  /// The surface this box lays out.
  Layout3dSurface get surface => layout3d as Layout3dSurface;

  int _passDepth = 0;
  bool _flushing = false;

  void _enterPass() => _passDepth++;

  void _exitPass() => _passDepth--;

  void _handleNeedVisualUpdate() {
    // Dirt raised while this surface is being laid out is part of the pass
    // already under way; anything else asks Flutter for a frame.
    if (_flushing || _passDepth > 0) return;
    markNeedsLayout();
  }

  /// Lays the surface out, so a change anywhere in the tree reaches the
  /// scene in the same frame.
  void flushSurface() {
    if (_flushing) return;
    _flushing = true;
    try {
      surface.flush();
    } finally {
      _flushing = false;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    surface.onNeedVisualUpdate = _handleNeedVisualUpdate;
  }

  @override
  void detach() {
    surface.onNeedVisualUpdate = null;
    super.detach();
  }
}

/// Replaces [parent]'s children with [children], moving any that came from
/// somewhere else.
///
/// The one place the widget layer edits the layout tree.
void adoptLayoutChildren(Layout3d parent, List<Layout3d> children) {
  for (final child in children) {
    final previous = child.parent;
    if (previous != null && !identical(previous, parent)) {
      detachLayout(child, previous);
    }
  }
  if (parent is MultiChildLayout3d) {
    parent.syncChildren(children);
    return;
  }
  if (parent is SingleChildLayout3d) {
    assert(
      children.length <= 1,
      '${parent.runtimeType} takes a single child, but was given '
      '${children.length}.',
    );
    parent.child = children.isEmpty ? null : children.first;
    return;
  }
  assert(
    children.isEmpty,
    '${parent.runtimeType} is a leaf layout and cannot take children.',
  );
}

/// Removes [child] from [parent], whatever kind of layout it is.
void detachLayout(Layout3d child, Layout3d parent) {
  if (parent is MultiChildLayout3d) {
    parent.remove(child);
  } else if (parent is SingleChildLayout3d && identical(parent.child, child)) {
    parent.child = null;
  }
}

/// The base of the declarative layouts: a widget that owns a [Layout3d] and
/// applies property changes to it on rebuild.
///
/// Subclasses create the layout once and update it in place, so an unchanged
/// rebuild writes nothing and a changed one costs only the properties that
/// changed, the same contract flutter_scene's own scene widgets keep with
/// their nodes.
abstract class Layout3dWidget extends MultiChildRenderObjectWidget {
  /// Creates a layout widget with the given children.
  const Layout3dWidget({super.key, super.children});

  /// Creates the layout object this widget describes.
  @protected
  Layout3d createLayout(BuildContext context);

  /// Applies this widget's properties to an existing layout.
  @protected
  void updateLayout(BuildContext context, covariant Layout3d layout);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      Layout3dRenderBox(createLayout(context));

  @override
  void updateRenderObject(
    BuildContext context,
    covariant Layout3dRenderBox renderObject,
  ) {
    updateLayout(context, renderObject.layout3d);
  }
}

/// A [Layout3dWidget] with at most one child.
abstract class SingleChildLayout3dWidget extends Layout3dWidget {
  /// Creates a single-child layout widget.
  SingleChildLayout3dWidget({super.key, Widget? child})
    : super(children: child == null ? const <Widget>[] : <Widget>[child]);
}
