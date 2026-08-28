---
status: completed
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T19:43:58Z
commit: f1225b07925a18ca3418da10312eb982e2aa4bc1
---

# Give a measured list a length it can stand behind

`SliverList3d.builder` and `ListView3d.builder` without an `itemExtent` guess
their own length, and the guess moves. This plan is about what to do instead.

It replaces the item the
[review remediation](2026_08_25_layout3d_review_remediation.md) left open as
"a real `scrollOffsetCorrection` producer", because measuring what actually
happens showed that a correction is the wrong tool. That is recorded below.

## What actually happens

Measured first, on a 40-item list of unequal children in a window of 10, with
another sliver after it:

```
start:          est=73.3   afterOffset=10.0   max=66.3
jumpTo(20)  ->  est=140.0  afterOffset=10.0   max=133.0
jumpTo(60)  ->  est=177.5  afterOffset=10.0   max=170.5
jumpTo(120) ->  est=201.5  afterOffset=10.0   max=194.5
```

And with the bias the other way — five long items, then thirty-five short ones,
true total 75:

```
start:          est=320.0  max=310.0
jumpTo(40)  ->  est=127.5  max=117.5
jumpTo(60)  ->  est=78.9   max=68.9
jumpTo(300) ->  est=75.0   max=65.0   offset clamped to 65
```

Two symptoms, and neither is the one the docs claimed before this plan was
written:

1. **The reachable range moves under the viewer.** The end of the list recedes
   as you scroll into it (first table) or rushes toward you (second), and when
   it rushes past where you are, `applyViewportMetrics` clamps the offset and
   the content jumps.
2. **A deep jump measures everything before it.** The running total starts at
   item 0, so reaching an offset in the middle of a long list builds every item
   up to it in one pass:

```
ListView3d.builder, 5000 items, no itemExtent
  after first layout:  built=6      active=5
  after jumpTo(4000):  built=2006   active=5

the same list with itemExtent: 2
  after jumpTo(4000):  built=12     active=6
```

Two thousand item builds for one jump, all but five thrown away again.

**What does *not* happen**, and what the previous round's documentation
wrongly said would: nothing moves. Item positions come from the measured
prefix, which is real measurement and exact, so an item never shifts under the
viewer. Nor does the sliver after it: `paintExtent` is clamped to the window,
and whenever the estimate is small enough for a following sliver to be visible
at all, the whole list has been measured and the estimate is exact. The
documentation was corrected in the commit that added this plan.

## Why `scrollOffsetCorrection` is the wrong tool

It exists for a sliver that discovers its *content* is not where the offset
assumed — Flutter's `RenderSliverList` issues one when it walks backwards to
find the first visible child and the child's real offset disagrees with the
estimate it arrived with.

That cannot happen here. `SliverList3d` only ever measures forward from item 0
and keeps every measurement, so the offsets it hands out are exact by
construction and there is nothing to correct. Issuing a correction would move
the viewer's position to compensate for an error that was never made.

The unstable quantity is the *total*, and a correction does not stabilise a
total. So: no correction producer. The viewport's support for corrections
stays, for slivers a caller writes; this plan does not touch it.

## What to do instead

The root of both symptoms is the same: the list has no way to know an item's
extent without building it. Give it one.

### 1. `prototypeItem` — the main piece

Flutter's answer for "uniform items whose extent I cannot state as a number" is
`SliverPrototypeExtentList` / `ListView.prototypeItem`: build **one** child,
lay it out, and use its extent for every item. Everything becomes arithmetic —
exactly as with `itemExtent`, but the number comes from the content instead of
the caller.

```dart
ListView3d.builder(
  itemCount: 5000,
  prototypeItem: () => NodeBox3d(content: sampleCard),
  itemBuilder: (index) => NodeBox3d(content: cards[index]),
)
```

Shape:

- A `Layout3d Function()` on `SliverList3d.builder`, `SliverList3d`,
  `ListView3d.builder` and `ListView3d`, mutually exclusive with `itemExtent`
  (assert).
- The prototype is a real child of the view, laid out against the same
  constraints an item gets, and its node is kept hidden — it is measured, never
  shown. Give it its own field rather than a slot in the built-children map,
  which is keyed by item index.
- Its extent is measured once per layout in which the child constraints
  changed, and then feeds the existing `itemExtent` path unchanged. That is the
  whole implementation: `_itemExtent ?? _prototypeExtent` at the four places
  `itemExtent` is read.
- `refresh()` re-measures it.

This is most of the value in this plan. It removes both symptoms for the case
that produces them most often — a long list of the same kind of thing.

### 2. A caller-supplied estimate, for genuinely ragged lists

For a list whose items really do differ, Flutter lets the delegate answer
`estimateMaxScrollOffset`. The 3D analogue is one optional callback:

```dart
/// The total extent along the scroll axis, when the caller knows it.
///
/// A list of free-sized items can only average what it has measured, and that
/// average moves as it measures more. An application that knows the real total
/// — because it knows the data — can say so and stop the range from moving.
final double Function(int itemCount)? contentExtentEstimator;
```

Small, optional, and it turns an unfixable guess into the caller's problem,
which is where the information is.

### 3. Bound the deep jump, or document it as the price

Symptom 2 has no cheap fix inside the measured mode: to know where item 4000
starts, something has to know the extent of the 4000 before it. The options are
`itemExtent`, `prototypeItem`, or measuring them.

Do **not** add a heuristic that skips ahead and guesses — that reintroduces
inexact offsets and *then* a `scrollOffsetCorrection` really would be needed,
which is a much larger piece of machinery than this package wants. Instead:

- State the cost plainly in the class doc (done in the commit that adds this
  plan), and
- Consider an assert in debug when a single pass builds more than, say, 500
  items, naming `itemExtent` and `prototypeItem`. It turns a mysterious frame
  hitch into a message. Decide during implementation whether a fixed threshold
  is honest enough to ship; if not, drop this bullet.

## Steps

1. [x] `prototypeItem` on the two lists and their sliver twins. Most of the work is
   in `Layout3dMeasuredChildrenMixin`'s callers, not the mixin.
2. [x] `contentExtentEstimator`, threaded into `estimatedContentExtent`.
3. [x] Documentation: the README's *Scrolling* and *Slivers* sections gain
   `prototypeItem` as the recommended answer, above the "give it an
   `itemExtent`" advice, since it needs nothing of the caller. The step named
   the README and so did the work; the CHANGELOG was missed, and three pieces
   of new public API went in without an entry. Added in the review afterwards.
4. [x] Optional: the debug assert on a runaway measuring pass.

## What the implementation changed about the plan

Four things came out differently, all of them decided while writing it:

**The mixin took more of the work, not less.** The plan expected the work to
sit in `Layout3dMeasuredChildrenMixin`'s callers. It ended up in the mixin:
`itemExtent` itself moved there from the two lists, which held identical
copies of the field, the getter and the setter, and `prototypeItem` sits next
to it. That is what makes the mutual-exclusion assert a single line in one
setter instead of four constructor asserts, and it turns "the four places
`itemExtent` is read" into one call, `resolveItemExtent(childConstraints,
axis)`. Each list is left with the part that is its own: which constraints an
item gets, and what to do with an extent once it has one.

**The prototype is not in the child list.** The plan said "a real child of the
view … its node is kept hidden". It is a child of neither list. Both views
index their children — `positionedChildren` walks `childCount` for an explicit
list, and `itemCount` *is* `childCount` there — so a prototype in that list
would be placed as an item and counted as one. It is held in a field, laid out
on its own, and its node is never added to the scene, which is a stronger
guarantee than hiding it: there is nothing to cull, hit, or draw. Its
`node.visible` is set false anyway, for whoever finds it in a debugger.

**The debug assert shipped, and its first form was wrong.** A fixed threshold
of 500 was applied to the items a pass *measured*, with one exemption: a list
laid out in unbounded room genuinely measures every item, so
`debugMeasuringPassWasSane` took a `boundedWindow` flag and said nothing there.
The exemption was the right instinct aimed at the wrong quantity. A bounded
window can also be long — 2000 items of 2 in a window of 1400 measures 701 of
them, every one of which is on screen — and that layout crashed in debug, with
a message claiming it had "kept only what the window shows".

The quantity that says a pass went wrong is what it *threw away*, not what it
measured. So the assert now takes `measured` and `discarded`, and the
`boundedWindow` exemption is gone because it falls out: a window that shows
what it measured, bounded or not, discards nothing. Pinned by two tests beside
the deep-jump one — a long bounded window and an unbounded one, both silent.

**The widget layer did not get either field.** `SceneListView3d` and
`SceneSliverList3d` take explicit children and are rebuilt from a `build`
method, where a closure is a new object every time. `prototypeItem` compares by
identity, so a widget field would discard and re-measure the prototype on every
rebuild — a trap worse than the problem. Both fields stay on the imperative
classes, which is where the plan put them; a widget-layer answer needs the
prototype to be a *widget*, compared the way Flutter compares one, and that is
a piece of the lazy-widget-building work rather than of this.

## Tests

All of these landed, in `test/scroll_test.dart` and `test/sliver_test.dart`:

- [x] A `prototypeItem` list builds a constant number of children whatever the
  scroll offset — the `built=2006` case above becomes `built=12`-ish.
- [x] A `prototypeItem` list reports the same `scrollExtent` at every offset.
- [x] The prototype's node is never visible — checked as never being in the
  list's node children at all, which is what the implementation guarantees.
- [x] `prototypeItem` and `itemExtent` together assert.
- [x] A `contentExtentEstimator` overrides the average, and the range holds
  still across a scroll that would otherwise move it.
- [x] The existing measured-mode tests keep passing unchanged: this adds modes,
  it does not change the one that is there.

Plus three the plan did not name: the prototype is measured once and again when
the constraints an item gets change, `refresh()` builds a new one, and an
estimate shorter than what has already been measured is raised to it — the
offsets are exact measurements, so a total under them would put items outside
the range they sit in.

## Where this sits

Independent of
[the controller ownership extraction](2026_08_25_scroll_controller_ownership.md).

Related to
[putting the views on the sliver protocol](2026_08_25_views_on_the_sliver_protocol.md):
if that lands first, `prototypeItem` is implemented once in `SliverList3d` and
`ListView3d` inherits it. If this lands first, it is implemented twice and the
other plan collapses the two. Either order works; doing that one first is
slightly less total work, doing this one first delivers value sooner.

This one landed first, and the "implemented twice" half of that turned out to
be nearly free: the measuring, the prototype and the estimate all sit in
`Layout3dMeasuredChildrenMixin`, which both lists already had, and what is
duplicated is three lines of wiring in each — resolve the extent, then hand it
to the code that was already reading `itemExtent`. That is evidence for the
other plan's "not yet": the copies that cost something are the placement
loops, not the features layered on them.
