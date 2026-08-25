---
status: pending
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T15:21:54Z
commit: 88e98579925771720a40c21b3d5ad607f787fdf7
---

# Should ListView3d and GridView3d be built on the sliver protocol?

Route 2 of item 2.1 in
[the review remediation](2026_08_25_layout3d_review_remediation.md), deferred
there because route 1 was the smaller change. Route 1 has since landed, which
changes the arithmetic on this one — read the decision section before starting.

**This plan opens with a decision, not a task.** The work is a real refactor of
two public classes, and the case for it got weaker when the mixins landed.

## What it would be

In Flutter, `ListView` *is* a `CustomScrollView` holding a `SliverList`. Here
they are separate implementations that answer different protocols. This would
make `ListView3d` own a `CustomScrollView3d` holding one `SliverList3d`, and
`GridView3d` the same with a `SliverGrid3d`, so the placement logic exists once.

## The case for

**One code path cannot drift from itself.** Every bug found in this package's
scrolling views so far was a divergence between copies: `itemCount` going stale
in one of four, `SliverList3d` keeping a measured prefix the other three
dropped, `activeIndices` existing on one. The mixins removed the *bookkeeping*
copies; the placement logic is still two copies of "where does item `i` go and
is it visible", about 80 lines each.

**Improvements land once.** `prototypeItem` from
[the measured-list plan](2026_08_25_measured_list_scroll_range.md) is the
immediate example: two implementations if the views stay separate, one if they
do not. The same goes for anything later — reverse lists, a `center` sliver,
keep-alive.

**It is the shape a reader expects.** The package's whole proposition is
"Flutter's protocol, one axis richer", and a reader who knows that `ListView`
is a sliver view will look for that here.

## The case against

**The remaining duplication is smaller than it was.** After route 1 the four
views share their bookkeeping; what is left is the part that genuinely differs
in shape — a grid places by arithmetic, a list by prefix sums. Two of the four
already share nothing with the other two.

**It costs a node per list.** `ListView3d` would become a wrapper holding a
viewport holding a sliver, so three `Layout3d` objects and three scene `Node`s
where there is one. In a scene graph, unlike a render tree, every node is
traversed each frame.

**`ListView3d.children` stops being its items.** It is a `MultiChildLayout3d`
whose children are the items today; it would become one whose single child is a
viewport. `children`, `childAt`, `childCount`, `add`, `remove` and
`syncChildren` all change meaning. That is a real break for the imperative API,
and the declarative layer's `adoptLayoutChildren` mirrors widget children onto
exactly those methods, so `SceneListView3d` needs a slot to put its children
*through* the wrapper into the inner sliver.

**Two protocols meeting is where the sharp edges are.** The one hit-testing
subtlety already in the package (a sliver's box is derived from the geometry it
reported) would now sit between a caller and their list.

## Decision

Recommended: **not yet.** The duplication that remains is the part that is
genuinely different, and the API break is paid by every caller of the
imperative `ListView3d`.

Reasons that would flip it, any one of them enough:

- A second feature after `prototypeItem` needs implementing in both places.
  Two is a coincidence; three is the pattern this exists to stop.
- `SceneListView3d` gains lazily built child widgets (README roadmap), which
  needs a `RenderObjectElement` of its own — at which point the declarative
  list and the declarative sliver list want the same element, and sharing the
  layout object underneath stops being optional.
- The package moves past experimental and the API break becomes expensive to
  make later. Then it is now or never.

If none of those has happened, spend the time on the other two plans.

## If it is done anyway, the shape

Recorded so the decision does not have to be re-derived.

**Keep the outer class the `Scrollable3d`.** `hit.firstOf<Scrollable3d>()` must
keep finding `ListView3d`, not the viewport inside it, or every drag handler
that reaches for the list breaks. Have the outer class implement `Scrollable3d`
by delegating to its viewport, and make sure the inner one is not itself found
first — the deepest match wins, so the inner viewport must not implement the
interface, or the outer must sit between them in the hit path.

**Give the outer class a child list that means what it meant.** `ListView3d`
should keep forwarding `children`, `add`, `remove` and `syncChildren` to the
inner sliver rather than to its own single child, so the imperative API and the
declarative mirroring both keep working. That is a forwarding layer, and it is
the bulk of the work.

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
