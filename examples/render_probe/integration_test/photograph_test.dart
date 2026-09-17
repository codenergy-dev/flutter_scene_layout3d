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
    final dialog = await photographAgain(
      tester,
      name: 'gallery_dialog',
      frames: 60,
    );
    keep(dialog);
    expectAFrame(dialog);
  });
}
