import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene/scene.dart' show Node;

import '../geometry/basis3d.dart';
import '../geometry/size3d.dart';
import 'text_layout.dart';

/// Everything a renderer needs to turn one laid-out string into geometry.
///
/// Handed to [Text3dRenderer.render] after every layout the box performs, and
/// valid only for the duration of that call: keep the numbers, not the
/// object.
class Text3dRenderRequest {
  /// Describes one render.
  const Text3dRenderRequest({
    required this.node,
    required this.layout,
    required this.style,
    required this.size,
    required this.basis,
    required this.unitsPerLogicalPixel,
    required this.logicalPixelsPerUnit,
  });

  /// The box's scene node, which the geometry hangs under.
  ///
  /// Its transform belongs to the layout and is rewritten on every
  /// placement; add children to it, do not move it.
  final Node node;

  /// The lines, runs and baselines, in logical pixels.
  ///
  /// The origin is the top-left of the block, `x` to the right and `y`
  /// downward — layout space, with the units still to be applied.
  final TextLayout3d layout;

  /// The style the text was measured at. Colour, decoration and font are the
  /// renderer's business; the size was already spent on the measurement.
  final TextStyle style;

  /// The box's own extent in world units.
  final Size3d size;

  /// The mapping from layout space to the surface's scene space.
  ///
  /// A renderer that builds geometry in layout axes (which is the easy way to
  /// build it, since the layout is expressed in them) has nothing to do with
  /// this; one that hands a preassembled quad to the engine has to undo the
  /// basis the way [NodeBox3d] does.
  final LayoutBasis3d basis;

  /// World units per logical pixel: what multiplies [layout] into [size].
  ///
  /// Includes the accessibility text scale, so it is not
  /// [Layout3dMetrics.unitsPerLogicalPixel] on its own.
  final double unitsPerLogicalPixel;

  /// Logical pixels per world unit at the surface's authored scale.
  ///
  /// The rasterization number: how many texels a unit of the plane is worth,
  /// and so the resolution a glyph atlas or a captured texture has to be
  /// generated at to come out sharp. It is a promise about screen pixels only
  /// for a camera-bound surface; a panel the viewer can walk toward covers a
  /// different number of real pixels every frame, and a renderer that cares
  /// needs a level-of-detail story of its own on top of this.
  final double logicalPixelsPerUnit;
}

/// Turns a laid-out string into something the scene draws.
///
/// The seam the two halves of text are separated by. Measurement and line
/// breaking are pure arithmetic and are tested headless; rasterization is
/// neither, and there is more than one defensible way to do it — a glyph
/// atlas of textured quads, a captured widget on a quad, extruded outlines
/// where a font parser is available. Keeping the box free of all three is
/// what lets the layout half be finished while the drawing half is still a
/// choice.
///
/// A [Text3d] with no renderer lays out, reports its size, answers intrinsics
/// and states a baseline, and draws nothing. That is a useful object on its
/// own: it is what every test in this package's suite measures, and it is
/// what a component library sizes its buttons against.
///
/// A renderer handed to a [Text3d] is owned by it: [render] is called after
/// each of the box's layouts, and [dispose] when the box is disposed.
abstract class Text3dRenderer {
  /// Allows subclasses to be const.
  const Text3dRenderer();

  /// Draws [request], replacing whatever the last call drew.
  ///
  /// Called once per layout of the box, which is often — a scroll, a resize,
  /// a frame of animation. Compare against what you built last time and do
  /// nothing when nothing that matters changed; the box does not do that for
  /// you, because only the renderer knows what it is sensitive to.
  void render(Text3dRenderRequest request);

  /// Releases whatever [render] built.
  void dispose();
}
