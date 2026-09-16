import 'dart:ui' show Color, Size, lerpDouble;

import 'package:flutter/painting.dart' show Gradient, TextDirection;
import 'package:flutter_scene/scene.dart' show MaterialParameters;
import 'package:vector_math/vector_math.dart' show Vector2, Vector3, Vector4;

import '../clip.dart';
import '../geometry/border_radius3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../metrics.dart';
import 'decoration.dart';
import 'decoration_image.dart';
import 'gradient.dart';

/// A line drawn around the outside of a decoration.
///
/// One width and one colour: Material borders are uniform on all four sides,
/// and a per-side border in three dimensions would mean six, which no
/// component in the catalogue asks for. The width is a logical-pixel figure,
/// like everything else on [BoxDecoration3d].
class Border3d {
  /// Creates a border.
  const Border3d({this.width = 0.0, this.color = const Color(0xFF000000)})
    : assert(width >= 0.0);

  /// No border, and the default.
  static const Border3d none = Border3d();

  /// The border's thickness, in logical pixels, drawn inside the box's
  /// outline.
  final double width;

  /// The border's colour.
  final Color color;

  /// Whether this border draws anything.
  bool get isNone => width <= 0.0 || color.a == 0.0;

  /// Linearly interpolates between two borders.
  static Border3d lerp(Border3d a, Border3d b, double t) => Border3d(
    width: lerpDouble(a.width, b.width, t)!.clamp(0.0, double.infinity),
    color: Color.lerp(a.color, b.color, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is Border3d && other.width == width && other.color == color;

  @override
  int get hashCode => Object.hash(width, color);

  @override
  String toString() => isNone ? 'Border3d.none' : 'Border3d($width, $color)';
}

/// A panel: a coloured slab with rounded corners, a border, a bevel and an
/// elevation.
///
/// This is the decoration every Material component is built out of — a card,
/// a button, an app bar, a dialog are all this object with different numbers
/// in it — and the reason it is one class rather than a family is the design
/// bet behind it. All of these are *uniforms* on a single signed-distance
/// shader over a single shared slab, so a screen full of panels is one mesh
/// and one material class, and animating any of them costs a parameter write
/// rather than a rebuilt mesh. [shouldRebuild] is therefore always false
/// between two `BoxDecoration3d`s, whatever changed.
///
/// **Every figure is in logical pixels.** [borderRadius], [bevel],
/// [Border3d.width] and [elevation] are spec numbers — a 12dp card corner, a
/// 1dp outline, a 6dp elevation — and the metrics turn them into world units
/// at paint time. That is what makes the same decoration correct on a
/// camera-bound surface and on a wall panel the author scaled by hand, and it
/// is the same bargain `Text3d` strikes with `TextStyle.fontSize`.
///
/// ```dart
/// DecoratedBox3d(
///   decoration: const BoxDecoration3d(
///     color: Color(0xFF1B6EF3),
///     borderRadius: BorderRadius3d.circular(12),
///     elevation: 6,
///   ),
///   child: Padding3d(padding: EdgeInsets3d.all(0.1), child: label),
/// )
/// ```
class BoxDecoration3d extends Decoration3d implements Decoration3dElevation {
  /// Creates a panel decoration.
  const BoxDecoration3d({
    this.color = const Color(0xFFFFFFFF),
    this.gradient,
    this.image,
    this.borderRadius = BorderRadius3d.zero,
    this.bevel = 0.0,
    this.border = Border3d.none,
    this.elevation = 0.0,
    this.surfaceTint,
  }) : assert(bevel >= 0.0),
       assert(elevation >= 0.0);

  /// The slab's colour.
  ///
  /// Ignored when there is a [gradient], exactly as `BoxDecoration.color` is.
  final Color color;

  /// A gradient filling the slab in place of [color], or null for none.
  ///
  /// Flutter's own [LinearGradient], [RadialGradient] and [SweepGradient],
  /// evaluated by the panel shader against the box's face — so it is exact at
  /// any size and any aspect ratio, and animating one costs a parameter write
  /// like everything else here.
  ///
  /// Two limits, both reported once in a debug build rather than ignored:
  /// **eight stops** ([GradientUniforms3d.maxStops]), past which the ramp is
  /// resampled, and no [Gradient.transform] or [RadialGradient.focal], which
  /// the shader has no arithmetic for.
  final Gradient? gradient;

  /// A picture drawn over the fill, or null for none.
  ///
  /// Drawn *by the panel shader*, which is what makes the corner radius cut
  /// it — there is no rounded clip in this package, so a photograph drawn any
  /// other way would sit square inside a rounded card. It arrives on its own
  /// clock; see [ImageTexture3d].
  final DecorationImage3d? image;

  /// The four in-plane corner radii, in logical pixels.
  final BorderRadius3d borderRadius;

  /// How far the slab's rim is rounded off along the depth axis, in logical
  /// pixels.
  ///
  /// A separate dial from [borderRadius] because it is a different edge: the
  /// corners are the outline you see face-on, the bevel is the thickness you
  /// see from the side. A fraction of a logical pixel is usually enough — it
  /// is there to keep a slab's silhouette from reading as a cut-out under a
  /// grazing light, not to make it a pillow.
  final double bevel;

  /// The line drawn inside the outline.
  final Border3d border;

  /// How far the panel stands off its parent, in logical pixels.
  ///
  /// Material's elevation. In Flutter an elevation is a painted shadow
  /// standing in for a height; here the height is real, so [DecoratedBox3d]
  /// lifts the geometry toward the viewer by `metrics.dp(elevation)` and a
  /// raised panel reads as raised because it moves under the camera and
  /// occludes what is behind it.
  ///
  /// **It casts no shadow, and cannot.** The panel shader declares
  /// `blending: alpha` — its anti-aliased outline *is* an alpha — and
  /// `flutter_scene` drops every non-opaque material before it reaches a
  /// shadow map. A catalogue wanting a card grounded on a surface has to put
  /// that shadow there itself; the engine's `ShadowCatcherMaterial` on a
  /// plane beneath the card is the shape of it.
  /// `examples/render_probe`'s `panel_shadow` scene is the standing check,
  /// and it fails the day this stops being true.
  ///
  /// The lift moves the *geometry* and nothing else: the box keeps the size
  /// and the position layout gave it, and a ray still reaches it where the
  /// layout put it. That is deliberate — a raised button whose touch target
  /// drifted away from its layout box would be a bug, not a feature — and it
  /// is the same rule `ParentData3d.sceneOffset` keeps. The one place the
  /// lift *is* visible outside the picture is the screen projection:
  /// `screenCenter` and friends read `worldTransform`, which undoes
  /// `hitTestTransform` and finds it null here, so a projected elevated panel
  /// is where the panel is drawn rather than where its box sits.
  @override
  final double elevation;

  /// The colour a raised surface is tinted with, or null for none.
  ///
  /// The half of Material 3's elevation that is not a height. The amount is
  /// derived from [elevation] by [surfaceTintOpacityFor]; this is only the
  /// hue, which in Material is the theme's primary colour.
  final Color? surfaceTint;

  /// Material 3's surface-tint opacity for an elevation in logical pixels.
  ///
  /// The published table — 0dp is untinted, 1dp is 5%, and it climbs to 14%
  /// at 12dp and stops — linearly interpolated between the listed levels.
  /// Reproduced here rather than imported because this package does not
  /// depend on `package:flutter/material.dart`, and because a component
  /// library that wants a different curve should be able to see what it is
  /// replacing.
  static double surfaceTintOpacityFor(double elevation) {
    const List<double> levels = <double>[0, 1, 3, 6, 8, 12];
    const List<double> opacities = <double>[0.0, 0.05, 0.08, 0.11, 0.12, 0.14];
    if (elevation <= 0.0) return 0.0;
    if (elevation >= levels.last) return opacities.last;
    for (var i = 1; i < levels.length; i++) {
      if (elevation > levels[i]) continue;
      final t = (elevation - levels[i - 1]) / (levels[i] - levels[i - 1]);
      return lerpDouble(opacities[i - 1], opacities[i], t)!;
    }
    return opacities.last;
  }

  /// A copy with the given fields replaced.
  ///
  /// [gradient], [image] and [surfaceTint] cannot be cleared this way;
  /// construct a new decoration for that, the way `copyWith` on a nullable
  /// field always has to be used.
  BoxDecoration3d copyWith({
    Color? color,
    Gradient? gradient,
    DecorationImage3d? image,
    BorderRadius3d? borderRadius,
    double? bevel,
    Border3d? border,
    double? elevation,
    Color? surfaceTint,
  }) => BoxDecoration3d(
    color: color ?? this.color,
    gradient: gradient ?? this.gradient,
    image: image ?? this.image,
    borderRadius: borderRadius ?? this.borderRadius,
    bevel: bevel ?? this.bevel,
    border: border ?? this.border,
    elevation: elevation ?? this.elevation,
    surfaceTint: surfaceTint ?? this.surfaceTint,
  );

  /// Linearly interpolates between two panels.
  ///
  /// Everything here is a uniform, so an interpolated decoration costs no
  /// more to draw than either end of it — which is what makes a hover that
  /// raises a card from 1dp to 3dp a free animation rather than a per-frame
  /// mesh rebuild.
  static BoxDecoration3d lerp(BoxDecoration3d a, BoxDecoration3d b, double t) =>
      BoxDecoration3d(
        color: Color.lerp(a.color, b.color, t)!,
        gradient: Gradient.lerp(a.gradient, b.gradient, t),
        image: DecorationImage3d.lerp(a.image, b.image, t),
        borderRadius: BorderRadius3d.lerp(a.borderRadius, b.borderRadius, t),
        bevel: lerpDouble(a.bevel, b.bevel, t)!.clamp(0.0, double.infinity),
        border: Border3d.lerp(a.border, b.border, t),
        elevation: lerpDouble(
          a.elevation,
          b.elevation,
          t,
        )!.clamp(0.0, double.infinity),
        surfaceTint: Color.lerp(a.surfaceTint, b.surfaceTint, t),
      );

  /// The factory that turns a panel into geometry, or null when nothing can.
  ///
  /// The one hook that decides whether panels are visible at all, and it is a
  /// static because the alternative — threading a painter down from the
  /// surface — would put an engine dependency in every component's
  /// constructor. An application that has a GPU context and the compiled
  /// `box_decoration3d.fmat` installs one at startup:
  ///
  /// ```dart
  /// final material = await loadFmatMaterial('assets/box_decoration3d.fmat');
  /// BoxDecoration3d.painterFactory =
  ///     (decoration) => BoxDecoration3dPainter(createMaterial: () => material);
  /// ```
  ///
  /// Handing every box the same instance is the cheap path, and right while
  /// the panels on a surface look alike — the last one painted wins the
  /// parameter block. Call `loadFmatMaterial` per box for a screen of panels
  /// in different colours.
  ///
  /// Left null — in a headless test, before `initializeStaticResources`
  /// resolves, in an application that decorates with its own meshes — every
  /// `BoxDecoration3d` lays out and measures exactly as it would and draws
  /// nothing.
  static Decoration3dPainter? Function(BoxDecoration3d decoration)?
  painterFactory;

  /// Every panel shares one painter, because every panel is the same slab
  /// with different numbers in it.
  ///
  /// Deliberately coarse: two decorations differing in colour, radius, border
  /// or elevation share a mesh and a material class and differ only in their
  /// [BoxDecoration3dUniforms]. That is the whole economy of the shader bet,
  /// and a key that mentioned any of those fields would throw it away.
  @override
  Object get cacheKey => BoxDecoration3d;

  /// Never. Two panels differ only in uniforms, whatever changed.
  @override
  bool shouldRebuild(BoxDecoration3d old) => false;

  @override
  Decoration3dPainter? createPainter() => painterFactory?.call(this);

  @override
  bool operator ==(Object other) =>
      other is BoxDecoration3d &&
      other.color == color &&
      other.gradient == gradient &&
      other.image == image &&
      other.borderRadius == borderRadius &&
      other.bevel == bevel &&
      other.border == border &&
      other.elevation == elevation &&
      other.surfaceTint == surfaceTint;

  @override
  int get hashCode => Object.hash(
    color,
    gradient,
    image,
    borderRadius,
    bevel,
    border,
    elevation,
    surfaceTint,
  );

  @override
  String toString() =>
      'BoxDecoration3d($color, $borderRadius, elevation: $elevation)';
}

/// One panel's parameter set: everything the signed-distance shader needs,
/// in world units, with the state layer and the clip already folded in.
///
/// The arithmetic half of the shader bet, separated out so it can be checked
/// without a GPU. Resolving a decoration against a size produces this; a
/// painter writes it onto a material and scales a shared slab, and nothing
/// about a size, a colour or a state change touches geometry.
///
/// The parameter names are the ones declared in the package's
/// `assets/box_decoration3d.fmat`, and [applyTo] writes exactly those. A
/// caller with a shader of its own can read the fields directly.
class BoxDecoration3dUniforms {
  /// Creates a parameter set outright, for a caller assembling one by hand.
  const BoxDecoration3dUniforms({
    required this.halfExtent,
    required this.radius,
    required this.bevel,
    required this.borderWidth,
    required this.color,
    required this.borderColor,
    required this.stateLayerColor,
    required this.surfaceTintColor,
    required this.clipPlanes,
    this.gradient,
    this.image = ImageUniforms3d.none,
    this.rippleOrigin = Offset3d.zero,
    this.rippleRadius = 0.0,
    this.rippleOpacity = 0.0,
  });

  /// Resolves [decoration] against a box of [size].
  ///
  /// The conversions, in the order they happen and for the reasons they
  /// happen in it: logical pixels become world units through [metrics], the
  /// corner radii are held down to what the box can fit (so a panel animating
  /// to nothing degenerates instead of folding inside out), the border is
  /// held to half the smaller face extent (so it cannot cross itself), the
  /// state layer's opacity is folded into its colour's alpha, and the
  /// elevation is turned into a surface-tint alpha through Material's table.
  ///
  /// The ripple is the exception to the first of those: [StateLayer3d.ripple]
  /// arrives in world units already and is copied across untouched. See
  /// [Ripple3d] for why it is measured differently from everything else here.
  factory BoxDecoration3dUniforms.resolve({
    required BoxDecoration3d decoration,
    required Size3d size,
    required Layout3dMetrics metrics,
    StateLayer3d stateLayer = StateLayer3d.none,
    Clip3dRegion clip = Clip3dRegion.none,
    Size? imagePixelSize,
    double imageScale = 1.0,
    TextDirection? textDirection,
  }) {
    final radius = (decoration.borderRadius * metrics.unitsPerLogicalPixel)
        .resolve(size);
    final halfFace =
        0.5 * (size.width < size.height ? size.width : size.height);
    final borderWidth = decoration.border.isNone
        ? 0.0
        : metrics.dp(decoration.border.width).clamp(0.0, halfFace);
    final tint = decoration.surfaceTint;
    final ripple = stateLayer.ripple;
    final gradient = decoration.gradient;
    final image = decoration.image;
    return BoxDecoration3dUniforms(
      halfExtent: size * 0.5,
      radius: radius,
      bevel: metrics
          .dp(decoration.bevel)
          .clamp(0.0, size.depth <= 0.0 ? 0.0 : size.depth / 2.0),
      borderWidth: borderWidth,
      color: decoration.color,
      borderColor: decoration.border.color,
      stateLayerColor: stateLayer.resolvedColor,
      surfaceTintColor: tint == null
          ? const Color(0x00000000)
          : tint.withValues(
              alpha:
                  tint.a *
                  BoxDecoration3d.surfaceTintOpacityFor(decoration.elevation),
            ),
      clipPlanes: clip.toPlaneBlock(),
      gradient: gradient == null
          ? null
          : GradientUniforms3d.resolve(
              gradient: gradient,
              size: size,
              textDirection: textDirection,
            ),
      image: image == null
          ? ImageUniforms3d.none
          : ImageUniforms3d.resolve(
              image: image,
              size: size,
              metrics: metrics,
              pixelSize: imagePixelSize,
              imageScale: imageScale,
              textDirection: textDirection,
            ),
      rippleOrigin: ripple?.origin ?? Offset3d.zero,
      rippleRadius: ripple?.radius ?? 0.0,
      rippleOpacity: ripple == null ? 0.0 : stateLayer.color.a * ripple.opacity,
    );
  }

  /// Half the box's extent, which is what an SDF over a slab centred on its
  /// own origin measures against.
  final Size3d halfExtent;

  /// The four corner radii, in world units, already held down to [halfExtent].
  final BorderRadius3d radius;

  /// The rim rounding along the depth axis, in world units.
  final double bevel;

  /// The border's thickness, in world units, drawn inside the outline.
  final double borderWidth;

  /// The slab's colour, in the sRGB space `setColor` decodes from.
  final Color color;

  /// The border's colour.
  final Color borderColor;

  /// The state overlay, its opacity already folded into its alpha.
  final Color stateLayerColor;

  /// The elevation tint, its opacity already derived from the elevation.
  final Color surfaceTintColor;

  /// The clip block, `xyz` a normal and `w` a distance, padded to
  /// [Clip3dRegion.maxPlanes] entries.
  final List<double> clipPlanes;

  /// The gradient filling the slab, or null for none — including for a
  /// gradient this package cannot draw, which is reported rather than
  /// substituted.
  final GradientUniforms3d? gradient;

  /// Where the picture lands, and how much of it to draw.
  ///
  /// [ImageUniforms3d.none] when the decoration has no picture **and while it
  /// has one that has not arrived**, which is what keeps a panel from drawing
  /// the sampler's white placeholder over its own colour for a frame.
  final ImageUniforms3d image;

  /// Where the press ripple is centred, in world units, in the box's own
  /// frame with the origin at its corner.
  ///
  /// The shader moves it to the centre frame the signed distance field works
  /// in; a caller with a shader of its own has to do the same.
  final Offset3d rippleOrigin;

  /// How far the ripple has expanded, in world units. Zero for none.
  final double rippleRadius;

  /// The ripple's alpha, with the state layer's own alpha already folded in,
  /// exactly as [stateLayerColor]'s is.
  ///
  /// The ripple's *colour* is [stateLayerColor]'s: Material's ripple is the
  /// press wash arriving from a point, not a second wash. See [Ripple3d].
  final double rippleOpacity;

  /// The radii in the order the shader's `vec4` expects them.
  ///
  /// Top-left, top-right, bottom-right, bottom-left — clockwise from the
  /// origin corner, which is the order every rounded-box SDF on the internet
  /// is written in, so the shader reads the way its source does.
  List<double> get radiusVector => <double>[
    radius.topLeft,
    radius.topRight,
    radius.bottomRight,
    radius.bottomLeft,
  ];

  /// Writes this parameter set onto [parameters].
  ///
  /// The names are the ones `assets/box_decoration3d.fmat` declares. Nothing
  /// here allocates a buffer or touches geometry: a frame of animation is
  /// this call and nothing else, which is the property the whole design is
  /// arranged around.
  void applyTo(MaterialParameters parameters) {
    parameters
      ..setVec3(
        'half_extent',
        Vector3(halfExtent.width, halfExtent.height, halfExtent.depth),
      )
      ..setVec4(
        'corner_radius',
        Vector4(
          radius.topLeft,
          radius.topRight,
          radius.bottomRight,
          radius.bottomLeft,
        ),
      )
      ..setFloat('bevel', bevel)
      ..setFloat('border_width', borderWidth)
      ..setColor('color', color)
      ..setColor('border_color', borderColor)
      ..setColor('state_layer', stateLayerColor)
      ..setVec2('ripple_origin', Vector2(rippleOrigin.x, rippleOrigin.y))
      ..setVec2('ripple', Vector2(rippleRadius, rippleOpacity))
      ..setColor('surface_tint', surfaceTintColor)
      ..setVec4(
        'image_rect',
        Vector4(
          image.destination.left,
          image.destination.top,
          image.destination.width,
          image.destination.height,
        ),
      )
      ..setVec4(
        'image_source',
        Vector4(
          image.source.left,
          image.source.top,
          image.source.right,
          image.source.bottom,
        ),
      )
      ..setFloat('image_opacity', image.opacity);
    final gradient = this.gradient;
    final descriptor = gradient?.descriptor ?? const <double>[0, 0, 0, 0];
    parameters
      ..setVec4(
        'gradient',
        Vector4(descriptor[0], descriptor[1], descriptor[2], descriptor[3]),
      )
      ..setVec4(
        'gradient_geometry',
        gradient == null
            ? Vector4.zero()
            : Vector4(
                gradient.geometry[0],
                gradient.geometry[1],
                gradient.geometry[2],
                gradient.geometry[3],
              ),
      );
    for (var i = 0; i < 2; i++) {
      final stops = gradient?.stopVector(i) ?? const <double>[0, 0, 0, 0];
      parameters.setVec4(
        'gradient_stops_$i',
        Vector4(stops[0], stops[1], stops[2], stops[3]),
      );
    }
    for (var i = 0; i < GradientUniforms3d.maxStops; i++) {
      final colors = gradient?.colors;
      final color = colors != null && i < colors.length
          ? colors[i]
          : const Color(0x00000000);
      // **`setVec4`, not `setColor`.** These are the sRGB values the shader
      // interpolates between before it decodes them, and `setColor` would
      // decode each stop on its own — which is a different colour ramp, and
      // not the one the same gradient draws in two dimensions.
      parameters.setVec4(
        'gradient_color_$i',
        Vector4(color.r, color.g, color.b, color.a),
      );
    }
    for (var i = 0; i < Clip3dRegion.maxPlanes; i++) {
      parameters.setVec4(
        'clip_plane_$i',
        Vector4(
          clipPlanes[i * 4],
          clipPlanes[i * 4 + 1],
          clipPlanes[i * 4 + 2],
          clipPlanes[i * 4 + 3],
        ),
      );
    }
  }

  @override
  String toString() =>
      'BoxDecoration3dUniforms($halfExtent, $radius, border: $borderWidth)';
}
