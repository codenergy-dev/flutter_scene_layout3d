---
status: in progress
reason: >-
  Everything in the list has landed except the last item, `Dismissible3d`,
  `Draggable3d`, `DragTarget3d` and reorderable lists. They wait on drag
  recognition that carries a payload between boxes and across surfaces, which
  the pointer plan put in its own "Out of scope" section, so the dependency
  this plan names does not exist yet. It is a plan of its own, not remaining
  work here; nothing else in this file is open.
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-28T14:16:51Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# The layout boxes still missing

The layout algebra is close to complete; a handful of Flutter's boxes have no
counterpart here, and a component catalogue asks for them by name. This plan
is a list with a difficulty grading, not one design — take an item, build it,
tick it off.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).

## The one that matters most

**`LayoutBuilder3d`.** Without it, nothing can build differently depending on
the room it is given: no responsive component, no "show the label only if it
fits", no `Scaffold3d` that changes shape on a narrow panel. It is the single
absent box that blocks the most.

It needs to build widgets during the layout pass, which is exactly the
machinery
[lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md)
builds. **Do that plan first and this becomes a small addition** — the same
`buildScope`-during-layout window, one child instead of many. Attempting it
before that plan means building the machinery twice.

Done, and the prediction held: `LayoutBuilder3d` is a
`Layout3dBuiltChildrenMixin` view with one index, and `SceneLayoutBuilder3d`
is a `LazyLayout3dWidget` hosted on `Layout3dLazyRenderBox`, so the element
that is already a `Layout3dChildManager` builds the child inside its own
build scope. Two seams had to be widened, both additive:

- `Layout3dBuiltChildrenMixin.rebuildChild(index)` beside `obtainChild`. A
  scrolling view builds an index once and keeps it; this box's child is a
  function of the constraints, so it has to ask again, and the manager
  reconciles rather than rebuilding from nothing so state below survives.
- `LazyLayout3dWidget.buildChild(context, index, layout)` in place of the
  element's private call to `itemBuilder`, with `isLazy` and a new
  `rebuildsItemsOnBuild` overridable. The layout is handed over because this
  is the one widget whose child comes from the layout's own state — the
  constraints — which the element tree cannot be asked for. And
  `rebuildsItemsOnBuild` is false here: rebuilding a builder's child in the
  build phase would build it from the *previous* pass's constraints and then
  build it again in the pass that follows, so the widget marks its layout as
  needing to build and lets the pass do it once. That is what Flutter's
  `_LayoutBuilderElement` does, arrived at the same way.

## Grade 1: mechanical

Each is a small `SingleChildLayout3d` with a constraints transformation and no
open questions. Any of them can be done in an afternoon, with a widget and a
test.

- [x] `LimitedBox3d` — caps an unbounded axis. Worth more here than in
      Flutter: a `Layout3dSurface` is unbounded on all three axes by default,
      so unbounded constraints are the normal case rather than the exception.
      Its *intrinsics* are capped unconditionally, unlike its layout: an
      intrinsic query is the unbounded case by definition.
- [x] `UnconstrainedBox3d` — with `constrainedAxes` (a set) rather than
      Flutter's single `constrainedAxis`, because keeping depth bounded while
      freeing the plane is the case that comes up.
- [x] `OverflowBox3d`
- [x] `FractionallySizedBox3d` — a factor on an unbounded axis asserts and
      names the fix, per the convention below.
- [x] `IndexedStack3d` — one visible child; with no clipping this is
      `Stack3d` plus `node.visible`, which is already how the scrolling views
      cull. Setting `index` therefore does not relayout at all.
- [x] `SliverPadding3d` (listed here rather than with
      [persistent headers](2026_08_25_persistent_sliver_headers.md) because it
      is mechanical and independent).

## Grade 2: needs a decision first

- [x] **`AspectRatio3d`.** A ratio between *which* two axes? Three sensible
      answers: a pair of axes plus a ratio; a full `Size3d` ratio constrained
      to fit; or a 2D ratio on the surface plane with depth free. Pick one,
      write down why, and note that the 2D-habit answer (width : height) is
      the one a caller will assume.

      **Decided: a pair of axes plus a ratio, defaulting to
      horizontal : vertical.** The whole-`Size3d` answer is a different
      operation wearing the same name — "make this subtree that shape and
      scale it into the room" — which is `FittedBox3d` for a subtree and
      `NodeBox3d.fit` for engine content, and neither of those *constrains*
      the child, which is the entire point of an aspect ratio in a layout
      protocol. The default is the 2D habit because it is right: a surface is
      a thing you look at, so its long axes are width and height and depth is
      the panel's thickness. The third axis is passed through untouched.

- [x] **`FittedBox3d`.** `NodeBox3d.fit` already does this for engine content.
      For a laid-out *subtree* it means laying out at one size and scaling by
      a transform, which is `Transform3d` territory — and `Transform3d` is
      already the documented exception in hit testing (it neither answers hits
      itself nor gates children on its extent). Decide whether `FittedBox3d`
      inherits that exception or does better, and say so in its doc.

      **Decided: it does better on the half that can be.** `Transform3d`
      cannot gate on its own extent because its size is measured in the frame
      *before* the matrix; a fitted box's size is the room it fills, in the
      frame the ray arrives in, and the scale is what put the child inside
      that size — so the gate is meaningful and is applied. It keeps the other
      half of the exception: it is not a target itself. The gate is exact for
      every fit except `BoxFit3d.none`, where an oversized child overflows and
      the part outside is out of reach, which is where Flutter clips.

- [x] **`Table3d`.** Flutter's `Table` is column widths negotiated from
      intrinsics. The intrinsic protocol here is per-axis and already
      supports it; the question is whether a third axis means anything for a
      table, or whether it is a plane arrangement with depth as an alignment
      axis, the choice `Wrap3d` already made and documented.

      **Decided: a plane, with depth as an alignment axis.** A third axis of
      *cells* is a different structure with a different name, and nothing the
      catalogue asks for wants one — a data table, a keypad, a calendar and a
      settings grid are all flat things standing in space. Cells are given in
      row-major order with a `columnCount`, the way `RenderTable` holds them,
      and a short last row is allowed. `TableColumnWidth3d` ships with fixed,
      flex, fraction and intrinsic policies; the width negotiation hands the
      leftover room to the flexible columns and, when the wants do not fit,
      takes the deficit back in proportion to each column's slack and never
      below its minimum. Cell alignment covers top, middle, bottom, fill and
      baseline; only `fill` cells are laid out twice.

      Not ported: Flutter's `MinColumnWidth`/`MaxColumnWidth` combinators, and
      per-row alignment overrides (the alignment is the table's). Both are
      additive, and neither is a decision this plan had to make.

## Grade 3: needs machinery

- [x] **`LayoutBuilder3d`** — see above; after
      [lazily built children](2026_08_25_lazily_built_children_in_the_widget_layer.md).
- [x] **`CustomMultiChildLayout3d` and `MultiChildLayout3dDelegate`.**
      Flutter's `Scaffold` is literally a `CustomMultiChildLayout`, so a
      faithful `Scaffold3d` wants this. The delegate API ports directly:
      `hasChild(id)`, `layoutChild(id, constraints)`, `positionChild(id,
      offset)`, with `Size3d`/`Offset3d`/`Constraints3d` substituted.

      It did port directly, with one substitution the plan did not name: the
      id. Flutter's `LayoutId` is a `ParentDataWidget`, and there is no
      parent-data machinery here — so `LayoutId3d` is a `ProxyLayout3d` that
      wraps the child and carries the id, exactly as `Positioned3d` carries a
      stack's pins. `getSize` defaults to filling the bounded axes and
      collapsing the unbounded ones rather than `constraints.biggest`, because
      an unbounded axis is normal here and `biggest` would be an infinity in
      the scene.

- [x] **`Flow3d`** — a paint-time transform per child. Here "paint time" is
      the node transform, which makes `Flow3d` *cheaper* than in Flutter: a
      repositioning that never touches layout, the same category as the
      node-only animations in
      [animation](2026_08_25_animation_and_scroll_physics.md).

      That is how it is built: `paintChild` writes `nodeOffset` and
      `nodeTransform`, a `repaint` listenable re-runs the delegate and nothing
      else, and a child the delegate skipped is hidden. One thing the plan did
      not anticipate: **a flow is the one box where a node transform is taken
      account of by hit testing**, against the rule the animation plan set.
      It has to be. Layout puts every child at the flow's origin corner, so
      the delegate's transform *is* the child's position, and a ray obeying
      the rule would always find the last child wherever the viewer saw them.
      Flutter's `Flow` makes the same exception. Documented in both places.

- [x] **`PageView3d` / `TabBarView3d`** — a viewport with paged physics.
      Depends on physics from
      [animation](2026_08_25_animation_and_scroll_physics.md).

      `PageScroll3dPhysics` extends the clamping physics — the ends behave the
      same — and replaces the release: half a page of bias in the direction of
      the throw, rounded, sprung onto. Its `pageExtent` defaults to the window
      and can be stated, which is how a carousel of peeking cards snaps a
      plain `ListView3d`. `PageView3d` is a `BoxScrollView3d` that writes its
      sliver's `itemExtent` from the window on every pass, so a surface that
      resizes re-pages, and it puts page physics on a position it creates for
      itself but never on one it was handed.

      **`TabBarView3d` is deliberately not here**, and it is not an open item
      of this plan: it is a `PageView3d` driven by a tab controller, and a tab
      controller is a Material concept that belongs to
      `flutter_scene_material3d` with the tab bar it is shared with. Nothing
      is missing from this package for it to be written there.

- [ ] **`Dismissible3d`, `Draggable3d`, `DragTarget3d`, reorderable lists** —
      all depend on real drag recognition from
      [pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md).

      **Still blocked, and not by this plan.** That plan shipped with
      "drag-and-drop between surfaces" in its own *Out of scope* section, so
      the dependency named here does not exist: there is a drag that scrolls a
      grabbed view, and there is no drag that carries a payload from one box
      to another across surfaces, no feedback subtree following the pointer,
      and no hit test *during* a drag to find what is underneath it. All four
      of these are that machinery plus a thin layer, and the machinery is a
      plan of its own — which is why this file's status stays `in progress`
      rather than `completed`, with nothing else in it open. Recorded in the
      README's roadmap as the next thing the catalogue is waiting on.

## Conventions to keep

Every item follows what the package already does, so none of this needs
re-deciding per box:

- A layout, then a `Scene`-prefixed widget for it, both named after the
  Flutter class with the `3d` suffix, and both exported.
- `crossAxisAlignment` is the first cross axis, `depthAxisAlignment` the
  second; the depth axis aligns rather than wraps.
- An unbounded axis is normal, not an error, and a box that cannot cope says
  so with an assertion that names the fix.
- Intrinsics are implemented, or refused for a stated reason (the scrolling
  views refuse; `Wrap3d` documents that its cross-run answer is a lower
  bound).
- The README's table of counterparts gains a row in the same pass.

All kept. Two refusals were needed: `LayoutBuilder3d` refuses intrinsics
(answering means building a subtree for constraints nothing will lay out, and
replacing the child that *is* laid out as a side effect), and
`FractionallySizedBox3d`, `AspectRatio3d` and `PageView3d` each assert on the
unbounded case they cannot answer, naming the fix. `Table3d` and
`CustomMultiChildLayout3d` answer intrinsics from their own arithmetic without
touching the children, which is the cheap half of Flutter's own approach.

## Tests

Per box: sizing under tight, loose and unbounded constraints on each of the
three axes; intrinsics; hit testing including the depth axis; and the widget
form applying a property change without rebuilding the layout object.

`test/missing_boxes_test.dart` (the layouts) and `test/layout_builder_test.dart`
(the declarative half, and the teardown path a built child takes when its
builder goes away). 74 tests; 692 in the package, all green, analyzer clean.
