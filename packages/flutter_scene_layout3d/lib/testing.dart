/// Testing a 3D screen the way a person uses it: find a box, press it through
/// the camera, and ask the layout what a picture would show.
///
/// The counterpart of `flutter_test`'s widget finders and gestures for the
/// layout tree, built on `flutter_test`'s own `FinderBase` so the matchers a
/// Flutter test already uses — `findsOne`, `findsNothing` — work unchanged.
///
/// ```dart
/// testWidgets('the settings destination opens the settings', (tester) async {
///   await tester.pumpSurface3d(const SettingsScreen());
///
///   await tester.tap3d(find3d.bySemanticsLabel('Settings'));
///   await tester.pump();
///
///   expect(find3d.bySemanticsLabel('Volume'), findsOne);
///   expect(find3d.bySemanticsLabel('Volume'), isReachable3d);
///   expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
/// });
/// ```
///
/// Everything here is headless: nothing draws, because drawing needs a GPU
/// `flutter test` does not have. What the layout can answer — whether a
/// control can be pressed, how big it is, whether it is hidden inside the
/// slab it is written on — is answered here. What only a frame can answer is
/// not, and `examples/render_probe` is where that is photographed.
///
/// This library depends on `flutter_test`, which is why it is a library of
/// its own: import it from tests only.
library;

export 'src/testing/finders.dart'
    show CommonLayout3dFinders, Layout3dFinder, find3d;
export 'src/testing/matchers.dart'
    show hasSize3d, hasSizeDp, isReachable3d, standsOnItsPanel3d;
export 'src/testing/tester.dart' show Layout3dWidgetTester, cameraFacing3d;
