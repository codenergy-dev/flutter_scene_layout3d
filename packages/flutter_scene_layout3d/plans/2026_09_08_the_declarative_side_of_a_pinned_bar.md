---
status: completed
created_at: 2026-09-08T14:10:00Z
updated_at: 2026-09-08T19:40:00Z
commit: b0fcde3fb3b1b438783bc79510cca53f1ea21ffa
---

# The declarative side of a pinned bar

Written and closed inside `flutter_scene_material3d`'s phase 5, the phase that
builds `Scaffold3d` and the app bars. Three things stood between the widget
layer and a `SliverAppBar3d`, and the third is a defect rather than a gap.

## Why this is a plan of its own rather than an amendment

Phase 4 recorded that `SceneClipBox3d` did not exist and that phase 5 "will
want it properly", and the obvious home for that one line is an amendment to
[the four things before a component](2026_09_01_the_four_things_before_a_component.md),
which shipped `SceneDecoratedBox3d` for exactly the same reason: a widget form
the declarative layer was missing.

That is the wrong home, because the widget forms turned out to be the small
half of the work. The large half is that **a pinned header's clip never
reached a shader either** — the same failure phase 4 found in `ClipBox3d`, in
a second place, found by pointing the same instrument at it. A live defect
does not belong inside a plan marked `completed`, where the next reader takes
everything as history. So: a plan of its own, and phase 0 keeps its meaning.

## What was wrong

### 1. `ClipBox3d` was imperative-only

`ClipBox3d` is the one place in the package that publishes a `Clip3dRegion`,
and it had no widget. A widget test that wanted a clipped subtree wrote a
four-line `SingleChildLayout3dWidget` adapter by hand;
`flutter_scene_material3d`'s `test/card_test.dart` still contains one.

### 2. `SliverPersistentHeader3d` was imperative-only, and could not simply
grow a widget

`SliverPersistentHeader3dDelegate.build` is called on **every layout the
header does**, which while scrolling is every frame. A widget cannot answer
that: a subtree is inflated by the element tree in Flutter's build phase, and
the only machinery here that inflates one inside a layout pass is the lazily
built children lane, which a header is not.

So the declarative form cannot be a delegate that builds. It is a widget that
owns one subtree, attaches it as the header's child the ordinary way, and a
delegate that hands that same instance back every time — which is the shape
the delegate's own dartdoc already asked callers to write, now stated as a
class.

### 3. And the clip a pinned header imposes never reached a shader

This is the finding. `CustomScrollView3d.clipRegionForChild` cuts a sliver at
the trailing edge of whatever pinned sliver is sitting on it, and
`test/persistent_header_test.dart` has asserted the planes since the header
landed. Every one of those assertions passed. **No frame was ever cut.**

The order inside `_layoutSliverSequence` is the whole of it:

```
_obstructedTo.clear();            // at the top of every pass
for (final sliver in children) {
  sliver.layoutSliver(...);       // the rows are laid out AND placed here
  sliver.place(placement);        // the sliver itself moves here
  _obstructedTo[sliver] = ...;    // and only now does the viewport know
}
```

A `DecoratedBox3d` publishes its plane block from `repaint()`, at the end of
its own `performLayout`, and `Layout3d.place` republishes down a subtree it
moved. Both of those happen on lines one and two, while `_obstructedTo` is
empty — so every row under the bar was told, correctly for that instant and
uselessly, that nothing covered it. `Layout3d.clipRegion` answered correctly
from the moment the pass ended, which is why the arithmetic tests were green
and the picture was not.

Measured, before the fix, on a six-row list under a 2-unit pinned bar scrolled
to 3: `list.clipRegion` reported the plane `(0,1,0) · -2`, each row reported
its own shifted copy — and all six published blocks were `Clip3dRegion.none`.

## What was done

- **`SceneClipBox3d`** — the widget form of `ClipBox3d`, with `clipDepth` and
  `cullNodes`. Its dartdoc states the two things a caller loses time to: only
  a material that reads the plane block honours the plane tier, and a clip is
  convex, so a corner radius is not one.
- **`HeldSliverPersistentHeader3dDelegate`** — a delegate over a subtree
  somebody else owns and keeps. `build` returns `header.child`, so `identical`
  holds and the header never drops or disposes content it did not create. It
  records `shrinkOffset` and `overlapsContent` rather than acting on them,
  because acting on either means building something different and there is
  nothing here that can.
- **`SceneSliverPersistentHeader3d`** — the widget, over that delegate. The
  collapse is expressed through the constraint the header already gives its
  child (loose, against whatever is left of `maxExtent`), so a bar that fills
  what it is offered shrinks with the window.
- **`Layout3d.refreshClipSubtree()`** — `_refreshClipSubtree` promoted to a
  `@protected` member, because there is now a second caller. `place` still
  uses it.
- **`CustomScrollView3d._publishObstructionClips()`** — called once the layout
  has settled, it tells every sliver a pinned header is sitting on to
  republish its clip, and tells a sliver that has *stopped* being covered to
  republish once too. Slivers nothing covers pay nothing, and a viewport with
  no pinned header never reaches the loop.

`test/persistent_header_test.dart` gains the group that would have caught it:
the block a row under a pinned bar draws with is the band and not the
unbounded one, it moves as the list scrolls, and it goes back to unbounded
when the viewer returns to the top. `test/widgets_test.dart` covers the two
new widgets, including the one that matters — a widget-built pinned bar cuts
a widget-built row.

## What it changed elsewhere

`docs/traps.md` claimed, under *Clipping*, that the seam "is live: a row half
under a pinned `SliverPersistentHeader3d`, or half out of a scrolling window,
is genuinely cut at the edge." Only the second half of that was true. Phase 4
corrected the page once for `ClipBox3d`; it is corrected again here for the
header, with the general rule stated where a reader will meet it: **a clip
that is discovered after the boxes under it have painted has to be
republished, and nothing warns you.**

`examples/render_probe`'s `sliver_app_bar_clip` scene is the picture, and
`scaffold_bar_depth` is the other half of the same question.

## One thing still true and worth knowing

**The lift and the clip are two mechanisms and a Material bar needs both at
the right size.** `SliverPersistentHeader3d.lift` defaults to one logical
pixel, which is a depth-buffer separation rather than a distance. A
`Thickness3d.structural` bar (8dp) covering a `Thickness3d.raised` card (4dp)
needs a step above the *mean* of the two — 6dp — before the card stops poking
through the bar, so a Material bar sets the lift from the same scale its
slabs came from. `flutter_scene_material3d`'s `Scaffold3d.depthStep` is where
that number is stated once for a whole screen.
