// What an `AtlasText3dRenderer` binds, and when it bakes again.
//
// The renderer's arithmetic is checked in `text_atlas_test.dart`; this is its
// *coordination* with the atlas behind it, which is where the defects have
// been. A mesh's texture coordinates and the texture they sample are a pair,
// and every bug in this file's history is the two halves of that pair coming
// from different generations of the atlas:
//
// - a panel that had stopped laying out lost its labels, because a repack
//   under someone else's glyph left its UVs stale and nothing re-baked them;
// - a settled screen drew `Noti▓ications` and `Lovel ce`, because it re-baked
//   them against a packing the uploaded texture was not a picture of.
//
// Both are invisible to a render probe: one needs two lots of type and a
// shared atlas, the other needs the frames between a repack and the
// rasterization that follows it. So the GPU step is behind
// `GlyphGeometryUpload3d`, and everything else runs here.

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene/scene.dart' show Node, TextureSource;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle style = TextStyle(fontSize: 10);

/// A glyph material that never builds an engine material and remembers what
/// it was pointed at.
class RecordingGlyphMaterial implements GlyphMaterial3d {
  /// Every material made since the last [reset], oldest first.
  static final List<RecordingGlyphMaterial> made = <RecordingGlyphMaterial>[];

  static void reset() => made.clear();

  /// The material the renderer is drawing with, or null before its first
  /// bake.
  static RecordingGlyphMaterial? get current => made.isEmpty ? null : made.last;

  RecordingGlyphMaterial() {
    made.add(this);
  }

  /// What [bindAtlas] was last handed. Null means *draw nothing*.
  Object? bound;

  /// How many times it was handed anything at all.
  int binds = 0;

  @override
  Never get material =>
      throw UnimplementedError('a headless test uploads no geometry');

  @override
  void bindAtlas(Object? atlas) {
    bound = atlas;
    binds++;
  }

  @override
  void tint(Object color) {}

  @override
  void fade(double opacity) {}
}

/// The wall around a glyph, which has no texture and so cannot be stopped by
/// binding one. It has to be told.
class RecordingWallMaterial implements GlyphWallMaterial3d {
  static final List<RecordingWallMaterial> made = <RecordingWallMaterial>[];

  static void reset() => made.clear();

  static RecordingWallMaterial? get current => made.isEmpty ? null : made.last;

  RecordingWallMaterial() {
    made.add(this);
  }

  /// The coverage the wall is drawing at. Zero is *not drawn at all*.
  double opacity = 1.0;

  @override
  Never get material =>
      throw UnimplementedError('a headless test uploads no geometry');

  @override
  void fade(double value) => opacity = value;
}

/// A texture that is not one, so a test can tell two pictures apart.
class FakeTexture implements TextureSource {
  FakeTexture(this.generation);

  /// The [GlyphAtlas3d.generation] the atlas was at when this was uploaded.
  final int generation;

  @override
  String toString() => 'FakeTexture(generation $generation)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An atlas whose uploads are fake textures a test can identify.
GlyphAtlasCache3d cacheOf({int initialSize = 64, int maxSize = 512}) =>
    GlyphAtlasCache3d(
      initialSize: initialSize,
      maxSize: maxSize,
      upload: (image) => FakeTexture(image.generation),
      // Explicitly the slow path: there is no GPU here to wrap a picture with,
      // and saying so beats letting the default fail into the fallback.
      uploadPicture: (picture) => null,
    );

/// A renderer with no thickness, so it never makes a wall material and the
/// one a wall test is looking at is unambiguously the label's own.
AtlasText3dRenderer flatRendererOn(GlyphAtlasCache3d atlases) =>
    AtlasText3dRenderer(
      atlases: atlases,
      resolution: 1.0,
      depth: 0.0,
      upload: (builder) => null,
    );

/// A renderer that does all of its bookkeeping and none of its uploads.
AtlasText3dRenderer rendererOn(GlyphAtlasCache3d atlases) =>
    AtlasText3dRenderer(
      atlases: atlases,
      resolution: 1.0,
      // The seam: the coordination runs, `GeometryBuilder.build` does not.
      upload: (builder) => null,
    );

TextLayout3d layoutOf(String text, [TextStyle textStyle = style]) {
  final measurement = SegmentedTextMeasurement3d();
  return measurement.layout(
    measurement.prepare(text, textStyle),
    minWidth: 0.0,
    maxWidth: double.infinity,
  );
}

/// Renders [text] through [renderer], the way a `Text3d` does after a layout.
void render(
  AtlasText3dRenderer renderer,
  Node node,
  TextLayout3d layout, {
  double opacity = 1.0,
  TextStyle textStyle = style,
}) => renderer.render(
  Text3dRenderRequest(
    node: node,
    layout: layout,
    style: textStyle,
    size: const Size3d(200.0, 20.0, 1.0),
    basis: LayoutBasis3d.xy,
    unitsPerLogicalPixel: 1.0,
    logicalPixelsPerUnit: 1.0,
    opacity: opacity,
  ),
);

void main() {
  setUp(() {
    RecordingGlyphMaterial.reset();
    RecordingWallMaterial.reset();
    GlyphMaterial3d.factory = RecordingGlyphMaterial.new;
    GlyphWallMaterial3d.factory = RecordingWallMaterial.new;
  });
  tearDown(() {
    GlyphMaterial3d.factory = UnlitGlyphMaterial3d.new;
    GlyphWallMaterial3d.factory = UnlitGlyphWallMaterial3d.new;
    RecordingGlyphMaterial.reset();
    RecordingWallMaterial.reset();
  });

  group('a label binds', () {
    test('nothing at all until the atlas has rasterized anything', () {
      final renderer = rendererOn(cacheOf());
      addTearDown(renderer.dispose);
      render(renderer, Node(), layoutOf('abc'));
      expect(renderer.quadCount, 3);
      expect(
        RecordingGlyphMaterial.current!.bound,
        isNull,
        reason:
            'a material with no texture samples a 1x1 white placeholder, '
            'so a label bound to nothing is a label drawn as solid blocks',
      );
    });

    test('the atlas the moment its picture arrives', () async {
      final atlases = cacheOf();
      final renderer = rendererOn(atlases);
      addTearDown(renderer.dispose);
      render(renderer, Node(), layoutOf('abc'));
      await renderer.atlas!.flush();
      final bound = RecordingGlyphMaterial.current!.bound;
      expect(bound, isA<FakeTexture>());
      expect((bound! as FakeTexture).generation, renderer.atlas!.generation);
    });
  });

  group('a settled label', () {
    // The pair, from both sides. See
    // `plans/2026_09_17_a_letter_that_comes_back_wrong.md`.

    /// One label on one atlas, settled and drawing correctly.
    ///
    /// The node and the layout come back because a settled label is one that
    /// keeps being handed **the same objects**: a `Text3d` returns the
    /// identical [TextLayout3d] when it relaid out at the same width, and
    /// that identity is how the renderer knows nothing changed. A test that
    /// lays out again has not settled anything.
    ///
    /// Twelve 14x19 cells fill a 64-texel atlas exactly, so one more letter
    /// is what repacks it — which is the whole mechanism here, and the
    /// opposite of what the `two_surfaces_of_type` family needs.
    Future<
      ({
        AtlasText3dRenderer label,
        GlyphAtlasCache3d atlases,
        Node node,
        TextLayout3d layout,
      })
    >
    settled() async {
      final atlases = cacheOf();
      final label = rendererOn(atlases);
      addTearDown(label.dispose);
      final node = Node();
      final layout = layoutOf('abcdefghijkl');
      render(label, node, layout);
      await label.atlas!.flush();
      expect(label.atlas!.textureIsCurrent, isTrue);
      return (label: label, atlases: atlases, node: node, layout: layout);
    }

    /// Doubles [settle]'s atlas with a letter it has never packed, and leaves
    /// the new packing unrasterized — the window the defect lives in.
    ///
    /// The label it returns is the one with nowhere to turn: its letters were
    /// measured against a packing no picture exists for.
    AtlasText3dRenderer repack(
      ({
        AtlasText3dRenderer label,
        GlyphAtlasCache3d atlases,
        Node node,
        TextLayout3d layout,
      })
      settle,
    ) {
      final atlas = settle.label.atlas!;
      final was = atlas.generation;
      final second = rendererOn(settle.atlases);
      addTearDown(second.dispose);
      render(second, Node(), layoutOf('mn'));
      expect(atlas.generation, greaterThan(was), reason: 'no repack happened');
      expect(atlas.textureIsCurrent, isFalse);
      return second;
    }

    test('lets a new one draw nothing rather than another letter', () async {
      // A label whose letters are new in the window has nothing it could
      // honestly draw: every coordinate it holds addresses texels belonging to
      // a neighbour, or to no letter at all. A material bound to nothing draws
      // nothing, and nothing is the better of the two.
      final settle = await settled();
      final second = repack(settle);
      expect(second.quadCount, 2);
      expect(second.bakedGeneration, settle.label.atlas!.generation);
      expect(
        RecordingGlyphMaterial.current!.bound,
        isNull,
        reason: 'a new label bound a picture of a packing it did not use',
      );
    });

    test('does not bake against a packing with no picture', () async {
      // The settled label is asked to draw again, the way a turning panel or a
      // scrolling list asks: the same layout object, the same node, the same
      // style. It must not bake again. The mesh it has and the texture bound
      // to it are a pair, and that pair is what draws the right letters —
      // baking now would swap a label that is correct for one that cannot
      // draw, which is what put a speckled block in the middle of
      // `Notifications` on a screen with nothing open.
      final settle = await settled();
      final was = settle.label.atlas!.generation;
      final material = RecordingGlyphMaterial.current!;
      expect((material.bound! as FakeTexture).generation, was);

      repack(settle);
      final bakes = RecordingGlyphMaterial.made.length;
      render(settle.label, settle.node, settle.layout);

      expect(
        RecordingGlyphMaterial.made,
        hasLength(bakes),
        reason: 'the settled label baked against a packing with no picture',
      );
      expect(settle.label.quadCount, 12);
      expect(
        settle.label.bakedGeneration,
        was,
        reason: 'the settled label measured itself against the new packing',
      );
      expect(
        (material.bound! as FakeTexture).generation,
        was,
        reason: 'the settled label dropped the picture its letters are in',
      );
    });

    test('bakes again once the picture catches up', () async {
      final settle = await settled();
      final atlas = settle.label.atlas!;
      final second = repack(settle);
      final generation = atlas.generation;

      // The flush that lands the new picture notifies, and both halves of
      // every pair move forward at once — with no layout anywhere in it.
      await atlas.flush();
      expect(atlas.textureIsCurrent, isTrue);
      expect(atlas.textureGeneration, generation);
      expect(settle.label.quadCount, 12);
      expect(settle.label.bakedGeneration, generation);
      expect(second.quadCount, 2);
      expect(second.bakedGeneration, generation);
      // Which is to say every label is now sampling the picture it was
      // measured against, rather than one of them drawing and one not.
      expect(
        RecordingGlyphMaterial.current!.bound,
        isA<FakeTexture>(),
        reason: 'a label is bound to nothing after the picture landed',
      );
    });

    test('is not left waiting for a picture that never comes', () async {
      // The wait rests on an invariant: a repack always leaves a raster
      // owing, and every path that waits says `flush` on the way out. Without
      // the second half a settled panel would hold its old letters for ever,
      // which is a worse defect than the one being fixed.
      final settle = await settled();
      final atlas = settle.label.atlas!;
      repack(settle);
      expect(atlas.needsRaster, isTrue);
      final generation = atlas.generation;

      // Nothing here awaits the atlas, and nothing lays anything out: the
      // only thing that happens is the settled label being drawn again, the
      // way a screen whose overlay has closed is drawn again. The flush it
      // leaves owing is what has to finish the job.
      render(settle.label, settle.node, settle.layout);
      await pumpEventQueue();
      expect(atlas.textureIsCurrent, isTrue);
      expect(atlas.textureGeneration, generation);
      expect(settle.label.bakedGeneration, generation);
      expect(RecordingGlyphMaterial.current!.bound, isA<FakeTexture>());
    });
  });

  group('a label whose atlas repacked under it', () {
    test('bakes again without a layout', () async {
      // The defect the listener exists for, and it must keep working: a panel
      // that has stopped laying out has nothing left to call `render`, so the
      // atlas's notification is the only thing that can bring its letters
      // back. An app bar read `nb` where it should have read `Inbox`.
      final atlases = cacheOf();
      final first = rendererOn(atlases);
      addTearDown(first.dispose);
      render(first, Node(), layoutOf('abcdefghijkl'));
      await first.atlas!.flush();
      final atlas = first.atlas!;
      final was = atlas.generation;

      final second = rendererOn(atlases);
      addTearDown(second.dispose);
      render(second, Node(), layoutOf('mn'));
      await atlas.flush();

      // No second `render` on the first label anywhere in this test.
      expect(atlas.generation, greaterThan(was));
      expect(atlas.textureIsCurrent, isTrue);
      expect(first.quadCount, 12);
      expect(first.bakedGeneration, atlas.generation);
      expect(second.bakedGeneration, atlas.generation);
    });
  });

  group('the wall around a glyph', () {
    // A glyph is a slab: a face drawn out of the atlas, and a wall swept
    // around its silhouette. Only the face has a texture in it, so binding
    // nothing stops the face and leaves the wall standing — and a wall with no
    // face is not a letter, it is the dark edge of one. On a turned panel that
    // reads as a smear where the letter belongs, hatched rather than solid
    // while the label is arriving, which is what a person saw on a gallery
    // whose faces this package had already learned to withhold.

    /// A label with a thickness, settled, with its silhouettes traced.
    Future<({AtlasText3dRenderer label, GlyphAtlasCache3d atlases, Node node})>
    walled() async {
      final atlases = cacheOf();
      final label = AtlasText3dRenderer(
        atlases: atlases,
        resolution: 1.0,
        depth: 2.0,
        upload: (builder) => null,
      );
      addTearDown(label.dispose);
      final node = Node();
      render(label, node, layoutOf('abcdefghijkl'));
      await label.atlas!.flush();
      // The silhouettes arrive with the pixels, so the wall exists only after
      // a flush — and a rebake, which the flush's notification performs.
      expect(label.wallSegmentCount, greaterThan(0));
      return (label: label, atlases: atlases, node: node);
    }

    test('draws while the face can', () async {
      final walls = await walled();
      expect(walls.label.atlas!.textureIsCurrent, isTrue);
      expect(RecordingWallMaterial.current!.opacity, 1.0);
      expect(RecordingGlyphMaterial.current!.bound, isA<FakeTexture>());
    });

    test('is hidden the moment the face cannot', () async {
      final walls = await walled();
      final atlas = walls.label.atlas!;

      // A repack under someone else's letter. Every label on this atlas is
      // now measured against a packing no picture exists for.
      final second = flatRendererOn(walls.atlases);
      addTearDown(second.dispose);
      render(second, Node(), layoutOf('mn'));
      expect(atlas.textureIsCurrent, isFalse);

      // The label lays out again — which is what resizing a window makes
      // every label on the screen do at once — so it cannot keep the mesh it
      // had and has to bake against the new packing.
      render(walls.label, walls.node, layoutOf('abcdefghijkl'));
      expect(
        RecordingGlyphMaterial.current!.bound,
        isNull,
        reason: 'the face bound a picture of a packing it did not use',
      );
      expect(
        RecordingWallMaterial.current!.opacity,
        0.0,
        reason: 'the wall outlived the face it belongs to',
      );
    });

    test(
      'is not told to draw against an atlas with no picture at all',
      () async {
        // The same rule as *hidden the moment the face cannot*, through the one
        // door that was left open. A renderer handed a **different** atlas —
        // the style changed, or the surface's scale crossed a bucket — forgets
        // which packing it baked against, and an atlas nothing has rasterized
        // has no picture to report either. Both say -1, and -1 == -1 read as
        // *the picture matches*: the face bound a texture that is not there and
        // drew nothing, while the wall, which has no texture to be stopped by,
        // was told to draw. A hollow letter, out of the same door as the last
        // one.
        final walls = await walled();
        final wall = RecordingWallMaterial.current!;
        expect(wall.opacity, 1.0);

        // A second style is a second atlas, and this one nothing has flushed.
        const other = TextStyle(fontSize: 20);
        render(
          walls.label,
          walls.node,
          layoutOf('abc', other),
          textStyle: other,
        );
        expect(walls.label.atlas!.textureGeneration, -1);
        expect(
          wall.opacity,
          0.0,
          reason:
              'a wall was told to draw against a picture that does not exist',
        );
        expect(RecordingGlyphMaterial.current!.bound, isNull);
      },
    );

    test('goes with the mesh when the renderer itself is rebuilt', () async {
      // **A label that is rebuilt cannot wait**, which is why the factory
      // behind `DefaultTextRenderer3d` has to be a stable function. A renderer
      // draws right through a repack because it holds a mesh and a texture
      // that agree; one built this frame holds neither, so it bakes against
      // whatever packing the atlas is handing out and has nothing it can
      // honestly draw until the picture lands. An application that writes a
      // new closure into `SceneTheme3d.textRendererFactory` on every build
      // throws every label's renderer in the scene away on every build — and
      // a window resize is dozens of builds — so nothing in it is ever
      // settled and this defence never applies to it. The gallery did exactly
      // that.
      final atlases = cacheOf();
      final node = Node();
      final layout = layoutOf('abcdefghijkl');
      AtlasText3dRenderer walled() => AtlasText3dRenderer(
        atlases: atlases,
        resolution: 1.0,
        depth: 2.0,
        upload: (builder) => null,
      );
      final label = walled();
      render(label, node, layout);
      await label.atlas!.flush();
      final atlas = label.atlas!;
      final settled = atlas.generation;
      expect(label.wallSegmentCount, greaterThan(0));

      // A repack under someone else's letter, with no picture of it yet.
      final second = flatRendererOn(atlases);
      addTearDown(second.dispose);
      render(second, Node(), layoutOf('mn'));
      expect(atlas.textureIsCurrent, isFalse);

      // The label that kept its renderer keeps its letters: same layout
      // object, same node, and the pair it is already drawing.
      render(label, node, layout);
      expect(label.bakedGeneration, settled);

      // The same label, rebuilt. A new renderer, on the same node, with the
      // same text and nothing to keep.
      label.dispose();
      final rebuilt = walled();
      addTearDown(rebuilt.dispose);
      render(rebuilt, node, layout);
      expect(rebuilt.bakedGeneration, atlas.generation);
      expect(rebuilt.bakedGeneration, greaterThan(settled));
      expect(
        RecordingGlyphMaterial.current!.bound,
        isNull,
        reason:
            'a renderer built inside the window has no mesh to keep, so it '
            'bakes against a packing with no picture and draws nothing',
      );
      expect(RecordingWallMaterial.current!.opacity, 0.0);
    });

    test('comes back with it, at the label\'s own opacity', () async {
      final walls = await walled();
      final atlas = walls.label.atlas!;
      final second = flatRendererOn(walls.atlases);
      addTearDown(second.dispose);
      render(second, Node(), layoutOf('mn'));
      render(walls.label, walls.node, layoutOf('abcdefghijkl'), opacity: 0.4);
      expect(RecordingWallMaterial.current!.opacity, 0.0);

      await atlas.flush();
      expect(atlas.textureIsCurrent, isTrue);
      expect(
        RecordingWallMaterial.current!.opacity,
        0.4,
        reason: 'the wall came back at full strength inside a fading subtree',
      );
    });
  });

  group('an opacity', () {
    test('reaches the material without rebuilding anything', () {
      final renderer = rendererOn(cacheOf());
      addTearDown(renderer.dispose);
      final node = Node();
      final layout = layoutOf('abc');
      render(renderer, node, layout);
      final material = RecordingGlyphMaterial.current!;
      render(renderer, node, layout, opacity: 0.3);
      expect(
        RecordingGlyphMaterial.current,
        same(material),
        reason: 'a fade rebuilt the mesh',
      );
    });
  });
}
