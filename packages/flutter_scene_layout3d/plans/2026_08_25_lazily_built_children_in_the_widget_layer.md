---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
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

- [ ] **Phase 1 — `Layout3dChildManager`**, with the current builder path
      reimplemented on top of it and every existing test still green.
- [ ] **Phase 2 — `Layout3dLazyElement`** and a lazy host render box, proven
      with `SceneSliverList3d.builder` alone.
- [ ] **Phase 3 — the other three views:** `SceneListView3d.builder`,
      `SceneGridView3d.builder`, `SceneSliverGrid3d.builder`.
- [ ] **Phase 4 — keys and reordering**, including `GlobalKey` moves.
- [ ] **Phase 5 — keep-alive.**
- [ ] **Phase 6 — README.** The Scrolling section currently describes the
      imperative builders only; it should say what a declarative builder does
      and does not keep alive.

## Tests

- An item built lazily reads an `InheritedWidget` (a theme) declared above the
  list.
- A `StatefulWidget` item keeps its state while scrolled within the cache and
  is disposed when it leaves it.
- Keyed items reorder without rebuilding, and a `GlobalKey` item moves
  between indices without losing state.
- `itemCount` changing up and down rebuilds the right range.
- The imperative `ListView3d.builder` path is untouched — the whole existing
  scrolling suite passes unchanged.
- A build during layout does not re-enter the surface flush (the
  `_enterPass`/`_exitPass` guard still holds).

## Out of scope

`PageView3d` and anything with paging physics
([animation](2026_08_25_animation_and_scroll_physics.md)), and
`LayoutBuilder3d` itself — which is a small plan of its own once this
machinery exists.
