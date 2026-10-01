---
status: completed
created_at: 2026-10-01T22:30:00Z
updated_at: 2026-10-01T23:20:00Z
commit: 9e782060c9898853974ea98ede4f025a26ea96a1
---

# A label wholly outside its window

Phase 5 of
[the components a screen still needs](../../flutter_scene_material3d/plans/2026_09_21_the_components_a_screen_still_needs.md)
needed one change here, and it was found by looking rather than planned: the
rule the catalogue's phase 0 set is that a change to the layout protocol the
catalogue needs gets its own plan in this package, so here it is, written as
the change was made.

## What the photograph showed

`TabBarView3d` is a page view, and the gallery's settings were put on two of
its pages. The photograph lane caught a tab change half way, and the page
leaving the window had its **labels drawn outside the panel** — "Notifications",
"Volume", "Reset", "About" floating in the room to the left of the screen —
while the cards they belonged to were cut cleanly at the window's edge.

Both halves are this package's documented behaviour, and that is the point:

- A panel is cut at a clip plane by its shader. The window the cards were cut
  at is the `ClipBox3d` a `Scaffold3d` puts round its body, and a box that
  moves under it republishes its clip from `Layout3d.place`, so a scroll cuts
  panels on every frame without laying anything out.
- A glyph's material reads no planes. `docs/traps.md` says a label half out
  of a window draws whole, and a list's row that straddles the edge shows it
  for the height of a row.

What the page view added is the *size* of the straddling thing. A sliver list
hides an item once the item is wholly outside, and the item here is a whole
page, so for the 300ms of a turn every label on the page was a candidate to
be drawn up to a page's width outside the window.

## The change

**A label wholly outside its clip draws nothing.** `Text3d` and `RichText3d`
override `Layout3d.refreshClipRegion` — the hook `place` already calls down a
moved subtree, and `ClipBox3d` over its own — and hide their node when
`Clip3dRegion.excludes` says the clip leaves none of them. They also read the
clip at the end of their own `performLayout`, as `DecoratedBox3d` does from
`repaint`, so a label laid out where it is already outside starts hidden.

**The test is against the ink, not the box.** A `Text3d`'s lines know where
alignment put them, so the span from the leftmost line's start to the
rightmost line's end is the label's letters, read off the cached layout. That
distinction is the second thing the photograph taught, below.

It is `ClipBox3d`'s whole-node tier, applied per label rather than per
subtree sweep, and it keeps that tier's two rules:

- **Only what it hid, it shows.** A label remembers that it hid itself and
  shows itself again only then, so a label that is a list's item — hidden by
  the list — or one hidden by anything else is not this hook's to show.
- **Nothing is laid out.** It is a node's visibility, written from the place
  a scroll already reaches.

A label straddling the edge is still drawn whole; that is the plane tier, and
the glyph material still has none.

## What the reasoning got wrong

**That a page view clips.** The first test put labels in a bare `PageView3d`
and the label stayed visible: a scroll view here publishes no window of its
own — a `CustomScrollView3d` publishes the band a pinned header covers and
nothing else, by design — and the window in the gallery was the scaffold's.
So the test puts the view in a `ClipBox3d`, which is the arrangement every
real case has, and `TabBarView3d` now clips its pages to its own window, as
Flutter's `TabBarView` does by default with `Clip.hardEdge`.

**That a label's box says where its letters are.** The second photograph,
with the box test in, still had "Volume" floating beside the panel. It is a
label in a column that stretches its children, so its box is as wide as the
card and half of it was still inside the window while every letter was out.
`RichText3d` keeps the box test: its box is its paragraph's width.

## Tests

`test/clip_test.dart`, *a label wholly outside its clip*: a label half a page
across hidden and its neighbour on the same page not; both back when the page
is; a label half in drawn whole; a label stretched across its page whose
letters are out though its box is not; nothing laid out; and a label hidden
by someone else left hidden. The half-page one fails with the override removed,
which was checked. The Material package's `test/tabs_test.dart` asks the same
of a tab view half way through a turn.
