---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# From a hit test to an event system

Hit testing here is finished and good. What comes after it is missing: there
is no way for a box to *receive* an event, so there is no tap, no hover, no
press state, no focus — and every interactive Material control is defined by
those four.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Drives the state layers in
[size-driven geometry](2026_08_25_size_driven_geometry.md); its focus half
needs `ensureVisible` from
[animation and scroll physics](2026_08_25_animation_and_scroll_physics.md).

## What exists today

[hit_test.dart](../lib/src/hit_test.dart) is the hard part and it is done: a
`Ray3d` walks the tree, each box clips the ray range to its own extent so a
child scrolled out of a list is unreachable, `HitTestResult3d.path` comes back
ordered deepest-first with a `localPosition` per entry, and
`firstOf<T>()`/`entryOf<T>()` find a typed ancestor.

[Layout3dPointer](../lib/src/input/pointer.dart) is where it stops. It does
exactly one thing: on `down` it looks for a `Scrollable3d` in the path, and
`move` drags it. A press that hits a button records `lastHit` and nothing
else. There is no dispatch, no recognition, no hover, no capture beyond the
scroll drag, and one pointer at a time.

Also relevant: `hitTestSelf` defaults to false, so a box that merely arranges
others is not a target — which means the padding around a button's label is
not tappable. `IgnorePointer3d` and `AbsorbPointer3d` exist.

## The design

The chain is **hit test → dispatch → recognition → state**. The first exists;
build the other three, in that order, and keep them separable.

### Dispatch

Mirror Flutter's shape, because `HitTestResult3d.path` is already the same
shape as `HitTestResult.path`:

```
abstract class HitTestTarget3d {
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry);
}
```

The pointer walks the recorded path deepest-first and calls `handleEvent` on
every layout that implements it. `PointerEvent3d` wraps Flutter's
`PointerEvent` — reuse the class, do not reinvent it — and adds the ray, the
entry, and the local position on the target's own frame.

**Capture is by path, not by box.** The path is recorded at `down` and reused
for `move`/`up`/`cancel`, which is what already keeps a scroll drag alive
when the finger leaves the list, and is the same rule Flutter uses.

### Behaviour

Add `HitTestBehavior3d { deferToChild, opaque, translucent }` and a wrapper
box that applies it, so a component can claim its whole box including padding.
Today the only self-answering boxes are `NodeBox3d` and the scrolling views;
a button made of a decoration and a label answers nothing.

### Recognition: reuse Flutter's arena

The observation that makes this cheap: a `GestureRecognizer` needs a pointer
id and a 2D position, nothing more. A hit on a box gives both — the entry's
`localPosition` projected onto the box's own plane is a perfectly good 2D
position, and it is *better* than a screen position, because it is already
perspective-corrected, which is the same insight `Layout3dPointer`'s drag is
built on.

So: synthesize Flutter `PointerEvent`s in the target's plane coordinates and
feed them to Flutter's own `GestureArenaManager`, `PointerRouter` and
recognizer classes (`TapGestureRecognizer`, `LongPressGestureRecognizer`,
`DragGestureRecognizer`, …), one router and one arena per surface. Material's
gesture semantics then match Flutter's exactly, for free, including the
disambiguation between a tap and a drag that a `ListTile` inside a
`ListView3d` needs on the first day.

`GestureDetector3d` is then a box that owns recognizers and routes to them;
`Listener3d` is the raw-event box beneath it.

The risk to check early: Flutter's recognizers assume a global pointer-id
space and `GestureBinding.instance.pointerRouter`. Owning a private router
and arena per surface is supported by the classes' public constructors, but
verify it before building on it — this is the one assumption the whole
approach rests on.

### Hover, enter and exit

A per-move pass that diffs the current path against the previous one and
emits enter/exit along the difference, the same thing `MouseTracker` does.
This is what drives the hover state layer. It needs the pointer to be fed
`move` events even when nothing is pressed, which today's API does not expect;
add `hover(Ray)` alongside `down`/`move`/`up`.

### Focus

Two halves, and only the second is novel.

- **The node graph is Flutter's.** `FocusNode`, `FocusScope`, `Shortcuts` and
  `Actions` all work in the declarative layer already, because these are real
  Flutter widgets. A `Focus3d` box ties a `FocusNode` to a layout so that a
  focus highlight can be drawn and so that `ensureVisible` can find the box.
- **Directional traversal is not.** Flutter's directional policy reasons about
  `Rect`s. Here a box has a `Size3d` and an offset in a 3D frame. The first
  cut is to project candidate boxes onto the surface plane and reuse the 2D
  policy; genuinely 3D traversal (and traversal *between* surfaces, which
  [overlays](2026_08_25_overlays_and_layered_surfaces.md) will need) is an
  open question this plan names and does not answer.

### Several pointers

`Layout3dPointer` holds one drag. Key the state by pointer id so two fingers
on two lists work, and so a VR controller and a mouse can coexist. While
there: `flutter_scene`'s
[ScenePointer](../../flutter_scene/lib/src/scene_pointer.dart) already solves
capture, hover state, layer masks and occlusion for widget surfaces. Decide
explicitly whether `Layout3dPointer` is built on it or stays parallel, and
write down the answer — two pointer abstractions in one scene with different
capture rules is a trap for users.

## The work

- [ ] **Phase 1 — events and dispatch.** `PointerEvent3d`, `HitTestTarget3d`,
      path capture, `Listener3d`.
- [ ] **Phase 2 — behaviour.** `HitTestBehavior3d` and its box.
- [ ] **Phase 3 — recognizers.** Private router and arena per surface, the
      plane-coordinate synthesis, `GestureDetector3d` with tap, double tap,
      long press and pan. Verify the arena assumption first.
- [ ] **Phase 4 — hover.** `hover(Ray)`, path diffing, enter/exit.
- [ ] **Phase 5 — focus.** `Focus3d`, highlight plumbing, the projected
      directional policy.
- [ ] **Phase 6 — multiple pointers**, and the `ScenePointer` decision.

## Tests

- A synthesized ray taps a box three levels down; the path order is
  deepest-first; an `AbsorbPointer3d` in between takes it instead.
- `opaque` behaviour makes a padded button's padding tappable;
  `deferToChild` does not.
- A drag that starts on a list still scrolls it — the existing behaviour, as a
  regression test, because it is the one thing that already works.
- Tap versus drag disambiguation on an item inside a `ListView3d`.
- Hover enter/exit sequences across a boundary, including leaving the surface
  entirely.
- Two pointers driving two scrollables independently.
- A hidden node receives nothing (already true; pin it).

## Out of scope

Text selection gestures, drag-and-drop between surfaces, IME, and the cursor
appearance (which is a platform concern the host `SceneView` owns).
