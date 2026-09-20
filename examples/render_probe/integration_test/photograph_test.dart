// Photographs of the gallery, taken on a real GPU and kept.
//
//   flutter drive --driver=test_driver/photograph.dart \
//     --target=integration_test/photograph_test.dart \
//     -d macos --enable-flutter-gpu
//
// The PNGs land in `build/photographs/`. CI uploads them from every run.
//
// This is not a probe. A probe asks one sharp question of a frame and fails
// when the answer is wrong; a photograph asks nothing beyond "did a frame come
// out", because the question it exists for — *is anything obviously wrong?* —
// is a person's. Ten of the worst defects this repository has shipped were
// invisible to every suite and every probe and were found by someone looking
// at the gallery's window. This is that window, on every run, without anyone
// having to start it.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show GlyphAtlasCache3d;
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart'
    show initializeMaterial3d;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:layout3d_gallery/main.dart' show Layout3dGalleryApp;
import 'photograph.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void keep(Photograph photograph) {
    final report = binding.reportData ??= <String, dynamic>{};
    ((report['screenshots'] ??= <dynamic>[]) as List<dynamic>).add(
      photograph.report,
    );
  }

  /// The floor a probe asserts, and nothing above it: the frame cleared, and
  /// something lit drew over a real share of it.
  void expectAFrame(Photograph photograph) {
    final frame = photograph.frame;
    expect(
      frame.cornersClear,
      isTrue,
      reason: '${photograph.name}: the corners are not the backdrop',
    );
    expect(
      frame.coverage,
      greaterThan(0.1),
      reason: '${photograph.name}: almost nothing drew',
    );
    expect(
      frame.foregroundMeanLuma,
      greaterThan(20),
      reason: '${photograph.name}: what drew is ~black; did lighting break?',
    );
  }

  testWidgets('the gallery, and the gallery a few seconds later', (
    tester,
  ) async {
    final first = await photograph(
      tester,
      const Layout3dGalleryApp(),
      name: 'gallery',
      initialize: initializeMaterial3d,
    );
    keep(first);
    expectAFrame(first);

    // The upright screen turns on a slow sine. Turning is a question of its
    // own — four of this repository's defects only showed at an angle — so
    // the second photograph is the same scene from somewhere else.
    final later = await photographAgain(
      tester,
      name: 'gallery_later',
      frames: 240,
    );
    keep(later);
    expectAFrame(later);

    // And the screen with something in front of it, which no photograph used
    // to take. Five of the catalogue's six arrivals and the whole of the
    // overlay lift had nowhere a person could look at them: the gallery sat
    // idle in every frame anyone ever kept. It is the third lane's job to
    // answer *is anything obviously wrong*, and it cannot answer for a state
    // it never gets into.
    //
    // This is what found the scrim sitting behind the app bar and behind the
    // floating action button, dimming neither.
    await tester.tap3d(find3d.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap3d(find3d.bySemanticsLabel('About'));

    // **And the dialog while it is still arriving**, which is a different
    // question from the dialog. The About dialog carries a paragraph of
    // `bodyMedium` — dozens of letters the screen behind it has never drawn,
    // in a style it is already using — so opening it repacks that style's
    // atlas, and for the few frames the rasterization takes, every coordinate
    // the atlas hands out describes a picture that does not exist yet. That
    // window is where `Noti▓ications` and `Lovel ce` lived. See
    // `plans/2026_09_17_a_letter_that_comes_back_wrong.md`.
    //
    // Ten frames rather than sixty, and the number is the whole point: at
    // three the menu is still closing, at sixty everything has settled and
    // there is nothing left to see. **Opening the overlay several times does
    // not help** — that was the obvious thing to try and it is wrong, because
    // after the first opening every letter is packed and no repack follows.
    // Early is the only way in.
    //
    // It is a photograph and not a probe, and the reason is worth stating
    // rather than discovering: with the defect deliberately put back, this
    // frame came out **correct** — the window is a race against a texture
    // readback and it is not open on every run or every machine. What pins
    // the defect is `atlas_text_renderer_test.dart`, which drives the same
    // cycle with no clock in it at all. This is here so that a person has
    // somewhere to see it, which is the only lane that ever saw it.
    keep(
      await photographAgain(
        tester,
        name: 'gallery_dialog_arriving',
        frames: 10,
      ),
    );

    final dialog = await photographAgain(
      tester,
      name: 'gallery_dialog',
      frames: 60,
    );
    keep(dialog);
    expectAFrame(dialog);

    // The one thing here that is a probe rather than a photograph, and it is
    // in this lane because nowhere else is there a real screen with real
    // overlays over it. A label whose atlas has repacked waits for the new
    // picture before it bakes again, and that wait is safe only because an
    // atlas that owes a raster always delivers one. If any atlas is still
    // behind after everything has settled, every label baked against it is
    // holding letters it will never be able to draw.
    for (final atlas in GlyphAtlasCache3d.shared.atlases) {
      expect(
        atlas.textureIsCurrent,
        isTrue,
        reason:
            '$atlas never rasterized the packing it is handing out, so every '
            'label measured against it is waiting for a picture that is not '
            'coming',
      );
    }
  });
}
