---
status: pending
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T16:21:57Z
commit: 88e98579925771720a40c21b3d5ad607f787fdf7
---

# Should ListView3d and GridView3d be built on the sliver protocol?

Route 2 of item 2.1 in
[the review remediation](2026_08_25_layout3d_review_remediation.md), deferred
there because route 1 was the smaller change. Route 1 has since landed, which
changes the arithmetic on this one — read the decision section before starting.

**This plan opens with a decision, not a task.** The work is a real refactor of
two public classes, and the case for it got weaker when the mixins landed.

**The premise this plan was written on was wrong.** It said Flutter's
`ListView` *is* a `CustomScrollView` holding a `SliverList`. It is not, and the
shape the plan derived from that — a `ListView3d` that *owns* a
`CustomScrollView3d` — is a shape Flutter has nowhere. The correction is below;
it changes the design and part of the cost, and it leaves the decision standing.

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

## What it would be

Here the list views and the sliver views are separate implementations that
answer different protocols. This would make `ListView3d` *be* a viewport over a
single `SliverList3d`, and `GridView3d` the same over a `SliverGrid3d`, so the
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

Recommended: **not yet** — unchanged by the correction above. The duplication
that remains is the part that is genuinely different, and the API break is paid
by every caller of the imperative `ListView3d`. What the correction changes is
the design to use when it *is* done, and it removes one of the three nodes from
the cost.

Reasons that would flip it, any one of them enough:

- A feature needs implementing in both *placement* loops. `prototypeItem` did
  not — it went into the shared measuring mixin — so that one is not the
  precedent this was watching for.
- `SceneListView3d` gains lazily built child widgets (README roadmap), which
  needs a `RenderObjectElement` of its own — at which point the declarative
  list and the declarative sliver list want the same element, and sharing the
  layout object underneath stops being optional.
- The package moves past experimental and the API break becomes expensive to
  make later. Then it is now or never. (At 0.5.0 it has not.)

If none of those has happened, spend the time on the other two plans.

## If it is done anyway, the shape

Recorded so the decision does not have to be re-derived. Revised for what
Flutter actually does.

**Make the list a viewport, not a wrapper around one.** `ListView3d extends
CustomScrollView3d`, seeded with one `SliverList3d`; `GridView3d` the same with
a `SliverGrid3d`. Flutter's `ListView` and `CustomScrollView` are siblings over
one `ScrollView`, and the render object at the top of both is the viewport. If
`CustomScrollView3d` turns out to want a narrower public surface than a
subclass should inherit, the equivalent move is to lift the viewport layout
into a shared base the way `ScrollView` does, and have both extend it — what
must not happen is a list that *contains* a scroll view.

**Scrollable3d then needs no delegation.** `hit.firstOf<Scrollable3d>()` must
keep finding `ListView3d`. Because `CustomScrollView3d` already carries
`Scroll3dHolderMixin`, a `ListView3d` that *is* one satisfies this for free,
and there is no inner viewport to be found first. This was the largest hazard
under the old shape and it disappears with it.

**Give the outer class a child list that means what it meant.** `ListView3d`
should forward `children`, `add`, `remove` and `syncChildren` to its one
`SliverList3d`, not to its own list of slivers, so that the imperative API
and the declarative mirroring both keep working. That is a forwarding
layer, and it is the bulk of the work.

**Do not make `Viewport3d` a sliver view.** It is `SingleChildScrollView`: one
child that slides, no culling, no protocol. It stays as it is.

**Order:** grid first. `GridView3d` and `SliverGrid3d` are the smaller pair,
their placement is pure arithmetic, and the shape of the forwarding layer can
be settled there before the list, which has the measured prefix to carry as
well.

## Tests

The bar is the whole existing suite passing **unchanged** — every scroll, grid,
sliver, hit-test and widget test. If a test needs editing, that edit is the API
break, and it should be listed in the CHANGELOG rather than absorbed.

Add: a hit test through a `ListView3d` returns the `ListView3d` as its
`Scrollable3d`, and a `ListView3d` built from an explicit list still answers
`children` with its items.
