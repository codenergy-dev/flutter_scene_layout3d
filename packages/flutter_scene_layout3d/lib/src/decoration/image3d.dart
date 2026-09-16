import 'dart:ui' show Color;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, EnumProperty;
import 'package:flutter/painting.dart'
    show
        Alignment,
        AlignmentGeometry,
        BoxFit,
        ImageErrorListener,
        ImageProvider,
        Size;

import '../geometry/border_radius3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import 'box_decoration.dart';
import 'decorated_box.dart';
import 'decoration_image.dart';

/// A picture, as a box of its own.
///
/// The 3D counterpart of `Image`, and it is a [DecoratedBox3d] underneath
/// rather than a leaf with a quad in it. That is the whole design decision of
/// this feature in one sentence: **the picture is drawn by the panel shader**,
/// so a corner radius carves it, a border frames it, a hover washes it, a
/// press ripples across it and a clip cuts it — none of which a separate
/// textured quad could be given, because a rounded clip does not exist here.
///
/// ```dart
/// Image3d(
///   image: const AssetImage('assets/avatar.jpg'),
///   fit: BoxFit.cover,
///   borderRadius: const BorderRadius3d.circular(999),   // a circle
/// )
/// ```
///
/// **It sizes itself to the picture, once the picture arrives.** With no
/// picture yet it takes the smallest size its constraints allow, exactly as
/// `RenderImage` does, and lays out again when the size is known — which
/// moves whatever is beside it, once. Give it a [SizedBox3d] (or tight
/// constraints) when that matters, which is Flutter's advice for the same
/// reason.
class Image3d extends DecoratedBox3d {
  /// Creates a box drawing [image].
  Image3d({
    required ImageProvider image,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    double opacity = 1.0,
    bool matchTextDirection = false,
    ImageErrorListener? onError,
    BorderRadius3d borderRadius = BorderRadius3d.zero,
    Border3d border = Border3d.none,
    super.configuration,
    ImageTexture3dCache? pictures,
    super.name,
  }) : _image = image,
       _fit = fit,
       _alignment = alignment,
       _opacity = opacity,
       _matchTextDirection = matchTextDirection,
       _onError = onError,
       _borderRadius = borderRadius,
       _border = border,
       _pictures = pictures ?? ImageTexture3dCache.shared,
       super(
         decoration: _decorationFor(
           image: image,
           fit: fit,
           alignment: alignment,
           opacity: opacity,
           matchTextDirection: matchTextDirection,
           onError: onError,
           borderRadius: borderRadius,
           border: border,
         ),
       );

  /// The decoration a set of these fields comes to.
  ///
  /// The colour is **transparent**: a picture's box is the picture, and a
  /// fill behind it would show wherever the fit leaves the box uncovered.
  /// Put the box in a `DecoratedBox3d` for a surface to stand it on.
  static BoxDecoration3d _decorationFor({
    required ImageProvider image,
    required BoxFit? fit,
    required AlignmentGeometry alignment,
    required double opacity,
    required bool matchTextDirection,
    required ImageErrorListener? onError,
    required BorderRadius3d borderRadius,
    required Border3d border,
  }) => BoxDecoration3d(
    color: const Color(0x00000000),
    borderRadius: borderRadius,
    border: border,
    image: DecorationImage3d(
      image: image,
      fit: fit,
      alignment: alignment,
      opacity: opacity,
      matchTextDirection: matchTextDirection,
      onError: onError,
    ),
  );

  final ImageTexture3dCache _pictures;

  ImageProvider _image;

  /// Where the pixels come from.
  ImageProvider get image => _image;

  set image(ImageProvider value) {
    if (_image == value) return;
    _image = value;
    _releasePicture();
    _rebuildDecoration();
    // A different picture is a different size, and the size is a layout
    // input here — unlike on a decoration, where it is not.
    markNeedsLayout();
  }

  BoxFit? _fit;

  /// How the picture fills the box, or null for [BoxFit.scaleDown].
  BoxFit? get fit => _fit;

  set fit(BoxFit? value) {
    if (_fit == value) return;
    _fit = value;
    _rebuildDecoration();
  }

  AlignmentGeometry _alignment;

  /// Where the picture sits inside the box.
  AlignmentGeometry get alignment => _alignment;

  set alignment(AlignmentGeometry value) {
    if (_alignment == value) return;
    _alignment = value;
    _rebuildDecoration();
  }

  double _opacity;

  /// How much of the picture to draw.
  double get opacity => _opacity;

  set opacity(double value) {
    if (_opacity == value) return;
    _opacity = value;
    _rebuildDecoration();
  }

  bool _matchTextDirection;

  /// Whether the picture is mirrored in a right-to-left reading.
  bool get matchTextDirection => _matchTextDirection;

  set matchTextDirection(bool value) {
    if (_matchTextDirection == value) return;
    _matchTextDirection = value;
    _rebuildDecoration();
  }

  ImageErrorListener? _onError;

  /// Called when the picture cannot be loaded.
  ImageErrorListener? get onError => _onError;

  set onError(ImageErrorListener? value) {
    if (_onError == value) return;
    _onError = value;
    _rebuildDecoration();
  }

  BorderRadius3d _borderRadius;

  /// The corners the picture is cut to, in logical pixels.
  ///
  /// What a `ClipRRect` around a Flutter `Image` does, stated where it can be
  /// honoured: the radius is carved out of the same signed distance field the
  /// picture is sampled in. A radius larger than the box is held down to half
  /// its shorter side, so a big enough one is a circle.
  BorderRadius3d get borderRadius => _borderRadius;

  set borderRadius(BorderRadius3d value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    _rebuildDecoration();
  }

  Border3d _border;

  /// A line drawn round the picture, inside its outline.
  Border3d get border => _border;

  set border(Border3d value) {
    if (_border == value) return;
    _border = value;
    _rebuildDecoration();
  }

  void _rebuildDecoration() {
    decoration = _decorationFor(
      image: _image,
      fit: _fit,
      alignment: _alignment,
      opacity: _opacity,
      matchTextDirection: _matchTextDirection,
      onError: _onError,
      borderRadius: _borderRadius,
      border: _border,
    );
  }

  ImageTexture3d? _picture;
  Size? _laidOutPixelSize;
  double _laidOutScale = 1.0;

  /// The picture this box is drawing, or waiting for, once it has been laid
  /// out at least once.
  ///
  /// Null before that: a box acquires its picture when it is laid out, so
  /// that constructing one in an application that has not started its engine
  /// yet costs nothing and touches no binding.
  ImageTexture3d? get picture => _picture;

  /// The picture's extent in logical pixels, or null until it has arrived.
  Size? get intrinsicSize => _picture?.size;

  void _acquirePicture() {
    final held = _picture;
    final key = ImageTexture3dCache.keyConfigurationOf(configuration);
    if (held != null && held.provider == _image && held.configuration == key) {
      return;
    }
    _releasePicture();
    final picture = _picture = _pictures.acquire(_image, configuration);
    picture.addListener(_onPicture);
    final onError = _onError;
    if (onError != null) picture.addErrorListener(onError);
  }

  void _releasePicture() {
    final picture = _picture;
    if (picture == null) return;
    picture.removeListener(_onPicture);
    final onError = _onError;
    if (onError != null) picture.removeErrorListener(onError);
    _picture = null;
    _laidOutPixelSize = null;
    _pictures.release(picture);
  }

  /// The picture said something. Only a change of *size* is this box's
  /// business: the texture arriving is the painter's, and it has a listener
  /// of its own.
  void _onPicture() {
    final picture = _picture;
    if (picture == null) return;
    if (picture.pixelSize == _laidOutPixelSize &&
        picture.scale == _laidOutScale) {
      return;
    }
    markNeedsLayout();
  }

  /// The size this box takes under [constraints], which is the picture's own
  /// logical size held to what it is allowed.
  ///
  /// `RenderImage._sizeForConstraints`, in world units: the picture's pixels
  /// over its scale are logical pixels, the metrics turn those into units,
  /// and the ratio is kept. With no picture yet it is the smallest size
  /// allowed — which is why a box with loose constraints appears to have
  /// nothing in it for a frame or two.
  Size3d sizeFor(Constraints3d constraints) {
    final size = _picture?.size;
    if (size == null || size.isEmpty) return constraints.smallest;
    final units = metrics.unitsPerLogicalPixel;
    return constraints.constrainSizeAndAttemptToPreserveAspectRatio(
      Size3d(size.width * units, size.height * units, 0.0),
    );
  }

  @override
  void performLayout() {
    _acquirePicture();
    final picture = _picture;
    _laidOutPixelSize = picture?.pixelSize;
    _laidOutScale = picture?.scale ?? 1.0;
    size = sizeFor(constraints);
    applyNodeTransform();
    repaint();
  }

  /// A picture asks for exactly its own size, and gives it up under pressure.
  ///
  /// The minimum is zero and the maximum is what the picture would take, the
  /// pair `RenderImage` answers: a picture scales rather than reflows, so
  /// there is nothing it has to give up below any particular extent, and
  /// nothing more room buys past its own size.
  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) => 0.0;

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) {
    final size = _picture?.size;
    if (size == null || size.isEmpty) return 0.0;
    final units = metrics.unitsPerLogicalPixel;
    final width = size.width * units;
    final height = size.height * units;
    return switch (axis) {
      Axis3d.horizontal =>
        limits.height.isFinite && limits.height > 0.0
            ? width * (limits.height / height)
            : width,
      Axis3d.vertical =>
        limits.width.isFinite && limits.width > 0.0
            ? height * (limits.width / width)
            : height,
      Axis3d.depth => 0.0,
    };
  }

  @override
  void dispose() {
    _releasePicture();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ImageProvider>('image', image));
    properties.add(EnumProperty<BoxFit>('fit', fit, defaultValue: null));
    properties.add(
      DiagnosticsProperty<AlignmentGeometry>('alignment', alignment),
    );
    properties.add(
      DiagnosticsProperty<Size>(
        'intrinsicSize',
        intrinsicSize,
        defaultValue: null,
        ifNull: 'not arrived',
      ),
    );
  }
}
