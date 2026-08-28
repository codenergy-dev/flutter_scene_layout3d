import 'dart:collection' show HashSet, SplayTreeMap;

import 'package:flutter/foundation.dart'
    show
        DiagnosticsNode,
        DiagnosticsTreeStyle,
        ErrorDescription,
        ErrorHint,
        ErrorSummary,
        FlutterError,
        protected;
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
    show
        BuildContext,
        Element,
        ElementVisitor,
        IndexedSlot,
        IndexedWidgetBuilder,
        DebugCreator,
        InheritedWidget,
        MultiChildRenderObjectWidget,
        RenderObjectElement,
        RenderObjectWidget,
        State,
        Widget;

import '../built_children.dart';
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

  /// The constraints every hosting box is laid out against.
  ///
  /// They take no space, so there is nothing to negotiate; what matters is
  /// that the constraints never change, which makes a clean box's layout a
  /// no-op however often it is walked.
  static const BoxConstraints hostConstraints = BoxConstraints.tightFor(
    width: 0,
    height: 0,
  );

  @override
  void performLayout() {
    _escalated = false;
    final root = findRoot();
    // Mirroring the child list dirties the layout tree, and the surface
    // reports that back by asking its host to relayout. That must not reach
    // Flutter while Flutter is laying this very box out, so the whole pass
    // runs with the surface's callback held.
    root?._enterPass();
    try {
      layoutChildBoxes();
    } finally {
      root?._exitPass();
    }
    // The outermost box of this pass lays the surface out, once, with the
    // whole tree reconciled. A box relaid out on its own is that box.
    if (root != null && root._passDepth == 0 && !root._flushing) {
      // Inside a layout callback, because the surface layout may build
      // widgets: a lazy view reaching a new index inflates its item here,
      // which inserts a render object into a tree Flutter has already laid
      // out. That is legal only below a box that is itself mid-layout and has
      // said so, which is exactly what this says. It is the same window
      // `SliverMultiBoxAdaptorElement` builds in.
      invokeLayoutCallback<BoxConstraints>((_) => root.flushSurface());
    }
  }

  /// Lays out the hosting boxes below this one and mirrors them onto the
  /// layout tree.
  ///
  /// Split out from [performLayout] because a lazy host does not mirror: it
  /// owns its layout children through a child manager rather than reading
  /// them off a render child list it did not build.
  @protected
  void layoutChildBoxes() {
    final layouts = <Layout3d>[];
    var child = firstChild;
    while (child != null) {
      child.layout(hostConstraints);
      if (child is Layout3dRenderBox) {
        layouts.add(child.layout3d);
      } else {
        assert(debugCheckNoInterposedRenderObject(child));
      }
      child = childAfter(child);
    }
    adoptLayoutChildren(layout3d, layouts);
  }

  /// Whether this box disposes [layout3d] when Flutter disposes this box.
  ///
  /// False for a widget's own layout, which lives and dies with the surface.
  /// True for a layout built on demand by a [Layout3dLazyElement]: nothing
  /// else holds it, and it has to come off its parent's books before the
  /// surface's own teardown walks over it a second time.
  bool disposeLayoutOnUnmount = false;

  @override
  void dispose() {
    if (disposeLayoutOnUnmount) {
      final parent = layout3d.parent;
      if (parent is Layout3dBuiltChildrenMixin) {
        parent.forgetBuiltChild(layout3d);
      } else if (parent != null) {
        detachLayout(layout3d, parent);
      }
      layout3d.dispose();
    }
    super.dispose();
  }

  bool _escalated = false;

  @override
  void markNeedsLayout() {
    super.markNeedsLayout();
    // Dirt anywhere in a surface is laid out from the root of it, not from
    // the box that raised it, so the whole chain up to the root is dirtied
    // with this one.
    //
    // Every hosting box is a relayout boundary — sized by its parent, against
    // constraints that never change — so Flutter would otherwise lay this one
    // out on its own, and the surface flush that followed would run inside a
    // layout callback that covers this box and nothing else. The surface
    // layout is whole-surface either way, and it may build a lazy view's
    // children anywhere in it; those builds edit the render tree, which is
    // legal only below the box whose callback is open. Dirtying the chain
    // makes that box the root, which is above everything in the surface.
    //
    // It costs one walk per box per dirty cycle: the flag is cleared when the
    // box is laid out, and a box that is already dirty is already on a dirty
    // chain.
    if (_escalated) return;
    final parent = this.parent;
    if (parent is! Layout3dRenderBox) return;
    final root = findRoot();
    if (root == null || root._inLayoutPass) return;
    _escalated = true;
    parent.markNeedsLayout();
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

/// Throws when an ordinary Flutter render object has been put between two
/// `Scene*3d` widgets, hiding the layout subtree below it.
///
/// The trap this exists for is the most expensive one in the declarative
/// layer, and it is silent. [Layout3dRenderBox.layoutChildBoxes] mirrors the
/// render tree onto the layout tree by collecting its render children that
/// are [Layout3dRenderBox]es; anything else is not one, so its whole subtree
/// — every `Scene*3d` widget below it — is simply not collected. Nothing
/// throws, nothing is laid out, and nothing appears in the scene.
///
/// What makes it easy to hit is that most Flutter widgets *are* transparent
/// here, and correctly so: a `StatelessWidget`, a `StatefulWidget`, an
/// `InheritedWidget`, a `Builder`, a `Consumer` create no render object of
/// their own, so their children are the hosting boxes' children and
/// everything works. Writing a component library depends on that. But one
/// `Padding`, one `Opacity`, one `SizedBox` reaching for the 2D spelling out
/// of habit creates a render object, and the subtree vanishes.
///
/// Returns true so it can be used inside an `assert`; throws otherwise.
/// Debug-only, and it costs one walk of an interposed subtree, which in a
/// correct tree does not exist.
bool debugCheckNoInterposedRenderObject(RenderObject interposed) {
  final lost = _findLayout3dDescendant(interposed);
  if (lost == null) return true;
  throw FlutterError.fromParts(<DiagnosticsNode>[
    ErrorSummary(
      'A ${interposed.runtimeType} was placed between two 3D layout widgets.',
    ),
    ErrorDescription(
      'The 3D layout tree is mirrored from the render tree, and only the '
      'zero-sized hosts that carry a Layout3d are mirrored. '
      '${_describeCreator(interposed)} creates a render object of its own, so '
      'everything below it — starting with ${lost.layout3d.runtimeType} — is '
      'not part of the layout tree at all. It is never laid out and never '
      'reaches the scene.',
    ),
    ErrorHint(
      'Only widgets that create no render object may sit between two 3D '
      'layout widgets: StatelessWidget, StatefulWidget, InheritedWidget, '
      'Builder, and anything else that only builds. For layout, use the 3D '
      'widget with the same name — ScenePadding3d for Padding, '
      'SceneSizedBox3d for SizedBox, SceneAlign3d for Align.',
    ),
    interposed.toDiagnosticsNode(
      name: 'The interposed render object was',
      style: DiagnosticsTreeStyle.errorProperty,
    ),
  ]);
}

/// The first [Layout3dRenderBox] anywhere below [node], or null.
Layout3dRenderBox? _findLayout3dDescendant(RenderObject node) {
  Layout3dRenderBox? found;
  void visit(RenderObject child) {
    if (found != null) return;
    if (child is Layout3dRenderBox) {
      found = child;
      return;
    }
    child.visitChildren(visit);
  }

  node.visitChildren(visit);
  return found;
}

/// What made [object], in the words a developer wrote, when Flutter knows.
String _describeCreator(RenderObject object) {
  final creator = object.debugCreator;
  if (creator is DebugCreator) {
    return 'The ${creator.element.widget.runtimeType} widget';
  }
  return 'It';
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

  /// Whether this surface is mid-pass: mirroring its tree, or laying it out.
  ///
  /// Dirt raised in either is part of the work already under way, and asking
  /// Flutter to lay this box out again for it would be a wasted pass at best
  /// and an illegal mutation at worst.
  bool get _inLayoutPass => _flushing || _passDepth > 0;

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
  // The mixins rather than the box classes, so a sliver that holds children
  // is adopted the same way a box is.
  if (parent is Layout3dWithChildrenMixin) {
    parent.syncChildren(children);
    return;
  }
  if (parent is Layout3dWithChildMixin) {
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
  if (parent is Layout3dWithChildrenMixin) {
    parent.remove(child);
  } else if (parent is Layout3dWithChildMixin &&
      identical(parent.child, child)) {
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
///
/// Flutter's `SingleChildRenderObjectWidget` is not the base here: its element
/// hands the child render object to a `RenderObjectWithChildMixin`, while
/// [Layout3dRenderBox] holds a child *list* so that one mirroring path serves
/// every layout shape. This is a multi-child widget that reports a list of
/// nought or one instead.
///
/// [children] is derived rather than built in the constructor, which is what
/// lets these widgets be `const`: `const ScenePadding3d(...)` in a `build`
/// method is a widget Flutter can skip rebuilding, the same as `const
/// Padding(...)`.
abstract class SingleChildLayout3dWidget extends Layout3dWidget {
  /// Creates a single-child layout widget.
  const SingleChildLayout3dWidget({super.key, this.child});

  /// The widget below this one in the tree.
  final Widget? child;

  @override
  List<Widget> get children {
    final child = this.child;
    return child == null ? const <Widget>[] : <Widget>[child];
  }
}

/// The host of a layout whose children are built as they are reached.
///
/// The difference from an ordinary [Layout3dRenderBox] is where the layout
/// children come from. An ordinary host mirrors: it reads the render child
/// list Flutter reconciled for it and hands that to its layout. A lazy host
/// cannot, because its render children are created *during* the layout that
/// decides which of them should exist — the list is being written while it
/// would be read. So it mirrors nothing, and the layout's child list is
/// maintained by [Layout3dLazyElement] acting as its [Layout3dChildManager]
/// instead. What is left here is laying the built subtrees out, so that each
/// item's own hosting boxes mirror their part of the tree.
class Layout3dLazyRenderBox extends Layout3dRenderBox {
  /// Creates a lazy host for [layout3d].
  Layout3dLazyRenderBox(super.layout3d);

  /// The view inside [layout3d] that holds the built children.
  Layout3dBuiltChildrenMixin get builtChildren => builtChildrenOf(layout3d);

  @override
  void layoutChildBoxes() {
    var child = firstChild;
    while (child != null) {
      child.layout(Layout3dRenderBox.hostConstraints);
      child = childAfter(child);
    }
  }

  /// Lays out the subtree of an item just built, so that it reaches the
  /// layout tree before the view that asked for it uses it.
  ///
  /// The item's own [Layout3dRenderBox.performLayout] is what mirrors its
  /// children onto its layout, and nothing else is going to run it: the pass
  /// that is asking for this item is already past the point where Flutter
  /// lays this box's children out.
  void layoutBuiltChild(RenderBox child) {
    assert(identical(child.parent, this));
    child.layout(Layout3dRenderBox.hostConstraints);
  }
}

/// A layout widget that may build its children on demand.
///
/// The declarative half of `ListView3d.builder` and its siblings. Both shapes
/// are one widget class with two constructors, the way Flutter's own
/// `ListView` is, and which shape a widget is in decides what it does with
/// its children: an explicit list is reconciled up front and mirrored onto
/// the layout, while a builder inflates items as the view reaches them.
///
/// A built item is an ordinary widget in an ordinary element tree, which is
/// the whole point of this class existing: it can read an [InheritedWidget],
/// keep [State], and rebuild on its own. What it must not do is resolve to
/// something that is not a layout — the top-most render object of an item has
/// to be a [Layout3dRenderBox] — so `SceneContainer3d`, `SceneText3d` and the
/// rest are fine, under any number of builders, providers and stateful
/// widgets, while a Flutter `Text` is not.
///
/// This is not a [Layout3dWidget], and cannot be: that class is a
/// `MultiChildRenderObjectWidget`, whose element type is fixed to
/// `MultiChildRenderObjectElement`, and a lazy view needs an element of its
/// own. The contract with the layout object is the same one, spelled again.
abstract class LazyLayout3dWidget extends RenderObjectWidget {
  /// Creates a layout widget in one of its two shapes: [children] given, or
  /// [itemBuilder] and [itemCount] given.
  const LazyLayout3dWidget({
    super.key,
    this.children = const <Widget>[],
    this.itemCount,
    this.itemBuilder,
  }) : assert(
         itemBuilder == null || itemCount != null,
         'A builder needs a count: without one nothing can say how long the '
         'content is, and a view of unbounded length is not something this '
         'package offers yet.',
       ),
       assert(itemCount == null || itemCount >= 0);

  /// The children, when they are given rather than built.
  final List<Widget> children;

  /// How many items [itemBuilder] serves.
  final int? itemCount;

  /// Builds the item at an index, called as the view reaches it.
  final IndexedWidgetBuilder? itemBuilder;

  /// Whether this widget builds its children on demand.
  ///
  /// Overridden by a widget whose children are built from something other
  /// than an [itemBuilder] — a `SceneLayoutBuilder3d` builds its one child
  /// from the constraints — which must then override [buildChild] as well.
  bool get isLazy => itemBuilder != null;

  /// Whether rebuilding this widget rebuilds the items standing now, there
  /// and then in the build phase.
  ///
  /// True for a view built from a list: the builder is a new closure that may
  /// return anything, so every item in the window is reconciled against it at
  /// once, which is what `SliverChildBuilderDelegate.shouldRebuild` says by
  /// always returning true.
  ///
  /// False for a widget whose children are a function of the layout's own
  /// state. A `SceneLayoutBuilder3d` rebuilt in the build phase would be
  /// built from the constraints of the *last* pass, and then built again in
  /// the pass that follows; instead it marks its layout as needing to build
  /// and lets that pass do it once, with the constraints that are true.
  ///
  /// An item that is dirty in its own right — because it holds state, or
  /// depends on an [InheritedWidget] that changed — is rebuilt by Flutter
  /// either way. This is only about the items being rebuilt *because this
  /// widget was*.
  bool get rebuildsItemsOnBuild => true;

  /// The widget standing for [index], or null when there is none.
  ///
  /// The seam between "which children exist" and "what they are". By default
  /// the answer is [itemBuilder] over the range [itemCount] describes, which
  /// is every view built from a list. A widget that decides otherwise
  /// overrides this: [layout] is the layout object that asked, handed over
  /// because the interesting case is a widget built from the layout's own
  /// state — the constraints a `LayoutBuilder3d` was given — and a layout
  /// mid-pass is not something the element tree can be asked for.
  ///
  /// Called inside the layout pass, in the build scope the element opens.
  @protected
  Widget? buildChild(
    BuildContext context,
    int index,
    covariant Layout3d layout,
  ) {
    final builder = itemBuilder;
    final count = itemCount;
    if (builder == null || count == null) return null;
    if (index < 0 || index >= count) return null;
    return builder(context, index);
  }

  /// Creates the layout object this widget describes.
  @protected
  Layout3d createLayout(BuildContext context);

  /// Applies this widget's properties to an existing layout.
  @protected
  void updateLayout(BuildContext context, covariant Layout3d layout);

  @override
  Layout3dLazyElement createElement() {
    assert(
      !isLazy || children.isEmpty,
      'A builder view has no children of its own: its items come from '
      'itemBuilder, and a child given here would never be laid out.',
    );
    return Layout3dLazyElement(this);
  }

  @override
  RenderObject createRenderObject(BuildContext context) => isLazy
      ? Layout3dLazyRenderBox(createLayout(context))
      : Layout3dRenderBox(createLayout(context));

  @override
  void updateRenderObject(
    BuildContext context,
    covariant Layout3dRenderBox renderObject,
  ) {
    updateLayout(context, renderObject.layout3d);
    final count = itemCount;
    if (isLazy && count != null) {
      // Before the items are rebuilt, so that a count which shrank has
      // already released the indices past the end by the time anything walks
      // them.
      builtChildrenOf(renderObject.layout3d).itemCount = count;
    }
  }
}

/// The element of a [LazyLayout3dWidget], and the child manager of the view
/// it hosts.
///
/// The 3D analogue of `SliverMultiBoxAdaptorElement`, and the same trade: the
/// element is the [Layout3dChildManager] its own layout consults, so both
/// trees are edited from one place. When the view reaches index 7 it arrives
/// here, in [createChild], which opens a build scope, inflates the widget,
/// mounts it, lays its subtree out, and hands back the [Layout3d] at the top
/// of it.
///
/// Building inside a layout is legal here for the reason it is legal in
/// Flutter: the surface's layout pass runs inside Flutter's layout phase,
/// below a box that has opened a layout callback, and inserting render
/// objects below such a box is exactly what that callback permits.
///
/// It also serves the explicit shape of the same widget, where it is an
/// ordinary multi-child element: `MultiChildRenderObjectElement` cannot be
/// reused for that, because it insists on a `MultiChildRenderObjectWidget`,
/// so the handful of lines that reconcile a child list are repeated here.
class Layout3dLazyElement extends RenderObjectElement
    implements Layout3dChildManager {
  /// Creates an element for [widget].
  Layout3dLazyElement(LazyLayout3dWidget super.widget);

  @override
  LazyLayout3dWidget get widget => super.widget as LazyLayout3dWidget;

  @override
  Layout3dRenderBox get renderObject => super.renderObject as Layout3dRenderBox;

  Layout3dBuiltChildrenMixin get _view =>
      (renderObject as Layout3dLazyRenderBox).builtChildren;

  // The explicit shape: the child list, reconciled the way every multi-child
  // element reconciles one.
  List<Element> _children = <Element>[];
  final Set<Element> _forgottenChildren = HashSet<Element>();

  /// The element standing for each built index, in index order.
  ///
  /// Sorted, because inserting a render child means naming the child it goes
  /// after, and that is the one at the greatest built index below this one.
  final SplayTreeMap<int, Element> _childElements =
      SplayTreeMap<int, Element>();

  /// The layout at the top of each built index's subtree.
  ///
  /// Kept so that a rebuild which swapped an item's render object can take
  /// the layout that went with the old one off the view's books before the
  /// view lays it out again.
  final Map<int, Layout3d> _childLayouts = <int, Layout3d>{};

  int? _currentlyUpdatingChildIndex;

  bool get _lazy => widget.isLazy;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    if (!_lazy) {
      _children = _inflateChildren(widget.children);
      return;
    }
    _view.childManager = this;
    final count = widget.itemCount;
    if (count != null) _view.itemCount = count;
  }

  List<Element> _inflateChildren(List<Widget> widgets) {
    final children = <Element>[];
    Element? previous;
    for (var index = 0; index < widgets.length; index++) {
      final child = inflateWidget(
        widgets[index],
        IndexedSlot<Element?>(index, previous),
      );
      children.add(child);
      previous = child;
    }
    return children;
  }

  @override
  void unmount() {
    // The items unmounted before this did — Flutter unmounts a subtree
    // child-first — so each of them has already taken itself off the view's
    // books. What is left is to stop being its manager, while the render
    // object that owns the view is still there to be asked.
    if (_lazy) _view.childManager = null;
    super.unmount();
  }

  @override
  void update(covariant LazyLayout3dWidget newWidget) {
    super.update(newWidget);
    if (!_lazy) {
      _children = updateChildren(
        _children,
        widget.children,
        forgottenChildren: _forgottenChildren,
      );
      _forgottenChildren.clear();
      return;
    }
    // The builder is a closure, and a new one may build anything at all, so
    // every item standing is rebuilt. That is what Flutter's own
    // `SliverChildBuilderDelegate.shouldRebuild` says by always returning
    // true, and the cost of it is bounded by what is in the window.
    performRebuild();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    if (!_lazy || !widget.rebuildsItemsOnBuild) return;
    assert(_currentlyUpdatingChildIndex == null);
    for (final index in _childElements.keys.toList()) {
      final Element? updated;
      try {
        _currentlyUpdatingChildIndex = index;
        updated = updateChild(
          _childElements[index],
          _build(index),
          _slotFor(index),
        );
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      if (updated == null) {
        _childElements.remove(index);
        _forgetLayout(index);
        continue;
      }
      _childElements[index] = updated;
      final host = _hostOf(updated, index)..disposeLayoutOnUnmount = true;
      // A rebuild that swapped the item's render object has left the view
      // holding a layout whose element is on its way out. Drop it now, in the
      // build phase, rather than let the next pass lay out something that is
      // about to be disposed; the pass builds the replacement.
      if (!identical(_childLayouts[index], host.layout3d)) _forgetLayout(index);
    }
  }

  /// Where the child for [index] goes: after the built child below it.
  IndexedSlot<Element?> _slotFor(int index) {
    final before = _childElements.lastKeyBefore(index);
    return IndexedSlot<Element?>(
      index,
      before == null ? null : _childElements[before],
    );
  }

  void _forgetLayout(int index) {
    final layout = _childLayouts.remove(index);
    if (layout != null && !layout.debugDisposed) _view.forgetBuiltChild(layout);
  }

  Widget? _build(int index) =>
      widget.buildChild(this, index, renderObject.layout3d);

  Layout3dRenderBox _hostOf(Element child, int index) {
    final render = child.renderObject;
    if (render is Layout3dRenderBox) return render;
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary(
        'The itemBuilder of a ${widget.runtimeType} returned something that '
        'is not a 3D layout.',
      ),
      ErrorDescription(
        'Item $index resolved to a ${render.runtimeType}. The items of a '
        'layout view are laid out on the plane, so each of them has to be a '
        'layout widget — SceneContainer3d, SceneNodeBox3d, SceneText3d, one '
        'of your own — under as many builders, inherited widgets and '
        'stateful widgets as you like.',
      ),
    ]);
  }

  // ------------------------------------------------------- the child manager

  /// How many items the widget says it has.
  @override
  int? get estimatedChildCount => widget.itemCount;

  /// Builds the item at [index] and returns the layout at the top of it.
  @override
  Layout3d? createChild(int index) {
    assert(_lazy);
    assert(_currentlyUpdatingChildIndex == null);
    owner!.buildScope(this, () {
      Element? newChild;
      try {
        _currentlyUpdatingChildIndex = index;
        newChild = updateChild(
          _childElements[index],
          _build(index),
          _slotFor(index),
        );
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      if (newChild == null) {
        _childElements.remove(index);
        _childLayouts.remove(index);
      } else {
        _childElements[index] = newChild;
      }
    });
    final child = _childElements[index];
    if (child == null) return null;
    final host = _hostOf(child, index)..disposeLayoutOnUnmount = true;
    (renderObject as Layout3dLazyRenderBox).layoutBuiltChild(host);
    _childLayouts[index] = host.layout3d;
    return host.layout3d;
  }

  /// Releases the item at [index], which the view has already unparented.
  @override
  void removeChild(int index, Layout3d child) {
    assert(_lazy);
    assert(_currentlyUpdatingChildIndex == null);
    _childLayouts.remove(index);
    owner!.buildScope(this, () {
      try {
        _currentlyUpdatingChildIndex = index;
        final result = updateChild(_childElements[index], null, null);
        assert(result == null);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      _childElements.remove(index);
    });
    // The element is inactive now rather than gone: a GlobalKey can still
    // claim it before the frame ends. Everything the layout holds — its node,
    // the painter a decoration took, the focus node a Focus3d owns — is
    // released when Flutter gives up on it and unmounts it, which disposes
    // the render object that owns the layout.
  }

  /// Asserts that no build is half-finished as a pass begins.
  @override
  void didStartLayout() {
    assert(_currentlyUpdatingChildIndex == null);
  }

  /// Asserts that no build is half-finished as a pass ends.
  @override
  void didFinishLayout() {
    assert(_currentlyUpdatingChildIndex == null);
  }

  // --------------------------------------------------- the element contract

  @override
  void forgetChild(Element child) {
    if (_lazy) {
      final slot = child.slot;
      assert(slot is IndexedSlot<Element?>);
      final index = (slot! as IndexedSlot<Element?>).index;
      assert(identical(_childElements[index], child));
      _childElements.remove(index);
      // A GlobalKey has moved this item, and its layout goes with it.
      // Unparent it here, because whoever claims it next adopts it, and a
      // layout has one parent.
      _forgetLayout(index);
    } else {
      assert(_children.contains(child));
      assert(!_forgottenChildren.contains(child));
      _forgottenChildren.add(child);
    }
    super.forgetChild(child);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_lazy) {
      _childElements.values.toList().forEach(visitor);
      return;
    }
    for (final child in _children) {
      if (!_forgottenChildren.contains(child)) visitor(child);
    }
  }

  @override
  void insertRenderObjectChild(
    covariant RenderBox child,
    IndexedSlot<Element?> slot,
  ) {
    renderObject.insert(child, after: slot.value?.renderObject as RenderBox?);
  }

  @override
  void moveRenderObjectChild(
    covariant RenderBox child,
    IndexedSlot<Element?> oldSlot,
    IndexedSlot<Element?> newSlot,
  ) {
    renderObject.move(child, after: newSlot.value?.renderObject as RenderBox?);
  }

  @override
  void removeRenderObjectChild(covariant RenderBox child, Object? slot) {
    renderObject.remove(child);
  }
}
