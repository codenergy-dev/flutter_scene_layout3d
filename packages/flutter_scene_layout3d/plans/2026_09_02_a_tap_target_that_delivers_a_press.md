---
status: completed
created_at: 2026-09-02T18:10:00Z
updated_at: 2026-09-02T18:10:00Z
commit: 959151babca3c9026c5b3e4830c4a82b22123620
---

# A tap target that delivers a press

This plan owns the gap
[the Material catalogue plan](../../flutter_scene_material3d/plans/2026_09_01_flutter_scene_material3d.md)
found in phase 2 and left standing with a test around it: **`TapTarget3d`'s
48dp minimum grows the ray region and delivers no press in the margin.** Phase
3 is the seven buttons, and a button is precisely the control the Material
minimum exists for, so a catalogue that shipped over this would be claiming a
target it does not have.

It lands here, in `flutter_scene_layout3d`, for the reason phase 0's four
things and the metrics scope did: public API must not arrive under another
package's plan number.

## The gap, exactly

`TapTarget3d.hitTest` grows the region it answers for and then hands its
children the **unmoved** ray:

```dart
hitTestChildren(result, ray: ray.clampedTo(range.near, range.far));
result.add(HitTestEntry3d(this, entry));
return true;
```

"The reach this box adds is its own." That is a defensible sentence and it is
what makes the box useless as a *target*: every box gates its children on its
own extent, so out in the margin the child chain — the `Focus3d`, the
`Listener3d`, the `GestureDetector3d` an `InkWell3d` puts under it — is
rejected, and the only entry on the path is the `TapTarget3d` itself, which
implements no `HitTestTarget3d` and dispatches nothing. `Layout3dPointer`
walks `hit.path` and hands each entry the event; a path with nothing on it but
a target is a press that lands nowhere.

So the minimum currently buys a ray that *finds* something — which is what
`Drag3dSession`'s nearest-acceptor rule needs, and why the box is not simply
wrong — and not a press.

## What Flutter does, and why it is the right answer here too

Flutter has the same box under a different name.
`material/constants.dart`'s `_RenderInputPadding` is what `ButtonStyleButton`
wraps every button in, and its hit test is:

```dart
if (super.hitTest(result, position: position)) return true;
final Offset center = child!.size.center(Offset.zero);
return result.addWithRawTransform(
  transform: MatrixUtils.forceToPoint(center),
  position: center,
  hitTest: (result, position) => child!.hitTest(result, position: center),
);
```

Two things to take from it. The fallback runs **only when the ordinary test
missed**, so a press inside the control behaves exactly as before and reports
its true position. And the fallback **forces the position to the child's
centre** rather than clamping it to the nearest edge: a press in the margin is
reported as a press in the middle of the control, which is the only position
every box down the chain agrees is inside itself.

The 3D translation is direct. `Ray3d.shifted` already moves a ray into another
frame, so aiming one at the centre is one subtraction:

```dart
final centre = Offset3d(size.width / 2, size.height / 2, entry.z);
hitTestChildren(result, ray: inside.shifted(entry - centre));
```

Keeping `entry.z` rather than the box's own mid-depth is deliberate: the depth
the ray actually entered at is what `_Sequence.begin` stores per box as the
plane every later position is measured on, and the reach is an in-plane reach
— `TapTarget3d` grows width and height and leaves depth alone — so the
fallback should move the ray in-plane and nowhere else.

## The other half: a target must be outside the surface it grows

Fixing the box is not enough on its own, and this is the part that is easy to
miss. `InkWell3d` puts its `SceneTapTarget3d` *inside* the `Material3d` whose
panel is the smaller box, so the ray is rejected by the panel a level **above**
the target and never reaches it at all. No change to `TapTarget3d` can reach
past its own parent.

Flutter has this exactly right and it is worth reading as a rule rather than
as a coincidence: `ButtonStyleButton` builds
`Semantics > _InputPadding > ConstrainedBox > Material > InkWell`. **The
padding is outside the material.** So the rule this plan writes down, in
`docs/traps.md` and in `TapTarget3d`'s own dartdoc, is:

> A `TapTarget3d` reaches beyond its own extent, and its parent does not. Put
> it outside every box whose extent is the thing you are trying to grow — the
> panel included — or the ray is gated a level above it.

The catalogue applies that by wrapping its buttons in a `SceneTapTarget3d`
outside the `Material3d` and asking the `InkWell3d` inside for
`minimumSize: Size3d.zero`, so there is one target rather than two nested ones
disagreeing about where the control is.

## The work

- [x] `TapTarget3d.hitTest` re-tests its children at the centre when the
      ordinary test misses and the ray is inside the grown region. Returns
      whatever the ordinary path would have, so the box still always answers
      for itself.
- [x] Dartdoc on `TapTarget3d` saying what the fallback reports and where a
      target has to sit.
- [x] `test/pointer_test.dart` covers: a press in the margin reaches the
      content and is reported at its centre; a press inside is unchanged and
      reports its true position; a target already big enough is untouched; a
      target whose child answers nothing still answers for itself; and the
      gating rule — a target inside a smaller parent is unreachable, which is
      the failure mode a component author will actually hit.
- [x] `docs/traps.md`'s *Pointers* section rewritten: the reach delivers a
      press now, and the placement rule replaces the old "it buys nothing"
      paragraph.
- [x] `flutter_scene_material3d`'s `test/ink_well_test.dart` updated — it was
      written to fail when this landed, which is what it was for.

## What this plan found

**The fallback changes what `result.target` is in the margin, and one existing
test said so.** `pointer_test.dart` asserted that a ray 30dp from the centre of
a 24dp icon found the *target*; it now finds the icon, at the icon's centre,
with the target still on the path behind it. That is the whole point of the
change, and the test now states the position as well as the identity — a
fallback that clamped to the edge instead of forcing the centre would pass the
identity check and fail this one.

**The gating rule is the load-bearing half.** The box fix is nine lines; the
reason the gap survived phase 2 is that `InkWell3d` had its target in the
wrong place, and no amount of work inside `TapTarget3d` could have shown that.
It is in `docs/traps.md` now because a component author writing the eighth
component will otherwise nest a target inside a panel and see nothing happen.

**A press in the margin is a press at the centre, and a drag from there is
not.** The fallback only affects the hit test that captures the path. Every
later move is delivered along that captured path with its own ray, so a
pointer that goes down in the margin and then moves reports real positions
from the second event onward — the first one jumps. Flutter has the same
discontinuity for the same reason, it is invisible for a tap, and a control
that cares (a slider) should size its own target rather than lean on the
minimum.
