---
status: completed
created_at: 2026-08-25T03:32:15Z
updated_at: 2026-08-25T18:04:00Z
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

### 2.1 Collapse the four parallel scrolling implementations — **done (route 1)**

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

**What was done.** Route 1, as two mixins in `lib/src/built_children.dart`:

- `Layout3dBuiltChildrenMixin` — the index-to-child map, `itemBuilder`,
  `itemCount`, `refresh`, `obtainChild`, `releaseOutside`,
  `positionedChildren`, the child-list guard from 2.2, and `runLayoutPass`,
  which replaces the hand-rolled `_layingOut` flag each view kept.
- `Layout3dMeasuredChildrenMixin` — the prefix sums the two *lists* keep, with
  `recordMeasurement`, `offsetOfIndex`, `contentExtentOf`,
  `estimatedContentExtent`, `indexAtOffset` and `lastIndexBefore`. The grids do
  not mix it in; their positions are arithmetic.
- One `scrollCrossOffset` function replaces four copies (`_crossOffset` twice,
  `_depthOffset` twice) of the same switch.

Named for what they hold rather than the plan's `Lazy`/`Extents`: the first
mixin serves explicit views too, so "lazy" would have been wrong. Both are
exported, alongside the other protocol mixins.

The four views lost 672 lines net and keep only what is theirs: where the
children go. `performLayout` in each is now one line delegating to
`runLayoutPass`.

**Two divergences had to be resolved rather than preserved**, since one mixin
cannot hold four rules:

- The `itemCount` setters differed in assert order, whether they dropped the
  measurements, and whether they disposed every built child. Unified on: assert
  first, drop the measurements, keep the children. That fixed a latent bug —
  `SliverList3d` kept its prefix, so a list that had measured ten items went on
  reporting all ten as its `scrollExtent` after being told there were five —
  and dropped `ListView3d`'s habit of rebuilding the whole window on a count
  change, which was never necessary. `refresh()` is still what to call when the
  builder's *data* moved.
- `activeIndices` and `isLazy` existed only on `ListView3d`. They are on all
  four now.

**Tests.** The bar was the existing suite passing untouched, and it does: 246
tests, no edits. One test was added for the `SliverList3d` bug the unification
fixed, and checked against the old behaviour — it fails with `20.0` where it
now expects `10`.

### 2.2 Lazy views expose the API that corrupts them — **done**

**Where.** the four `.builder` constructors above.

`ListView3d.builder` and friends inherit public `add`, `insert`, `remove`,
`removeAll` and `syncChildren` from `Layout3dWithChildrenMixin`. A child
inserted that way is not in `_active`: it is never laid out (so `child.size`
trips the "has not been laid out yet" assert) and never released. Nothing warns.

**What was done.** A `_assertNotBuilt(String method)` helper in each of the
four views, called from overrides of `insert`, `remove`, `removeAll` and
`syncChildren`. The views' own bookkeeping (`_obtainChild`, `_releaseOutside`,
`_resetChildren`, `refresh`) calls `super.insert` / `super.remove` to go round
it.

Worth knowing if this moves into a shared mixin with 2.1: the first attempt
gated the assert on `!_layingOut` instead, which looked equivalent and was not.
`refresh()` edits the child list from *outside* layout, so it tripped its own
assert. Routing the internal callers through `super` is what makes the guard
mean "no edits from outside", which is the actual rule.

**Tests.** `test/scroll_test.dart`: `refuses a child list edit, which its
bookkeeping would not survive`, and `refresh still edits the child list it
owns` — the second is what would have caught the `_layingOut` version.

### 2.3 No built-in sliver ever emits `scrollOffsetCorrection` — **documented**

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

**What was done.** The documentation route. `SliverList3d`'s class doc and the
README's *Slivers* section now say that the estimate is revised silently, that
whatever follows the list in the viewport shifts when it is, that no built-in
sliver issues a correction, and that a uniform `itemExtent` removes the problem
by making the length arithmetic.

Emitting a real correction is still open and still wants a plan of its own: it
exercises a viewport path only a test drives today, and a sliver that never
settles needs a test of its own rather than leaning on `_maxLayoutCycles`.

### 2.4 No single-child `Scene*3d` widget can be `const` — **done**

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

**What was done**, and it is smaller than this item assumed. Flutter's
`SingleChildRenderObjectWidget` could not be the base: its element hands the
child to a `RenderObjectWithChildMixin`, while `Layout3dRenderBox` holds a child
*list* so that one mirroring path serves every layout shape. Writing a custom
element was the obvious next thought, and it was not needed either.

`MultiChildRenderObjectWidget.children` is a `final` field, and a subclass can
override a field's getter. So `SingleChildLayout3dWidget` keeps the multi-child
base, holds `final Widget? child`, and *derives* the list:

```dart
const SingleChildLayout3dWidget({super.key, this.child});
final Widget? child;
@override
List<Widget> get children =>
    child == null ? const <Widget>[] : <Widget>[child!];
```

Nothing is built in the constructor, so the constructor is `const`. One render
box, one element type, one mirroring path, and the analyzer's
`prefer_const_constructors_in_immutables` then named every subclass that could
follow: seventeen directly, plus `SceneCenter3d` and `SceneExpanded3d` once
their superclasses were const.

**Test.** `test/widgets_test.dart`: `a const single-child widget is const, and
skips its rebuild` — the `const` keyword is the assertion, and the test also
checks that rebuilding with the identical const widget reconciles onto the same
layout object.

---

## Phase 3 — Documentation truth — **done**

Each of these is a place where the docs state something the code does not do.
They are cheap and should land with phase 1.

### 3.1 Stale promise in the widget layer — **done**

`lib/src/widgets/layouts.dart:732` says lazy declarative building waits on "the
element machinery that the sliver work will bring". The sliver work landed in
0.4.0, and the README now says the opposite: that it needs "a
`RenderObjectElement` of its own and a build scope". Replace the widget doc with
the README's current account.

### 3.2 README undercounts the examples — **done**

*Seeing it run* claims "two scenes in `examples/smoke_render` (`layout3d_panel`
and `layout3d_ground`)". There are five: `layout3d_wrap_grid`,
`layout3d_slivers` and `layout3d_intrinsic` also exist
(`examples/smoke_render/lib/smoke_scenes.dart:1754`, `1883`, `1963`, `2046`,
`2134`). Fix the count, and note that the live `examples/flutter_app` example
demonstrates only `SceneListView3d` — wrap, grid, slivers, intrinsics and
baselines have headless coverage but no interactive demo.

### 3.3 `Viewport3d` neither culls nor clips — **done**

Documented on the class, absent from the README. In a 3D scene this means
geometry renders outside the panel, which is more surprising than in Flutter
where clipping is the default. Add it to the README's *Scrolling* section
alongside the `ListView3d` culling description.

### 3.4 `Layout3dController` promises more than it exposes — **done**

The README says to attach one "for measured sizes, scroll positions, or the
plane node". The class (`lib/src/widgets/surface.dart:26`) exposes only
`surface` and `plane`; everything else means walking the layout tree by hand.
Either narrow the README sentence, or add the accessors it advertises
(`size`, and a lookup for a named scrollable). Narrowing is honest and takes a
line.

### 3.5 `Offset3dBox` is an orphan that breaks the naming rule — **done**

`lib/src/boxes/shifted.dart:205`, exported from
`lib/flutter_scene_layout3d.dart:61`. It is absent from the README, the
CHANGELOG, the tests and the declarative layer, and it is the only public type
that does not end in `3d` — in a package whose README spends a section
defending exactly that rule. `Transform3d.translate` already covers the use.

**What was done.** Removed, with a breaking-change note in the CHANGELOG.
Nothing in the repository referenced it. If it is ever wanted back it needs a
conforming name (`Shift3d`), a `SceneShift3d`, a test and a README row.

### 3.6 Three identical typedefs — **done**

`Layout3dItemBuilder` (`list_view.dart:12`), `Grid3dItemBuilder`
(`grid_view.dart:12`) and `Sliver3dItemBuilder` (`sliver_list.dart:11`) are all
`Layout3d Function(int index)`.

**What was done.** `Layout3dItemBuilder` moved to `layout3d.dart`, beside the
protocol, since all four views take it and none of them should have to import
another view to name it. The other two are now `@Deprecated` aliases for it,
still exported so existing callers keep compiling, to be dropped in a later
release.

---

## Phase 4 — Minor — **done**

- ~~`if (basis != null) _surface.basis = basis` never restores the default when
  `basis` goes back to null on a rebuild. The same `if (x != null)` pattern
  applies to `controller`; decide one rule and apply it to both.~~ **Done.**
  The rule: a null declarative property means *the default*, not "leave the
  last value alone", and the widget always assigns the resolved value. For
  `basis` the default is `LayoutBasis3d.xy`. For a controller it is one the
  view owns, so the four imperative setters now take `Scroll3dController?` and
  make a fresh one for null — which is also what the constructor has always
  meant by null.
- ~~`_lastIndexBefore` is a linear scan sitting next to `_indexAtOffset`, a
  binary search over the same sorted array.~~ **Done** in both files: the
  prefix is non-decreasing, so the predicate is monotone and the same
  last-true search applies. The linear version made the cost of a layout climb
  with how far the list had ever been scrolled.
- ~~`IgnorePointer3d.ignoring` and `AbsorbPointer3d.absorbing` are public
  mutable fields.~~ **Done.** Both are a getter and setter pair now, and still
  cost nothing to flip.
- ~~`horizontal`, `vertical`, `alongDepth` — the third breaks the pattern.~~
  **Done.** `depth` is the name, matching the other two, the `depth` argument
  of `EdgeInsets3d.symmetric`, and `Size3d.depth`. `alongDepth` is deprecated.
- ~~`dispose()` neither unparents the layout nor marks it disposed.~~ **Done**,
  the marking half. `Layout3d.debugDisposed`, with asserts against laying out,
  re-disposing, or dirtying a disposed layout. Unparenting is deliberately not
  done: whoever disposes a layout is the one that removed it, which is exactly
  what the lazy views do.
- ~~`GridView3d.dispose()` does not clear `_active`; `ListView3d.dispose()`
  does.~~ **Done.** Harmless either way, but it was one more copy that had
  drifted.

---

## Sequencing

1. ~~Phase 1 in one pass, with phase 3's doc fixes~~ — **done.** Landed with
   only the documentation phase 1 itself invalidated (the `depthStep` class
   doc, the property doc and the README's *How it differs from Flutter* entry),
   plus an `Unreleased` CHANGELOG section. The rest of phase 3 is untouched and
   still stands.
2. ~~Phase 2.2 and 2.3 (documentation route)~~ — **done**, together with all
   of phase 3 and the two phase 4 items in the files that were already open
   (`_lastIndexBefore`, `GridView3d.dispose`).
3. ~~Phase 2.1 route 1 (mixin extraction), then re-run the whole suite
   untouched.~~ **Done.**
4. ~~Phase 2.4 as its own change, since it moves the widget base class.~~
   **Done**, without moving the base class after all.
5. ~~The rest of phase 4 whenever a file is open for another reason.~~ **Done.**

Everything in this plan has landed. The suite went from 239 tests to 249, all
green, with `flutter analyze` clean throughout.

**What it deliberately did not do.** Three of these now have plans of their
own:

- [Extract the scroll-controller ownership](2026_08_25_scroll_controller_ownership.md)
  — the fifth duplication cluster, found while doing 2.1 and phase 4 but out of
  scope for both. `Viewport3d`, `ListView3d`, `GridView3d` and
  `CustomScrollView3d` each carry the same `_controller` / `_ownsController`
  pair, setter, `_handleScrollChanged` and dispose handling. **Done**, as
  `Scroll3dHolderMixin` over `Layout3dLayoutPassMixin`.
- [Give a measured list a length it can stand behind](2026_08_25_measured_list_scroll_range.md)
  — what 2.3 left open. Measuring the symptom showed that a
  `scrollOffsetCorrection` producer is the *wrong* tool, and that the
  documentation written for 2.3 described a symptom that does not occur; both
  are recorded there, and the documentation is fixed.
- [Views on the sliver protocol](2026_08_25_views_on_the_sliver_protocol.md) —
  route 2 of 2.1, written as a decision rather than a task, because route 1
  landing weakened the case for it.

Not planned, because they are feature work already scoped on the README's
roadmap rather than findings from this review: lazily built child *widgets* in
the declarative layer, and pinned or floating sliver headers.

Route 2 of 2.1 (rebuilding the views on the sliver protocol) and the real
`scrollOffsetCorrection` producer in 2.3 each deserve a plan of their own.
