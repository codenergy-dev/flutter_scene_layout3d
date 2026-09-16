// A picture on a panel: the value, the texture that arrives, the arithmetic
// that places it, and the gradient beside it.
//
// Everything here runs headless. The two things that cannot — compiling the
// panel shader and uploading a texture to a GPU — are each behind a seam this
// file stands in for: `ImageTexture3dUpload` for the upload, and
// `Decoration3dPainter` for the drawing. What the frame does with the
// uniforms is `examples/render_probe`'s question.

import 'dart:async' show Completer;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, SynchronousFuture;
import 'package:flutter/painting.dart'
    show
        Alignment,
        AlignmentDirectional,
        BoxFit,
        Color,
        ImageConfiguration,
        ImageDecoderCallback,
        ImageInfo,
        ImageProvider,
        ImageStreamCompleter,
        GradientRotation,
        LinearGradient,
        OneFrameImageStreamCompleter,
        RadialGradient,
        Rect,
        Size,
        SweepGradient,
        TextDirection,
        TileMode;
import 'package:flutter/widgets.dart'
    show
        Builder,
        BuildContext,
        Directionality,
        MediaQuery,
        MediaQueryData,
        SizedBox,
        Widget;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart' show Node, TextureSource;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A texture that never touches a GPU.
///
/// The upload seam's return value is opaque to everything in this package
/// except the painter, which asks it for a `gpu.Texture` — so this reports
/// none and is still the identity the box compares against.
class FakeTexture implements TextureSource {
  @override
  gpu.Texture? get sampledTexture => null;

  @override
  gpu.SamplerOptions get sampledSampler => gpu.SamplerOptions();
}

/// A provider over a picture a test made itself.
///
/// Equality is identity, which is what a test wants: two of these are two
/// different pictures however alike their pixels are.
class TestPicture extends ImageProvider<TestPicture> {
  TestPicture(this.image, {this.scale = 1.0});

  final ui.Image image;
  final double scale;

  @override
  Future<TestPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<TestPicture>(this);

  @override
  ImageStreamCompleter loadImage(
    TestPicture key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.value(ImageInfo(image: image.clone(), scale: scale)),
  );
}

/// A provider whose frames a test delivers by hand.
class ManualPicture extends ImageProvider<ManualPicture> {
  final ManualCompleter completer = ManualCompleter();

  @override
  Future<ManualPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ManualPicture>(this);

  @override
  ImageStreamCompleter loadImage(
    ManualPicture key,
    ImageDecoderCallback decode,
  ) => completer;
}

class ManualCompleter extends ImageStreamCompleter {
  void emit(ui.Image image, {double scale = 1.0}) =>
      setImage(ImageInfo(image: image.clone(), scale: scale));

  void fail(Object exception) => reportError(exception: exception);
}

/// A provider that never produces anything.
class FailingPicture extends ImageProvider<FailingPicture> {
  FailingPicture(this.exception);

  final Object exception;

  @override
  Future<FailingPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FailingPicture>(this);

  @override
  ImageStreamCompleter loadImage(
    FailingPicture key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Future<ImageInfo>.error(exception));
}

/// A picture of [width] by [height], every texel the same colour.
Future<ui.Image> solidImage(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0x40;
    pixels[i + 1] = 0x80;
    pixels[i + 2] = 0xC0;
    pixels[i + 3] = 0xFF;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// A painter that records what it was asked to do, and keeps the callback it
/// was handed so a test can be the picture that arrives late.
class SeamPainter extends Decoration3dPainter {
  SeamPainter() {
    created.add(this);
  }

  static final List<SeamPainter> created = <SeamPainter>[];

  static void reset() => created.clear();

  final List<Decoration3dPaintRequest> paints = <Decoration3dPaintRequest>[];

  Decoration3dPaintRequest get last => paints.last;

  @override
  void paint(Decoration3dPaintRequest request) => paints.add(request);

  @override
  void release(Node node) {}

  @override
  void dispose() {}
}

const Layout3dMetrics metrics = Layout3dMetrics(unitsPerLogicalPixel: 0.01);

/// A decoration over [image], at the box size the fit is measured against.
ImageUniforms3d place(
  DecorationImage3d image, {
  required Size3d size,
  Size? pixelSize = const Size(200, 100),
  double imageScale = 1.0,
  TextDirection? textDirection,
}) => ImageUniforms3d.resolve(
  image: image,
  size: size,
  metrics: metrics,
  pixelSize: pixelSize,
  imageScale: imageScale,
  textDirection: textDirection,
);

void main() {
  setUp(SeamPainter.reset);
  tearDown(() {
    SeamPainter.reset();
    BoxDecoration3d.painterFactory = null;
    GradientUniforms3d.debugResetReports();
  });

  group('ImageTexture3d', () {
    testWidgets('reports the size first and the texture after', (tester) async {
      await tester.runAsync(() async {
        final image = await solidImage(8, 4);
        final uploads = <ImageTexture3dPixels>[];
        final texture = FakeTexture();
        final picture = ImageTexture3d(
          provider: TestPicture(image),
          upload: (pixels) {
            uploads.add(pixels);
            return texture;
          },
        );
        final notices = <String>[];
        picture.addListener(
          () => notices.add(picture.isReady ? 'texture' : 'size'),
        );

        // Nothing yet: a box that asks during layout gets an empty answer and
        // is told later, which is the whole reason this object exists.
        expect(picture.size, isNull);
        expect(picture.isReady, isFalse);

        await pumpEventQueue();
        expect(notices, <String>['size', 'texture']);
        expect(picture.pixelSize, const Size(8, 4));
        expect(picture.size, const Size(8, 4));
        expect(picture.texture, same(texture));
        expect(uploads, hasLength(1));
        expect(uploads.single.width, 8);
        expect(uploads.single.height, 4);
        expect(uploads.single.pixels, hasLength(8 * 4 * 4));
      });
    });

    testWidgets('a provider scale is logical pixels, not texels', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(40, 20);
        final picture = ImageTexture3d(
          provider: TestPicture(image, scale: 2.0),
          upload: (_) => FakeTexture(),
        );
        await pumpEventQueue();
        expect(picture.pixelSize, const Size(40, 20));
        expect(picture.scale, 2.0);
        expect(picture.size, const Size(20, 10));
      });
    });

    testWidgets('an animated picture draws its first frame and stands still', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final first = await solidImage(8, 8);
        final second = await solidImage(16, 16);
        final provider = ManualPicture();
        final picture = ImageTexture3d(
          provider: provider,
          upload: (_) => FakeTexture(),
        );
        provider.completer.emit(first);
        await pumpEventQueue();
        expect(picture.pixelSize, const Size(8, 8));

        // A texture upload per frame is exactly the cost the decoration
        // design exists to avoid, so later frames are not listened for.
        provider.completer.emit(second);
        await pumpEventQueue();
        expect(picture.pixelSize, const Size(8, 8));
      });
    });

    testWidgets('a failure reaches a listener', (tester) async {
      await tester.runAsync(() async {
        final failure = StateError('no such picture');
        final picture = ImageTexture3d(
          provider: FailingPicture(failure),
          upload: (_) => FakeTexture(),
        );
        final seen = <Object>[];
        picture.addErrorListener((exception, stack) => seen.add(exception));
        await pumpEventQueue();
        expect(seen, <Object>[failure]);

        // And one that arrives after the failure hears about it too, which is
        // what keeps a box built late from waiting for a picture that is
        // never coming.
        final late = <Object>[];
        picture.addErrorListener((exception, stack) => late.add(exception));
        expect(late, <Object>[failure]);
      });
    });

    testWidgets('a failure nobody is listening for is reported', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final reported = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reported.add;
        try {
          ImageTexture3d(
            provider: FailingPicture(StateError('no such picture')),
            upload: (_) => FakeTexture(),
          );
          await pumpEventQueue();
        } finally {
          FlutterError.onError = previous;
        }
        expect(reported, hasLength(1));
        expect(reported.single.library, 'flutter_scene_layout3d');
      });
    });
  });

  group('ImageTexture3dCache', () {
    testWidgets('one picture is decoded and uploaded once', (tester) async {
      await tester.runAsync(() async {
        final image = await solidImage(8, 8);
        final provider = TestPicture(image);
        var uploads = 0;
        final cache = ImageTexture3dCache(
          upload: (_) {
            uploads++;
            return FakeTexture();
          },
        );
        final first = cache.acquire(provider);
        final second = cache.acquire(provider);
        expect(second, same(first));
        expect(cache.length, 1);
        await pumpEventQueue();
        expect(uploads, 1);

        cache.release(first);
        expect(cache.length, 1, reason: 'someone is still drawing it');
        cache.release(second);
        expect(cache.length, 0);
        expect(isDisposed(first), isTrue);
      });
    });

    testWidgets('the reading direction does not split the cache', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(4, 4);
        final provider = TestPicture(image);
        final cache = ImageTexture3dCache(upload: (_) => FakeTexture());
        final ltr = cache.acquire(
          provider,
          const ImageConfiguration(textDirection: TextDirection.ltr),
        );
        final rtl = cache.acquire(
          provider,
          const ImageConfiguration(textDirection: TextDirection.rtl),
        );
        // Which way the text runs decides where a picture is *placed*, not
        // which pixels it has.
        expect(rtl, same(ltr));
        expect(cache.length, 1);
      });
    });

    testWidgets('a different device pixel ratio is a different picture', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(4, 4);
        final provider = TestPicture(image);
        final cache = ImageTexture3dCache(upload: (_) => FakeTexture());
        final low = cache.acquire(
          provider,
          const ImageConfiguration(devicePixelRatio: 1.0),
        );
        final high = cache.acquire(
          provider,
          const ImageConfiguration(devicePixelRatio: 3.0),
        );
        // An asset resolves a different variant at each, which is the whole
        // reason the configuration is part of the key.
        expect(high, isNot(same(low)));
        expect(cache.length, 2);
      });
    });
  });

  group('ImageUniforms3d', () {
    const image = DecorationImage3d(image: _NullProvider());

    test('a picture that has not arrived draws nothing', () {
      expect(
        place(image, size: const Size3d(4, 2, 0), pixelSize: null).isNone,
        isTrue,
      );
    });

    test('cover fills the box and keeps the middle of the picture', () {
      // A 200x100 picture in a box 2 units by 2 — 200dp by 200dp at this
      // rate. Covering it means scaling to the height and cutting the sides.
      final placed = place(
        const DecorationImage3d(image: _NullProvider(), fit: BoxFit.cover),
        size: const Size3d(2, 2, 0),
      );
      expect(placed.destination, const Rect.fromLTWH(0, 0, 2, 2));
      expect(placed.source.left, closeTo(0.25, 1e-9));
      expect(placed.source.right, closeTo(0.75, 1e-9));
      expect(placed.source.top, 0.0);
      expect(placed.source.bottom, 1.0);
    });

    test('contain leaves the box uncovered, and says where', () {
      final placed = place(
        const DecorationImage3d(image: _NullProvider(), fit: BoxFit.contain),
        size: const Size3d(2, 2, 0),
      );
      // The whole picture, half as tall as it is wide, centred.
      expect(placed.source, const Rect.fromLTRB(0, 0, 1, 1));
      expect(placed.destination.width, closeTo(2.0, 1e-9));
      expect(placed.destination.height, closeTo(1.0, 1e-9));
      expect(placed.destination.top, closeTo(0.5, 1e-9));
    });

    test('none keeps the picture at its own logical size', () {
      // 200 by 100 logical pixels is 2 by 1 world units at a hundredth of a
      // unit each, whatever the box is.
      final placed = place(
        const DecorationImage3d(image: _NullProvider(), fit: BoxFit.none),
        size: const Size3d(4, 4, 0),
      );
      expect(placed.destination.width, closeTo(2.0, 1e-9));
      expect(placed.destination.height, closeTo(1.0, 1e-9));
      expect(placed.destination.left, closeTo(1.0, 1e-9));
    });

    test("a provider's own scale shrinks the picture, not the box", () {
      final placed = place(
        const DecorationImage3d(image: _NullProvider(), fit: BoxFit.none),
        size: const Size3d(4, 4, 0),
        imageScale: 2.0,
      );
      expect(placed.destination.width, closeTo(1.0, 1e-9));
      expect(placed.destination.height, closeTo(0.5, 1e-9));
    });

    test('an alignment moves the destination and the source', () {
      final contained = place(
        const DecorationImage3d(
          image: _NullProvider(),
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
        ),
        size: const Size3d(2, 2, 0),
      );
      expect(contained.destination.top, 0.0);

      final covered = place(
        const DecorationImage3d(
          image: _NullProvider(),
          fit: BoxFit.cover,
          alignment: Alignment.centerLeft,
        ),
        size: const Size3d(2, 2, 0),
      );
      expect(covered.source.left, 0.0);
      expect(covered.source.right, closeTo(0.5, 1e-9));
    });

    test('a directional alignment reads the direction it is given', () {
      final rtl = place(
        const DecorationImage3d(
          image: _NullProvider(),
          fit: BoxFit.contain,
          alignment: AlignmentDirectional.centerStart,
        ),
        size: const Size3d(4, 2, 0),
        textDirection: TextDirection.rtl,
      );
      // Start is the right in a right-to-left reading, so the picture sits
      // against the far edge.
      expect(rtl.destination.right, closeTo(4.0, 1e-9));
    });

    test('matchTextDirection mirrors the source, not the destination', () {
      const mirrored = DecorationImage3d(
        image: _NullProvider(),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        matchTextDirection: true,
      );
      final ltr = place(
        mirrored,
        size: const Size3d(4, 2, 0),
        textDirection: TextDirection.ltr,
      );
      final rtl = place(
        mirrored,
        size: const Size3d(4, 2, 0),
        textDirection: TextDirection.rtl,
      );
      expect(rtl.destination, ltr.destination);
      expect(rtl.source.left, ltr.source.right);
      expect(rtl.source.right, ltr.source.left);
    });

    test('no opacity is nothing to draw', () {
      expect(
        place(
          const DecorationImage3d(image: _NullProvider(), opacity: 0.0),
          size: const Size3d(2, 2, 0),
        ).isNone,
        isTrue,
      );
    });
  });

  group('GradientUniforms3d', () {
    const size = Size3d(4, 2, 0);
    const colors = <Color>[Color(0xFFFF0000), Color(0xFF0000FF)];

    test('a linear gradient runs between the points its alignments name', () {
      final resolved = GradientUniforms3d.resolve(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
        ),
        size: size,
      )!;
      expect(resolved.kind, GradientKind3d.linear);
      expect(resolved.geometry, <double>[0, 1, 4, 1]);
      expect(resolved.stops, <double>[0.0, 1.0]);
      expect(resolved.descriptor, <double>[
        1,
        TileMode.clamp.index * 1.0,
        2,
        0,
      ]);
    });

    test('a directional gradient begins on the right in right to left', () {
      final resolved = GradientUniforms3d.resolve(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: colors,
        ),
        size: size,
        textDirection: TextDirection.rtl,
      )!;
      expect(resolved.geometry.take(2), <double>[4, 1]);
    });

    test("a radial gradient's radius is a fraction of the shorter side", () {
      final resolved = GradientUniforms3d.resolve(
        gradient: const RadialGradient(colors: colors),
        size: size,
      )!;
      expect(resolved.kind, GradientKind3d.radial);
      // Flutter's default radius is 0.5, and the shorter side here is 2.
      expect(resolved.geometry, <double>[2, 1, 1, 0]);
    });

    test('a sweep gradient carries its two angles', () {
      final resolved = GradientUniforms3d.resolve(
        gradient: const SweepGradient(
          colors: colors,
          startAngle: 0.5,
          endAngle: 2.5,
          tileMode: TileMode.repeated,
        ),
        size: size,
      )!;
      expect(resolved.kind, GradientKind3d.sweep);
      expect(resolved.geometry, <double>[2, 1, 0.5, 2.5]);
      expect(resolved.tileMode, TileMode.repeated);
    });

    test('stops default to evenly spaced, as Flutter does', () {
      expect(
        GradientUniforms3d.stopsOf(const <Color>[
          Color(0xFF000000),
          Color(0xFF111111),
          Color(0xFF222222),
        ], null),
        <double>[0.0, 0.5, 1.0],
      );
    });

    test('more than eight stops are resampled off the ramp', () {
      final many = <Color>[
        for (var i = 0; i < 12; i++) Color(0xFF000000 + i * 0x010101),
      ];
      final resolved = GradientUniforms3d.resolve(
        gradient: LinearGradient(colors: many),
        size: size,
      )!;
      expect(resolved.colors, hasLength(GradientUniforms3d.maxStops));
      expect(resolved.stops.first, 0.0);
      expect(resolved.stops.last, 1.0);
      // The ends are exact; the middle is the ramp read at that position.
      expect(resolved.colors.first, many.first);
      expect(resolved.colors.last, many.last);
    });

    test('a gradient transform is refused, and says so once', () {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      final gradient = LinearGradient(
        colors: colors,
        transform: const GradientRotation(0.5),
      );
      try {
        expect(
          GradientUniforms3d.resolve(gradient: gradient, size: size),
          isNull,
        );
        expect(
          GradientUniforms3d.resolve(gradient: gradient, size: size),
          isNull,
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(reported, hasLength(1));
    });

    test("a radial gradient's focal point is refused", () {
      final previous = FlutterError.onError;
      FlutterError.onError = (_) {};
      try {
        expect(
          GradientUniforms3d.resolve(
            gradient: const RadialGradient(
              colors: colors,
              focal: Alignment.topLeft,
            ),
            size: size,
          ),
          isNull,
        );
      } finally {
        FlutterError.onError = previous;
      }
    });

    test('the ramp is read the way Skia reads it', () {
      const stops = <double>[0.0, 0.5, 0.5, 1.0];
      const ramp = <Color>[
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
      ];
      expect(GradientUniforms3d.colorAt(ramp, stops, -1.0), ramp.first);
      expect(GradientUniforms3d.colorAt(ramp, stops, 2.0), ramp.last);
      // A hard stop: two positions at one place, and nothing in between.
      expect(GradientUniforms3d.colorAt(ramp, stops, 0.49).r, lessThan(0.5));
      expect(GradientUniforms3d.colorAt(ramp, stops, 0.51).r, greaterThan(0.5));
    });

    test('the uniforms resolve a decoration gradient against its box', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(
          gradient: LinearGradient(colors: colors),
        ),
        size: const Size3d(4, 2, 0),
        metrics: metrics,
      );
      expect(uniforms.gradient, isNotNull);
      expect(uniforms.gradient!.kind, GradientKind3d.linear);
      expect(uniforms.image.isNone, isTrue);
    });
  });

  group('BoxDecoration3d with a picture', () {
    const picture = DecorationImage3d(image: _NullProvider());
    const other = DecorationImage3d(image: _NullProvider(tag: 1));

    test('the picture and the gradient are part of the value', () {
      const plain = BoxDecoration3d(color: Color(0xFF123456));
      expect(plain.copyWith(image: picture), isNot(plain));
      expect(
        plain.copyWith(image: picture),
        const BoxDecoration3d(color: Color(0xFF123456), image: picture),
      );
      expect(
        plain.copyWith(image: picture).hashCode,
        const BoxDecoration3d(
          color: Color(0xFF123456),
          image: picture,
        ).hashCode,
      );
    });

    test('a picture appearing fades in', () {
      final half = BoxDecoration3d.lerp(
        const BoxDecoration3d(),
        const BoxDecoration3d(image: picture),
        0.5,
      );
      expect(half.image!.image, picture.image);
      expect(half.image!.opacity, closeTo(0.5, 1e-9));
    });

    test('two different pictures change at the midpoint', () {
      // One sampler holds one picture, so this is a step rather than a
      // cross-fade — and saying which step is the whole of the decision.
      expect(
        BoxDecoration3d.lerp(
          const BoxDecoration3d(image: picture),
          const BoxDecoration3d(image: other),
          0.4,
        ).image,
        picture,
      );
      expect(
        BoxDecoration3d.lerp(
          const BoxDecoration3d(image: picture),
          const BoxDecoration3d(image: other),
          0.6,
        ).image,
        other,
      );
    });

    test('a gradient interpolates through Flutter’s own lerp', () {
      final half = BoxDecoration3d.lerp(
        const BoxDecoration3d(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFF000000), Color(0xFF000000)],
          ),
        ),
        const BoxDecoration3d(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
          ),
        ),
        0.5,
      );
      final gradient = half.gradient! as LinearGradient;
      expect(gradient.colors.first.r, closeTo(0.5, 0.05));
    });
  });

  group('the seam a late picture arrives through', () {
    test('a painter is handed a way to ask for another paint', () {
      final box = DecoratedBox3d(decoration: const _SeamDecoration());
      laidOut(box);
      final painter = SeamPainter.created.single;
      expect(painter.paints, hasLength(1));

      // This is what the picture's own listener does: it cannot draw, and it
      // cannot lay out. It asks the box for another paint, and is handed the
      // box's current size, state and clip.
      painter.last.onChanged!();
      expect(painter.paints, hasLength(2));
      expect(painter.last.size, painter.paints.first.size);
    });

    test('the image configuration reaches the painter', () {
      const configuration = ImageConfiguration(
        devicePixelRatio: 3.0,
        textDirection: TextDirection.rtl,
      );
      final box = DecoratedBox3d(
        decoration: const _SeamDecoration(),
        configuration: configuration,
      );
      laidOut(box);
      final painter = SeamPainter.created.single;
      expect(painter.last.configuration, configuration);
    });

    test('a new configuration repaints and lays nothing out', () {
      final child = TestBox(const Size3d(1, 1, 0));
      final box = DecoratedBox3d(
        decoration: const _SeamDecoration(),
        child: child,
      );
      laidOut(box);
      final painter = SeamPainter.created.single;
      final layouts = child.layoutCount;
      final paints = painter.paints.length;

      box.configuration = const ImageConfiguration(devicePixelRatio: 2.0);
      expect(child.layoutCount, layouts);
      expect(painter.paints.length, paints + 1);
    });
  });

  group('Image3d', () {
    testWidgets('is as small as it may be until the picture arrives', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(200, 100);
        final cache = ImageTexture3dCache(upload: (_) => FakeTexture());
        final box = Image3d(image: TestPicture(image), pictures: cache);
        final surface = laidOut(
          box,
          constraints: const Constraints3d(maxWidth: 4, maxHeight: 4),
          metrics: metrics,
        );
        expect(box.size, Size3d.zero);

        // And it lays out again when the size is known, which is the one
        // thing an image on a *decoration* never does.
        await pumpEventQueue();
        surface.flush();
        expect(box.size, const Size3d(2, 1, 0));
        box.dispose();
        expect(cache.length, 0);
      });
    });

    testWidgets('keeps the picture’s shape inside constraints it cannot fill', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(200, 100);
        final cache = ImageTexture3dCache(upload: (_) => FakeTexture());
        final box = Image3d(image: TestPicture(image), pictures: cache);
        final surface = laidOut(
          box,
          constraints: const Constraints3d(maxWidth: 1, maxHeight: 4),
          metrics: metrics,
        );
        await pumpEventQueue();
        surface.flush();
        // A 2-by-1 picture held to one unit wide is half a unit tall, rather
        // than one unit of whatever room was left.
        expect(box.size.width, closeTo(1.0, 1e-9));
        expect(box.size.height, closeTo(0.5, 1e-9));
        box.dispose();
      });
    });

    testWidgets('asks for its own extent, and gives it up under pressure', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await solidImage(200, 100);
        final cache = ImageTexture3dCache(upload: (_) => FakeTexture());
        final box = Image3d(image: TestPicture(image), pictures: cache);
        final surface = laidOut(box, metrics: metrics);
        await pumpEventQueue();
        surface.flush();

        expect(box.getMinIntrinsicExtent(Axis3d.horizontal), 0.0);
        expect(
          box.getMaxIntrinsicExtent(Axis3d.horizontal),
          closeTo(2.0, 1e-9),
        );
        // Asked how tall it would be in one unit of width, it answers the
        // shape it keeps.
        expect(
          box.getMaxIntrinsicExtent(Axis3d.vertical, const Size3d(1, 0, 0)),
          closeTo(0.5, 1e-9),
        );
        box.dispose();
      });
    });
  });

  group('the widget forms', () {
    testWidgets('SceneImage3d builds an Image3d and updates it', (
      tester,
    ) async {
      final image = await tester.runAsync(() => solidImage(8, 8));
      final provider = TestPicture(image!);
      final controller = Layout3dController();

      Widget screen(BoxFit fit) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 0.1),
        controller: controller,
        child: SceneImage3d(image: provider, fit: fit),
      );

      await tester.pumpWidget(screen(BoxFit.contain));
      final box = controller.surface!.child! as Image3d;
      expect(box.fit, BoxFit.contain);
      // The configuration comes from the tree, so an asset would pick the
      // variant the window's device pixel ratio asks for.
      expect(box.configuration.devicePixelRatio, isNotNull);

      await tester.pumpWidget(screen(BoxFit.cover));
      expect(controller.surface!.child!, same(box));
      expect(box.fit, BoxFit.cover);
    });

    testWidgets('a decorated box with a picture reads the ambient direction', (
      tester,
    ) async {
      const decoration = BoxDecoration3d(
        image: DecorationImage3d(image: _NullProvider()),
      );
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3.0),
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final configuration = SceneDecoratedBox3d.configurationFor(
        captured,
        decoration,
      );
      expect(configuration.textDirection, TextDirection.rtl);
      expect(configuration.devicePixelRatio, 3.0);

      // A panel with nothing but a colour on it asks for none of that, so it
      // does not depend on the media query to draw.
      expect(
        SceneDecoratedBox3d.configurationFor(captured, const BoxDecoration3d()),
        ImageConfiguration.empty,
      );
    });
  });

  group('the slab a picture is drawn on', () {
    test('a box with no thickness is still drawn with a normal', () {
      // A picture's box has no depth — `Image3d` takes what its constraints
      // allow, and a loose surface allows none — and a slab scaled to exactly
      // zero on an axis has a singular transform, which is a normal matrix of
      // nothing. The panel shader is lit, so such a slab comes out **black**,
      // which reads as a picture that failed to bind rather than as geometry
      // with no normal. The render probe found it on the first frame it drew
      // an `Image3d`.
      final flat = BoxDecoration3dPainter.slabTransformFor(
        const Size3d(2, 1, 0),
      );
      expect(flat.determinant(), isNot(0.0));
      final scale = flat.getMaxScaleOnAxis();
      expect(scale, closeTo(2.0, 1e-9));

      // And a box that does have a thickness is scaled to exactly it.
      final slab = BoxDecoration3dPainter.slabTransformFor(
        const Size3d(2, 1, 0.5),
      );
      expect(slab.getTranslation().z, closeTo(0.25, 1e-9));
      expect(slab.entry(2, 2), closeTo(0.5, 1e-9));
    });
  });

  group('Constraints3d.constrainSizeAndAttemptToPreserveAspectRatio', () {
    test('keeps the ratio in the plane and constrains depth on its own', () {
      const constraints = Constraints3d(
        maxWidth: 2,
        maxHeight: 10,
        minDepth: 0.4,
        maxDepth: 0.4,
      );
      final size = constraints.constrainSizeAndAttemptToPreserveAspectRatio(
        const Size3d(4, 2, 0),
      );
      expect(size, const Size3d(2, 1, 0.4));
    });

    test('a tight box is that box', () {
      final size = Constraints3d.tight(
        const Size3d(3, 3, 0),
      ).constrainSizeAndAttemptToPreserveAspectRatio(const Size3d(4, 2, 0));
      expect(size, const Size3d(3, 3, 0));
    });
  });
}

/// A decoration whose painter is the seam recorder.
class _SeamDecoration extends Decoration3d {
  const _SeamDecoration();

  @override
  Object get cacheKey => _SeamDecoration;

  @override
  bool shouldRebuild(_SeamDecoration old) => false;

  @override
  Decoration3dPainter? createPainter() => SeamPainter();
}

/// A provider that is never resolved: the placement arithmetic never touches
/// one, so the tests above name a picture without loading it.
class _NullProvider extends ImageProvider<_NullProvider> {
  const _NullProvider({this.tag = 0});

  final int tag;

  @override
  Future<_NullProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NullProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _NullProvider key,
    ImageDecoderCallback decode,
  ) => throw UnimplementedError('this picture is never loaded');

  @override
  bool operator ==(Object other) => other is _NullProvider && other.tag == tag;

  @override
  int get hashCode => tag;
}
