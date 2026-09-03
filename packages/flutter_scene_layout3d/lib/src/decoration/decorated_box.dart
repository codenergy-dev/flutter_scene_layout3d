import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsProperty,
        DoubleProperty,
        FlagProperty;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../geometry/offset3d.dart';
import '../layout3d.dart';
import 'decoration.dart';

/// A box that makes itself visible.
///
/// The 3D analogue of `DecoratedBox`, and the one place in this package where
/// layout turns into something you can see. Everything else here arranges;
/// this box lays its child out exactly as a pass-through would and then hands
/// its own [size] to a [Decoration3dPainter], which puts a mesh under the
/// box's node and keeps it the right size.
///
/// ```dart
/// DecoratedBox3d(
///   decoration: const BoxDecoration3d(
///     color: Color(0xFF202124),
///     borderRadius: BorderRadius3d.circular(12),
///     elevation: 3,
///   ),
///   child: Padding3d(
///     padding: EdgeInsets3d.all(0.12),
///     child: Text3d('Continue'),
///   ),
/// )
/// ```
///
/// The direction of the dependency is what matters. `NodeBox3d`, the other
/// leaf that holds geometry, takes content that already exists and *scales
/// it* into the room available — which distorts a 12dp corner into whatever
/// the box's aspect ratio makes of it. A decoration goes the other way: it is
/// told the size and produces the right shape at that size, so a card is 12dp
/// round whether it is a chip or a sheet.
///
/// **A size change never rebuilds geometry.** That is the contract with the
/// painter, and it is why decorations are shader parameters rather than
/// meshes: a screen of components animating dirties layout every frame, and a
/// mesh rebuild on that path is the cost the whole design exists to avoid.
/// [stateLayer] takes it one step further and does not even dirty layout.
///
/// **Elevation lifts the geometry, not the box.** A raised panel's mesh moves
/// toward the viewer; its layout box, its intrinsics and what a ray reaches
/// stay exactly where layout put them. See [BoxDecoration3d.elevation].
class DecoratedBox3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a decorated box.
  DecoratedBox3d({
    required Decoration3d decoration,
    StateLayer3d stateLayer = StateLayer3d.none,
    super.child,
    super.name,
  }) : _decoration = decoration,
       _stateLayer = stateLayer;

  Decoration3d _decoration;

  /// What this box looks like.
  ///
  /// Setting it never relayouts: a decoration has no say in any extent, so
  /// the sizes above and below are unchanged and only the picture differs.
  /// When the new decoration keeps the old one's
  /// [Decoration3d.cacheKey] and says it does not need rebuilding, even the
  /// painter is kept — a colour or an elevation animating over a
  /// `BoxDecoration3d` is a parameter write per frame and nothing more.
  Decoration3d get decoration => _decoration;

  set decoration(Decoration3d value) {
    final old = _decoration;
    if (old == value) return;
    _decoration = value;
    final keepsPainter =
        old.cacheKey == value.cacheKey && !value.shouldRebuild(old);
    if (!keepsPainter) _releasePainter();
    // Elevation rides in the node transform, so a change to it has to be
    // written out even though nothing was laid out again.
    if (hasSize) applyNodeTransform();
    markNeedsRepaint();
  }

  StateLayer3d _stateLayer;

  /// The hover, focus, press or drag overlay in force.
  ///
  /// Setting it writes one uniform and asks for a frame. It marks *nothing*
  /// dirty for layout, and that is a promise rather than an optimization: a
  /// pointer moving across a screen of controls changes this on every box it
  /// crosses, and a design where that relayouts is a design where hovering a
  /// list is a stutter.
  StateLayer3d get stateLayer => _stateLayer;

  set stateLayer(StateLayer3d value) {
    if (_stateLayer == value) return;
    _stateLayer = value;
    markNeedsRepaint();
  }

  Decoration3dPainter? _painter;
  Decoration3d? _painterKey;

  /// The painter realizing this box's decoration, or null when nothing is.
  ///
  /// Null in a headless test and before the engine is ready; see
  /// [Decoration3d.createPainter].
  Decoration3dPainter? get painter => _painter;

  /// How far this box's geometry is lifted toward the viewer, in world units.
  ///
  /// Zero for a decoration that is not a [BoxDecoration3d], since elevation
  /// is that decoration's idea.
  double get elevationUnits {
    final decoration = _decoration;
    if (decoration is Decoration3dElevation) {
      return metrics.dp((decoration as Decoration3dElevation).elevation);
    }
    return 0.0;
  }

  /// The lift, as the transform the box's node carries.
  ///
  /// Layout space runs `z` away from the viewer, so standing off the parent
  /// is a step toward negative `z`.
  @override
  Matrix4? get localTransform {
    final lift = elevationUnits;
    if (lift == 0.0) return null;
    return Matrix4.translationValues(0.0, 0.0, -lift);
  }

  /// The lift is a nudge to the geometry, not a change of frame.
  ///
  /// Returning null here is what keeps the box's own extent, its children's
  /// offsets and everything a ray finds in the frame layout put them in —
  /// exactly the distinction `ParentData3d.sceneOffset` draws, and the reason
  /// a raised button is still pointable where it was drawn flat.
  @override
  Matrix4? get hitTestTransform => null;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
    } else {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
      child.place(Offset3d.zero);
    }
    applyNodeTransform();
    repaint();
  }

  /// Republishes the clip in force, which is what actually cuts this panel.
  ///
  /// The plane tier of the clip contract lives in a shader block, and the
  /// block is written by [repaint]. A box paints from inside its own
  /// `performLayout`, where an enclosing `ClipBox3d` may not have an extent
  /// yet — so without this the first block a panel ever gets is the
  /// unbounded one, and a row half inside a window draws straight through
  /// its edge. `ClipBox3d` calls this over its subtree once it has a size.
  @override
  void refreshClipRegion() {
    if (!hasSize) return;
    repaint();
  }

  /// Repaints and asks the host for a frame.
  ///
  /// The counterpart of [markNeedsLayout] for everything a decoration owns.
  /// Nothing here goes through the layout pipeline, because nothing here can
  /// change a size.
  void markNeedsRepaint() {
    repaint();
    owner?.requestVisualUpdate();
  }

  /// Hands the current size, state and clip to the painter.
  ///
  /// Called after every layout, and again whenever something the painter
  /// reads has changed without a layout. Cheap by construction: acquiring the
  /// painter is a map lookup after the first box asks for that shape, and the
  /// painter's job is to write parameters rather than build anything.
  void repaint() {
    if (!hasSize) return;
    final painter = _acquirePainter();
    if (painter == null) return;
    painter.paint(
      Decoration3dPaintRequest(
        node: node,
        decoration: _decoration,
        size: size,
        elevation: elevationUnits,
        stateLayer: _stateLayer,
        clip: clipRegion,
        basis: basis,
        metrics: metrics,
      ),
    );
  }

  Decoration3dPainter? _acquirePainter() {
    final existing = _painter;
    if (existing != null) return existing;
    final cache = owner?.painters;
    if (cache == null) return null;
    final painter = cache.acquire(_decoration);
    if (painter == null) return null;
    _painter = painter;
    _painterKey = _decoration;
    return painter;
  }

  void _releasePainter() {
    final key = _painterKey;
    if (key == null) return;
    owner?.painters.release(key, node);
    _painter = null;
    _painterKey = null;
  }

  /// The panel is the thing the reader points at.
  ///
  /// A card, a button and an app bar answer for their whole face, including
  /// the gaps between whatever is laid out on them, which is what makes them
  /// easy to hit. Wrap the box in an `IgnorePointer3d` for a decoration that
  /// is purely a backdrop.
  @override
  bool hitTestSelf(Offset3d position) => true;

  @override
  void detach() {
    // Before `super`, which is what clears the owner the cache hangs off.
    _releasePainter();
    super.detach();
  }

  @override
  void dispose() {
    _releasePainter();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Decoration3d>('decoration', decoration));
    properties.add(
      DiagnosticsProperty<StateLayer3d>(
        'stateLayer',
        stateLayer,
        defaultValue: StateLayer3d.none,
      ),
    );
    properties.add(
      DoubleProperty(
        'elevationUnits',
        hasSize ? elevationUnits : null,
        defaultValue: 0.0,
      ),
    );
    properties.add(
      FlagProperty('painter', value: painter != null, ifFalse: 'not painting'),
    );
  }
}
