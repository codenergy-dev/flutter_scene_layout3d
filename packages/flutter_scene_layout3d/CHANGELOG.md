## Unreleased

- `ListView3d` and `GridView3d` are built on the sliver protocol now: each one
  *is* a scrolling window over a single sliver — a `SliverList3d`, a
  `SliverGrid3d` — reachable as `view.sliver`. That is the shape Flutter's
  views have (there is no `RenderListView`: a `ListView`'s items are placed by
  `RenderSliverList` inside a `RenderViewport`), and it leaves one copy of
  "where does item `i` go and is it visible" where there were two. The new
  `BoxScrollView3d` holds the forwarding, and `SliverMultiBoxAdaptor3d` is the
  base the two slivers now share; both are exported.
  - The imperative API is unchanged: `children`, `childAt`, `childCount`,
    `add`, `insert`, `remove`, `removeAll`, `syncChildren`, `itemCount`,
    `isLazy`, `activeIndices` and `refresh` all still mean the items, and a
    hit test still answers `firstOf<Scrollable3d>()` with the list or the grid
    rather than with the sliver inside it. The one member that went with the
    move is `itemBuilder`, which the sliver now implements; it was `@protected`
    on the views, so nothing outside them should have been reading it.
  - **Behaviour change:** `cacheExtent` decides what is built and kept alive,
    not what is drawn. An item inside the cache but outside the window used to
    be visible; it is hidden now, and shown when the window reaches it. Since
    a scene has nothing to clip with, that item was drawn outside the list.
  - **Behaviour change:** a list or a grid needs a bounded extent across its
    scroll axis, which is what an item is given to span, and it asserts when it
    has none. It used to size that axis to the widest item. Flutter's viewport
    makes the same demand. It also takes no depth when the depth axis is
    unbounded, where it used to grow to the deepest item.
  - It costs one scene node per view, the sliver's, which is the node Flutter's
    render tree has there too.
- `CustomScrollView3d` shrink-wraps when the scroll axis is unbounded, laying
  its slivers out against an endless window and coming out as long as they
  filled, the way Flutter's `ShrinkWrappingViewport` does. It used to assert.
  This is what keeps an unbounded `ListView3d` sizing to its content.
- **`prototypeItem`** on `ListView3d`, `SliverList3d` and their `.builder`
  constructors: an item built once and measured, standing for the extent of
  them all, which is Flutter's `ListView.prototypeItem`. It is `itemExtent` for
  a list whose items are uniform in a size that comes from the content rather
  than from a number the caller can write down, and it buys back everything
  `itemExtent` buys — arithmetic offsets, a total that does not move, and a
  jump anywhere that builds only the window. The prototype is measured and
  never shown: it is not one of the items and its node never enters the scene.
  The two are answers to the same question, so a list takes one of them and
  asserts on both.
- **`contentExtentEstimator`** on the same four, for a list whose items
  genuinely differ and whose total the application knows anyway. Offsets stay
  measured and exact; what stops moving is the reachable range. An estimate
  shorter than what has already been measured is raised to it.
- In debug, a measuring pass that builds more than five hundred items **only to
  release them again** now says so, naming both ways out. It is the discarded
  items that make it a symptom: a long window genuinely showing hundreds of
  items, or a list laid out in unbounded room showing all of them, throws
  nothing away and passes quietly.

- Every single-child `Scene*3d` widget is `const` now — `ScenePadding3d`,
  `SceneAlign3d`, `SceneCenter3d`, `SceneSizedBox3d`, `SceneContainer3d`,
  `SceneTransform3d`, `ScenePositioned3d`, `SceneFlexible3d`, `SceneExpanded3d`,
  `SceneViewport3d`, `SceneSliverToBoxAdapter3d` and the three
  `SceneIntrinsic*3d`. `SingleChildLayout3dWidget` folded its child into a list
  in its constructor, which no const expression can do, so these were rebuilt on
  every build of their parent while the multi-child widgets beside them were
  not. The list is derived from `child` instead.
- **Deprecated:** `EdgeInsets3d.alongDepth` is now `EdgeInsets3d.depth`,
  matching `horizontal`, `vertical`, and the `depth` argument of
  `EdgeInsets3d.symmetric`. The old name still works.
- A null declarative property now means "the default" everywhere, rather than
  "leave the last value alone". Dropping `basis` from a `SceneLayout3d` puts the
  plane back upright, and dropping `controller` from a scrolling widget gives
  the view a fresh one of its own instead of keeping the last one that was
  passed. The imperative `controller` setters accept null to say the same
  thing.
- `Layout3d.debugDisposed`, and asserts against laying out, re-disposing, or
  dirtying a disposed layout. The failure used to surface much later and
  somewhere else.
- `IgnorePointer3d.ignoring` and `AbsorbPointer3d.absorbing` are a getter and
  setter pair like every other property in the package, rather than bare public
  fields. They still cost nothing to flip.

- `Viewport3d`, `ListView3d`, `GridView3d` and `CustomScrollView3d` held their
  scroll controller four separate times over — the same field, setter,
  listener and `dispose` in each — and the ownership rule underneath was easy
  to get subtly wrong. It is one mixin now, `Scroll3dHolderMixin`, which the
  four install from their constructors with `initController`. The rule it
  keeps is unchanged: a controller the view made is disposed with the view, and
  one handed in from outside never is.
- `Layout3dLayoutPassMixin`, the flag that makes a view deaf to the dirt raised
  by its own layout pass, is its own mixin rather than a part of
  `Layout3dBuiltChildrenMixin`, because holding a scroll position needs it
  without holding built children. Both new mixins are exported.
- **Behaviour change:** `Viewport3d` now ignores *any* relayout request raised
  during its own layout pass, not just one from its own scroll controller. It
  had half of this guard; the other three views had all of it.
- `ListView3d`, `GridView3d`, `SliverList3d` and `SliverGrid3d` were four
  independent implementations of the same bookkeeping, and had already drifted
  apart in three places. The shared half is now two mixins,
  `Layout3dBuiltChildrenMixin` (the index-to-child map, `itemCount`, `refresh`,
  and the child-list guard above) and
  `Layout3dMeasuredChildrenMixin` (the running prefix a list of free-sized
  children keeps). Both are exported, for writing a scrolling view of your own.
  The four views shed 672 lines between them and keep only what is actually
  theirs: where the children go.
- Fixed: `SliverList3d.itemCount` left the measured prefix in place, so a list
  that had measured ten items went on reporting all ten as its `scrollExtent`
  after being told there were five. Setting `itemCount` now drops the
  measurements on all four views.
- `ListView3d.itemCount` no longer disposes every built child when it changes.
  The children are still right for their own indices; the next layout releases
  whatever falls outside the window, which includes anything past the new end.
  Call `refresh()` when what the builder *returns* has changed.
- `activeIndices` and `isLazy`, previously on `ListView3d` alone, are now on
  all four views.

- **Breaking:** `Offset3dBox` is gone. It was undocumented, untested, had no
  widget, and was the one public type that did not end in `3d`;
  `Transform3d.translate` does the same thing.
- **Deprecated:** `Grid3dItemBuilder` and `Sliver3dItemBuilder`, which were
  identical to `Layout3dItemBuilder`. That one name now lives beside the
  protocol in `layout3d.dart` and every builder takes it; the two aliases still
  work and will be removed in a later release.
- A `ListView3d.builder`, `GridView3d.builder`, `SliverList3d.builder` or
  `SliverGrid3d.builder` now asserts when its child list is edited from
  outside. A built view tracks its children by index, so a child inserted that
  way was never laid out and never released; the failure used to surface much
  later as a size assert on a box nobody remembered adding. Items come from the
  builder: set `itemCount`, or call `refresh()`.
- `_lastIndexBefore` in `ListView3d` and `SliverList3d` is a binary search
  rather than a linear scan, so the cost of a layout no longer climbs with how
  far the list has ever been scrolled.
- `GridView3d.dispose` clears the map of built cells, as `ListView3d` already
  did.
- Documented what was already true: a `SliverList3d.builder` with no
  `itemExtent` guesses the part of its length it has not measured, so the
  *reachable scroll range* moves as it is revised — taking the position with it
  when the estimate shrinks past where the viewer is — and reaching an offset
  deep in the list measures every item before it in one pass. (Item offsets
  themselves are exact and never move, and neither does a following sliver;
  an earlier draft of this entry said otherwise.) Also: `Viewport3d` neither
  culls nor clips, unlike the lists; the declarative layer
  builds every child widget up front, and lazy *widgets* need a
  `RenderObjectElement` this layer does not have (the old note promised the
  sliver work would bring it, which it did not); `Layout3dController` reaches
  the surface and its plane node, not measured sizes or scroll positions; and
  `examples/smoke_render` has five layout scenes, not two.

- Fixed: `Stack3d.depthStep` moved its children in the *layout*, which broke
  the two things the stack promises. A `Positioned3d` pinned to a face landed
  short of it by the step, and a coplanar child was pushed in front of the
  stack's own front face, where the ray gate could not reach it — so on a flat
  stack, the child on top became the one hit testing could not find, the exact
  inverse of the documented rule. The step is now written to
  `ParentData3d.sceneOffset`, a new per-child offset that moves the scene node
  and nothing else: the geometry separates in the depth buffer, and the layout,
  the pins and the hit test are untouched. `Stack3d` sizing is unchanged.
- `ParentData3d.sceneOffset` and `Layout3d.sceneOffset`, for a parent that
  needs to nudge a child's geometry without moving its box.
  `Layout3d.worldTransform` undoes it, so it still describes the layout frame.
- Fixed: `ListView3d.itemCount` reported the count captured when the list was
  built, so it went stale as soon as a child was added or removed. It now
  follows the child list, as `GridView3d`, `SliverList3d` and `SliverGrid3d`
  already did.
- A non-sliver child of a `CustomScrollView3d` now asserts as it is adopted,
  naming `SliverToBoxAdapter3d`, instead of failing as a bare cast error in the
  middle of layout. The constructor was typed, but `add`, `insert` and
  `syncChildren` come from the child-list mixin and the declarative layer
  passes plain widgets.

## 0.5.0

- Intrinsic sizing: `Layout3d.getMinIntrinsicExtent` and `getMaxIntrinsicExtent`
  ask a box how much room it would like, one axis at a time. Flutter's four
  methods would be six with a third axis, so the axis is a parameter and the
  `Size3d` beside it carries the limits on the other two.
- `IntrinsicWidth3d`, `IntrinsicHeight3d` and `IntrinsicDepth3d` (over a shared
  `IntrinsicExtent3d`), which size their child to the extent it asks for, with
  Flutter's `stepWidth` under the name `step`.
- Baselines: `Layout3d.getDistanceToBaseline`, `Baseline3d`, and
  `CrossAxisAlignment3d.baseline`, so a line of content can hang from a line
  inside it rather than from an edge. A baseline belongs to an axis here, and
  `Baseline3d` declares one outright, because nothing in a scene reports one
  the way text does.
- Every box answers for itself: `NodeBox3d` measures the content it holds,
  `Padding3d` and `Container3d` add their insets, `SizedBox3d` answers from its
  fixed extents without asking the child, and `Flex3d`, `Stack3d` and `Wrap3d`
  are ported from their Flutter counterparts. A `Wrap3d`'s answer across its
  runs is the one-run lower bound; the rest are exact.
- The scrolling views refuse the question, as Flutter's viewport does: a
  viewport's content is whatever length it is, and the view exists so that it
  need not grow to match.
- Answers are cached until the box goes dirty, and a box whose answer was taken
  pushes its dirt up past its own relayout boundary, because a parent decided
  something from a number that has just gone stale.
- `SceneIntrinsicWidth3d`, `SceneIntrinsicHeight3d`, `SceneIntrinsicDepth3d` and
  `SceneBaseline3d` in the declarative layer.
- `Constraints3d.hasTightAlong` and `tightenAlong`, `EdgeInsets3d.alongAxis` and
  `lowAlong`.

## 0.4.0

- The sliver protocol: `SliverConstraints3d` and `SliverGeometry3d`, and
  `Sliver3d`, a layout that answers a window rather than a size. The box
  protocol is the wrong shape for "there are ten thousand of these and you can
  see nine"; this is the one Flutter reaches for, ported.
- `CustomScrollView3d`, a viewport that puts several sections on one scroll
  position and gives each only the part of the window it can see. It honours
  `SliverGeometry3d.scrollOffsetCorrection`, so a sliver that finds its content
  elsewhere mid-layout can move the offset and have the pass run again.
- `SliverList3d`, `SliverGrid3d` (sharing `GridView3d`'s `Grid3dDelegate`) and
  `SliverToBoxAdapter3d`, the glue that gives an ordinary box its turn.
- `SceneCustomScrollView3d`, `SceneSliverList3d`, `SceneSliverGrid3d` and
  `SceneSliverToBoxAdapter3d` in the declarative layer. Child widgets are still
  built up front there; only the imperative builders are lazy.
- `Layout3dWithChildMixin` and `Layout3dWithChildrenMixin`, extracted from
  `SingleChildLayout3d` and `MultiChildLayout3d` so a sliver can hold children
  without being a box.
- `Scroll3dController.correctBy`, for a viewport applying a correction during
  its own layout.
- Fixed: `Scroll3dController.contentExtent` reported the viewport's extent for
  content shorter than the window, because the scroll range alone cannot tell
  the two apart. Views now report the extent they measured.

## 0.3.0

- `Wrap3d`, which breaks into runs where a flex would overflow. Runs stack on
  the first cross axis only; the depth axis aligns children rather than
  wrapping them, so a wrap of models stays a readable plane.
- `GridView3d`, laying cells out on a grid a `Grid3dDelegate` decides from the
  room across the scroll axis, with `Grid3dDelegateWithFixedCrossAxisCount`
  and `Grid3dDelegateWithMaxCrossAxisExtent` provided.
- `GridView3d.builder` is exactly lazy: cell positions are arithmetic, so the
  total extent is known without building anything, and only the window (plus
  `cacheExtent`) is ever built.
- `Grid3dLayout` exposes that arithmetic on its own, for callers that want to
  know where a cell lands without asking the view.
- `SceneWrap3d` and `SceneGridView3d` in the declarative layer. An unchanged
  grid delegate does not relayout, the way Flutter's `shouldRelayout` works.

## 0.2.0

- Hit testing, the other half of the layout protocol. `Layout3d.hitTest` walks
  the tree with a `Ray3d` rather than a point, because in a scene the pointer
  is a direction and the boxes stand at different depths; a box bounds the
  stretch of ray its children can be found in, which is the 3D form of
  Flutter's `size.contains(position)` gate.
- `Layout3dSurface.hitTestRay` brings a camera ray into layout space (the
  surface node already carries the basis, so its inverse world transform is
  the whole conversion), and `hitTestAt` asks with a point on the plane.
- `HitTestResult3d` reports the boxes hit, deepest first, with
  `firstOf<T>()` to pick an ancestor such as the list a finger landed in.
- `Layout3dPointer` turns pointer rays into scrolling. It measures the drag on
  the grabbed view's own plane rather than across the screen, so content stays
  under the finger at any viewing angle, and it keeps the grab until release.
- `Scrollable3d`, implemented by `Viewport3d` and `ListView3d`, which are now
  opaque to hits across their whole window so a drag can start on a gap.
- `IgnorePointer3d` and `AbsorbPointer3d`, plus their `Scene`-prefixed
  widgets. `NodeBox3d` answers hits on its own account; boxes that only
  arrange others do not. `Transform3d` neither answers nor gates, matching
  Flutter's `RenderTransform`.
- `Layout3d.worldTransform`, the transform from a box's own frame to world
  space.

## 0.1.0

- Initial release. Flutter's box layout protocol in three dimensions, laid out
  on a freely transformable plane in a flutter_scene scene.
- Core protocol: `Layout3dSurface`, `Layout3d`, `SingleChildLayout3d`,
  `MultiChildLayout3d`, `ProxyLayout3d`, `Layout3dOwner`, with relayout
  boundaries and a dirty-list flush.
- Value types: `Constraints3d`, `Size3d`, `Offset3d`, `Alignment3d`,
  `EdgeInsets3d`, `Axis3d`, and `LayoutBasis3d` for mapping layout space onto
  the plane (`xy` upright, `xz` on the ground, or any invertible matrix).
- Layouts: `Container3d`, `Padding3d`, `Align3d`, `Center3d`, `SizedBox3d`,
  `ConstrainedBox3d`, `Transform3d`, `Row3d`, `Column3d`, `Depth3d`,
  `Flexible3d`, `Expanded3d`, `Spacer3d`, `Stack3d`, `Positioned3d`.
- `NodeBox3d`, which measures engine content through
  `Node.combinedLocalBounds` and fits it into the box.
- Scrolling: `Viewport3d`, `ListView3d` (explicit children or a lazy
  `ListView3d.builder`), and `Scroll3dController`.
- A declarative widget layer in `package:flutter_scene_layout3d/widgets.dart`:
  `SceneLayout3d` plus a `Scene`-prefixed widget for every layout, reconciled
  through the Flutter element tree.
- The built-in bases follow the engine's screen convention (flutter_scene
  builds its camera basis with `right = up x forward`, so world `-x` is screen
  right for a camera facing a plane), which is what makes a `Row3d` read left
  to right on screen.
- `BoxFit3d` follows `FittedBox`: the box takes the size the constraints and
  the measurement give it, and the fit scales the content into that box, so a
  loose parent never inflates the box and an axis with no room does not
  collapse the content.
