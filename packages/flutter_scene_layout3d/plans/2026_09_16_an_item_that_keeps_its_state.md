---
status: completed
created_at: 2026-09-16T15:09:10Z
updated_at: 2026-09-16T16:05:00Z
commit: 1aa45e09ea0ca5867d7e73aa9e69ae26e43a8fb7
---

# An item that keeps its state

The sixth plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the third of the four that map says the first real port will demand.
Right to left went first because another item waited on it, a picture second
because every screen has one; this one goes next because it is the one a
*form* waits on, and a form is what a real application is.

Its entry on the map is two gaps filed as one plan, and the reason given there
is the whole design: they are the same seam. **A view wants a say in the
lifetime of a built child.** Keep-alive is that view saying "do not release
this one yet". A reorderable list is that view saying "what I hold is not what
you built" — it wraps every item in a `Draggable3d` of its own, while the
declarative contract is that `Layout3dChildManager.removeChild` is handed back
the very layout `createChild` returned. One seam, two customers, and neither
is buildable without it.

## What is actually missing

Checked at `1aa45e0`, against a green 1175/545/4.

- **Nothing keeps a scrolled-away item alive.** `cacheExtent` decides how far
  past the window a child is built and held, and past that
  `Layout3dBuiltChildrenMixin.releaseOutside` disposes it — through the
  manager for a widget item, outright for a built one. There is no
  `KeepAlive3d`, no `SceneKeepAlive3d`, and no `keepAlive` anywhere in either
  package: `grep -rn "KeepAlive"` over `lib/` returns two dartdoc sentences
  saying it does not exist. A `SceneListView3d.builder` of expanding rows
  forgets which ones were open; a list of text fields, once there are text
  fields, forgets what was typed.
- **Six declarative widgets are missing that the imperative layer has.**
  `SceneRichText3d`, `SceneVisibility3d`, `SceneOffstage3d`,
  `SceneIntrinsicExtent3d`, `SceneReorderableList3d` and
  `SceneSliverReorderableList3d`. The first four are mechanical — a
  `SingleChildLayout3dWidget` or `Layout3dWidget` each, of the shape
  `lib/src/widgets/layouts.dart` already has seventy of. The reorderable pair
  is not, and is why the two halves share a plan.
- **`RichText3d`'s absence from the declarative layer is the cheapest
  inconsistency on the map.** It has absorbed two phases of work — a paragraph
  with a side to it, its own CPU rasterization, per-span wall colours — and a
  `build` method cannot reach a line of it.

The prior plan predicted this one precisely, and the prediction holds.
[Lazily built children in the widget layer](2026_08_25_lazily_built_children_in_the_widget_layer.md)
closed phase 5 as out of scope with a note to its successor: *"the manager is
the only thing that releases a child, so parking one instead of releasing it
is a change to `releaseOutside` and to what `positionedChildren` yields, not to
the element."* That is right about where the change goes. It is wrong about
the element, and *What the reasoning got wrong* below will say so: the element
has to learn one thing, because an item can be rebuilt while it is parked.

## The seam

Two protected hooks on `Layout3dBuiltChildrenMixin`, and they are the whole of
the reorderable half.

```dart
/// Wraps what was built before this view adopts it.
@protected
Layout3d wrapBuiltChild(int index, Layout3d built) => built;

/// What was built, given what this view holds in its place.
@protected
Layout3d builtChildOf(Layout3d adopted) => adopted;
```

`obtainChild` calls the first on whatever the builder or the manager handed
back, and holds the result. `releaseOutside` calls the second before telling
the manager, so the manager is handed the layout it created and not the
wrapper around it; the wrapper is then let go of its child and disposed on its
own, because the manager disposes what the manager built. A view with a
manager and no wrapping is the identity on both, which is every view here
except one.

`SliverReorderableList3d` already wraps — in `_buildWrapped`, by overriding
`itemBuilder` — and that override is deleted. It only ever worked on the
imperative path, because the manager path never consults `itemBuilder` at all.
Moving it to `wrapBuiltChild` makes one wrapping site serve both, which is
what lets the widget exist.

**The rule this sets, and it is the interesting one:** a built child has two
identities, what was built and what the view holds, and *every* question
about the child's contents asks `builtChildOf`. Keep-alive is the first
customer: the `KeepAlive3d` is the top of the item, which under a reorderable
list is inside the handle.

## Keeping one alive

`KeepAlive3d`, a `ProxyLayout3d` with a `keepAlive` flag, at the top of the
item. `SceneKeepAlive3d` is its widget. That is the house idiom for per-child
configuration — `Flexible3d` and `Positioned3d` are layouts wrapping a child,
not `ParentDataWidget`s — and it is why this needs no parent-data layer.

The bookkeeping is Flutter's, and deliberately so: a parked child is
**dropped from the layout tree**, not hidden in it.

- `releaseOutside` asks `builtChildOf(adopted)` whether it is a
  `KeepAlive3d` that wants keeping. If it is, and its index is still inside
  `itemCount`, the child leaves `_active` and the child list and goes into a
  `_keptAlive` bucket, unparented, with the manager not told.
- `obtainChild` looks in the bucket before it builds, and re-adopts what it
  finds at the right position in index order.
- An index past a shrunken `itemCount` is released from the bucket rather than
  parked, and `refresh()` empties the bucket, because both mean the data
  behind the index changed.

Dropping rather than hiding is the decision worth writing down, because hiding
is the cheaper patch and it is wrong. An unparented child is invisible to
*every* walk at once — layout, drawing, hit testing, semantics, the
diagnostics tree — with no per-walk exception to write and none to forget. A
parked child left in the child list would need `node.visible` to carry all six
meanings, and would still dirty its view from off-screen on every rebuild.
`RenderSliverMultiBoxAdaptor._keepAliveBucket` drops for the same reason.

What dropping costs is the disposal bookkeeping, and that is where the element
comes in:

- **At teardown**, an item's element unmounts before the view's does, so a
  parked child is disposed through `Layout3dRenderBox.dispose` like any other
  — except that its `layout3d.parent` is null now, so it does not reach
  `forgetBuiltChild`. The view therefore *clears* its bucket on dispose rather
  than disposing it, exactly as it already clears `_active`. A view with no
  manager owns its children outright and does dispose them.
- **A rebuild that swaps a parked item's layout** — a widget that changed type
  — unmounts the old element while the view still holds its layout in the
  bucket. `Layout3dLazyElement._forgetLayout` guards on `debugDisposed` today
  and so would skip it, leaving a disposed layout in the bucket for the window
  to walk back into. The guard goes; `forgetBuiltChild` learns to scan both
  maps and to tolerate a child already disposed. Evicting the index is the
  right answer rather than swapping it: the element is mounted, so the next
  pass that reaches the index reconciles against it and gets the new layout.

## What this plan does not do

- **No `AutomaticKeepAlive3d`.** Flutter's `KeepAliveNotification` lets a
  widget deep in an item ask to be kept, and the list listens. Here the
  `KeepAlive3d` is the top of the item and nothing bubbles. That is a smaller
  promise, it is the one this package can keep without a notification tier,
  and it is what the four mechanical widgets are worth more than.
- **Focus is not taken away from a parked item.** Dropping a child detaches
  its subtree from the `Layout3dOwner`, but a `Focus3d` inside it keeps its
  Flutter `FocusNode`, because the item's *element* is still mounted. Flutter
  is in the same position with a kept-alive `TextField`. Noted rather than
  solved; if it becomes a defect it is
  [a letter someone can type](2026_09_11_what_a_real_application_still_needs.md#a-letter-someone-can-type)'s,
  which is the plan that makes an off-screen focus mean anything.
- **No widget form of `prototypeItem`**, still, and for the reason the README
  already gives: a prototype is measured without being mounted.

## The work

- [x] **Phase 1 — the seam.** `wrapBuiltChild` and `builtChildOf` on
      `Layout3dBuiltChildrenMixin`; `obtainChild`, `rebuildChild`,
      `releaseOutside` and `refresh` routed through them.
      `SliverReorderableList3d` loses `_buildWrapped` and overrides the two.
      Every existing test stays green, which is the phase's own check: the
      identity case is every view but one.
- [x] **Phase 2 — `KeepAlive3d` and the bucket.** The box in
      `lib/src/boxes/visibility.dart`, beside `Visibility3d` and `Offstage3d`,
      which is where a reader looks for a box that changes what happens to a
      child rather than where it sits. The bucket, the eviction rules and the
      dispose path in `built_children.dart`; `forgetBuiltChild` scanning both
      maps; `_forgetLayout`'s guard dropped in `framework.dart`.
- [x] **Phase 3 — the four mechanical widgets.** `SceneRichText3d`,
      `SceneVisibility3d`, `SceneOffstage3d`, `SceneIntrinsicExtent3d`, plus
      `SceneKeepAlive3d`. `SceneRichText3d` resolves the ambient
      `Directionality` the way `SceneText3d` does; the rest are property
      forwarding.
- [x] **Phase 4 — the reorderable pair.** `SceneReorderableList3d` and
      `SceneSliverReorderableList3d` over the phase 1 seam, with `onReorder`
      and the rest forwarded, and the `refresh()` story documented: the widget
      layer rebuilds an item when its builder changes, but a reorder is a
      change to the caller's *data*, so a `setState` that reorders the list
      still has to reach the layout. Decide there whether the widget can do
      that itself from `updateLayout` — it knows the item count changed, not
      that the order did — and write down the answer.
- [x] **Phase 5 — tests.** Keep-alive: an item that leaves the cache and comes
      back with its `State` intact; one without the flag that does not; a
      shrinking `itemCount` that evicts rather than parks; a parked item
      disposed once and not twice at teardown; a parked index rebuilt to a
      different widget type. The seam: a `SceneReorderableList3d` whose items
      are widgets, dragged, dropped, reordered. The four widgets:
      one apiece against their imperative twin.
- [x] **Phase 6 — the pages.** `CHANGELOG.md`; the README's *Scrolling*
      section, which currently tells a reader in as many words that an item is
      **not kept alive** and that `KeepAlive` "has no counterpart here", and
      its roadmap entries 2 and 3, which name both of this plan's halves as
      what is left; the two dartdoc sentences in `layouts.dart` that say the
      same; and the map entry, struck, with what this reasoning got wrong.

## What the reasoning got wrong

Four things, and the first is the one a reader should carry away.

- **The seam was right and the disposal bookkeeping was the work.** This plan
  budgeted two hooks and got two hooks; what it did not see is that dropping a
  parked child from the tree breaks the one assumption the whole teardown path
  rests on — that a built child can be found from its own `parent`. Three
  separate paths had to learn about the bucket: `forgetBuiltChild` scans it,
  `Layout3dLazyElement._forgetLayout` stopped guarding on `debugDisposed` so a
  parked item rebuilt into another widget type is evicted, and the view's own
  `dispose` had to stop asking `childManager` whether it had one.
- **That last one is the defect this plan found, and it is a good one.** The
  plan's own text says a view with no manager disposes its parked children and
  a view with one does not, which is true and was implemented as
  `if (_childManager == null)`. It is the wrong question at teardown: the
  element clears itself as the manager on the way out, *before* the surface
  disposes the view, so every declarative list reached its own `dispose` with
  no manager and disposed children its elements had already disposed. It
  failed as "KeepAlive3d was disposed twice" in the first test that ran. The
  fix is `_hadManager`, a flag that is never cleared — and the general shape of
  it is worth remembering: **at teardown, "is there an X" and "was there ever
  an X" are different questions, and the books outlive the answer to the
  first.**
- **The declarative reorderable list could not carry a copy of its item, and
  the plan did not ask.** Phase 4 said to decide how a widget list refreshes
  and write the answer down; that turned out to be the easy half (a `setState`
  rebuilds the items standing, so there is no `refresh()` to call). The hard
  half was never listed: the feedback under the pointer is a *second* copy of
  the item, built from the same builder, and a widget cannot be built a second
  time outside a layout pass — `createChild` opens a build scope and lays a
  render box out, while a drag begins during a pointer event. So
  `feedbackBuilder` is required in the widget form and returns a `Layout3d`.
  That is a real asymmetry between the two shapes and it is documented in both
  of them rather than smoothed over.
- **"Four are mechanical" was right, and one of the four was not worth as
  little as that implies.** `SceneRichText3d` is twenty lines of property
  forwarding, and it unlocked two phases of work that a `build` method simply
  could not reach.

What the plan got right and is worth keeping: the argument for dropping a
parked child rather than hiding it. Every walk in this package — layout,
drawing, hit testing, semantics, diagnostics — reads the child list, and an
unparented child is absent from all of them with no per-walk exception to
write. The test that pins it asserts the child is unparented, off its parent's
node and absent from `children`, which is the shape of assertion to copy the
next time something is "taken out of the way".
