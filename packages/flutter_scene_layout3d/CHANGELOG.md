## Unreleased

- **A route carries its own clock.** `Route3d.transition` is a transition on
  the route rather than on the navigator, consulted before
  `Navigator3d.transition` and null by default, so every route built today is
  unaffected. `PageRoute3d` and `WidgetPageRoute3d` take it as an argument.
  - **The navigator's single field was not merely inconvenient, it was
    wrong.** A navigator reads it twice per route — once in `push` and once
    in `removeRoute`, arbitrarily later — so a caller writing it before each
    push closes an already-open route on whatever the *last* push set.
    A dialog opened over a sheet used to give the sheet the dialog's timing on
    the way out. The failure only appears when two overlays overlap, which is the
    case nobody tries by hand.
  - It is also how a route opts **out**: a menu whose button leaves the tree
    sets `Route3dTransition.none` and goes at once, rather than shrinking away
    from an anchor that no longer exists on a tree that is already leaving.

- **A box fades.** `Opacity3d` draws everything below it at a fraction of its
  strength, and it reaches all three of the things this package draws with: a
  panel, a label's glyphs, and the wall around those glyphs. The item had been
  parked twice on an upstream gate — `flutter_scene` has no opacity on `Node`
  — and that gate was never the one: this package draws with materials it owns
  and both of them already multiplied alpha. What stood in the way was
  `depth_write`, and a fading subtree is the *partly* transparent slab the
  transparent-slab work left open, everywhere at once.
  - **It is coverage, not alpha, and that is the whole design.** A faded box
    keeps roughly `opacity` of its fragments, chosen by an ordered 4x4 matrix
    over the fragment's screen position, and throws the rest away; the
    survivors draw at full strength and write depth exactly as an unfaded
    box's do. So fading stops depending on the translucent pass's
    back-to-front sort, which is one number per draw and which a panel and the
    label on it routinely tie in. The price is group opacity: a label on a
    faded card is about half again as strong as Flutter would draw it at 30%,
    and exactly right at either end. Five approaches were built and
    photographed before this one was chosen, and the two that get group
    opacity right both fail at opacity **1.0**.
  - **`Layout3d.inheritedOpacity`** is the value in force on a box, computed
    by walking up exactly as `clipRegion` is, with `refreshOpacity` and
    `refreshOpacitySubtree` as the republish hooks and `opacityForChild` as
    the override a box imposing one uses. `Layout3dOpacityMixin` is that
    behaviour; `Opacity3d` and `MotionTransition3d` are what mix it in.
    Changing an opacity lays **nothing** out and rebuilds no geometry: it
    walks the subtree writing one uniform per box that draws.
  - **`FadeTransition3d`, `SceneOpacity3d`, `SceneFadeTransition3d` and
    `SceneAnimatedOpacity3d`** are the rest of the lane — Flutter's
    `FadeTransition` and `AnimatedOpacity`, on the tier where a run rebuilds
    no widget and marks no box dirty.
  - **`Motion3d.opacity`** finishes an arrival, and `Motion3d.fade()` is the
    plainest one there is. The field was left out when `Motion3d` shipped, for
    a reason this work found to be aimed at the wrong thing.
  - **`assets/text_glyph_wall3d.fmat`** is a third shader, and the find behind
    this work. A glyph is three primitives, not one: the faces, their back
    faces, and the **wall** around each letter's silhouette — and the wall was
    drawn with an opaque `UnlitMaterial` whose colour is baked into its vertex
    colours, so nothing a uniform could say would fade it. Fading a label
    naively therefore did not leave it behind, it *dissolved the letter and
    kept its outline*. `GlyphWallMaterial3d` is the seam,
    `installGlyphMaterial3d` installs both shaders now, and
    `AtlasText3dRenderer.buildWallMaterial()` is gone in its favour.
  - **`Decoration3dPaintRequest.opacity`, `BoxDecoration3dUniforms.opacity`
    and `GlyphMaterial3d.fade`** carry it to the materials. The panel shader
    and the glyph shader each declare a new `fade` parameter, which a caller
    with a `.fmat` of its own has to declare too — `applyTo` writes exactly
    the parameters this package's shader declares, and that set has grown by
    one.
  - **`NodeBox3d.onFade`** is how geometry an application brought says it can
    fade, and a `NodeBox3d` inside a faded subtree without one **asserts** in
    debug rather than drawing at full strength next to everything that faded.

- **A route arrives instead of appearing.** `Route3dTransition.none` was the
  only implementation that shipped, so a dialog, a menu and a sheet each
  existed between one frame and the next. The clock now exists, and it is on
  the node tier: an arrival costs one matrix a frame and lays nothing out.
  - **`Route3d.animation`** is an `Animation<double>` that reads 0 while the
    route is away and 1 once it is here. The route owns it because the route
    has the right lifetime — a transition is held on the navigator and shared
    by every route on it — and it **rests at 1**, which is arrival, so a route
    pushed with `Route3dTransition.none` is at rest from its first layout
    rather than parked wherever its motion says "away".
  - **`TimedRoute3dTransition`** winds it: a `duration`, a `reverseDuration`, a
    `curve` and a `reverseCurve`, and nothing else. A pop that interrupts an
    arrival reverses from wherever the route had got to, over that fraction of
    the duration, so a dialog dismissed a frame after it opened closes at once
    instead of crawling back. A zero duration keeps `Navigator3d.removeRoute`'s
    synchronous path, and `Navigator3d.vsync` is the ticker provider, null
    meaning a bare `Ticker`, as everywhere else in this package.
  - **`Motion3d`** says where content stands before it has arrived: an offset
    in logical pixels, an offset as a fraction of the content's own size, a
    scale, and a turn about an axis with a pivot both of the last two use.
    `Motion3d.fromBelow` is a sheet, `Motion3d.grow()` a dialog,
    `Motion3d.fromBehind` an arrival through the plane, and `Motion3d.turn()`
    the one with no two-dimensional analogue. It shipped with **no opacity**,
    on the reasoning that `flutter_scene` has none on `Node` and a dialog
    whose panel fades while its label does not is worse than one that does not
    fade. The second half was right and the first was beside the point; the
    entry above is where the fade landed.
  - **`MotionTransition3d`** and **`SceneMotionTransition3d`** apply it —
    Flutter's `SlideTransition`, `ScaleTransition` and `RotationTransition` in
    one box, writing `nodeOffset` and `nodeTransform` and never marking
    anything dirty. It re-applies from its own `performLayout` as well as on
    every tick, because half of what a motion says is a fraction of a size the
    box does not have until it has been laid out — and a widget-built entry's
    subtree does not exist until the build after the insertion.
  - **`PageRoute3d.motion` and `WidgetPageRoute3d.motion`** wrap a route's own
    content in one. Content that carries a scrim of its own puts the box
    *inside* the scrim instead, which is why the box is placed by whoever
    builds the content rather than by the entry: a dim that slides in with the
    dialog it dims is wrong.

- **A screen knows how big it is, and the reader's own font setting reaches
  it.** Two absences that were one: nothing in either package had ever read
  `MediaQuery`, so a 3D screen could not be asked its size and could not be
  enlarged by a person who needs larger type.
  - **`Layout3dMetrics.textScaler` replaces `textScaleFactor`**, a `TextScaler`
    where there was a `double`, because accessibility scaling is not linear
    across sizes: a platform that grows 14dp body copy by 1.8 does not grow a
    57dp display line by 1.8. `sp` asks the scaler; `textScaleFor(fontSize)` is
    the same scaler stated as the multiplier a box applies to type it has
    already measured. The scale lives here rather than on the screen data
    because the *layout* measures with it, and a `performLayout` has no
    `BuildContext` to look one up through.
  - **`SceneLayout3d` reads the ambient setting** — `MediaQuery.textScalerOf` —
    and writes it onto the surface's contract, so a label three boxes deep
    grows without anything being threaded by hand. A `metrics` that states a
    scaler of its own now asserts and says where to put it instead: the
    alternative was silent, and a panel that states a scale to say it is a
    smaller screen would have quietly opted its labels out of scaling.
  - **A `Text3d` still measures at its style's own size** and multiplies, so
    the prepared handle survives a change of scale and the font is never
    consulted again. A `RichText3d` cannot — it holds spans of several sizes —
    so its painter and its captured subtree take the scaler, and each span is
    measured at its own scaled size. Its `logicalPixelScale` is now the unit
    rate alone.
  - **`Layout3dCameraBinding.update` takes a `Layout3dView`** in place of a
    bare `viewSize`: the platform view as much of it as a binding derives from,
    which is its size and the reader's font setting. `needsViewSize` is
    `needsView`; the bindings' `textScaleFactor` is a nullable `textScaler`
    where null means *the view's*.
- **`MediaQuery3d`, `MediaQuery3dData` and `SceneSafeArea3d`**: what a `build`
  method branches on, in logical pixels. `size` is the surface's own extent —
  the view's, for a panel that stands in for it — and `orientation` comes off
  it; an axis the surface was given no bound on reports infinity, because a
  plane that shrink-wraps has no screen size yet.
  - **A safe area belongs to the view, and only a surface that stands in for
    the view inherits one.** `Layout3dCameraBinding.screenFilling` is what that
    means — `standsInForTheView` says so — and every other surface reports a
    zero padding, because a plane hanging in a room does not have a notch.
    `SceneSafeArea3d` pads by it and republishes the data with what it consumed
    removed, so a nested one pads nothing.
  - It carries **no `devicePixelRatio` and no text scaler**, deliberately: the
    first is a promise only a camera-bound surface could keep, and the second
    belongs to the unit contract. There are no size classes either — that
    question is the catalogue's, and this leaves it the extent to answer it
    with.

- **An item can keep its state after the window has left it.** A lazily built
  item used to be disposed once the window and its cache had moved past it, and
  everything it held went with it — the `State` of a stateful row, a scroll
  position, a half-filled form. A form in a list is what a real application is,
  so it now has an answer.
  - **`KeepAlive3d` and `SceneKeepAlive3d`** wrap the item that has something to
    lose. The view parks it instead of releasing it, and hands it back whole
    when the window comes round. It has to be the item itself, at the top of
    what the builder returns: there is no counterpart to Flutter's
    `AutomaticKeepAlive` listening for a notification from deeper in.
  - **A parked child is off the layout tree, not hidden in it.** Unparented and
    off its parent's node, so nothing lays it out, draws it, points at it or
    walks it for semantics — the same trade `RenderSliverMultiBoxAdaptor`'s
    keep-alive bucket makes, and the reason a kept item costs memory and
    nothing else. `Layout3dBuiltChildrenMixin.keptAliveIndices` says which they
    are. An index the data no longer has is released rather than parked, and
    `refresh()` empties the bucket.
- **A view can hold something other than what was built.**
  `Layout3dBuiltChildrenMixin.wrapBuiltChild` and `builtChildOf` are the seam:
  a view wraps a built child before adopting it, and the manager is still
  handed back the very layout its `createChild` returned. `SliverReorderableList3d`
  is the customer — it puts every item inside a `Draggable3d` — and moving its
  wrapping here is what made the widget forms below possible, because a widget
  item is built by a child manager that never consults `itemBuilder` at all.
- **`SceneReorderableList3d` and `SceneSliverReorderableList3d`**, the widget
  forms of the two reorderable views, over
  `ReorderableList3d.managed` and `SliverReorderableList3d.managed`. Their
  `feedbackBuilder` is required where the imperative list's is optional: what
  flies under the pointer is a second copy of the item, and a widget item
  cannot be copied outside a layout pass, so what is carried is stated as
  geometry. `ReorderableList3d.vsync` is now readable and writable in place,
  which is what lets a rebuild move the list onto a new ticker provider.
- **`SceneRichText3d`, `SceneVisibility3d`, `SceneOffstage3d` and
  `SceneIntrinsicExtent3d`**, the four declarative forms the imperative layer
  had and a `build` method could not reach. `SceneRichText3d` is the notable
  one: `RichText3d` had absorbed a paragraph with a side to it, its own CPU
  rasterization and per-span wall colours, and none of it was reachable from a
  widget. It resolves the ambient `Directionality` the way `SceneText3d` does,
  and merges no style, because the spans carry their own.

- **A panel can hold a picture, and a gradient.** `BoxDecoration3d` carried one
  colour and nothing else; every real screen has an avatar, a photograph, a
  logo or a brand gradient on it, and the only way to draw one was to leave the
  layout for a hand-built `NodeBox3d` with a textured material — losing the
  corner radius, the border, the state layer, the ripple and the clip on the
  way out.
  - **`BoxDecoration3d.image`** takes a `DecorationImage3d`: an `ImageProvider`,
    a `BoxFit`, an `AlignmentGeometry`, a scale, an opacity, `matchTextDirection`
    and an `onError`, with `paintImage`'s own arithmetic behind them — including
    Flutter's default that a null fit is `BoxFit.scaleDown`. What Flutter has
    and this does not is what the shader cannot do: repeat, centre slicing,
    colour filters, inverted colours, filter quality. Nothing is ignored
    silently.
  - **`BoxDecoration3d.gradient`** takes Flutter's own `LinearGradient`,
    `RadialGradient` or `SweepGradient`, evaluated as uniforms rather than baked
    into a texture, so it is exact at any aspect ratio and animating between two
    gradients is a parameter write. Eight stops, past which the ramp is
    resampled; a `GradientTransform` and a focal radial gradient are refused.
    Both are reported once in a debug build.
  - **The picture is drawn by the panel shader**, which is the decision the rest
    follows from: there is no rounded clip here, so only the signed distance
    field that carves a card's corners can carve a photograph's. A picture is
    therefore inside the border, the surface tint, the state layer, the press
    ripple and the clip planes for free.
  - **`Image3d` and `SceneImage3d`** are a box that wears one and sizes itself
    to the picture, the way `RenderImage` does, with `.asset`, `.network` and
    `.memory` constructors and a `borderRadius` of its own — which is what a
    `ClipRRect` around a Flutter `Image` would have been, and what makes a
    circular avatar.
  - **`ImageTexture3d` is the picture arriving**: one per provider, shared
    through `ImageTexture3dCache.shared`, reference counted, reporting its size
    as soon as the provider has one and its texture once the pixels are
    uploaded — with the upload behind `ImageTexture3dUpload` so the whole path
    runs in `flutter test`. An animated image draws its first frame and stands
    still.
  - **`Decoration3dPaintRequest.onChanged`** is the seam a late resource asks to
    be drawn through, and `Decoration3dPaintRequest.configuration` is what a
    provider is resolved against — filled by the widget layer from
    `createLocalImageConfiguration`, so an asset picks its `2.0x` variant and a
    directional alignment reads the ambient `Directionality`.
  - **`Constraints3d.constrainSizeAndAttemptToPreserveAspectRatio`**, Flutter's,
    with depth constrained on its own.

- **A box with no thickness is no longer drawn black.** A slab scaled to exactly
  zero on an axis has a singular transform and therefore no normal, and the
  panel shader is lit — so a zero-depth `DecoratedBox3d` came out black rather
  than in its own colour. `BoxDecoration3dPainter.slabTransformFor` holds every
  axis to `minimumSlabExtent`, a hundredth of a logical pixel. A picture is the
  ordinary way to meet this, since a box that sizes itself to one takes the
  depth its constraints allow.

- **A row reads right to left.** Reading direction used to reach the text and
  stop there: a `Row3d` arranged left to right around Arabic, no padding could
  say *start*, and there was no reversed `Column3d`. It is Flutter's contract
  now, flip for flip.
  - **`Flex3d`, `Row3d`, `Column3d` and `Depth3d` take `textDirection` and
    `verticalDirection`**, and so does `Wrap3d`; `Table3d` takes
    `textDirection` and puts its first column at the right. Each flips
    whichever of its axes is horizontal or vertical, with Flutter's own walk —
    an overflowing right-to-left row keeps its last child at the left edge,
    not a mirror image of the left-to-right overflow. Depth never flips.
  - **`EdgeInsetsDirectional3d` and `AlignmentDirectional3d`**, over new
    `EdgeInsetsGeometry3d` and `AlignmentGeometry3d` bases that `EdgeInsets3d`
    and `Alignment3d` now extend. A physical and a directional value add and
    interpolate into a kind that holds both until it is resolved;
    `EdgeInsetsGeometry3dTween` and `AlignmentGeometry3dTween` animate across
    kinds, and `Layout3dMetrics.dpInsets` converts any kind to the same kind.
  - **Every box that takes a padding or an alignment takes the geometry and a
    `textDirection` to resolve it in**: `Padding3d`, `Align3d`, `Container3d`,
    `Stack3d`, `IndexedStack3d`, `FittedBox3d`, `Transform3d`, `NodeBox3d`,
    `UnconstrainedBox3d`, `OverflowBox3d`, `FractionallySizedBox3d` and
    `SliverPadding3d`. A physical value does not relayout when only the
    direction changes. **This is a breaking change for code that reads
    `.left` off one of those getters**, which is now a geometry;
    `padding.resolve(box.textDirection)` is the physical value the box used.
  - **`Positioned3d.directional`** resolves `start` and `end` against a
    direction it is handed, and **`ScenePositionedDirectional3d`** against the
    ambient one.
  - **The widget forms read the ambient `Directionality`** when no direction
    is stated, as Flutter's do, so an application under a right-to-left
    `MaterialApp` mirrors without a line of code.
  - **A null direction reads left to right** on the imperative layer, where
    Flutter's render objects assert — the fallback `Text3d` already had.
  - **Direction belongs to the layout, not the viewer**: a panel seen from
    behind keeps its start on the side it was laid out on.

- **`Layout3dTestGeometry.drawnOffsetInSurface` says where a box is drawn.** One
  answer to "where is this box", in `testing.dart`: its corner in the
  surface's layout frame, every offset and node nudge above and on it counted.
  The Material package's tests carried two helpers named `offsetInSurface`,
  one that counted a `Stack3d`'s depth step and one that did not, and neither
  counted a node offset; both are gone in favour of this. Moving to it is what
  showed that a menu was being pressed where nothing was drawn.

- **`Layout3dPointerGroup.hitTest` answers with the front-most surface, as its
  documentation always said.** Past a surface added with `absorbs: false` it
  used to hand back the path of the *last* surface that answered — a HUD in
  front of a panel reported the panel — while `down`, `hover`, the wheel and
  the trackpad all kept the first. It keeps the first now, and so does
  `lastHit` after it. The walk itself is unchanged: every surface a press would
  reach still tests the ray. Nothing in either package called it, which is how
  the two answers lived side by side.

- **A test library for the screens an application builds.**
  `package:flutter_scene_layout3d/testing.dart` is `flutter_test`'s vocabulary
  pointed at the layout tree. Until now the package exported nothing a test
  could use, and every suite here reached its boxes through helpers private
  to its own `test/` directory — written four times over, with two copies of
  "where is this box" that disagreed.
  - **`find3d`** finds boxes on every surface in the widget tree, a dialog on
    a surface of its own included: by semantic label, by text, by type and
    subtype, by node name, by predicate, the box holding the focus, and
    descendant and ancestor. The finders are built on `flutter_test`'s own
    `FinderBase`, so `findsOne` and `findsNothing` work unchanged.
  - **`tester.pumpSurface3d`** and **`tester.pumpScene3d`** mount a screen
    under a `SceneInput3d` whose camera looks straight at it, or through the
    camera the test gives. **`cameraFacing3d`** is that framing on its own.
  - **`tester.tap3d`**, **`drag3d`** and **`scroll3d`** press a box through
    the screen: its centre is projected through the host's camera and tapped
    with Flutter's own `tapAt`, so the ray, the order of the surfaces,
    absorption and the arena all run. **A press that would not reach the box
    fails the test**, naming what it would reach instead — stricter than
    Flutter's `tap`, which only warns, because a control nobody could press is
    the defect this stack has actually shipped. `getCenter3d`, `hitTest3d`,
    `layout3d` and `layouts3d` are the counterparts of the widget tester's.
  - **`isReachable3d`**, **`hasSizeDp`**, **`hasSize3d`** and
    **`standsOnItsPanel3d`** match every box a finder found. The last is the
    check for content inset behind the front face of the card it is on, which
    is how a slider once shipped invisible.
  - **`flutter_test` is now a regular dependency** rather than a dev one,
    because a library under `lib/` imports it. Every Flutter application
    already resolves it, and nothing that does not import `testing.dart`
    compiles any of it.

- **`Input3dHost.hitTestAt` says what a press would reach, without pressing.**
  Every path a press at a point of the view would be dispatched to, front to
  back, with the overlays' entries synced first — the question a tooltip, an
  editor's pick or a test asks. **`Layout3dPointerGroup.hitTestAll`** is the
  same walk given a ray; `hitTest` answers with only the first of those paths,
  and a box on the panel behind a HUD is reached by a press as surely as the
  HUD is.

- **Tab walks from one surface to the next, and out of the scene.** Traversal
  used to cycle inside whichever surface held the focus, so a keyboard that got
  into a scene could neither reach a second panel nor leave. Tab off the end of
  a surface now goes on to the next one, in the order the surfaces mounted,
  with each overlay's floating entries straight after the panel that opened
  them; Tab off the last surface hands the focus back to Flutter's traversal,
  so it lands on the widget after the scene, or comes round to the first box
  when there is none. A dialog that traps the focus still cycles inside
  itself. Arriving by Tab lands on the first box of the scene, and by
  Shift-Tab on the last.
  - **`Layout3dOwner.onFocusTraversalEdge`** is the seam: the default Tab
    action asks it before wrapping a tree, and `SceneInput3d` answers it.
    **`Focus3dTraversal.lastFocus`** is the counterpart of `firstFocus`.
  - **A surface's focus scope hides its nodes from Flutter's own traversal**
    with `descendantsAreTraversable`. A surface's scope hangs under the root
    scope, so traversal running *in* the root scope — which is where it runs
    in an application with no navigator, and where Tab leaving the scene now
    sends it — could reach a `FocusNode` handed to a `Focus3d` and ask it for
    `FocusNode.rect`, which dereferences a context the node does not have.

- **A wheel, two fingers on a trackpad and a key reach a box.** The inputs a
  desktop reaches for first, none of which this package routed: a list
  scrolled by drag alone, and a focused control did nothing with a key.
  - **A wheel goes where a press would have gone**, then to the innermost view
    that would actually move — Flutter's rule, so a vertical wheel over a
    sideways carousel scrolls the list around it, and a wheel at the end of an
    inner list goes on to the outer one. A dialog in front takes the wheel
    even when it has nothing to scroll. `SceneInput3d` claims it through
    Flutter's `pointerSignalResolver`, and only when something would move, so
    a scroll view in the widget tree around the scene still gets the rest.
    Shift turns a mouse wheel sideways. The rule is **`PointerScroll3d`**, and
    **`Layout3dPointer.resolveScroll`** and the group's counterpart apply it.
  - **`Scroll3dController.pointerScroll`** is `ScrollPosition.pointerScroll`:
    a jump clamped to the range whatever the physics — a wheel has no finger to
    let go of, so nothing would spring an overscrolled list back — followed by
    a settle at rest, which is what snaps a page view after a notch.
  - **A trackpad pan is a drag by a finger that went down where the cursor
    is**, through `panZoomStart`, `panZoomUpdate` and `panZoomEnd`. It runs
    through the ray-plane arithmetic a touch drag uses, so the content stays
    under the fingers on a tilted panel and flings on release, and it presses
    nothing: no control under two fingers is tapped or focused. Its scale and
    rotation are ignored. **`cancelScrollInertia`** stops a coasting list when
    the fingers land on it again.
  - **`Shortcuts3d` and `Actions3d`** are Flutter's `Shortcuts` and `Actions`,
    walked over the layout tree, because a focus node on a plane has no
    context and no widget ancestors for Flutter's to find. The activators, the
    intents and the actions are Flutter's own classes. A key goes up from the
    focused box nearest first; a `Focus3d` around a region now hears the keys
    of the controls inside it; a disabled nearer binding does not fall through.
    **`Actions3d.maybeInvoke`** fires an intent with no key behind it.
  - **The defaults are `WidgetsApp`'s**: Tab and Shift-Tab walk
    `Focus3dTraversal` inside the focused box's scope, the arrows move focus on
    the plane, Page Up and Page Down scroll the enclosing list. Enter and Space
    map to `ActivateIntent` and Escape to `DismissIntent`, with no default
    action for either — a control and a modal supply them.
  - **A trapping `Overlay3dEntry` takes the focus when it opens**, and an entry
    that is modal or traps focus **closes on Escape** through its `onDismiss`,
    while `dismissible`. Before this the button that opened a dialog kept the
    focus behind the barrier — invisible while keys did nothing, and a dialog
    opened twice by one Enter the moment they did. **`FocusScope3d.autofocus`**
    is what the entry uses.
  - **`SceneInput3d.autofocus` and `Input3dHost.requestSceneFocus`** are the
    way a keyboard gets into a scene nothing has focused: the host is one
    focusable widget in Flutter's traversal and hands the focus into the
    scene. `Input3dHitPhase.scroll` reports a wheel and a pan.
  - **`Focus3d.onKeyEvent` is mutable**, and exposed on `SceneFocus3d`; a node
    handed in keeps the handler it came with, and gets it back.
    **`Focus3d.layoutFor`** finds the box a focus node stands for.
    **`SceneShortcuts3d`** and **`SceneActions3d`** are the widget forms.
- **`SceneFocus3d` states `canRequestFocus` on a node handed in when it is
  created**, not only when it is updated, so a control built disabled around a
  node of its own is not focusable until its first rebuild.

- **An application no longer wires its own rays.** `SceneInput3d` wraps the
  `SceneView` and owns the input: the listener, the camera arithmetic that
  turns a pointer position into a world ray, the `Layout3dPointerGroup`, and
  which surfaces are in it. It saves an application about ninety lines — the
  gallery lost 107 of them — and closes three failure modes that said nothing
  when they happened: a z-order in the wrong relative order routing a press to
  the panel behind, a surface registered before it existed and skipped
  forever, and a dialog never synced into the group and so unpressable.
  - **A surface announces itself on mount.** `SceneLayout3d` registers with
    the host above it in `didChangeDependencies` and takes itself out when it
    goes, so there is nothing to re-assert from a per-frame tick and no window
    in which a mounted panel cannot be pressed.
  - **`SceneLayout3d.zOrder` and `absorbsPointer`** state what is in front of
    what where the rest of a surface is configured. Stated rather than
    derived, because geometry cannot answer it for a panel turned away from
    the camera: it is in front for some pixels and behind for others, while a
    pointer needs one answer for the whole surface.
  - **A `SceneOverlay3d`'s detached entries are synced immediately before each
    dispatch** rather than once a frame. A per-frame sync is both too often —
    entries change when a dialog opens, not when a frame is drawn — and not
    often enough, since an entry inserted from a pointer callback was
    unpressable until the next one. An entry lands one whole z-order step in
    front of the surface whose overlay opened it, so nothing restates that.
  - **The camera is ambient.** `SceneLayout3d` and `SceneOverlay3d` fall back
    to the host's camera, so an application states it once at the top instead
    of on every panel; an explicit one still wins.
  - **`Input3dHost`, `Input3dController`, `Input3dHit`** are the seam: the
    group and the camera in force, reachable with `SceneInput3d.of(context)`
    from inside the scene or through a controller from the widget that built
    it. `onHit` reports what a press or a hover found, and whether the press
    took hold of a scrolling view.
  - **A pointer that leaves the view is taken off every surface**, so a box
    lit by a hover no longer keeps its state layer when the cursor leaves the
    window — nothing else would ever have told it otherwise.
- **`Layout3dPointerGroup` keeps its detached-entry bookkeeping per overlay.**
  It was one flat set shared across every overlay it was called for, so with
  two overlays each `syncDetachedEntries` took out the other's entries — a
  defect only one overlay had ever been tried against.
  **`forgetDetachedEntries`** is the counterpart an overlay going away needs.

- **A paragraph has a side to it.** `RichText3d` was the one label left flat by
  the glyph work, and its capture is a `gpu.Texture` with no readable copy, so
  the atlas trick does not transfer. The silhouette comes from a **second, CPU
  rasterization of the box's own `TextPainter`** instead — `rasterizeParagraph`
  and `ParagraphRaster3d` — and because that mask is on this side of the GPU,
  each wall segment's colour is *sampled off it* through `sampleParagraphInk`,
  which is how one wall carries a span's several colours.
  `buildParagraphWallSegments` assembles them and `kParagraphWallSampleDepth`
  is where along the wall the sample is taken.
  - **`RichText3d.maxWallSegments`** refuses the work out loud rather than
    quietly. The benefit runs opposite to the cost: thickness is invisible on
    body copy, which is exactly the text that traces into thousands of
    segments.
  - The cheap answer was photographed failing. Extruding the *box* rather than
    the letters — which `RichText3d.depth` already reserved room for — produces
    a doubled paragraph with a back face and a stray rule without one, because
    extrusion reads as thickness only when the thing extruded is the ink.
- **A letter has a side to it.** A glyph is a front face, a back face and a
  wall around its silhouette, rather than one flat quad — so a screen of type
  on a four-millimetre panel no longer reads as a decal stuck to it, and
  `Icon3d` came out thick for free because an icon is one glyph of a font.
  `dart:ui` exposes no glyph outlines and there is no font parser here, so the
  outline is **traced out of the atlas raster** (`traceGlyphOutline`,
  `GlyphOutline3d`, with `kGlyphOutlineThreshold` and
  `kGlyphOutlineTolerance`), which the atlas already reads back to the CPU on
  its way to the GPU. That makes it arithmetic over a bitmap, and testable
  headless like the rest of the text layer.
  - **`GlyphAtlas3d.outlineRevision`**, and the trap it adds: **a glyph's wall
    arrives with the texture rather than with the layout.** A label is flat on
    the frame it is first laid out on and grows its thickness when the atlas
    listener fires. It is a third counter answering a third question, beside
    the two the atlas already had.
  - `GlyphWallSegment3d` and `buildGlyphWallSegments` are the geometry;
    `AtlasText3dRenderer` consumes them.
- **A label stays on the panel it is written on while the panel turns.** Four
  defects, reported as one symptom — type on an upright screen appearing and
  disappearing as it rotated — and none of them was the atlas.
  - **The decoration's slab was built inside out.** Its depth-facing triangles
    wound clockwise around their own normals, so back-face culling kept the
    face pointing *away* from the camera: every panel wrote the depth of its
    rear face, lit by a normal facing away, drawn at the projected size of the
    wrong face. Fixed in `BoxDecoration3dPainter`.
  - **A line's depth cross axis now starts at the front.** It centred by
    default, and since a `Material3d` hands its child a tight depth, that
    buried every label inside the slab it was written on. `Flex3d` and
    `Table3d` default their depth cross axis to the front; an explicit
    `Center3d` still centres in depth, which is the documented way to ask for
    the old behaviour. **The depth axis is not symmetric with the other two,
    because the viewer is on one side of it.** This and the winding fix had to
    land together: correcting the winding turns a buried label from a coin toss
    into a certainty.
  - **A glyph mesh now writes depth.** It did not, and the translucent sort is
    one number per draw — the distance to the centre of an object's bounds — so
    a turned panel could be drawn *after* the label written on it and paint
    over it. The package ships **`assets/text_glyph3d.fmat`** for that, with
    `FmatGlyphMaterial3d`, `UnlitGlyphMaterial3d`, `installGlyphMaterial3d`,
    `kGlyphMaterialSource` and `linearColor` as the seam; `hook/build.dart`
    compiles it beside the panel shader, and `initializeMaterial3d()` installs
    it.
  - **The glyph atlas is keyed by a style stripped of what cannot change a
    raster.** It still carried `decorationColor`, so the gallery held
    twenty-seven atlases for nine styles.
- **A glyph reserved while the atlas was being rasterized is now drawn into the
  texture.** It never was: only a *repack* moved the generation the flush
  compared against, and a reservation with room to spare does not repack. An
  atlas that grows hides the defect, which is why one Material screen looked
  perfect and two did not.
- **A transparent slab no longer erases what it stands on.** The panel shader
  wrote depth for a fragment with no alpha, so a colourless `Material3d`
  punched a hole through whatever was behind it; `box_decoration3d.fmat`
  discards where its own alpha is zero. The obvious fix — turning `depth_write`
  off — was photographed doing something worse, and that judgement is recorded
  in `docs/traps.md` rather than only in the diff.
- **A press has an origin, and it reaches the shader.** **`Ripple3d`** on
  `StateLayer3d`, with `rippleOrigin`, `rippleRadius` and `rippleOpacity` in
  `BoxDecoration3dUniforms` and two new parameters in the panel shader — the
  first thing here that writes a uniform every frame and never leaves the
  repaint-only tier while doing it.
  - **`Layout3d.localPointFrom`** carries the point from the box that
    recognized the press to the box that draws the wash. It is
    `anchorOffsetTo`'s own change of frame generalized off an alignment,
    because a finger is not an alignment.
  - The ripple is evaluated *after* the panel's signed distance field has
    discarded everything outside the slab, which is what makes a bounded ripple
    free and an unbounded one impossible.
- **A widget subtree can be an overlay entry's content, and a box can be
  anchored to another.** Two things the declarative layer could not do at all.
  `SceneOverlay3d`, `Overlay3dController`, `WidgetOverlay3dEntry`,
  `WidgetOverlay3dBuilder`, `Overlay3dContentSlot3d`, `SceneModalBarrier3d` and
  `WidgetPageRoute3d` are the first half.
  - **`Layout3d.anchorOffsetTo`** and `Layout3dAnchoring` are the second, and
    they close a gap worth stating plainly: **nothing anchored anything.** An
    overlay entry sat where the overlay's alignment put it, so a menu could not
    be *at* its button. The offset is applied on the node tier, never in a
    child's position.
- **A pinned header's clip now reaches the shader.** The same defect as the one
  below, found in a second place: a viewport learns what a pinned header is
  sitting on only after its rows have painted, so a `SliverAppBar3d` cut
  nothing. **A clip discovered after the boxes under it have painted has to be
  republished** — `CustomScrollView3d` and `SliverPersistentHeader3d` do.
  - **`SceneClipBox3d`** and **`SceneSliverPersistentHeader3d`**, the two
    widget forms the declarative layer was missing.
- **The clip contract's plane tier had never fired at all.** A `ClipBox3d`
  takes its size from its child, so every panel underneath one was born with
  the unbounded block and kept it: the tier that cuts a box half inside a
  window was dead code from the day it shipped. `ClipBox3d`, `DecoratedBox3d`
  and `Layout3d.clipRegionForChild` between them make it fire.
- **A `build` method can read the unit contract.** `SceneLayout3d` publishes
  the surface's `Layout3dMetrics` as a `Layout3dMetricsScope`, so
  `Layout3dMetricsScope.of(context)` (or `maybeOf`) hands a widget the same
  number a box reads inside `performLayout`, and a component library can
  finally state a figure the way its specification does:
  `padding: metrics.dpInsets(const EdgeInsets3d.all(16))`. The scope has no
  public constructor — it reports what the surface measures with, and a second
  one inserted by hand would say something no box agrees with.
  - **A dependent rebuilds before the layout that uses what it computed.** A
    camera binding is applied from the view's per-frame clock (a `Ticker`, so
    the transient phase) or from a post-frame callback, never during build or
    layout, and Flutter builds before it lays out. The one exception — a
    contract written from *inside* a layout pass, which `Overlay3d` does for a
    detached entry — defers its rebuild to the next frame, and is documented
    rather than supported.
  - It does not make a metrics change cheaper: writing the contract still
    relayouts the whole subtree, because most boxes were never rebuilt and read
    the number in `performLayout`.
- **`SceneLayout3d.metrics`**, the authored unit contract as a widget property.
  The declarative layer could only get one from a binding before, which left
  `Layout3dCameraBinding.billboard` — whose own documentation says to pair it
  with an authored contract — with nothing to pair with. A binding that derives
  the metrics owns it and asserts against the property, exactly as a
  screen-filling binding does against `size`.
- **`Layout3dMetrics.dpInsets`**, the `EdgeInsets3d` counterpart of `dpSize`,
  and **`Layout3dSurface.metricsListenable`**, which is how the widget layer
  hears about a contract a binding derived.

- `ListView3d` and `GridView3d` are built on the sliver protocol now: each one
  *is* a scrolling window over a single sliver — a `SliverList3d`, a
  `SliverGrid3d` — reachable as `view.sliver`. That is the shape Flutter's
  views have (there is no `RenderListView`: a `ListView`'s items are placed by
  `RenderSliverList` inside a `RenderViewport`), and it leaves one copy of
  "where does item `i` go and is it visible" where there were two. The new
  `BoxScrollView3d` holds the forwarding, and `SliverMultiBoxAdaptor3d` is the
  base the two slivers now share; both are exported.
  - The imperative API is unchanged: `children`, `childAt`, `childCount`,
    `add`, `insert`, `remove`, `removeAll`, `syncChildren`, `itemCount`,
    `isLazy`, `activeIndices` and `refresh` all still mean the items, and a
    hit test still answers `firstOf<Scrollable3d>()` with the list or the grid
    rather than with the sliver inside it. The one member that went with the
    move is `itemBuilder`, which the sliver now implements; it was `@protected`
    on the views, so nothing outside them should have been reading it.
  - **Behaviour change:** `cacheExtent` decides what is built and kept alive,
    not what is drawn. An item inside the cache but outside the window used to
    be visible; it is hidden now, and shown when the window reaches it. Since
    a scene has nothing to clip with, that item was drawn outside the list.
  - **Behaviour change:** a list or a grid needs a bounded extent across its
    scroll axis, which is what an item is given to span, and it asserts when it
    has none. It used to size that axis to the widest item. Flutter's viewport
    makes the same demand. It also takes no depth when the depth axis is
    unbounded, where it used to grow to the deepest item.
  - It costs one scene node per view, the sliver's, which is the node Flutter's
    render tree has there too.
- `CustomScrollView3d` shrink-wraps when the scroll axis is unbounded, laying
  its slivers out against an endless window and coming out as long as they
  filled, the way Flutter's `ShrinkWrappingViewport` does. It used to assert.
  This is what keeps an unbounded `ListView3d` sizing to its content.
- **`prototypeItem`** on `ListView3d`, `SliverList3d` and their `.builder`
  constructors: an item built once and measured, standing for the extent of
  them all, which is Flutter's `ListView.prototypeItem`. It is `itemExtent` for
  a list whose items are uniform in a size that comes from the content rather
  than from a number the caller can write down, and it buys back everything
  `itemExtent` buys — arithmetic offsets, a total that does not move, and a
  jump anywhere that builds only the window. The prototype is measured and
  never shown: it is not one of the items and its node never enters the scene.
  The two are answers to the same question, so a list takes one of them and
  asserts on both.
- **`contentExtentEstimator`** on the same four, for a list whose items
  genuinely differ and whose total the application knows anyway. Offsets stay
  measured and exact; what stops moving is the reachable range. An estimate
  shorter than what has already been measured is raised to it.
- In debug, a measuring pass that builds more than five hundred items **only to
  release them again** now says so, naming both ways out. It is the discarded
  items that make it a symptom: a long window genuinely showing hundreds of
  items, or a list laid out in unbounded room showing all of them, throws
  nothing away and passes quietly.

- Every single-child `Scene*3d` widget is `const` now — `ScenePadding3d`,
  `SceneAlign3d`, `SceneCenter3d`, `SceneSizedBox3d`, `SceneContainer3d`,
  `SceneTransform3d`, `ScenePositioned3d`, `SceneFlexible3d`, `SceneExpanded3d`,
  `SceneViewport3d`, `SceneSliverToBoxAdapter3d` and the three
  `SceneIntrinsic*3d`. `SingleChildLayout3dWidget` folded its child into a list
  in its constructor, which no const expression can do, so these were rebuilt on
  every build of their parent while the multi-child widgets beside them were
  not. The list is derived from `child` instead.
- **Deprecated:** `EdgeInsets3d.alongDepth` is now `EdgeInsets3d.depth`,
  matching `horizontal`, `vertical`, and the `depth` argument of
  `EdgeInsets3d.symmetric`. The old name still works.
- A null declarative property now means "the default" everywhere, rather than
  "leave the last value alone". Dropping `basis` from a `SceneLayout3d` puts the
  plane back upright, and dropping `controller` from a scrolling widget gives
  the view a fresh one of its own instead of keeping the last one that was
  passed. The imperative `controller` setters accept null to say the same
  thing.
- `Layout3d.debugDisposed`, and asserts against laying out, re-disposing, or
  dirtying a disposed layout. The failure used to surface much later and
  somewhere else.
- `IgnorePointer3d.ignoring` and `AbsorbPointer3d.absorbing` are a getter and
  setter pair like every other property in the package, rather than bare public
  fields. They still cost nothing to flip.

- `Viewport3d`, `ListView3d`, `GridView3d` and `CustomScrollView3d` held their
  scroll controller four separate times over — the same field, setter,
  listener and `dispose` in each — and the ownership rule underneath was easy
  to get subtly wrong. It is one mixin now, `Scroll3dHolderMixin`, which the
  four install from their constructors with `initController`. The rule it
  keeps is unchanged: a controller the view made is disposed with the view, and
  one handed in from outside never is.
- `Layout3dLayoutPassMixin`, the flag that makes a view deaf to the dirt raised
  by its own layout pass, is its own mixin rather than a part of
  `Layout3dBuiltChildrenMixin`, because holding a scroll position needs it
  without holding built children. Both new mixins are exported.
- **Behaviour change:** `Viewport3d` now ignores *any* relayout request raised
  during its own layout pass, not just one from its own scroll controller. It
  had half of this guard; the other three views had all of it.
- `ListView3d`, `GridView3d`, `SliverList3d` and `SliverGrid3d` were four
  independent implementations of the same bookkeeping, and had already drifted
  apart in three places. The shared half is now two mixins,
  `Layout3dBuiltChildrenMixin` (the index-to-child map, `itemCount`, `refresh`,
  and the child-list guard above) and
  `Layout3dMeasuredChildrenMixin` (the running prefix a list of free-sized
  children keeps). Both are exported, for writing a scrolling view of your own.
  The four views shed 672 lines between them and keep only what is actually
  theirs: where the children go.
- Fixed: `SliverList3d.itemCount` left the measured prefix in place, so a list
  that had measured ten items went on reporting all ten as its `scrollExtent`
  after being told there were five. Setting `itemCount` now drops the
  measurements on all four views.
- `ListView3d.itemCount` no longer disposes every built child when it changes.
  The children are still right for their own indices; the next layout releases
  whatever falls outside the window, which includes anything past the new end.
  Call `refresh()` when what the builder *returns* has changed.
- `activeIndices` and `isLazy`, previously on `ListView3d` alone, are now on
  all four views.

- **Breaking:** `Offset3dBox` is gone. It was undocumented, untested, had no
  widget, and was the one public type that did not end in `3d`;
  `Transform3d.translate` does the same thing.
- **Deprecated:** `Grid3dItemBuilder` and `Sliver3dItemBuilder`, which were
  identical to `Layout3dItemBuilder`. That one name now lives beside the
  protocol in `layout3d.dart` and every builder takes it; the two aliases still
  work and will be removed in a later release.
- A `ListView3d.builder`, `GridView3d.builder`, `SliverList3d.builder` or
  `SliverGrid3d.builder` now asserts when its child list is edited from
  outside. A built view tracks its children by index, so a child inserted that
  way was never laid out and never released; the failure used to surface much
  later as a size assert on a box nobody remembered adding. Items come from the
  builder: set `itemCount`, or call `refresh()`.
- `_lastIndexBefore` in `ListView3d` and `SliverList3d` is a binary search
  rather than a linear scan, so the cost of a layout no longer climbs with how
  far the list has ever been scrolled.
- `GridView3d.dispose` clears the map of built cells, as `ListView3d` already
  did.
- Documented what was already true: a `SliverList3d.builder` with no
  `itemExtent` guesses the part of its length it has not measured, so the
  *reachable scroll range* moves as it is revised — taking the position with it
  when the estimate shrinks past where the viewer is — and reaching an offset
  deep in the list measures every item before it in one pass. (Item offsets
  themselves are exact and never move, and neither does a following sliver;
  an earlier draft of this entry said otherwise.) Also: `Viewport3d` neither
  culls nor clips, unlike the lists; the declarative layer
  builds every child widget up front, and lazy *widgets* need a
  `RenderObjectElement` this layer does not have (the old note promised the
  sliver work would bring it, which it did not); `Layout3dController` reaches
  the surface and its plane node, not measured sizes or scroll positions; and
  `examples/smoke_render` has five layout scenes, not two.

- Fixed: `Stack3d.depthStep` moved its children in the *layout*, which broke
  the two things the stack promises. A `Positioned3d` pinned to a face landed
  short of it by the step, and a coplanar child was pushed in front of the
  stack's own front face, where the ray gate could not reach it — so on a flat
  stack, the child on top became the one hit testing could not find, the exact
  inverse of the documented rule. The step is now written to
  `ParentData3d.sceneOffset`, a new per-child offset that moves the scene node
  and nothing else: the geometry separates in the depth buffer, and the layout,
  the pins and the hit test are untouched. `Stack3d` sizing is unchanged.
- `ParentData3d.sceneOffset` and `Layout3d.sceneOffset`, for a parent that
  needs to nudge a child's geometry without moving its box.
  `Layout3d.worldTransform` undoes it, so it still describes the layout frame.
- Fixed: `ListView3d.itemCount` reported the count captured when the list was
  built, so it went stale as soon as a child was added or removed. It now
  follows the child list, as `GridView3d`, `SliverList3d` and `SliverGrid3d`
  already did.
- A non-sliver child of a `CustomScrollView3d` now asserts as it is adopted,
  naming `SliverToBoxAdapter3d`, instead of failing as a bare cast error in the
  middle of layout. The constructor was typed, but `add`, `insert` and
  `syncChildren` come from the child-list mixin and the declarative layer
  passes plain widgets.

## 0.5.0

- Intrinsic sizing: `Layout3d.getMinIntrinsicExtent` and `getMaxIntrinsicExtent`
  ask a box how much room it would like, one axis at a time. Flutter's four
  methods would be six with a third axis, so the axis is a parameter and the
  `Size3d` beside it carries the limits on the other two.
- `IntrinsicWidth3d`, `IntrinsicHeight3d` and `IntrinsicDepth3d` (over a shared
  `IntrinsicExtent3d`), which size their child to the extent it asks for, with
  Flutter's `stepWidth` under the name `step`.
- Baselines: `Layout3d.getDistanceToBaseline`, `Baseline3d`, and
  `CrossAxisAlignment3d.baseline`, so a line of content can hang from a line
  inside it rather than from an edge. A baseline belongs to an axis here, and
  `Baseline3d` declares one outright, because nothing in a scene reports one
  the way text does.
- Every box answers for itself: `NodeBox3d` measures the content it holds,
  `Padding3d` and `Container3d` add their insets, `SizedBox3d` answers from its
  fixed extents without asking the child, and `Flex3d`, `Stack3d` and `Wrap3d`
  are ported from their Flutter counterparts. A `Wrap3d`'s answer across its
  runs is the one-run lower bound; the rest are exact.
- The scrolling views refuse the question, as Flutter's viewport does: a
  viewport's content is whatever length it is, and the view exists so that it
  need not grow to match.
- Answers are cached until the box goes dirty, and a box whose answer was taken
  pushes its dirt up past its own relayout boundary, because a parent decided
  something from a number that has just gone stale.
- `SceneIntrinsicWidth3d`, `SceneIntrinsicHeight3d`, `SceneIntrinsicDepth3d` and
  `SceneBaseline3d` in the declarative layer.
- `Constraints3d.hasTightAlong` and `tightenAlong`, `EdgeInsets3d.alongAxis` and
  `lowAlong`.

## 0.4.0

- The sliver protocol: `SliverConstraints3d` and `SliverGeometry3d`, and
  `Sliver3d`, a layout that answers a window rather than a size. The box
  protocol is the wrong shape for "there are ten thousand of these and you can
  see nine"; this is the one Flutter reaches for, ported.
- `CustomScrollView3d`, a viewport that puts several sections on one scroll
  position and gives each only the part of the window it can see. It honours
  `SliverGeometry3d.scrollOffsetCorrection`, so a sliver that finds its content
  elsewhere mid-layout can move the offset and have the pass run again.
- `SliverList3d`, `SliverGrid3d` (sharing `GridView3d`'s `Grid3dDelegate`) and
  `SliverToBoxAdapter3d`, the glue that gives an ordinary box its turn.
- `SceneCustomScrollView3d`, `SceneSliverList3d`, `SceneSliverGrid3d` and
  `SceneSliverToBoxAdapter3d` in the declarative layer. Child widgets are still
  built up front there; only the imperative builders are lazy.
- `Layout3dWithChildMixin` and `Layout3dWithChildrenMixin`, extracted from
  `SingleChildLayout3d` and `MultiChildLayout3d` so a sliver can hold children
  without being a box.
- `Scroll3dController.correctBy`, for a viewport applying a correction during
  its own layout.
- Fixed: `Scroll3dController.contentExtent` reported the viewport's extent for
  content shorter than the window, because the scroll range alone cannot tell
  the two apart. Views now report the extent they measured.

## 0.3.0

- `Wrap3d`, which breaks into runs where a flex would overflow. Runs stack on
  the first cross axis only; the depth axis aligns children rather than
  wrapping them, so a wrap of models stays a readable plane.
- `GridView3d`, laying cells out on a grid a `Grid3dDelegate` decides from the
  room across the scroll axis, with `Grid3dDelegateWithFixedCrossAxisCount`
  and `Grid3dDelegateWithMaxCrossAxisExtent` provided.
- `GridView3d.builder` is exactly lazy: cell positions are arithmetic, so the
  total extent is known without building anything, and only the window (plus
  `cacheExtent`) is ever built.
- `Grid3dLayout` exposes that arithmetic on its own, for callers that want to
  know where a cell lands without asking the view.
- `SceneWrap3d` and `SceneGridView3d` in the declarative layer. An unchanged
  grid delegate does not relayout, the way Flutter's `shouldRelayout` works.

## 0.2.0

- Hit testing, the other half of the layout protocol. `Layout3d.hitTest` walks
  the tree with a `Ray3d` rather than a point, because in a scene the pointer
  is a direction and the boxes stand at different depths; a box bounds the
  stretch of ray its children can be found in, which is the 3D form of
  Flutter's `size.contains(position)` gate.
- `Layout3dSurface.hitTestRay` brings a camera ray into layout space (the
  surface node already carries the basis, so its inverse world transform is
  the whole conversion), and `hitTestAt` asks with a point on the plane.
- `HitTestResult3d` reports the boxes hit, deepest first, with
  `firstOf<T>()` to pick an ancestor such as the list a finger landed in.
- `Layout3dPointer` turns pointer rays into scrolling. It measures the drag on
  the grabbed view's own plane rather than across the screen, so content stays
  under the finger at any viewing angle, and it keeps the grab until release.
- `Scrollable3d`, implemented by `Viewport3d` and `ListView3d`, which are now
  opaque to hits across their whole window so a drag can start on a gap.
- `IgnorePointer3d` and `AbsorbPointer3d`, plus their `Scene`-prefixed
  widgets. `NodeBox3d` answers hits on its own account; boxes that only
  arrange others do not. `Transform3d` neither answers nor gates, matching
  Flutter's `RenderTransform`.
- `Layout3d.worldTransform`, the transform from a box's own frame to world
  space.

## 0.1.0

- Initial release. Flutter's box layout protocol in three dimensions, laid out
  on a freely transformable plane in a flutter_scene scene.
- Core protocol: `Layout3dSurface`, `Layout3d`, `SingleChildLayout3d`,
  `MultiChildLayout3d`, `ProxyLayout3d`, `Layout3dOwner`, with relayout
  boundaries and a dirty-list flush.
- Value types: `Constraints3d`, `Size3d`, `Offset3d`, `Alignment3d`,
  `EdgeInsets3d`, `Axis3d`, and `LayoutBasis3d` for mapping layout space onto
  the plane (`xy` upright, `xz` on the ground, or any invertible matrix).
- Layouts: `Container3d`, `Padding3d`, `Align3d`, `Center3d`, `SizedBox3d`,
  `ConstrainedBox3d`, `Transform3d`, `Row3d`, `Column3d`, `Depth3d`,
  `Flexible3d`, `Expanded3d`, `Spacer3d`, `Stack3d`, `Positioned3d`.
- `NodeBox3d`, which measures engine content through
  `Node.combinedLocalBounds` and fits it into the box.
- Scrolling: `Viewport3d`, `ListView3d` (explicit children or a lazy
  `ListView3d.builder`), and `Scroll3dController`.
- A declarative widget layer in `package:flutter_scene_layout3d/widgets.dart`:
  `SceneLayout3d` plus a `Scene`-prefixed widget for every layout, reconciled
  through the Flutter element tree.
- The built-in bases follow the engine's screen convention (flutter_scene
  builds its camera basis with `right = up x forward`, so world `-x` is screen
  right for a camera facing a plane), which is what makes a `Row3d` read left
  to right on screen.
- `BoxFit3d` follows `FittedBox`: the box takes the size the constraints and
  the measurement give it, and the fit scales the content into that box, so a
  loose parent never inflates the box and an axis with no room does not
  collapse the content.
