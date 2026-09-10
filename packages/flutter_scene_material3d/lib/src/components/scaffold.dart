import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Constraints3d, MultiChildLayout3dDelegate, Offset3d, Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneClipBox3d,
        SceneCustomMultiChildLayout3d,
        SceneLayoutId3d,
        ScenePositioned3d,
        SceneStack3d,
        StackFit3d;

import '../theme/theme.dart';
import 'material.dart';
import 'node_shift.dart';

/// The parts a [Scaffold3d] arranges, **in depth order**.
///
/// The order is the API. `index` is how many depth steps in front of the
/// scaffold's own backing a slot sits, plus one — see [Scaffold3d.liftFor] —
/// so adding a value in the middle of this enum moves everything after it,
/// and that is deliberate: the ordering is a guarantee the scaffold makes,
/// not a detail of one build method.
enum Scaffold3dSlot {
  /// The screen's content. One step in front of the backing, so that a
  /// component resting on the body is not coplanar with the scaffold's own
  /// slab.
  body,

  /// The navigation bar across the bottom.
  bottomNavigationBar,

  /// The bar across the top.
  appBar,

  /// The floating action button, which is in front of everything.
  floatingActionButton,
}

/// A screen: a bar at the top, a body, a bar at the bottom, and a floating
/// action button.
///
/// ```dart
/// Scaffold3d(
///   appBar: AppBar3d.text(title: 'Inbox'),
///   body: SceneListView3d(children: rows),
///   bottomNavigationBar: NavigationBar3d(
///     selectedIndex: index,
///     destinations: destinations,
///     onDestinationSelected: (i) => setState(() => index = i),
///   ),
///   floatingActionButton: FloatingActionButton3d(
///     icon: Icons.edit,
///     onPressed: _compose,
///     semanticLabel: 'Compose',
///   ),
/// )
/// ```
///
/// ## What it owns, and what it merely positions
///
/// It owns three things and nothing else: the **backing** every screen has
/// (a `Material3d` at `colorScheme.surface`), the **arrangement** — a
/// `CustomMultiChildLayout3d`, exactly as Flutter's `Scaffold` is one, with
/// the body given whatever the bars left over — and the **depths**. Everything
/// in the slots is a widget the caller built and the scaffold does not touch.
///
/// **It does not bind a surface, and that is a decision.** A
/// `Layout3dCameraBinding` makes a surface cover the view, which is what turns
/// a scene into a screen; a scaffold that did that for you could only ever be
/// the whole view, and half the reason this package exists is that a Material
/// screen here can be a panel on a wall in a room. So a `Scaffold3d` is a box
/// like any other, and an application that wants a full-view screen says so
/// once, where it mounts the surface:
///
/// ```dart
/// SceneLayout3d(
///   camera: camera,
///   binding: const Layout3dCameraBinding.screenFilling(distance: 2),
///   child: SceneTheme3d(
///     data: Theme3dData.light,
///     textRendererFactory: AtlasText3dRenderer.new,
///     child: Scaffold3d(appBar: bar, body: body),
///   ),
/// )
/// ```
///
/// ## The depths, which are the part with no Flutter equivalent
///
/// An app bar is over content that scrolls under it and a navigation bar is
/// over the same content at the other end. In two dimensions that is paint
/// order and it costs nothing. Here every slot is a **slab** — the bars are
/// `Thickness3d.structural`, 8dp — and a bar no nearer the viewer than the
/// rows passing beneath it loses the depth test to them somewhere, in
/// patches, differently on every frame.
///
/// So the scaffold does not leave the depths to the components. It places
/// each slot at its own distance, [depthStep] apart, in the order
/// [Scaffold3dSlot] declares, and asserts that the step it was given is
/// actually enough:
///
/// ```dart
/// theme.thickness.separates(
///   theme.thickness.raised,        // the deepest thing a body holds
///   theme.thickness.structural,    // a bar
///   step: depthStep,
/// )
/// ```
///
/// Two slabs are separated only when the step exceeds the **mean** of their
/// thicknesses, so an 8dp bar over a 4dp card needs more than 6dp. The
/// theme's own `thickness.depthStep` is 12, which clears it with half again
/// to spare, and is the default.
///
/// **A `SliverAppBar3d` inside the body is a separate guarantee**, because it
/// is not in the [appBar] slot at all — it is a sliver in the body's own
/// scroll view, and what keeps content out of it is
/// `SliverPersistentHeader3d.lift`. `SliverAppBar3d` defaults that to the
/// same `thickness.depthStep`, for the same arithmetic.
///
/// ## The body is clipped, and it has to be
///
/// The body's slot is a window: a list in it is taller than the room it was
/// given, and without a clip its rows draw over the bars rather than ending
/// at them. `SceneClipBox3d` is that window. It clips the **face and not the
/// depth**, so a raised card in the body still stands proud of the screen —
/// and it cuts a row that is *half* out, which whole-node culling cannot do.
/// A row's `Material3d` honours the plane block; a leaf holding an
/// application's own mesh does not, and will draw through the edge.
///
/// ## What phase 6 puts on top of this
///
/// Dialogs, sheets, snack bars and menus are **not** scaffold slots. They go
/// through `Overlay3d`, which is a property of the surface rather than of the
/// screen, so that a route can outlive the screen that opened it and a modal
/// barrier can cover the whole view. What this class owes them is the depth
/// vocabulary above and nothing else: an overlay layer states its own lift,
/// in the same logical pixels, against the frontmost slot here —
/// `Scaffold3d.liftFor(Scaffold3dSlot.floatingActionButton, depthStep)`.
class Scaffold3d extends StatelessWidget {
  /// Creates a screen.
  const Scaffold3d({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.depthStep,
    this.floatingActionButtonMargin = defaultFloatingActionButtonMargin,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
  });

  /// Material's inset for a floating action button, in logical pixels.
  static const double defaultFloatingActionButtonMargin = 16.0;

  /// How far in front of the scaffold's backing [slot] sits, in the unit
  /// [depthStep] is stated in.
  ///
  /// The guarantee, as arithmetic. Every slot is one step in front of the one
  /// before it in [Scaffold3dSlot], and the body is one step in front of the
  /// backing rather than on it — two coplanar surfaces z-fight, and the body
  /// resting exactly on the screen it is drawn on is the commonest way to
  /// produce a pair.
  static double liftFor(Scaffold3dSlot slot, double depthStep) =>
      (slot.index + 1) * depthStep;

  /// How far in front of a screen's backing an **overlay** sits, in the unit
  /// [depthStep] is stated in.
  ///
  /// One step in front of the frontmost slot, which is the same rule every
  /// other slot follows — so a dialog clears the whole screen rather than
  /// only the body, and it clears it *by construction*: adding a slot to
  /// [Scaffold3dSlot] moves this number with it.
  ///
  /// This is what an `Overlay3d` entry's lift is set from. It is not a
  /// scaffold slot and it is deliberately not one: an overlay belongs to the
  /// surface rather than to the screen, so that a route can outlive the
  /// screen that opened it and a barrier can cover the whole view. What the
  /// scaffold owes it is the depth vocabulary, and this is that vocabulary
  /// stated once.
  ///
  /// ```dart
  /// OverlayLayer3d.inPlane(
  ///   lift: metrics.dp(Scaffold3d.overlayLift(theme.thickness.depthStep)),
  /// )
  /// ```
  ///
  /// `Overlay3d.defaultLift` is eight logical pixels, which is a
  /// depth-buffer separation rather than a distance and is nowhere near
  /// enough here: a screen has already spent four steps of its own, and the
  /// floating action button in front of them is a slab. See *Depth ordering*
  /// in `docs/traps.md`.
  static double overlayLift(double depthStep) =>
      liftFor(Scaffold3dSlot.values.last, depthStep) + depthStep;

  /// The bar across the top, usually an [AppBar3d].
  ///
  /// A `SliverAppBar3d` does **not** go here: it is a sliver, and it belongs
  /// in the body's own `SceneCustomScrollView3d`, which is the whole point of
  /// it — content scrolls under a sliver bar and cannot scroll under this
  /// slot, because this slot is not in the scroll view.
  final Widget? appBar;

  /// The screen's content.
  final Widget? body;

  /// The bar across the bottom, usually a `NavigationBar3d`.
  final Widget? bottomNavigationBar;

  /// The button floating over the body at the trailing bottom corner.
  final Widget? floatingActionButton;

  /// The backing's colour, or null for `colorScheme.surface`.
  final Color? backgroundColor;

  /// How far apart, in logical pixels, two successive slots sit in depth, or
  /// null for the theme's `thickness.depthStep`.
  ///
  /// Asserted to separate a `thickness.raised` slab from a
  /// `thickness.structural` one, which is the deepest pair this arrangement
  /// can produce: a card in the body passing under a bar.
  final double? depthStep;

  /// How far the floating action button is inset from the trailing and
  /// bottom edges, in logical pixels.
  final double floatingActionButtonMargin;

  /// Whether the body runs behind [bottomNavigationBar] rather than stopping
  /// at it.
  final bool extendBody;

  /// Whether the body runs behind [appBar] rather than starting under it.
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final step = depthStep ?? theme.thickness.depthStep;
    assert(
      theme.thickness.separates(
        theme.thickness.raised,
        theme.thickness.structural,
        step: step,
      ),
      'A Scaffold3d with a ${step}dp depth step cannot keep a '
      '${theme.thickness.structural}dp bar in front of a '
      '${theme.thickness.raised}dp card passing under it: two slabs are '
      'separated only when the step exceeds the mean of their thicknesses, '
      'which is '
      '${theme.thickness.raised + theme.thickness.structural / 2}dp here. '
      'Raise depthStep, or thin the scale it came from.',
    );

    // The backing and the arrangement are **siblings**, not parent and child,
    // and that is not a matter of taste. A `Material3d`'s thickness is a
    // *tight* depth constraint on everything below it, so a screen whose
    // backing is a `thickness.thin` slab used to hand every slot a 1dp depth
    // budget: an 8dp app bar came out 1dp, its title ended up coplanar with
    // the bar it was drawn on, and the title vanished into the depth test —
    // which is the failure `AppBar3d`'s own front-face alignment exists to
    // avoid, reintroduced one level up. Cards inside the body lost their
    // labels the same way. `docs/traps.md` states the rule in general: two
    // surfaces of different depths are siblings in a stack, never one inside
    // the other.
    return SceneStack3d(
      fit: StackFit3d.expand,
      children: <Widget>[
        ScenePositioned3d(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          back: 0,
          depth: metrics.dp(theme.thickness.thin),
          child: Material3d(
            color: backgroundColor ?? theme.colorScheme.surface,
            shape: theme.shape.none,
            elevation: theme.elevation.level0,
            thickness: theme.thickness.thin,
            surfaceTint: const Color(0x00000000),
          ),
        ),
        SceneCustomMultiChildLayout3d(
          delegate: _Scaffold3dLayout(
            fabMargin: metrics.dp(floatingActionButtonMargin),
            extendBody: extendBody,
            extendBodyBehindAppBar: extendBodyBehindAppBar,
          ),
          children: <Widget>[
            if (body != null)
              _lifted(
                Scaffold3dSlot.body,
                metrics.dp(step),
                // The window. Without it a list taller than its slot draws
                // over the bars instead of ending at them.
                SceneClipBox3d(child: body!),
              ),
            if (bottomNavigationBar != null)
              _lifted(
                Scaffold3dSlot.bottomNavigationBar,
                metrics.dp(step),
                bottomNavigationBar!,
              ),
            if (appBar != null)
              _lifted(Scaffold3dSlot.appBar, metrics.dp(step), appBar!),
            if (floatingActionButton != null)
              _lifted(
                Scaffold3dSlot.floatingActionButton,
                metrics.dp(step),
                floatingActionButton!,
              ),
          ],
        ),
      ],
    );
  }

  /// One slot: the box the delegate arranges, with its subtree's **geometry**
  /// moved [Scaffold3d.liftFor] toward the viewer.
  ///
  /// The lift is a [SceneNodeShift3d] rather than a z in the position the
  /// delegate gives the slot, and the difference is the whole reason this
  /// helper exists. Toward the viewer is *negative* z, so a slot positioned
  /// there sits outside its parent's own extent — and a ray is clamped to the
  /// stretch inside each box before its children are asked, exactly as
  /// Flutter gates a hit on `size.contains(position)`. A screen lifted that
  /// way draws correctly and **cannot be pressed at all**: the scaffold's own
  /// backing answers every hit and no bar, tile or button below it is ever
  /// reached.
  ///
  /// So the depth ordering goes on the node tier, where `Stack3d.depthStep`
  /// has always put it: the geometry moves, the box stays where layout put
  /// it, and [Layout3d.worldTransform] undoes the shift so a ray still finds
  /// it. Drawing is unaffected — the slabs are the same distance apart in the
  /// scene — and the guarantee is the same one, stated in the tier that can
  /// keep it.
  static Widget _lifted(Scaffold3dSlot slot, double step, Widget child) =>
      SceneLayoutId3d(
        id: slot,
        child: SceneNodeShift3d(
          shift: Offset3d(0, 0, -liftFor(slot, step)),
          child: child,
        ),
      );
}

/// The arrangement, which is Flutter's `_ScaffoldLayout` with a third axis.
///
/// It arranges in **two dimensions only**: every `positionChild` here carries
/// z zero. The depth ordering is real and is applied one level down, by the
/// [SceneNodeShift3d] `Scaffold3d._lifted` wraps each slot in — see there for
/// why a lift written into the position instead makes a whole screen
/// unpressable.
class _Scaffold3dLayout extends MultiChildLayout3dDelegate {
  _Scaffold3dLayout({
    required this.fabMargin,
    required this.extendBody,
    required this.extendBodyBehindAppBar,
  });

  /// The floating action button's inset, in world units.
  final double fabMargin;

  final bool extendBody;
  final bool extendBodyBehindAppBar;

  @override
  void performLayout(Size3d size) {
    var top = 0.0;
    var bottom = 0.0;

    // A bar takes the full width and as much height as it asks for, which is
    // its own token — 64dp for an app bar, 80dp for a navigation bar — rather
    // than anything this delegate knows.
    Constraints3d barConstraints() => Constraints3d(
      minWidth: size.width,
      maxWidth: size.width,
      maxHeight: size.height,
      maxDepth: size.depth,
    );

    if (hasChild(Scaffold3dSlot.appBar)) {
      final bar = layoutChild(Scaffold3dSlot.appBar, barConstraints());
      top = bar.height;
      positionChild(Scaffold3dSlot.appBar, Offset3d.zero);
    }

    if (hasChild(Scaffold3dSlot.bottomNavigationBar)) {
      final bar = layoutChild(
        Scaffold3dSlot.bottomNavigationBar,
        barConstraints(),
      );
      bottom = bar.height;
      positionChild(
        Scaffold3dSlot.bottomNavigationBar,
        Offset3d(0, size.height - bottom, 0),
      );
    }

    if (hasChild(Scaffold3dSlot.body)) {
      final bodyTop = extendBodyBehindAppBar ? 0.0 : top;
      final bodyBottom = extendBody ? 0.0 : bottom;
      layoutChild(
        Scaffold3dSlot.body,
        Constraints3d.tight(
          Size3d(
            size.width,
            math.max(0.0, size.height - bodyTop - bodyBottom),
            size.depth,
          ),
        ),
      );
      positionChild(Scaffold3dSlot.body, Offset3d(0, bodyTop, 0));
    }

    if (hasChild(Scaffold3dSlot.floatingActionButton)) {
      final fab = layoutChild(
        Scaffold3dSlot.floatingActionButton,
        Constraints3d.loose(size),
      );
      positionChild(
        Scaffold3dSlot.floatingActionButton,
        Offset3d(
          math.max(0.0, size.width - fab.width - fabMargin),
          math.max(0.0, size.height - bottom - fab.height - fabMargin),
          0,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_Scaffold3dLayout oldDelegate) =>
      oldDelegate.fabMargin != fabMargin ||
      oldDelegate.extendBody != extendBody ||
      oldDelegate.extendBodyBehindAppBar != extendBodyBehindAppBar;
}
