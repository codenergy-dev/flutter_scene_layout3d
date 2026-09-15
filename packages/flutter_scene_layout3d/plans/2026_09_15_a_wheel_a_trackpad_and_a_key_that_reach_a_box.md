---
status: completed
created_at: 2026-09-15T11:49:21Z
updated_at: 2026-09-15T14:18:23Z
commit: 12384ff196c7ba5d6d2b4c7125fb244b45263c06
---

# A wheel, a trackpad and a key that reach a box

The second plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the one that map puts immediately after the application widget because
the first ported screen meets it in the first minute on a desktop. Two
absences that are one plan: **an input Flutter has and this stack does not
route**.

## What is actually missing

**The wheel and the trackpad.** `PointerScrollEvent`, `PointerPanZoomEvent`
and `onPointerSignal` appear nowhere in either package. A `ListView3d` scrolls
by drag alone, so on macOS, Windows, Linux and web a person reaches for the
wheel or two fingers and nothing moves. `SceneInput3d` left the seam visibly
empty on purpose. The mechanism underneath is there — `Scroll3dController` has
`jumpBy`, `applyUserOffset`, `fling` and `stopAnimation` — so what is missing
is routing.

**The key.** The only keyboard contact in the stack is
`Focus3d(onKeyEvent:)`, and it is less than it looks. Every `Focus3d` node is
reparented *flat* under its enclosing scope when it asks for focus, so a
`Focus3d` wrapping a region does not see the keys of the controls inside it the
way Flutter's `Focus` does. Beyond that, nothing: no Tab moving focus (the
`Focus3dTraversal` policy exists and nothing calls it), no Space or Enter
activating a control, no Escape dismissing a dialog, no Page Down scrolling a
list, and no `Shortcuts`/`Actions`/`Intent` layer to hang any of it on.

And there is a defect waiting underneath that the missing activation hides:
**a trapped overlay entry does not take the focus when it opens.** Its
`FocusScope3d` is parented, not focused, so the button that opened a dialog
keeps primary focus behind the barrier. Today that is invisible, because a
focused button does nothing with a key. The moment Enter activates a focused
control, Enter on "Delete" opens a second confirmation dialog on top of the
first, and Escape — walking up from a button that is not inside the dialog —
cannot find the dialog to dismiss. Flutter's `ModalRoute` focuses its scope on
push for exactly this reason.

## What Flutter does, checked against the SDK this repository resolves

Flutter 3.47.1. Each of these was read in the framework source rather than
remembered, because the design below copies them.

- **A wheel goes to the innermost scrollable that would actually move.**
  `ScrollableState._receivedPointerSignal` computes the clamped target offset
  and registers with `GestureBinding.pointerSignalResolver` only when the
  target differs from the current pixels; the resolver takes the first
  registration, which is the deepest in the hit test. So a vertical wheel over
  a horizontal carousel inside a vertical list scrolls the list. The delta is
  `scrollDelta.dy` for a vertical view and `.dx` for a horizontal one, with the
  axes swapped for a **mouse** while Shift is held (`pointerAxisModifiers`),
  and not for a trackpad on web, which already has both axes.
- **`ScrollPosition.pointerScroll` jumps, clamped, and then goes ballistic at
  zero velocity.** No animation, no overscroll even under bouncing physics.
  The ballistic step is what lets a page view snap after a wheel tick.
- **A trackpad pan is a drag, not a wheel.** On macOS, Windows and ChromeOS
  two fingers arrive as `PointerPanZoomStart/Update/End`, and `Scrollable`'s
  drag recognizer accepts them and flings on release.
  `PointerScrollInertiaCancelEvent` — fingers landing on a list the OS was
  still coasting — stops every scrollable under the cursor.
- **A key walks the focus tree, not the widget tree.**
  `FocusManager.handleKeyMessage` calls `onKeyEvent` on the primary focus and
  then on each of its focus-tree ancestors until one does not ignore it. With
  no primary focus the key is dropped.
- **`Shortcuts` finds the intent, `Actions` finds the handler, and the handler
  is looked up from the primary focus.** `ShortcutManager.handleKeypress` maps
  the event to an intent, calls `Actions.maybeFind(primaryFocus.context)` —
  the nearest `Actions` mapping that intent's type, with no fallthrough if it
  is disabled — and returns `ignored` so the key bubbles on when there is no
  enabled action.
- **The defaults live in `WidgetsApp`**: Enter, Numpad Enter, Space, Select
  and Game A activate; Escape dismisses; Tab and Shift-Tab traverse; the
  arrows move focus directionally; Ctrl-arrows and Page Up/Down scroll, a line
  being 50 logical pixels and a page 80% of the viewport. Neither
  `ActivateIntent` nor `DismissIntent` has a default *action* — a control
  supplies the first and a `ModalRoute` the second, enabled only when
  `barrierDismissible`.

## The decisions

### A wheel goes where a press would have gone, then to the innermost view that would move

The group walks its surfaces front to back with the ordinary rules, and the
front-most surface that answers the ray is the one the wheel is for. Absorption
holds: a wheel over a dialog does not scroll the page behind it, for the same
reason a drop cannot land behind the dialog that covers it. On that surface's
path, deepest first, the first `Scrollable3d` whose axis has a component in the
delta and whose clamped target differs from its offset takes it — Flutter's
rule, unchanged.

**The delta is measured in logical pixels on the plane**, turned into layout
units through the surface's `Layout3dMetrics`, which is the conversion every
threshold in `Layout3dPointer` — the touch slop, the fling speeds — already
uses. A 100-pixel wheel notch
moves a list 100dp of its own content, whatever angle it is seen at and however
far away it is.

**And a wheel does not care which side of the plane the viewer is on.** A
panel seen from behind has "down" on the other side of nothing — the wheel is
about moving further into the list, not about a direction on the screen. That
is the position the map expects the right-to-left item to take for `start`,
and it is taken here first: direction belongs to the layout, not the view.

`SceneInput3d` registers with `pointerSignalResolver` rather than scrolling
directly, and only when something would move. That keeps it a good citizen of
a widget tree that has its own scroll views around the scene.

### A trackpad pan is a drag by a finger that starts at the cursor

The virtual-finger answer, and it is the one worth the paragraph. A trackpad
pan reports an offset on the screen while the cursor does not move. Treating it
as scroll deltas — what `flutter_scene`'s own `SceneView` does for widget
surfaces — would ignore the angle of the plane, and a panel tipped away from
the viewer would scroll at the wrong speed. Treating it as a drag of a finger
that went down where the cursor is and has moved by the pan offset runs it
through the ray-plane arithmetic every touch drag already uses: the content
stays under the fingers at any angle, the velocity tracker measures the
release, and the view flings. It is also Flutter's own model.

What a pan-zoom is **not** is a press. It dispatches no pointer events to
targets: a two-finger scroll across a button must not tap it, and must not
focus it. So it grabs the nearest scrolling view on the front-most answering
surface's path and moves nothing else — the same view a touch drag would grab,
including the same limitation (a horizontal view nested in a vertical one takes
the vertical pan too; that is the touch drag's behaviour today and belongs with
the arena rather than here).

**Scale and rotation are ignored, deliberately.** A pinch that zooms the camera
and a pinch that zooms the layout are different products, and this package
builds neither. An application that wants one wraps its own `Listener` around
the `SceneInput3d`; a `Listener` does not consume what it hears.

### A key walks the layout tree from the focused box

Flutter's `Shortcuts` and `Actions` cannot be reused as widgets, for two
reasons that are both structural. The action is looked up from
`primaryFocus.context`, and a `Focus3d`'s node has no context. And the node's
focus-tree ancestors are its scope and the surface's scope, not the boxes that
contain it, so a `Shortcuts` widget anywhere in the application never sees a
key meant for a box on a plane.

So the walk is re-expressed over the layout tree, and the vocabulary is kept
unchanged. **`Intent`, `Action`, `ShortcutActivator`, `ActivateIntent`,
`DismissIntent`, `ScrollIntent` and the focus intents are Flutter's own
classes**, the way `Semantics3d` takes Flutter's own `SemanticsProperties`:
a key binding written for a 2D screen reads the same here, and a
`CallbackAction` works in both.

- **`Shortcuts3d`** maps an activator to an intent for the boxes below it.
- **`Actions3d`** maps an intent type to an action for the boxes below it.
- When a key reaches the box holding primary focus, it walks its own
  ancestors nearest first. A `Focus3d` with an `onKeyEvent` is offered the key
  (which gives a region's `Focus3d` back the bubbling Flutter's has); a
  `Shortcuts3d` that maps it names an intent, whose action is looked up from
  the focused box upward — nearest `Actions3d`, no fallthrough, then the
  defaults — and invoked if enabled. After the root, `Shortcuts3d.defaults`
  has the same chance.
- Only the handler of the node that holds primary focus walks. The focus
  manager will go on to call the scopes above it, and the walk has already
  covered everything they could contribute.

A scope can be the primary focus — a dialog that has just opened, a surface
whose focused box was removed — so a `FocusScope3d` and the surface's own
scope walk too, from the box they stand for.

### The defaults are Flutter's, minus what needs a context

`Shortcuts3d.defaults` is `WidgetsApp`'s map for the non-web platforms.
`Actions3d.defaults` supplies the actions Flutter's app supplies, re-expressed
for a plane: Tab and the arrows move focus with `Focus3dTraversal` inside
`traversalRootFor` the focused box (so a dialog cycles itself), `ScrollIntent`
animates the enclosing `Scrollable3d` by Flutter's line and page increments
over Flutter's 100ms, and the do-nothing and void-callback intents do what
they do. Activation and dismissal have no default, as in Flutter.

Overriding a default is the Flutter move: a `Shortcuts3d` nearer the focused
box mapping the activator to something else, or to
`DoNothingAndStopPropagationIntent`.

### A modal entry takes the focus, and owns Escape

An `Overlay3dEntry` that traps focus now **requests focus on its scope when it
is attached**, which is `ModalRoute`'s behaviour. A control inside with
`autofocus` still wins, because its request is made against the same scope;
without one, the scope itself holds primary focus, and a Tab lands on the first
control inside.

An entry that is modal or traps focus carries an `Actions3d` binding
`DismissIntent` to its `onDismiss`, enabled exactly when `dismissible` is true
and there is an `onDismiss` — `barrierDismissible`, in Flutter's words. A route
already passes `pop` there. A snack bar or a tooltip is neither modal nor
trapping, and Escape leaves it alone, which is also Flutter's behaviour.

### Activation is the control's, and in this stack the control is `InkWell3d`

Flutter's `GestureDetector` does not activate on Enter — `InkWell` does, by
binding `ActivateIntent` in an `Actions` of its own. The same split holds here:
`GestureDetector3d` stays a gesture detector, and `InkWell3d` binds
`ActivateIntent`. Every interactive component in the catalogue — buttons,
cards, list tiles, chips, menus, the selection controls, the navigation
destinations and the snack bar's action — is built on it, so one binding
reaches them all.

An activation is a press with no noted point: the pressed state goes on and
off, the ripple starts from the middle of the surface — the landing pad the
ripple phase left, whose "nothing does yet" this plan retires — and `onTap`
runs. It is enabled only for an enabled control with an `onTap`, so Enter on a
control that would do nothing bubbles on instead of being swallowed.

`Shortcuts3d` and `Actions3d` **do not gate the hit test on their own extent**:
they have nothing to do with pointers, and a box the size of a control wrapped
around its `TapTarget3d` would otherwise cut off the 48dp reach — the placement
rule from
[a tap target that delivers a press](2026_09_02_a_tap_target_that_delivers_a_press.md).

### Getting the keyboard into the scene at all

A key goes nowhere without a primary focus, and a surface's scope joins the
application's focus only when something on it asks. So a scene is unreachable
from the keyboard until someone clicks in it. `SceneInput3d` gets a `Focus` of
its own, taking part in Flutter's traversal like any other focusable widget,
and **hands the focus straight into the scene** when it receives it: to the
first focusable box on the front-most surface that has one. `autofocus` does
that on the first frame; `Input3dHost.requestSceneFocus` does it on demand.

Leaving the scene again with Tab was left out of the first pass, and so was
traversal between surfaces. Both were then taken in the same plan — see
*The follow-up* at the end, which also changed how a Tab *arrives*.

## The API

```dart
// Wheel and trackpad, on the imperative layer.
class PointerScroll3d {            // a wheel resolved to the view it moves
  Scrollable3d get scrollable;
  double get delta;                // layout units along the view's axis
  bool apply();
}
Layout3dPointer.resolveScroll(Ray ray, Offset scrollDelta) -> PointerScroll3d?
Layout3dPointer.cancelScrollInertia(Ray ray)
Layout3dPointer.panZoomStart(Ray ray, {pointer, timeStamp}) -> bool
Layout3dPointer.panZoomUpdate(Ray ray, {pointer, timeStamp}) -> bool
Layout3dPointer.panZoomEnd({Ray? worldRay, pointer, timeStamp})
// …and the same five on Layout3dPointerGroup, walking front to back.
Scroll3dController.pointerScroll(double delta) -> bool
Scroll3dController.pointerScrollTarget(double delta) -> double

// Keys.
class Shortcuts3d extends ProxyLayout3d { Map<ShortcutActivator, Intent> shortcuts; static const defaults; }
class Actions3d extends ProxyLayout3d {
  Map<Type, Action<Intent>> actions;
  static final defaults;
  static Action<Intent>? maybeFind(Layout3d from, Intent intent);
  static (bool, Object?) maybeInvoke(Layout3d from, Intent intent);
  static KeyEventResult handleKeyEvent(Layout3d from, KeyEvent event);
}
Focus3d.onKeyEvent                 // now mutable, and bubbles through regions
Focus3d.layoutFor(FocusNode node)  // the box a node stands for, when there is one
FocusScope3d(autofocus: ...)

// Widgets.
SceneShortcuts3d, SceneActions3d, SceneFocus3d(onKeyEvent: ...)
SceneInput3d(autofocus: ...), Input3dHost.requestSceneFocus()
Input3dHitPhase.scroll
```

## The boundary

- **Not text entry.** Anything that composes characters is
  [a letter someone can type](2026_09_11_what_a_real_application_still_needs.md#a-letter-someone-can-type).
- ~~**Not a slider on the arrow keys.**~~ Left out of the first pass and taken
  in *The follow-up*.
- ~~**Not traversal out of a surface.**~~ The same.
- **Not the back button.** Escape is `DismissIntent`; the system back button
  arrives through a `WidgetsBindingObserver` and is
  [the navigation item's](2026_09_11_what_a_real_application_still_needs.md#an-application-with-more-than-one-screen).
- **Not pinch-to-zoom**, as above.

## The work

- [x] `Scroll3dController.pointerScroll`, and `pointerScrollTarget`, which a
      view asks before claiming a wheel.
- [x] `PointerScroll3d`, `resolveScroll`, `cancelScrollInertia` and the
      pan-zoom sequence on `Layout3dPointer`; the same on
      `Layout3dPointerGroup`, with pans held apart from presses.
- [x] `SceneInput3d`: `onPointerSignal` through the resolver, the pan-zoom
      events as a virtual finger, `Input3dHitPhase.scroll`, the scene `Focus`,
      `autofocus` and `requestSceneFocus`.
- [x] `Shortcuts3d`, `Actions3d`, the walk and the defaults, in
      `lib/src/input/shortcuts.dart`; key handlers on `Focus3d`,
      `FocusScope3d` and the owner's scope; `Focus3d.layoutFor`.
- [x] `Overlay3dEntry`: focus on insertion for a trapping entry, and the
      `DismissIntent` binding.
- [x] Widget forms: `SceneShortcuts3d`, `SceneActions3d`,
      `SceneFocus3d.onKeyEvent`.
- [x] `InkWell3d`: bind `ActivateIntent`. `showDialog3d` and
      `showModalBottomSheet3d` pass `barrierDismissible` to their route.
- [x] Tests: 22 in `test/wheel_test.dart` and 23 in `test/keys_test.dart`
      here, four in the Material package's `ink_well_test.dart` and
      `dialog_test.dart`. The suites are 1050 and 521.
- [x] Both package READMEs, the gallery README, `docs/traps.md` (a new
      *The wheel and the keyboard* section, and two test-harness items), both
      changelogs, `docs/README.md`, `AGENTS.md`'s table and counts, and the
      map's row, entry and seams.

## Verification

`flutter test` in both packages and the gallery, `dart analyze` clean,
`dart format .`. The oracle for this one is a desktop and a person with a
trackpad: the gallery's list has to scroll under two fingers and under a
wheel, the Material screen has to take a Tab and an Enter, and a dialog has to
close on Escape. Headless tests cover the arithmetic and the walk; they cannot
cover what the platform actually sends.

**Done**, on 2026-09-15: the gallery was run on a desktop and the wheel, the
trackpad, Tab, the arrows and Enter all behaved. The follow-up below is
headless-verified only; it has not been looked at in a window.

## What the reasoning got wrong

**The map said the wheel and the key route through the application widget.
The wheel does; the key does not pass through it at all.** A key goes to the
focus, and the focus manager walks from the primary focus up its ancestors
without ever consulting the widget that owns the rays. What the host owed the
keyboard was not routing but an *entrance*: a scene nothing has focused is
unreachable, because a key with no primary focus is dropped, and nobody had
noticed because nothing did anything with a key once it arrived. The seam the
map named still holds for everything positional; it is simply the wrong seam
for something that is not.

**"Focus3dTraversal moves focus correctly and then nothing happens"** was half
true. The policy was correct and nothing called it — there was no Tab. The map
read the class and assumed the binding.

**And the defect under the key was in the overlay, again.** The previous plan
found that the overlay held the only real defect in the machinery; this one
found the second there. A trapping entry parented its scope without focusing
it, so the button that opened a dialog kept the focus behind the barrier. With
keys doing nothing that was invisible. The moment Enter activates, it opens the
dialog a second time and Escape cannot reach the first. Building activation
first and discovering this in the gallery would have been the expensive order.

**"What is missing is routing rather than mechanism" was not quite right for
the wheel either.** `jumpBy` and `applyUserOffset` both exist and both are
wrong for a wheel: the first is programmatic, so a floating header reads it as
not the viewer scrolling, and the second runs the drag physics, so a bouncing
list overscrolls on a notch with no finger to let go and spring it back. A
wheel wanted an operation of its own, which is what Flutter has too.

**The pan-zoom sequence could not merely skip its dispatch.** The first cut
built the down, move and up events and declined to hand them to anyone;
Flutter asserts that no such event carries the trackpad kind, so the events
must not be built at all.

**Three smaller things surfaced on the way, all latent before this plan:**

- `Focus3d` attached a handed-in `FocusNode` with a handler of its own, which
  silently replaced whatever `onKeyEvent` the node already had. It now calls
  it, and puts it back when it lets the node go.
- `SceneFocus3d.createLayout` stated `canRequestFocus` only on a node the box
  made, while `updateLayout` stated it on any node. Harmless while almost
  nobody handed a node in; `InkWell3d` now always does, and every disabled
  control would have been focusable until its first rebuild.
- A keyboard activation would have rippled from a stale point: a pointer press
  that became a scroll notes a point that nothing clears until a ripple runs.
  The ink controller's own dartdoc says such a point "is simply overwritten by
  the next one", which was true only of the next *pointer* press. `InkWell3d`
  notes its own centre before activating.

**And one test taught a trap rather than a fix.** The resolver-citizenship
test first used a plain `Listener` as the page around the scene, and it never
heard the wheel — because `SceneInput3d`'s listener is translucent and nothing
under it answers a hit test, so a parent that defers to its child is not on
the path. Flutter's `Scrollable` is opaque, so a real page works; the trap is
written down in `docs/traps.md`.

## The follow-up: the two things the boundary left out

Asked for once the first pass had been tried in the gallery.

### A slider on the arrow keys

`Slider3d` binds all four arrows through a `SceneShortcuts3d` and a
`SceneActions3d` around its gesture box, which is above the ink well's focus
box and so on the key walk. Everything is Flutter's: up and right raise, down
and left lower, one division or Flutter's platform unit (a tenth on Apple
platforms, a twentieth elsewhere), and `onChangeStart` and `onChangeEnd`
bracket each press. The arrows therefore stop moving the focus off a slider,
which is Flutter's trade as well.

One deliberate divergence: **left and right follow the track, not the reading
direction.** Flutter mirrors both in a right-to-left locale. This track does
not mirror yet, and arrows that disagreed with the thumb they move would be
worse than arrows that ignore the locale — the right-to-left item owns both.

### Tab across surfaces, and out of the scene

- **The seam is `Layout3dOwner.onFocusTraversalEdge`.** The default Tab action
  asks it when a step would wrap round the *tree* — never inside a
  `FocusScope3d`, so a dialog still cycles like a `ModalRoute` — and wraps only
  when it declines. `Focus3dTraversal` stays a policy about one tree.
- **`SceneInput3d` answers it**, on every surface it registers and on every
  floating entry, re-installed whenever an overlay's `entriesChanged` fires so
  that a snack bar shown while the keyboard is in use is reachable without a
  pointer event first.
- **The order is mount order**, with each overlay's floating entries straight
  after the panel that opened them. Geometry cannot say which of two panels in
  a room is "next" any more than it can say which is in front, and `zOrder`
  answers the pointer's question, not the reader's.
- **Out is Flutter's traversal from the host's place in it.** Flutter moves
  from a scope's focused child, so the host takes the focus quietly first and
  then calls `nextFocus`. When that comes back to the host — a window that is
  nothing but the scene — it goes straight back in at the other end.
- **In changed.** Arriving by Tab now lands on the first box of the first
  surface, and by Shift-Tab on the last box of the last — the host reads Shift
  off the keyboard, because Flutter's traversal does not say which direction
  landed on it. `requestSceneFocus` keeps its "back to where it was" meaning,
  which is right for a programmatic return and wrong for a Tab: restoring the
  last box on a forward Tab would hand the focus to the box that was just
  tabbed away from, and the next Tab would leave again.
- **Tabbing onto a panel with a trapping dialog open lands inside the
  dialog**: the owner's scope remembers the dialog's scope as its focused
  child, and asking that scope restores its own.
- **A surface's scope sets `descendantsAreTraversable` false.** Its nodes have
  no context, and `FocusNode.rect` dereferences one; traversal running in the
  root scope — where it runs without a navigator, and where leaving the scene
  now sends it — could otherwise reach a node handed to a `Focus3d`.

### The work

- [x] `Slider3d` arrows, `keyboardStep`; four tests in `slider_test.dart`.
- [x] `Layout3dOwner.onFocusTraversalEdge`, `Focus3dTraversal.lastFocus`, the
      edge check in the default Tab action, `descendantsAreTraversable` on the
      surface's scope.
- [x] `SceneInput3d`: the traversal order, the edge handler on surfaces and
      entries, leaving and entering the scene; four tests in `keys_test.dart`.
      The suites are 1054 and 525.
- [x] Both READMEs, `docs/traps.md`, both changelogs, `AGENTS.md`'s counts,
      and the map.

### What this reasoning got wrong

**The first plan said traversal between surfaces "is still nobody's", and
filed it with the overlays.** It turned out to belong to the host, for the
same reason every other cross-surface question does: the host is the only
thing that knows which surfaces exist and which overlay hangs off which panel.
The overlay only knows its own entries.

**Arrival was wrong in the first pass, and nobody could have seen it.** With no
way out, "back to where the focus was" and "the first box" only differ on a
second visit, and there was no way to leave to make one. The moment Tab could
leave, restoring on a forward Tab became a loop between the last box and the
page.

**Three test mistakes, worth recording because each reads as a code bug.** A
traversal test put the scope's own boxes in the tree's order and so never
reached the tree's edge; seeding the focus with `requestSceneFocus` picked the
most recently registered of two surfaces at equal z-order, because that call
means "front-most" and not "first"; and the changelog first called the
`FocusNode.rect` dereference a crash waiting for any application with a page
and a scene, when with a navigator the traversal never runs in the root scope
at all. It was checked against the SDK before it was written down, and the
wording narrowed to what is true.
