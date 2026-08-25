---
status: pending
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T15:21:54Z
commit: 88e98579925771720a40c21b3d5ad607f787fdf7
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

1. `prototypeItem` on the two lists and their sliver twins. Most of the work is
   in `Layout3dMeasuredChildrenMixin`'s callers, not the mixin.
2. `contentExtentEstimator`, threaded into `estimatedContentExtent`.
3. Documentation: the README's *Scrolling* and *Slivers* sections gain
   `prototypeItem` as the recommended answer, above the "give it an
   `itemExtent`" advice, since it needs nothing of the caller.
4. Optional: the debug assert on a runaway measuring pass.

## Tests

- A `prototypeItem` list builds a constant number of children whatever the
  scroll offset — the `built=2006` case above becomes `built=12`-ish.
- A `prototypeItem` list reports the same `scrollExtent` at every offset.
- The prototype's node is never visible.
- `prototypeItem` and `itemExtent` together assert.
- A `contentExtentEstimator` overrides the average, and the range holds still
  across a scroll that would otherwise move it.
- The existing measured-mode tests keep passing unchanged: this adds modes, it
  does not change the one that is there.

## Where this sits

Independent of
[the controller ownership extraction](2026_08_25_scroll_controller_ownership.md).

Related to
[putting the views on the sliver protocol](2026_08_25_views_on_the_sliver_protocol.md):
if that lands first, `prototypeItem` is implemented once in `SliverList3d` and
`ListView3d` inherits it. If this lands first, it is implemented twice and the
other plan collapses the two. Either order works; doing that one first is
slightly less total work, doing this one first delivers value sooner.
