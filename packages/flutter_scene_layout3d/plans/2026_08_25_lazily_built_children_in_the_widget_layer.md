---
status: completed
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-27T16:05:00Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# Lazily built children in the widget layer

The declarative layer cannot build items on demand. `SceneListView3d`,
`SceneGridView3d`, `SceneSliverList3d` and `SceneSliverGrid3d` take `children`
and nothing else; the `.builder` constructors exist only on the imperative
classes, and `Layout3dItemBuilder` returns a `Layout3d`, not a `Widget`.

So a lazily built item is a bare layout object: no `State`, no
`Theme.of(context)`, no `AnimatedBuilder`, no gesture widget, no
`InheritedWidget` of any kind. A long list of `ListTile3d` — one of the first
things anyone will write against a Material catalogue — is not expressible.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
It builds the same machinery `LayoutBuilder3d` needs, which is why
[the boxes still missing](2026_08_25_the_boxes_still_missing.md) waits on it.

**Where it landed.** `Layout3dChildManager` in `lib/src/built_children.dart`;
`LazyLayout3dWidget`, `Layout3dLazyElement` and `Layout3dLazyRenderBox` in
`lib/src/widgets/framework.dart`; the four `.builder` constructors in
`lib/src/widgets/layouts.dart`; the tests in `test/lazy_widgets_test.dart`.

## What exists today

- [Layout3dRenderBox](../lib/src/widgets/framework.dart) hosts one `Layout3d`
  in a zero-sized `RenderBox`. Its `performLayout` walks its render children,
  lays each out at a tight zero size, collects the ones that are
  `Layout3dRenderBox`, and mirrors that list onto the layout tree with
  `adoptLayoutChildren`.
- `Layout3dRootRenderBox` runs the whole surface layout from inside its own
  `performLayout`, guarding re-entrancy with `_enterPass`/`_exitPass` and
  calling `flushSurface()` when the outermost pass finishes.
- The imperative side already has the bookkeeping: `Layout3dBuiltChildrenMixin`
  and `Layout3dMeasuredChildrenMixin` hold built children, active indices,
  measured extents, `prototypeItem` and the estimator.
  `SliverMultiBoxAdaptor3d` is the analogue of
  `RenderSliverMultiBoxAdaptor`.

**The fact that makes this possible:** the layout pass runs *inside* Flutter's
own layout phase, so building widgets during it is legal in exactly the window
Flutter's own slivers use. This is not a hack being invented here; it is the
same trick `SliverMultiBoxAdaptorElement` plays.

## The design

Mirror Flutter, class for class.

### The layout side: a child manager

```
abstract class Layout3dChildManager {
  void createChild(int index, {Layout3d? after});
  void removeChild(Layout3d child);
  void didStartLayout();
  void didFinishLayout();
  double estimateContentExtent({...});
  int? get estimatedChildCount;
}
```

the analogue of `RenderSliverBoxChildManager`. `SliverMultiBoxAdaptor3d`
consults it instead of calling a `Layout3dItemBuilder` directly; the existing
builder path becomes one implementation of the manager (a manager that
constructs layouts straight from a function), so nothing that works today
changes shape.

### The element side

`Layout3dLazyElement extends RenderObjectElement`, implementing
`Layout3dChildManager`. During the layout pass it calls
`owner!.buildScope(this, ...)`, inflates the widget for an index, mounts it,
and hands the resulting `Layout3d` to the layout. The parts that will take the
time are the parts that take the time in Flutter:

- tracking which index is currently being built, so `insertRenderObjectChild`
  knows where the new child belongs;
- keys, reordering and `GlobalKey` reparenting;
- removing children that fall outside the cache, and letting their state be
  disposed;
- keeping the render child list and the layout child list in agreement while
  both are being edited mid-pass.

### The wrinkle specific to this package

`Layout3dRenderBox.performLayout` mirrors children by iterating the render
child list. A lazy element inserts and removes render children *during* that
iteration. Flutter's sliver adaptor does exactly this against a
`RenderSliverMultiBoxAdaptor`, but ours is a `RenderBox` with
`ContainerRenderObjectMixin` and a mirroring step the framework's has no
counterpart for. Expect to split `performLayout` so that a lazy host does not
use the mirroring path at all: it owns its children directly, through the
manager, rather than mirroring a list it did not build.

### Keep-alive

Flutter has `KeepAlive` and `AutomaticKeepAlive` for items that must survive
leaving the cache. Note it, design the manager so it can be added, and leave
it to a follow-up.

## The work

- [x] **Phase 1 — `Layout3dChildManager`**, in `lib/src/built_children.dart`,
      consulted by `Layout3dBuiltChildrenMixin` wherever it used to call
      `itemBuilder`. Every existing test stayed green.
- [x] **Phase 2 — `Layout3dLazyElement`** and `Layout3dLazyRenderBox`, in
      `lib/src/widgets/framework.dart`.
- [x] **Phase 3 — all four views:** `SceneListView3d.builder`,
      `SceneGridView3d.builder`, `SceneSliverList3d.builder`,
      `SceneSliverGrid3d.builder`.
- [x] **Phase 4 — keys and reordering.** A `GlobalKey` item moves between
      indices with its state; a local-key reorder is correct but rebuilds in
      place. See *What the reasoning got wrong*, point 5.
- **Phase 5 — keep-alive: out of scope, by this plan's own design section**
      ("note it, design the manager so it can be added, and leave it to a
      follow-up"). Not implemented, and not a gap in this plan. As it
      says: an item that leaves the window and its cache is disposed. What a
      follow-up needs is here already — the manager is the only thing that
      releases a child, so parking one instead of releasing it is a change to
      `releaseOutside` and to what `positionedChildren` yields, not to the
      element.
- [x] **Phase 6 — README.** *Scrolling* now covers the declarative builders
      and what a built item does not keep; the roadmap's sliver entry no
      longer says lazy widgets have no answer.

## What the reasoning got wrong

1. **The manager's shape.** `createChild(int index, {Layout3d? after})`
   returning void was the wrong signature. Flutter needs `after` because the
   render object holds the child list and the element calls back into it to
   insert; here `Layout3dBuiltChildrenMixin` already keeps the index-to-child
   map and inserts in index order, so there is nothing for `after` to
   disambiguate. `createChild` returns the child instead, and `removeChild`
   takes the index and the child the view has already unparented.
   `estimateContentExtent` was dropped outright: `contentExtentEstimator` on
   `Layout3dMeasuredChildrenMixin` already answers that question, and an
   element knows nothing the view does not.
2. **"The existing builder path becomes one implementation of the manager."**
   It did not. Wrapping a function in a manager object would allocate one per
   view and buy nothing: `obtainChild` and `releaseOutside` are the only two
   places that ask, and each branches in a line. What did happen is that
   every *other* site stopped asking which mode it was in — `isLazy` is now
   the single predicate, and the two sliver layouts read it instead of their
   own `_builder` field.
3. **The mutation root, which the plan did not see at all.** Building during
   layout is legal only *below a render object that has opened a layout
   callback*, and the surface flush is driven by whichever hosting box
   finished the outermost pass — which is often not the root, because every
   hosting box is a relayout boundary and Flutter lays a dirty one out on its
   own. A list built from a flush driven by a sibling subtree threw "A
   Layout3dLazyRenderBox was mutated in Layout3dRenderBox.performLayout". Two
   changes fix it: the flush runs inside `invokeLayoutCallback`, and
   `Layout3dRenderBox.markNeedsLayout` dirties the chain of hosting boxes up
   to the root, so the root is always the box that flushes and its callback
   covers the whole surface. `test/lazy_widgets_test.dart` has the case that
   caught it.
4. **The widget could not stay a `Layout3dWidget`.** That class is a
   `MultiChildRenderObjectWidget`, whose `createElement` is typed to return a
   `MultiChildRenderObjectElement`, and a lazy view needs an element of its
   own. So `LazyLayout3dWidget` is a sibling class on `RenderObjectWidget`,
   and `Layout3dLazyElement` reconciles the explicit shape as well — the
   handful of lines `MultiChildRenderObjectElement` would have contributed.
   The four views moved to the new base; nothing a caller writes changed.
5. **Keys.** A `GlobalKey` item moves between indices with its state, because
   Flutter's own reparenting does that once `forgetChild` unparents the
   layout from the view. A *local* key reorder is correct but rebuilds: there
   is no analogue of `SliverChildDelegate.findIndexByKey` here, so an index
   whose key changed is an index whose element is replaced.
6. **A widget-built layout has to be disposed, and nothing did that.** The
   declarative layer never disposed a `Layout3d` — the surface disposes the
   whole tree at the end — but an item that comes and goes has to release its
   painter and its focus node while the surface lives on.
   `Layout3dRenderBox.disposeLayoutOnUnmount`, set by the element on each item
   it builds, disposes the layout when Flutter disposes the render object that
   owns it; `forgetBuiltChild` takes it off the view's books first, so a
   teardown that unmounts items before the surface does not dispose them
   twice.

## Tests

`test/lazy_widgets_test.dart`, fifteen of them:

- [x] An item built lazily reads an `InheritedWidget` declared above the list,
      and follows it when it changes.
- [x] A `StatefulWidget` item keeps its state while the window holds it and is
      disposed when the window leaves it.
- [x] A `GlobalKey` item moves between indices without losing state. Keyed
      items reorder *correctly*, but they do rebuild — see point 5 above.
- [x] `itemCount` changing up and down rebuilds the right range.
- [x] The imperative path is untouched: the whole existing suite passes
      unchanged (518 tests before, 533 with these).
- [x] A build during layout does not re-enter the surface flush, and is legal
      from a partial relayout in a sibling subtree.
- [x] The seam plans 3 and 4 left: a released item gives its painter back to
      `Layout3dOwner.painters` and disposes the `FocusNode` a `Focus3d` owns,
      and a surface torn down with items standing disposes none of them twice.

## Out of scope

`PageView3d` and anything with paging physics
([animation](2026_08_25_animation_and_scroll_physics.md)), and
`LayoutBuilder3d` itself — which is a small plan of its own once this
machinery exists. It has what it needs now: `LazyLayout3dWidget` for a widget
that builds inside the layout pass, `Layout3dLazyRenderBox` for a host that
does not mirror, and the mutation-root work above, which is what makes
building from inside `performLayout` legal wherever the flush was driven
from.
