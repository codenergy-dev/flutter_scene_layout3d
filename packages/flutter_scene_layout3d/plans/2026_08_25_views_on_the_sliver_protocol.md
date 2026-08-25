---
status: completed
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T19:43:58Z
commit: 88e98579925771720a40c21b3d5ad607f787fdf7
---

# Should ListView3d and GridView3d be built on the sliver protocol?

Route 2 of item 2.1 in
[the review remediation](2026_08_25_layout3d_review_remediation.md), deferred
there because route 1 was the smaller change.

**Done.** This plan opened with a decision rather than a task, recommended
*not yet*, and was then directed to go ahead on fidelity grounds. The case on
both sides is kept as it was written; what happened is under *Decision* and
*What was done*.

**The premise this plan was written on was wrong.** It said Flutter's
`ListView` *is* a `CustomScrollView` holding a `SliverList`. It is not, and the
shape the plan derived from that — a `ListView3d` that *owns* a
`CustomScrollView3d` — is a shape Flutter has nowhere. The correction is below,
and the work was built on the corrected shape.

## What Flutter actually does

Checked against Flutter 3.47.1, all of it in one file —
`packages/flutter/lib/src/widgets/scroll_view.dart`:

```
ScrollView (abstract, :95)
│   build() → Scrollable(viewportBuilder: buildViewport(…))       :503
│   buildViewport() → Viewport(slivers:) / ShrinkWrappingViewport :456
├── CustomScrollView (:718)
│       buildSlivers() => slivers                                 :848
└── BoxScrollView (abstract, :867)
    │   buildSlivers() => [SliverPadding(buildChildLayout())]     :898
    ├── ListView (:1294)
    │       buildChildLayout() => SliverList, or the fixed-,      :1708
    │       varied- and prototype-extent lists
    └── GridView (:1976)
            buildChildLayout() => SliverGrid                      :2244
```

`ListView` and `CustomScrollView` are **siblings**, not a container and its
content. `ListView` holds no `CustomScrollView`; the two share `ScrollView`,
which builds the `Scrollable` and the `Viewport` for both. `CustomScrollView`
adds exactly one line of its own — it hands its `slivers` straight through.

Two things follow, and they pull in opposite directions.

**The half that is true is the important half.** A `ListView` has no layout
algorithm of its own. Its items are placed by `RenderSliverList` inside a
`RenderViewport`, the same two render objects a `CustomScrollView` over one
`SliverList` produces. There is no `RenderListView` in Flutter, and that is the
statement that matters here, because `ListView3d` is a `Layout3d` — a render
object, not a widget. The package's `ListView3d` is a box-level list layout
that Flutter does not have.

**The half that is false is the half the plan built its design on.** Flutter
does not pay a wrapper for `ListView`: the outermost render object of a
`ListView` *is* the viewport. A `ListView3d` holding a `CustomScrollView3d`
holding a `SliverList3d` would be three nodes where Flutter has two, plus a
forwarding layer with no counterpart in the framework — further from Flutter's
shape, not closer.

## What it was to be

The list views and the sliver views were separate implementations answering
different protocols. This makes `ListView3d` *be* a viewport over a single
`SliverList3d`, and `GridView3d` the same over a `SliverGrid3d`, so the
placement logic exists once and the class hierarchy says what Flutter's says:
a list view is a scroll view whose one sliver happens to be chosen for it.

## The case for

**One code path cannot drift from itself.** Every bug found in this package's
scrolling views so far was a divergence between copies: `itemCount` going stale
in one of four, `SliverList3d` keeping a measured prefix the other three
dropped, `activeIndices` existing on one. The mixins removed the *bookkeeping*
copies; the placement logic is still two copies of "where does item `i` go and
is it visible", about 80 lines each.

**Improvements land once.** `prototypeItem` from
[the measured-list plan](2026_08_25_measured_list_scroll_range.md) was the
immediate example, and it has since landed with the views still separate. It
is weaker evidence than it looked: the feature went into
`Layout3dMeasuredChildrenMixin`, which both lists already share, and each list
pays three lines of wiring for it. The argument still holds for anything that
touches *placement* — reverse lists, a `center` sliver, keep-alive — because
that is the part the two views actually keep two copies of.

**It is the shape a reader expects, and the render-level claim is exact.** The
package's whole proposition is "Flutter's protocol, one axis richer". A reader
who knows the render tree knows a list's children are placed by a sliver inside
a viewport, and that Flutter ships no box-level list layout at all. This is the
strongest form of the fidelity argument, and it is about the `Layout3d` layer,
not the widget layer.

## The case against

**The remaining duplication is smaller than it was.** After route 1 the four
views share their bookkeeping; what is left is the part that genuinely differs
in shape — a grid places by arithmetic, a list by prefix sums. Two of the four
already share nothing with the other two.

**It still costs a node per list.** Even in the corrected shape — the list *is*
the viewport — there is a `SliverList3d` under it where there is one object
today, so two `Layout3d`s and two scene `Node`s instead of one. Flutter pays
that too, but in a scene graph, unlike a render tree, every node is traversed
each frame.

**`ListView3d.children` stops being its items.** It is a `MultiChildLayout3d`
whose children are the items today; it would become one whose children are
slivers, with a single `SliverList3d` among them. `children`, `childAt`,
`childCount`, `add`, `remove` and `syncChildren` all change meaning unless they
are forwarded. That is a real break for the imperative API, and the declarative
layer's `adoptLayoutChildren` mirrors widget children onto exactly those
methods, so `SceneListView3d` needs its children to reach the inner sliver.
Flutter never faces this: its `ListView` is a widget, and widget children are
rebuilt configuration, not adopted objects.

**Two protocols meeting is where the sharp edges are.** The one hit-testing
subtlety already in the package (a sliver's box is derived from the geometry it
reported) would now sit between a caller and their list.

## Decision

**Done**, on the corrected shape, at the caller's direction. The plan had
recommended *not yet*, and the reasoning behind that recommendation is kept
below because it is the honest account of the trade: the duplication left after
route 1 is the part that genuinely differs, and the shape had to be paid for in
forwarding. What decided it was fidelity — the package's whole proposition is
Flutter's protocol one axis richer, and a box-level list layout is a thing
Flutter does not have anywhere.

What was recommended against, and why, at the time:

- No feature had needed implementing in both *placement* loops.
  `prototypeItem` went into the shared measuring mixin instead.
- `SceneListView3d` still has no lazily built child widgets, so the declarative
  list and the declarative sliver list do not yet want the same element.
- The package is at 0.5.0, so the API break was not yet expensive to make
  later.

Of those, the third turned out to argue *for* doing it now rather than against:
the break is cheapest while the package is pre-1.0, and it is now paid.

## What was done

**`BoxScrollView3d`**, the 3D analogue of Flutter's `BoxScrollView`: a
`CustomScrollView3d` whose window holds exactly one sliver, and which forwards
its public child list to it. `ListView3d extends BoxScrollView3d<SliverList3d>`
and `GridView3d extends BoxScrollView3d<SliverGrid3d>`; each public constructor
builds its sliver and redirects to a private one that wires the viewport.

**`SliverMultiBoxAdaptor3d`**, the analogue of `RenderSliverMultiBoxAdaptor`:
the child list, the index-keyed bookkeeping and the layout pass that
`SliverList3d` and `SliverGrid3d` had been declaring one mixin at a time. It is
also the type bound `BoxScrollView3d` forwards to.

**Two accessors the forwarding needed.** `Layout3dWithChildrenMixin` gained a
protected `heldChildren` — the list a layout actually holds, as against the one
[children] answers with — because `CustomScrollView3d` lays out its own slivers
and must not read the forwarded list. And the refusal message a built view
gives a child-list edit moved into `builtChildEditRefused`, so the wrapper can
refuse in its own name (`ListView3d.builder`, not `SliverList3d.builder`)
before forwarding.

**`CustomScrollView3d` learned to shrink-wrap.** It asserted on an unbounded
scroll axis; the box views sized themselves to their content there, and that
had to survive. It now lays its slivers out against an endless window and comes
out as long as they filled, which is `ShrinkWrappingViewport`.

**`Grid3dDelegate` and `Grid3dLayout` moved** to `src/scroll/grid_delegate.dart`
so that `grid_view.dart` and `sliver_grid.dart` do not import each other. No
public API moved with them: both libraries export the same names.

### What it cost, measured

- One scene node per list or grid, the sliver's — the node Flutter's render
  tree has in the same place.
- Two behaviour changes, both toward Flutter and both in the CHANGELOG:
  `cacheExtent` no longer draws what it keeps alive, and a view now needs a
  bounded extent across its scroll axis rather than shrink-wrapping to the
  widest item (it takes no depth on an unbounded depth axis for the same
  reason).
- One test edited, which is what those changes look like from outside: the
  cache-extent test now reads the built set rather than the visible set.

The forwarding layer is 50 lines, less than the "bulk of the work" this plan
predicted, because the corrected shape needs no `Scrollable3d` delegation: a
view that *is* a `CustomScrollView3d` already carries `Scroll3dHolderMixin`.

### What the review afterwards turned up

Two things, both about the seam this work created rather than about the shape
of it:

- **The bounded-extent demand reached the CHANGELOG but not the README.** It
  matters more here than the entry admits: a `Layout3dSurface` is unbounded on
  all three axes by default, so `Layout3dSurface(child: ListView3d(...))` — the
  shortest thing a reader would write — now asserts where it used to
  shrink-wrap. Flutter never faces this because the screen bounds everything.
  The *Scrolling* section says so now, with the fix, and *Traps* carries the
  unbounded depth axis, which leaves a view with no depth for items to stand
  in.
- **One assertion message still named the sliver.** `builtChildEditRefused`
  exists so that a wrapper can refuse in its own name, and the child-list edits
  use it; the `itemCount` setter was left telling a `ListView3d` caller about
  `SliverList3d.builder`. It has a matching `explicitChildCountRefused` now,
  refused in `BoxScrollView3d` before it forwards, the way the edits are.

## The shape it was built on

**The list is a viewport, not a wrapper around one.** Flutter's `ListView` and
`CustomScrollView` are siblings over one `ScrollView`, and the render object at
the top of both is the viewport. A list that *contains* a scroll view is the
thing this plan originally proposed and the thing Flutter has nowhere.

**`Scrollable3d` needs no delegation.** `hit.firstOf<Scrollable3d>()` keeps
finding `ListView3d` because a `ListView3d` *is* a `Scroll3dHolderMixin`, and
the sliver in between is not one. Pinned by a test.

**The child list means the items.** `children`, `childAt`, `childCount`, `add`,
`insert`, `remove`, `removeAll`, `syncChildren`, `itemCount`, `isLazy`,
`activeIndices` and `refresh` forward to the sliver; `visitChildren` and hit
testing walk the tree as it really is. That is what keeps both the imperative
API and the declarative `adoptLayoutChildren` mirroring working untouched.

**`Viewport3d` was not made a sliver view.** It is `SingleChildScrollView`: one
child that slides, no culling, no protocol. Unchanged.

**Order:** grid first, then the list, as planned. The grid landed with its
whole suite passing before the list was started.

## Tests

The bar was the whole existing suite passing **unchanged**. It does, with one
exception, listed in the CHANGELOG rather than absorbed: `a cache extent keeps
neighbours alive` asserted that an item in the cache was *visible*, which is
the behaviour that changed.

Added:

- a `ListView3d` holds its sliver, answers `children` with the items, and
  parents them to the sliver in both the layout tree and the scene graph;
- a hit through a `ListView3d` answers `firstOf<Scrollable3d>()` with the list,
  passes through the sliver, and the sliver is not a `Scrollable3d`;
- the same structural test for `GridView3d`;
- a list and a viewport each shrink-wrap when the scroll axis has no edge;
- a cache extent builds past the window without showing it.
