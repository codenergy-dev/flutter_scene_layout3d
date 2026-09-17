// The pieces every overlay in this catalogue shares: the depth it sits at,
// the modal frame around it, and the way it finds somewhere to be put.

import 'package:flutter/animation.dart' show Animation;
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        BoxDecoration3d,
        Layout3dMetrics,
        Navigator3d,
        Overlay3d,
        OverlayLayer3d,
        StackFit3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        SceneDecoratedBox3d,
        SceneFadeTransition3d,
        SceneOpacity3d,
        SceneModalBarrier3d,
        SceneOverlay3d,
        SceneStack3d;

import 'package:flutter/painting.dart' show Color;

import '../theme/theme_data.dart';
import 'scaffold.dart';

/// How far in front of the screen an overlay sits, in **world units**.
///
/// One number for every overlay in the catalogue, taken from the place a
/// screen's own depths are stated. A `Scaffold3d` steps each of its slots one
/// `thickness.depthStep` in front of the last, and this is one step in front
/// of the frontmost of them — so a dialog clears the whole screen rather than
/// only the body, and it clears it by construction: adding a slot to
/// `Scaffold3dSlot` moves this with it.
///
/// It is emphatically **not** `Overlay3d.defaultLift`, which is eight logical
/// pixels — a depth-buffer separation between two things with no thickness,
/// and about a seventh of what a Material screen has already spent.
double overlayLift3d(Theme3dData theme, Layout3dMetrics metrics) =>
    metrics.dp(Scaffold3d.overlayLift(theme.thickness.depthStep));

/// The layer an overlay entry is inserted on.
OverlayLayer3d overlayLayer3d(Theme3dData theme, Layout3dMetrics metrics) =>
    OverlayLayer3d.inPlane(lift: overlayLift3d(theme, metrics));

/// The navigator over the overlay above [context], made if there is not one.
///
/// A `Navigator3d` registers itself against its overlay, so asking for one
/// twice gives the same object; an application that made its own gets that
/// one, and an application that never thought about routes still gets a
/// dialog that returns a future.
Navigator3d navigatorOf3d(BuildContext context) {
  final overlay = SceneOverlay3d.of(context);
  return Navigator3d.of(overlay) ?? Navigator3d(overlay);
}

/// The overlay above [context].
Overlay3d overlayOf3d(BuildContext context) => SceneOverlay3d.of(context);

/// How much of a scrim's fragments survive, out of [scrimColor]'s alpha.
///
/// **A scrim dims by coverage rather than by blending**, and the difference is
/// not an optimisation — it is the only arrangement that dims a screen
/// *evenly*. This is the rule the whole catalogue's modals are built on, so it
/// is stated once, here.
///
/// A translucent slab in front of a screen has to be composited against
/// everything behind it, and in this stack that ordering is decided twice
/// over: `box_decoration3d.fmat` and `text_glyph3d.fmat` both write depth —
/// each for a reason its own header explains — and the translucent pass sorts
/// by one number per draw. A 32%-alpha scrim standing in front of a Material
/// screen therefore erases whatever the sort puts after it instead of dimming
/// it: **an app bar's title came out as a bare outline while the navigation
/// bar's labels were untouched**, on the same screen, under the same scrim.
///
/// Four treatments of the same dim were built and photographed over the
/// gallery, and only this one is even:
///
///  * **32% alpha**, as it was — the app bar erased, the navigation bar not.
///  * **`depth_write: false`** on the panel shader, which is what
///    `box_decoration3d.fmat`'s own note prescribes — the error inverts rather
///    than closing: the app bar is then drawn *over* the scrim and is not
///    dimmed at all.
///  * **A fully opaque scrim** — even, by construction, and the screen behind
///    is simply gone. Consistent, and not Material.
///  * **Coverage**, which is this. The slab keeps `alpha` of its fragments and
///    draws them at full strength, so each one writes depth exactly as an
///    opaque fragment does and the result stops depending on the order at all:
///    drawn before the screen or after it, the same fraction of pixels is
///    scrim and the rest is screen.
///
/// The cost is that the dim is dithered rather than smooth — the same
/// screen-door coverage `Opacity3d` fades a subtree with, and the same
/// trade. It was chosen by looking at a window, which is the only thing that
/// answers whether a dither reads.
double scrimCoverage3d(Color scrimColor) => scrimColor.a;

/// A barrier, a scrim on it, and [child] a depth step in front of both.
///
/// The frame every modal overlay is wrapped in, and it is built **here**
/// rather than by `Overlay3dEntry.modal` for one reason: the entry's own
/// modal stack has no depth step, so its barrier and its content sit on the
/// same plane and z-fight wherever the scrim shows through. A scrim in a
/// scene is a slab, and two slabs need a step between them like any other
/// pair.
///
/// [scrimThickness] and [depthStep] are in world units; [scrimColor] is a
/// colour with Material's own alpha in it, which the panel shader blends.
///
/// ## The scrim fades, and it fades on its own
///
/// Give [scrimFade] a route's animation and the dim comes up with the route
/// instead of snapping to full strength on the first frame. It is applied
/// **here**, to the scrim alone, and never to the frame as a whole — which is
/// the same rule that keeps `PageRoute3d.motion` out of a catalogue modal:
/// *a dim must not slide in with the thing it dims.* So the content's own
/// motion goes around [child], one level down, and the two animations share a
/// clock without sharing a transform.
Widget modalFrame3d({
  required Widget child,
  required Color? scrimColor,
  required double scrimThickness,
  required double depthStep,
  required bool dismissible,
  required VoidCallback onDismiss,
  Alignment3d alignment = Alignment3d.center,
  Animation<double>? scrimFade,
}) => SceneStack3d(
  // The caller's alignment across, and the **front** face in depth, whatever
  // it said. A scrim is the backmost thing in this frame and still has to be
  // in front of the whole screen; centred in the frame's depth it sits a
  // fraction of a slab behind the frame's own face, which is how a dialog's
  // scrim and a sheet's — whose frames differ in depth — ended up at two
  // different depths over the same screen. `Alignment3d` centres in depth as
  // well as across, and that is the trap `docs/traps.md` records.
  alignment: Alignment3d(alignment.x, alignment.y, -1),
  // The stack takes the barrier's size, which is the whole overlay, so the
  // content is placed inside a full-screen frame rather than shrink-wrapped
  // around itself.
  fit: StackFit3d.loose,
  depthStep: depthStep,
  children: <Widget>[
    SceneModalBarrier3d(
      dismissible: dismissible,
      onDismiss: onDismiss,
      thickness: scrimThickness,
      // Null for a menu, which dims nothing: the barrier is still there and
      // still closes what is above it, and a barrier with no child shows
      // nothing at all, which is exactly what `ModalBarrier3d` documents.
      child: scrimColor == null
          ? null
          // **A scrim's alpha is spent as coverage, not as a blend**, so the
          // slab is drawn in its colour at full strength and keeps that
          // fraction of its fragments. See `scrimCoverage3d`.
          : SceneFadeTransition3d(
              opacity: scrimFade,
              child: SceneOpacity3d(
                opacity: scrimCoverage3d(scrimColor),
                child: SceneDecoratedBox3d(
                  decoration: BoxDecoration3d(
                    color: scrimColor.withValues(alpha: 1.0),
                  ),
                ),
              ),
            ),
    ),
    child,
  ],
);
