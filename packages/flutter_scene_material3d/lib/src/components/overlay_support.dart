// The pieces every overlay in this catalogue shares: the depth it sits at,
// the modal frame around it, and the way it finds somewhere to be put.

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
    show SceneDecoratedBox3d, SceneModalBarrier3d, SceneOverlay3d, SceneStack3d;

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
Widget modalFrame3d({
  required Widget child,
  required Color? scrimColor,
  required double scrimThickness,
  required double depthStep,
  required bool dismissible,
  required VoidCallback onDismiss,
  Alignment3d alignment = Alignment3d.center,
}) => SceneStack3d(
  alignment: alignment,
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
          : SceneDecoratedBox3d(decoration: BoxDecoration3d(color: scrimColor)),
    ),
    child,
  ],
);
