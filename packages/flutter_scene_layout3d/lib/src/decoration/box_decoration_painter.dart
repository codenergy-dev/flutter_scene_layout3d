import 'package:flutter_scene/scene.dart'
    show GeometryBuilder, Mesh, MeshGeometry, Node, PreprocessedMaterial;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import 'box_decoration.dart';
import 'decoration.dart';

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
/// The material is the caller's, because compiling one needs a build hook
/// this package cannot run from inside a dependency. Install the shipped
/// `assets/box_decoration3d.fmat` in your app's hook, load it once, and hand
/// the loader in:
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
  }) : _createMaterial = createMaterial,
       _createGeometry = createGeometry ?? buildUnitSlab;

  final PreprocessedMaterial Function() _createMaterial;
  final MeshGeometry Function() _createGeometry;

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
    final centre = size.center;
    slab.node.localTransform = Matrix4.translationValues(
      centre.x,
      centre.y,
      centre.z,
    ).multiplied(Matrix4.diagonal3Values(size.width, size.height, size.depth));

    BoxDecoration3dUniforms.resolve(
      decoration: decoration,
      size: size,
      metrics: request.metrics,
      stateLayer: request.stateLayer,
      clip: request.clip,
    ).applyTo(slab.material.parameters);
  }

  @override
  void release(Node node) {
    final slab = _slabs.remove(node);
    if (slab == null) return;
    node.remove(slab.node);
  }

  @override
  void dispose() {
    for (final entry in _slabs.entries) {
      entry.key.remove(entry.value.node);
    }
    _slabs.clear();
    _geometry = null;
  }

  /// The shared slab: a unit cube, centred on the origin, whose vertex
  /// colours carry each corner's own position offset into `[0, 1]`.
  ///
  /// Built with flat per-face normals and no vertex merging, because a cube
  /// with averaged corner normals lights like a sphere. Six faces, twenty-four
  /// vertices, twelve triangles, built once for a whole application.
  static MeshGeometry buildUnitSlab() {
    final builder = GeometryBuilder(deduplicate: false);
    // (normal, first in-plane axis, second in-plane axis) for each face.
    final List<(Vector3, Vector3, Vector3)> spec =
        <(Vector3, Vector3, Vector3)>[
          (Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)),
          (Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)),
          (Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
          (Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
          (Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)),
          (Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)),
        ];
    for (final (normal, u, v) in spec) {
      builder.normal(normal);
      final centre = normal * 0.5;
      final corners = <Vector3>[
        centre - u * 0.5 - v * 0.5,
        centre + u * 0.5 - v * 0.5,
        centre + u * 0.5 + v * 0.5,
        centre - u * 0.5 + v * 0.5,
      ];
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
}

class _Slab {
  _Slab(this.node, this.material);

  final Node node;
  final PreprocessedMaterial material;
}
