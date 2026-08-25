---
status: in progress
created_at: 2026-08-25T03:32:15Z
updated_at: 2026-08-25T04:14:00Z
commit: 495b1ec4e93e3588c93612ef02862355d380933a
---

# flutter_scene_layout3d review remediation

Work items from the structural review of `packages/flutter_scene_layout3d` at
commit `495b1ec4`. Baseline at the time of writing: `flutter analyze` clean,
239 tests green. Every item in phase 1 was reproduced with a throwaway test
before being written down; the reproduction is quoted with it.

The phases are ordered by what actually hurts a caller. Phase 1 is silently
wrong behaviour, phase 2 is the structure that keeps producing phase 1, phase 3
is documentation that says something the code does not do. Phase 4 is polish
and can be dropped without losing anything.

---

## Phase 1 — Confirmed bugs — **done**

Landed together with the `depthStep` documentation it invalidated. Suite went
from 239 to 244 tests, all green; `flutter analyze` clean. The four original
reproductions now read:

```
pinned offset: Offset3d(0.000, 0.000, 0.900)   // was 0.850
hit target:    front                            // was back
after add:     itemCount=2 childCount=2         // was 1 / 2
CustomScrollView3d takes slivers, but was given a TestBox. Wrap an ordinary
box in a SliverToBoxAdapter3d ...                // was a bare _TypeError
```

### 1.1 `Stack3d.depthStep` breaks `Positioned3d` pins and inverts hit testing — **done**

**Where.** `lib/src/boxes/stack.dart:330`

```dart
child.place(anchor - Offset3d(0, 0, index * _depthStep));
```

**What is wrong.** The step is applied to every child by list index, positioned
children included, and it moves children outside the stack's own box.

Two separate failures, both reproduced:

```
// Positioned3d(back: 0, depth: 0.1) in a stack of depth 1, depthStep 0.05
pinned offset: Offset3d(0.000, 0.000, 0.850)   // expected 0.900

// Two coplanar (depth 0) pointable children, depthStep 0.05
front offset: Offset3d(0.000, 0.000, -0.050)
hit target: back                                // expected front
```

The first contradicts the README's own *Traps* section, which recommends
`Positioned3d(back: 0, depth: ...)` for a backing slab while *How it differs
from Flutter* recommends `depthStep` for coplanar children. Used together, each
quietly defeats the other.

The second is worse. `Layout3d.hitTest` clips the ray to the stretch inside the
box before descending, so a child pulled in front of the stack's front face is
unreachable there. With flat panels — the case `depthStep` exists for — the
topmost child becomes the *least* reachable, inverting the documented "the box
on top wins" rule.

**Both fixes proposed here were wrong.** Recorded because the reasoning is the
useful part:

- *"Apply the step only to non-positioned children"* fixes the pin but not the
  hit test, and it makes the feature's rule conditional on a child's type for
  no reason a caller could predict.
- *"Place the first child at `+totalStep` and walk toward the viewer so the fan
  stays inside `[0, depth]`"* only holds when `depth >= totalStep +
  maxChildDepth`. The headline case for `depthStep` is **coplanar** content,
  where the stack's depth is 0 and no fan of any sign fits inside it. Growing
  the box instead fails the same way whenever the caller pins the depth — and
  `Constraints3d.tight(Size3d(2, 2, 0))` is exactly what a flat panel is given.

**What was actually done.** The premise was wrong: `depthStep` is not a layout
quantity at all. It is an epsilon that breaks a tie in the depth buffer, and the
class doc already claimed it "does not affect the stack's size". So it now moves
the child's **scene node** and nothing else:

- `ParentData3d.sceneOffset`, a new per-child offset in layout axes that
  `applyNodeTransform` adds to the translation and that layout, intrinsics and
  hit testing never see. `Layout3d.sceneOffset` reads it;
  `Layout3d.worldTransform` undoes it, so it still describes the layout frame
  (translations commute, so it is one multiply on the right).
- `Stack3d` writes `Offset3d(0, 0, -index * depthStep)` there and calls
  `place(anchor)` with the unmodified anchor.

Every failure falls out at once. The pin is exact because the box never moved.
The coplanar children stay inside the stack, so the ray gate lets the walk
through, and since they are all at the same `z` in layout space,
`hitTestChildren` testing last-to-first returns the topmost — which is the same
child the separated geometry shows the eye. And the size claim becomes literally
true instead of nearly true.

Applying the step to *every* child, positioned ones included, is now harmless
and was kept: it is what makes "later children render in front" unconditional,
and it costs a pinned child nothing but an epsilon of geometry.

**Tests.** `test/boxes_test.dart`: the existing `depthStep pulls later children
toward the viewer` was asserting the old layout offsets and now asserts the node
translation *and* that the layout offsets are untouched; plus `depthStep leaves
a Positioned3d on the face it pinned` and `depthStep does not change the stack
size`. `test/hit_test_test.dart`: `depthStep does not take the child on top out
of reach`, on a zero-depth stack, which is the case that failed.

Node transforms are float32, so anything reading back through
`translationOf` needs a `closeTo` tolerance around `1e-6`, not an exact match.

### 1.2 `ListView3d.itemCount` goes stale — **done**

**Where.** `lib/src/scroll/list_view.dart:192`

```dart
int get itemCount => _itemCount;
```

`_itemCount` is captured from `children.length` in the constructor and never
follows the child list.

```
before:    itemCount=1 childCount=1
after add: itemCount=1 childCount=2
```

**How to fix.** Match the three sibling classes, which are already correct
(`grid_view.dart:359`, `sliver_list.dart:120`, `sliver_grid.dart:77`):

```dart
int get itemCount => _builder == null ? childCount : _itemCount;
```

The setter's assert stays. Internal layout already computed the right value
inline, so `_performListLayout` now calls the getter rather than repeating the
expression — one fewer copy to drift.

**Test.** `test/scroll_test.dart`: `itemCount follows the child list`, checking
`add` and `remove`.

### 1.3 A non-sliver in `CustomScrollView3d` throws a raw `_TypeError` — **done**

**Where.** `lib/src/sliver/custom_scroll_view.dart:223`

```dart
final sliver = child as Sliver3d;
```

The constructor takes `List<Sliver3d>`, but `add`, `insert`, `remove` and
`syncChildren` come from `Layout3dWithChildrenMixin` and accept any `Layout3d`;
`SceneCustomScrollView3d` takes `List<Widget>` with no constraint at all.
Reproduced:

```
error: _TypeError: type 'TestBox' is not a subtype of type 'Sliver3d' in type cast
```

**How to fix.** Fail at insertion, where the caller's mistake is, not deep in
layout. Override `setupParentData` (called for every adopted child) in
`CustomScrollView3d`:

```dart
@override
void setupParentData(Layout3d child) {
  assert(
    child is Sliver3d,
    'CustomScrollView3d takes slivers, but was given a ${child.runtimeType}. '
    'Wrap an ordinary box in a SliverToBoxAdapter3d.',
  );
  super.setupParentData(child);
}
```

The widget layer needs no separate assert: `adoptLayoutChildren` reaches the
same `adoptChild`, so a bad `SceneCustomScrollView3d` child trips it too. The
message names both spellings (`SliverToBoxAdapter3d` and
`SceneSliverToBoxAdapter3d`) so it reads correctly from either layer. A marker
type for sliver *widgets*, which would catch it at compile time, belongs with
phase 2.

**Test.** `test/sliver_test.dart`: `rejects a child that is not a sliver, where
the caller can see it`.

---

## Phase 2 — Structure

### 2.1 Collapse the four parallel scrolling implementations

**Where.** `lib/src/scroll/list_view.dart`, `lib/src/scroll/grid_view.dart`,
`lib/src/sliver/sliver_list.dart`, `lib/src/sliver/sliver_grid.dart`.

In Flutter, `ListView` *is* a `CustomScrollView` holding a `SliverList` — one
implementation, two entry points. Here they are four independent ones that
repeat `_obtainChild`, `_releaseOutside`, `_prefix`, `_indexAtOffset`,
`_lastIndexBefore`, `_estimatedContentExtent`, `_crossOffset`,
`_positionedChildren`, `refresh()`, the `_layingOut` guard on `markNeedsLayout`,
and every property setter. Roughly 600 duplicated lines. Item 1.2 is exactly the
drift this produces: one of four copies of the same getter diverged and nothing
caught it.

**How to fix.** Two routes, in increasing order of ambition:

1. **Extract the shared machinery into mixins.** A
   `Layout3dLazyChildrenMixin` holding `_active`, `_obtainChild`,
   `_releaseOutside`, `refresh`, the `_layingOut` guard and `itemCount`; a
   `Layout3dMeasuredExtentsMixin` holding `_prefix`, `_indexAtOffset`,
   `_lastIndexBefore`, `_estimatedContentExtent`. The four views keep their own
   `performLayout`. Low risk, mostly mechanical, kills the drift.
2. **Rebuild `ListView3d` and `GridView3d` on top of the sliver protocol**, as
   Flutter does: each becomes a `CustomScrollView3d` with one sliver inside.
   Removes the duplication outright and makes one code path the only one that
   can be wrong. Larger change, and it moves observable behaviour (metrics
   reporting, culling, the `Scrollable3d` identity a hit test finds), so it
   needs the existing scroll and sliver tests to pass unchanged as the
   acceptance criterion.

Route 1 is the recommendation for this pass; route 2 is worth its own plan.

**Tests.** No new behaviour, so the bar is the existing `test/scroll_test.dart`,
`test/grid_test.dart` and `test/sliver_test.dart` passing untouched.

### 2.2 Lazy views expose the API that corrupts them

**Where.** the four `.builder` constructors above.

`ListView3d.builder` and friends inherit public `add`, `insert`, `remove`,
`removeAll` and `syncChildren` from `Layout3dWithChildrenMixin`. A child
inserted that way is not in `_active`: it is never laid out (so `child.size`
trips the "has not been laid out yet" assert) and never released. Nothing warns.

**How to fix.** Assert in the mutating entry points when `_builder != null`:
a built view owns its children and the way to change them is `itemCount`,
`itemBuilder` data plus `refresh()`. The cleanest place is a single
`_assertNotLazy(String method)` helper called from overrides of `insert`,
`remove` and `removeAll`; `_obtainChild` and `_releaseOutside` bypass it by
calling `super`. If 2.1 route 1 lands first, this belongs in the shared mixin.

**Test.** `test/scroll_test.dart`: `ListView3d.builder(...).add(box)` throws.

### 2.3 No built-in sliver ever emits `scrollOffsetCorrection`

**Where.** `lib/src/sliver/sliver_list.dart` (the estimating branch).

The viewport honours corrections (`custom_scroll_view.dart:243`) and the README
highlights it, but a `grep` finds no producer outside a test. The practical
consequence is undocumented: `SliverList3d.builder` without `itemExtent`
estimates the total extent from the average of what it has measured, and never
corrects, so content below it jumps as new items are measured.

**How to fix.** Two acceptable outcomes, and either closes the item:

- **Document it.** Add the consequence to the README's *Slivers* section and to
  `SliverList3d`'s class doc: the estimate is revised silently, and anything
  after the list moves when it is. Cheap, honest, and enough for an
  experimental package.
- **Emit the correction.** When the measured prefix disagrees with the estimate
  the pass was laid out against, report the difference as
  `scrollOffsetCorrection`. This is the real fix and exercises a path that
  currently only a test drives, so it needs a guard against oscillation
  (the viewport's `_maxLayoutCycles` catches it, but a sliver that never settles
  is a bug worth its own test).

Do the documentation now; put the correction behind its own plan entry if it is
wanted.

### 2.4 No single-child `Scene*3d` widget can be `const`

**Where.** `lib/src/widgets/framework.dart:232`

```dart
SingleChildLayout3dWidget({super.key, Widget? child})
  : super(children: child == null ? const <Widget>[] : <Widget>[child]);
```

Building the list in the constructor body forbids `const`. Confirmed by the
analyzer: `const ScenePadding3d(padding: EdgeInsets3d.zero)` fails with
`const_with_non_const`. This hits `ScenePadding3d`, `SceneAlign3d`,
`SceneCenter3d`, `SceneSizedBox3d`, `SceneContainer3d`, `SceneTransform3d`,
`ScenePositioned3d`, `SceneFlexible3d`, `SceneExpanded3d`, `SceneViewport3d`,
`SceneSliverToBoxAdapter3d` and the three `SceneIntrinsic*3d` — while the
multi-child widgets (`SceneRow3d`, `SceneStack3d`, `SceneNodeBox3d`) *are*
const. In Flutter `const Padding(...)` is idiomatic and skips rebuild work; the
asymmetry here is invisible until a caller tries it.

**How to fix.** Give the single-child widgets a `RenderObjectWidget` base that
holds `final Widget? child` and its own `Element`, rather than folding the child
into a `MultiChildRenderObjectWidget`'s list — the shape Flutter's own
`SingleChildRenderObjectWidget` has. The layout-tree mirroring in
`Layout3dRenderBox.performLayout` walks the render children, so a single-child
render object needs the equivalent walk; keeping `ContainerRenderObjectMixin`
with exactly zero or one child is the smaller change and keeps one code path.

This is a public API change (constructors gain `const`), so it is additive for
callers but touches every single-child widget. Sequence it after phase 1.

**Test.** `test/widgets_test.dart`: a `const ScenePadding3d(...)` compiles (the
test file failing to analyze is the assertion) and rebuilds without writing to
its layout.

---

## Phase 3 — Documentation truth

Each of these is a place where the docs state something the code does not do.
They are cheap and should land with phase 1.

### 3.1 Stale promise in the widget layer

`lib/src/widgets/layouts.dart:732` says lazy declarative building waits on "the
element machinery that the sliver work will bring". The sliver work landed in
0.4.0, and the README now says the opposite: that it needs "a
`RenderObjectElement` of its own and a build scope". Replace the widget doc with
the README's current account.

### 3.2 README undercounts the examples

*Seeing it run* claims "two scenes in `examples/smoke_render` (`layout3d_panel`
and `layout3d_ground`)". There are five: `layout3d_wrap_grid`,
`layout3d_slivers` and `layout3d_intrinsic` also exist
(`examples/smoke_render/lib/smoke_scenes.dart:1754`, `1883`, `1963`, `2046`,
`2134`). Fix the count, and note that the live `examples/flutter_app` example
demonstrates only `SceneListView3d` — wrap, grid, slivers, intrinsics and
baselines have headless coverage but no interactive demo.

### 3.3 `Viewport3d` neither culls nor clips

Documented on the class, absent from the README. In a 3D scene this means
geometry renders outside the panel, which is more surprising than in Flutter
where clipping is the default. Add it to the README's *Scrolling* section
alongside the `ListView3d` culling description.

### 3.4 `Layout3dController` promises more than it exposes

The README says to attach one "for measured sizes, scroll positions, or the
plane node". The class (`lib/src/widgets/surface.dart:26`) exposes only
`surface` and `plane`; everything else means walking the layout tree by hand.
Either narrow the README sentence, or add the accessors it advertises
(`size`, and a lookup for a named scrollable). Narrowing is honest and takes a
line.

### 3.5 `Offset3dBox` is an orphan that breaks the naming rule

`lib/src/boxes/shifted.dart:205`, exported from
`lib/flutter_scene_layout3d.dart:61`. It is absent from the README, the
CHANGELOG, the tests and the declarative layer, and it is the only public type
that does not end in `3d` — in a package whose README spends a section
defending exactly that rule. `Transform3d.translate` already covers the use.

Remove it, and say so in the CHANGELOG as a breaking removal. If it is wanted,
it needs a conforming name (`Shift3d`), a `SceneShift3d`, a test and a README
row.

### 3.6 Three identical typedefs

`Layout3dItemBuilder` (`list_view.dart:12`), `Grid3dItemBuilder`
(`grid_view.dart:12`) and `Sliver3dItemBuilder` (`sliver_list.dart:11`) are all
`Layout3d Function(int index)`. Keep `Layout3dItemBuilder`, deprecate the other
two as aliases for one release, then drop them.

---

## Phase 4 — Minor

- `lib/src/widgets/surface.dart:162`: `if (basis != null) _surface.basis = basis`
  never restores the default when `basis` goes back to null on a rebuild, unlike
  `size` and `constraints`. The same `if (x != null)` pattern applies to
  `controller` in every `updateLayout`; decide one rule and apply it to both.
- `lib/src/scroll/list_view.dart:530` and `lib/src/sliver/sliver_list.dart:371`:
  `_lastIndexBefore` is a linear scan sitting next to `_indexAtOffset`, a binary
  search over the same sorted array. Make it a binary search.
- `lib/src/boxes/ignore_pointer.dart`: `IgnorePointer3d.ignoring` and
  `AbsorbPointer3d.absorbing` are public mutable fields; every other property in
  the package is a private field with a getter/setter pair. They genuinely need
  no relayout, so keep the cheapness and add the pair for consistency.
- `lib/src/geometry/edge_insets3d.dart`: `horizontal`, `vertical`, `alongDepth`
  — the third breaks the pattern, and `EdgeInsets3d.symmetric`'s parameter for
  the same axis is called `depth`. Pick one spelling.
- `lib/src/layout3d.dart`: `dispose()` neither unparents the layout nor marks it
  disposed, so a discarded layout stays hanging off its parent with no warning.
  Add a `debugDisposed` flag and assert on use, as `RenderObject` does.
- `lib/src/scroll/grid_view.dart`: `dispose()` does not clear `_active`;
  `ListView3d.dispose()` does. Harmless, but it is one more copy that drifted.

---

## Sequencing

1. ~~Phase 1 in one pass, with phase 3's doc fixes~~ — **done.** Landed with
   only the documentation phase 1 itself invalidated (the `depthStep` class
   doc, the property doc and the README's *How it differs from Flutter* entry),
   plus an `Unreleased` CHANGELOG section. The rest of phase 3 is untouched and
   still stands.
2. Phase 2.2 and 2.3 (documentation route), which are small.
3. Phase 2.1 route 1 (mixin extraction), then re-run the whole suite untouched.
4. Phase 2.4 as its own change, since it moves the widget base class.
5. Phase 4 whenever a file is open for another reason.

Route 2 of 2.1 (rebuilding the views on the sliver protocol) and the real
`scrollOffsetCorrection` producer in 2.3 each deserve a plan of their own.
