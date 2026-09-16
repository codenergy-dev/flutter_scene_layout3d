import 'dart:math' as math;
import 'dart:ui' show VoidCallback;

import 'package:flutter/painting.dart' show ImageErrorListener;
import 'package:flutter_scene/scene.dart'
    show
        GeometryBuilder,
        Mesh,
        MeshGeometry,
        Node,
        PreprocessedMaterial,
        TextureSource;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../geometry/size3d.dart';
import 'box_decoration.dart';
import 'decoration.dart';
import 'decoration_image.dart';

/// Draws every [BoxDecoration3d] in a tree with one mesh and one material per
/// box.
///
/// The realization of the design bet. One unit slab is built the first time
/// anything asks and is never rebuilt; each decorated box gets a child node
/// holding that slab and a material of its own; a layout writes a transform
/// and eight parameters. No size, colour, elevation or state change allocates
/// anything.
///
/// **The slab is a unit cube whose vertex colours are its own object-space
/// coordinates.** That is the trick that makes the shader possible at all: a
/// `.fmat` fragment shader is handed a world position, a normal and a UV, and
/// none of those tells it where in the *box* a fragment is. Encoding
/// `position + 0.5` in the vertex colour does, exactly, because a cube's face
/// is planar and the interpolation of a linear function across it is that
/// function. The shader recovers
/// `p = (GetVertexColor().rgb - 0.5) * 2.0 * half_extent` and evaluates a
/// rounded-box signed distance there.
///
/// **The slab is authored in layout axes, not scene axes.** A `NodeBox3d`
/// undoes the surface basis so a loaded model keeps the orientation it was
/// authored with; a decoration has no authored orientation to keep, and its
/// faces should line up with the box it is decorating. So the basis in the
/// paint request is deliberately unused here.
///
/// The material is the caller's, because building one needs a GPU context
/// that this package cannot assume it has. Compiling the shader is *not* the
/// caller's job any more: this package's own `hook/build.dart` runs
/// `impellerc` over `assets/box_decoration3d.fmat` for whatever app depends
/// on it, so loading it is one line and the app's hook needs nothing in it
/// about panels:
///
/// ```dart
/// final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
/// BoxDecoration3d.painterFactory = (_) =>
///     BoxDecoration3dPainter(createMaterial: () => material);
/// ```
///
/// Handing every box the *same* material, as above, is the cheap path and is
/// right as long as the panels on the surface look alike, since the last one
/// painted wins the parameter block. A screen with panels of different
/// colours wants a fresh instance per box, which is what the callback shape
/// is for: `loadFmatMaterial` returns a new instance on each call.
class BoxDecoration3dPainter implements Decoration3dPainter {
  /// Creates a painter over a caller-supplied material.
  ///
  /// [createMaterial] is called once per decorated box, because the
  /// parameters are per-box; the geometry is shared. [createGeometry]
  /// defaults to [buildUnitSlab] and is there for a caller with a slab of its
  /// own — a rounded mesh, a nine-slice — that carries the same object-space
  /// vertex colours.
  BoxDecoration3dPainter({
    required PreprocessedMaterial Function() createMaterial,
    MeshGeometry Function()? createGeometry,
    ImageTexture3dCache? pictures,
  }) : _createMaterial = createMaterial,
       _createGeometry = createGeometry ?? buildUnitSlab,
       _pictures = pictures ?? ImageTexture3dCache.shared;

  final PreprocessedMaterial Function() _createMaterial;
  final MeshGeometry Function() _createGeometry;

  /// Where the pictures come from, shared with every other painter unless a
  /// caller says otherwise.
  final ImageTexture3dCache _pictures;

  MeshGeometry? _geometry;
  final Map<Node, _Slab> _slabs = <Node, _Slab>{};

  /// How many boxes this painter is currently drawing.
  int get boxCount => _slabs.length;

  /// Whether the shared geometry has been built.
  bool get hasGeometry => _geometry != null;

  @override
  void paint(Decoration3dPaintRequest request) {
    final decoration = request.decoration;
    if (decoration is! BoxDecoration3d) return;
    final slab = _slabs.putIfAbsent(request.node, () {
      final geometry = _geometry ??= _createGeometry();
      final material = _createMaterial();
      final node = Node(mesh: Mesh(geometry, material))
        ..name = 'BoxDecoration3d';
      request.node.add(node);
      return _Slab(node, material);
    });

    // The slab fills the box: a unit cube centred on its own origin, scaled
    // to the extent and moved to the box's centre. A scale is not a rebuild —
    // that is the whole point — and a box that animates from a chip to a
    // sheet writes these sixteen floats and nothing else.
    final size = request.size;
    slab.node.localTransform = slabTransformFor(size);

    // The picture, which may not be here yet. Acquiring is synchronous and
    // hands back an object with nothing in it; what fills it in is the
    // listener below, which asks the box to paint again — the one thing a
    // painter cannot do for itself.
    slab.onChanged = request.onChanged;
    final picture = _syncPicture(slab, request);
    final texture = picture?.texture;
    if (texture != null && !identical(texture, slab.bound)) {
      final sampled = texture.sampledTexture;
      if (sampled != null) {
        slab.bound = texture;
        slab.material.parameters.setTexture(
          'image_texture',
          sampled,
          sampler: texture.sampledSampler,
        );
      }
    }

    BoxDecoration3dUniforms.resolve(
      decoration: decoration,
      size: size,
      metrics: request.metrics,
      stateLayer: request.stateLayer,
      clip: request.clip,
      // Only once the texture is actually bound. A picture whose size is
      // known but whose pixels are not would otherwise be drawn as the
      // sampler's white placeholder — the same defect a glyph mesh attached
      // before its atlas shows as black rectangles where the letters go.
      imagePixelSize: identical(slab.bound, texture)
          ? picture?.pixelSize
          : null,
      imageScale: picture?.scale ?? 1.0,
      textDirection: request.configuration.textDirection,
    ).applyTo(slab.material.parameters);
  }

  /// Points [slab] at the picture its decoration names, acquiring and
  /// releasing as that changes.
  ImageTexture3d? _syncPicture(_Slab slab, Decoration3dPaintRequest request) {
    final image = (request.decoration as BoxDecoration3d).image;
    final wanted = image?.image;
    final held = slab.picture;
    final configuration = ImageTexture3dCache.keyConfigurationOf(
      request.configuration,
    );
    if (held != null &&
        wanted == held.provider &&
        configuration == held.configuration) {
      // The same picture, and possibly a different listener for a failure to
      // load it: a decoration can be rebuilt with a new `onError` without
      // changing which pixels it wants.
      final onError = image?.onError;
      if (onError != slab.onError) {
        final previous = slab.onError;
        if (previous != null) held.removeErrorListener(previous);
        slab.onError = onError;
        if (onError != null) held.addErrorListener(onError);
      }
      return held;
    }
    _releasePicture(slab);
    if (image == null) return null;
    final picture = slab.picture = _pictures.acquire(
      image.image,
      request.configuration,
    );
    picture.addListener(slab.repaint);
    final onError = slab.onError = image.onError;
    if (onError != null) picture.addErrorListener(onError);
    return picture;
  }

  void _releasePicture(_Slab slab) {
    final picture = slab.picture;
    if (picture == null) return;
    picture.removeListener(slab.repaint);
    final onError = slab.onError;
    if (onError != null) picture.removeErrorListener(onError);
    slab.onError = null;
    slab.picture = null;
    slab.bound = null;
    _pictures.release(picture);
  }

  @override
  void release(Node node) {
    final slab = _slabs.remove(node);
    if (slab == null) return;
    _releasePicture(slab);
    node.remove(slab.node);
  }

  @override
  void dispose() {
    for (final entry in _slabs.entries) {
      _releasePicture(entry.value);
      entry.key.remove(entry.value.node);
    }
    _slabs.clear();
    _geometry = null;
  }

  /// The thinnest a slab is ever drawn, in world units.
  ///
  /// A hundredth of a logical pixel at the standard rate, which is invisible,
  /// and the reason it is not zero is [slabTransformFor].
  static const double minimumSlabExtent = 1e-4;

  /// The transform that puts the shared unit slab onto a box of [size]: a
  /// scale to the extent and a move to the box's centre.
  ///
  /// A scale is not a rebuild — that is the whole point — and a box that
  /// animates from a chip to a sheet writes these sixteen floats and nothing
  /// else.
  ///
  /// **No axis is ever scaled to exactly zero**, and that is not tidiness. A
  /// singular transform has no normal matrix, so a slab with no thickness is
  /// lit by a normal of nothing and comes out **black** — which looks like a
  /// missing texture rather than like missing geometry, and is the one thing
  /// about this shader that a colour probe cannot tell from a defect in the
  /// picture. A box with no depth is not exotic either: [Image3d] takes the
  /// depth its constraints allow, and in a loose surface that is none, so an
  /// ordinary photograph on its own is exactly the case that meets it.
  static Matrix4 slabTransformFor(Size3d size) {
    final centre = size.center;
    return Matrix4.translationValues(centre.x, centre.y, centre.z).multiplied(
      Matrix4.diagonal3Values(
        math.max(size.width, minimumSlabExtent),
        math.max(size.height, minimumSlabExtent),
        math.max(size.depth, minimumSlabExtent),
      ),
    );
  }

  /// The shared slab: a unit cube, centred on the origin, whose vertex
  /// colours carry each corner's own position offset into `[0, 1]`.
  ///
  /// Built with flat per-face normals and no vertex merging, because a cube
  /// with averaged corner normals lights like a sphere. Six faces, twenty-four
  /// vertices, twelve triangles, built once for a whole application.
  ///
  /// **Each face's triangles wind counter-clockwise around that face's own
  /// normal**, which is the package's convention and is load-bearing rather
  /// than tidy. The slab is authored in layout axes, a surface's basis is a
  /// mirror, and `flutter_scene` flips the front face for a mirrored transform
  /// on its own; wound the other way that flip lands on the wrong side and
  /// `culling: back` keeps the face **pointing away from the camera**. It
  /// looks almost right — a convex box has the same silhouette either way —
  /// and it is not: the panel is lit by a normal facing away from the viewer,
  /// and it writes its depth a whole thickness too far back, so nothing drawn
  /// *inside* the slab is ever rejected by the depth test. That is what the
  /// panel shader's `depth_write: true` is for and it had never landed where
  /// it was aimed. `examples/render_probe`'s `slab_occludes_its_inside` is the
  /// standing check; see
  /// `plans/2026_09_10_a_letter_on_a_slab.md`.
  static MeshGeometry buildUnitSlab() {
    final builder = GeometryBuilder(deduplicate: false);
    for (final (normal, corners) in unitSlabFaces()) {
      builder.normal(normal);
      final indices = <int>[];
      for (final corner in corners) {
        builder.color(
          Vector4(corner.x + 0.5, corner.y + 0.5, corner.z + 0.5, 1.0),
        );
        indices.add(builder.addVertex(corner));
      }
      builder
        ..addTriangle(indices[0], indices[1], indices[2])
        ..addTriangle(indices[0], indices[2], indices[3]);
    }
    return builder.build();
  }

  /// The six faces [buildUnitSlab] is made of: each one's outward normal, and
  /// its four corners in winding order.
  ///
  /// Separated from [buildUnitSlab] for the reason
  /// `AtlasText3dRenderer.glyphQuadCorners` is separated from its mesh:
  /// everything up to `build()` is arithmetic a headless test can check, and
  /// `build()` is a GPU upload no headless test survives. A face wound the
  /// wrong way is exactly the kind of defect that wants checking that way —
  /// it draws a picture that looks almost right and orders depth wrongly.
  ///
  /// The ring runs `-u-v`, `+u-v`, `+u+v`, `-u+v` around each face's centre,
  /// so `u cross v == normal` is what makes it counter-clockwise around the
  /// outward normal.
  static List<(Vector3, List<Vector3>)> unitSlabFaces() {
    // (normal, first in-plane axis, second in-plane axis), with
    // `u cross v == normal` on every row. The four side faces always had that
    // identity; the two facing along the depth axis — the ones a viewer
    // actually looks at — did not.
    final List<(Vector3, Vector3, Vector3)> spec =
        <(Vector3, Vector3, Vector3)>[
          (Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)),
          (Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0)),
          (Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
          (Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
          (Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)),
          (Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)),
        ];
    return <(Vector3, List<Vector3>)>[
      for (final (normal, u, v) in spec)
        (
          normal,
          <Vector3>[
            normal * 0.5 - u * 0.5 - v * 0.5,
            normal * 0.5 + u * 0.5 - v * 0.5,
            normal * 0.5 + u * 0.5 + v * 0.5,
            normal * 0.5 - u * 0.5 + v * 0.5,
          ],
        ),
    ];
  }
}

class _Slab {
  _Slab(this.node, this.material);

  final Node node;
  final PreprocessedMaterial material;

  /// The picture this box is waiting for or drawing, and the texture that
  /// has actually been bound to the material — which is not the same
  /// question, since a picture reports its size before its pixels.
  ImageTexture3d? picture;
  TextureSource? bound;
  ImageErrorListener? onError;

  /// The box's own way of asking for another paint. Kept per slab because a
  /// painter is shared between boxes and the picture's listener has to wake
  /// the right one.
  VoidCallback? onChanged;

  void repaint() => onChanged?.call();
}
