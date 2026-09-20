// The gallery, driven through a person's reproduction recipe, in a real
// window, photographed at every step.
//
//   cd examples/render_probe
//   flutter run -d macos --enable-flutter-gpu -t lib/main_self_drive.dart \
//     --dart-define=report_repacks=true
//
// The recipe is the one a person found, and the order of it is the finding:
// open the window small, let the layout settle, **maximize**, and only then
// start changing what is on the screen. Exploring first and maximizing after
// produces nothing.
//
// See `lib/self_drive.dart` for why this is a harness of its own and not a
// `flutter drive` test, and *Driving the real window* in `README.md`.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show debugReportGlyphAtlasRepacks, debugVerifyGlyphAtlasInk;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart'
    show initializeMaterial3d;
import 'package:layout3d_gallery/main.dart' show Layout3dGalleryApp;

import 'self_drive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugReportGlyphAtlasRepacks = const bool.fromEnvironment(
    'report_repacks',
    defaultValue: true,
  );
  // On for a scripted run: the cost is a scan of the atlas per flush, and what
  // it buys is the difference between *the mesh is pointing at the wrong
  // address* and *the address is right and nothing was drawn there*.
  debugVerifyGlyphAtlasInk = true;
  await initializeMaterial3d();
  // **The application, whole.** Not its screen widget under a `MaterialApp`
  // of this file's own: the first run of this harness did that, and every
  // glyph in every atlas came back with a double rule under it — Flutter's
  // `_errorTextStyle`, which is what a `Text` resolves to with no `Material`
  // above it, and whose `decoration` a `Text3d` inherits and the atlas bakes.
  // The harness has to photograph the application a person runs.
  runApp(selfDriveBoundary(const Layout3dGalleryApp()));
  unawaited(SelfDrive.start(_script));
}

/// What the run does, in order.
///
/// Each step is *an act, then real time, then a photograph*. The settle times
/// are long where something asynchronous has to land — a window animating to
/// full screen, a glyph atlas reading a texture back, which measures 700–900ms
/// on the machine this was written against — and short where the question is
/// what the frame looks like **while** something is still arriving.
final List<SelfDriveStep> _script = <SelfDriveStep>[
  // **Small first, and it has to be said rather than assumed**: macOS
  // restores the frame the window last had, so a run after a maximized one
  // starts maximized and the recipe's first half never happens.
  SelfDriveStep(
    'small_settled',
    act: SelfDrive.restore,
    settle: const Duration(seconds: 4),
  ),

  // The pictures the atlases are handing out, beside the frame drawn from
  // them. A letter drawn wrong is either a wrong coordinate or a wrong
  // picture, and only this says which.
  SelfDriveStep('atlases_early', act: SelfDrive.dumpAtlases),

  // The resize itself. macOS animates it, so the wait is for the animation and
  // not only for the frame.
  SelfDriveStep(
    'maximized',
    act: SelfDrive.zoom,
    settle: const Duration(seconds: 3),
  ),

  // From here on the screen changes, which is the half of the recipe that
  // matters: a maximized window that is never touched again shows nothing.
  SelfDriveStep(
    'menu_open',
    act: () => SelfDrive.tap('More'),
    settle: const Duration(milliseconds: 150),
    dumpAtlases: true,
  ),
  // Early on purpose. The About dialog carries a paragraph of letters the
  // screen behind it has never drawn, in a style it is already using, so
  // opening it repacks that style's atlas — and the frames worth looking at
  // are the ones before the readback lands, not after.
  SelfDriveStep(
    'dialog_arriving',
    act: () => SelfDrive.tap('About'),
    settle: const Duration(milliseconds: 120),
    dumpAtlases: true,
  ),
  const SelfDriveStep('dialog_settled', settle: Duration(seconds: 1)),
  SelfDriveStep('dialog_dismissed', act: () => SelfDrive.tap('Close')),

  SelfDriveStep('settings', act: () => SelfDrive.tap('Settings')),
  const SelfDriveStep('settings_settled', settle: Duration(seconds: 1)),
  SelfDriveStep('inbox_again', act: () => SelfDrive.tap('Inbox')),

  SelfDriveStep(
    'scrolled',
    act: () => SelfDrive.scroll('Inbox', const Offset(0, 220)),
    settle: const Duration(milliseconds: 400),
  ),
  SelfDriveStep(
    'scrolled_more',
    act: () => SelfDrive.scroll('Inbox', const Offset(0, 320)),
    settle: const Duration(milliseconds: 400),
  ),

  SelfDriveStep('menu_again', act: () => SelfDrive.tap('More')),
  SelfDriveStep(
    'sort_arriving',
    act: () => SelfDrive.tap('Sort by'),
    settle: const Duration(milliseconds: 120),
    dumpAtlases: true,
  ),
  const SelfDriveStep('sort_settled', settle: Duration(seconds: 1)),

  // And the state the artifacts were photographed in: everything settled,
  // nothing open, a while after the last thing happened.
  const SelfDriveStep('idle_after', settle: Duration(seconds: 3)),
  SelfDriveStep(
    'atlases_late',
    act: () => SelfDrive.dumpAtlases(prefix: 'late'),
  ),
];
