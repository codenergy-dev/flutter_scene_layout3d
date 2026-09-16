import 'dart:typed_data';
import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, FlutterError, FlutterErrorDetails, ErrorDescription;
import 'dart:ui' show lerpDouble;

import 'package:flutter/painting.dart'
    show
        Alignment,
        AlignmentGeometry,
        BoxFit,
        FittedSizes,
        ImageConfiguration,
        ImageErrorListener,
        ImageInfo,
        ImageProvider,
        ImageStream,
        ImageStreamListener,
        Offset,
        Rect,
        Size,
        TextDirection,
        applyBoxFit;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart'
    show Texture2D, TextureSampling, TextureSource;

import '../geometry/size3d.dart';
import '../metrics.dart';

/// A picture drawn on a decoration: which picture, how it is fitted, and how
/// much of it to draw.
///
/// The 3D counterpart of `DecorationImage`, and it is a type of this
/// package's own rather than Flutter's for one reason: **more than half of
/// Flutter's fields could not be honoured here**, and a field that is
/// silently ignored is worse than one that does not exist. What is missing,
/// and why, is in the class's own section of the package README — repeat,
/// centre slicing, colour filters, inverted colours and filter quality are
/// all things the panel shader does not do.
///
/// Everything it *does* take is Flutter's vocabulary, unchanged:
/// [ImageProvider] for what to draw, [BoxFit] for how it fills the box,
/// [AlignmentGeometry] for where it sits, and Flutter's own defaults,
/// including the one that is easy to miss — **a null [fit] is
/// [BoxFit.scaleDown]**, which is what `paintImage` defaults to.
///
/// ```dart
/// DecoratedBox3d(
///   decoration: BoxDecoration3d(
///     borderRadius: const BorderRadius3d.circular(12),
///     image: DecorationImage3d(
///       image: const AssetImage('assets/cover.jpg'),
///       fit: BoxFit.cover,
///     ),
///   ),
/// )
/// ```
///
/// **The picture is drawn by the panel shader**, not as a quad of its own,
/// which is what makes that corner radius cut it. It arrives late — an
/// [ImageProvider] resolves asynchronously and the texture has to be uploaded
/// — so a decorated box draws its colour first and its picture on a later
/// frame, without laying anything out again. See [ImageTexture3d].
class DecorationImage3d {
  /// Describes a picture on a decoration.
  const DecorationImage3d({
    required this.image,
    this.fit,
    this.alignment = Alignment.center,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.matchTextDirection = false,
    this.onError,
  }) : assert(scale > 0.0),
       assert(opacity >= 0.0 && opacity <= 1.0);

  /// Where the pixels come from.
  final ImageProvider image;

  /// How the picture fills the box, or null for Flutter's own default,
  /// [BoxFit.scaleDown].
  final BoxFit? fit;

  /// Where the picture sits when it does not fill the box, and which part of
  /// it is kept when it overflows.
  ///
  /// A directional alignment is resolved against the text direction of the
  /// [ImageConfiguration] the box is painted with.
  final AlignmentGeometry alignment;

  /// How many image pixels there are to a logical pixel, on top of whatever
  /// the provider itself reports.
  ///
  /// Multiplied with `ImageInfo.scale`, exactly as `DecorationImage.scale`
  /// is: a `2.0x` asset resolved at two pixels per logical pixel and given a
  /// scale of 2 here draws at four.
  final double scale;

  /// How much of the picture to draw, from zero to one.
  final double opacity;

  /// Whether the picture is mirrored in a right-to-left reading.
  ///
  /// For a picture that means *forward* — an arrow, a chevron, a swipe
  /// illustration. Flutter asserts when there is no text direction to match;
  /// here, as everywhere else in this package, a missing direction reads left
  /// to right.
  final bool matchTextDirection;

  /// Called when the picture cannot be loaded.
  ///
  /// Without one, a failure is reported through [FlutterError] the way
  /// Flutter's own image loading reports it. It is per *decoration*: two
  /// boxes sharing a provider share the load, and each of their listeners is
  /// told.
  final ImageErrorListener? onError;

  /// A copy with the given fields replaced.
  ///
  /// [fit] and [onError] cannot be cleared this way; construct a new value
  /// for that, as `copyWith` on a nullable field always has to be used.
  DecorationImage3d copyWith({
    ImageProvider? image,
    BoxFit? fit,
    AlignmentGeometry? alignment,
    double? scale,
    double? opacity,
    bool? matchTextDirection,
    ImageErrorListener? onError,
  }) => DecorationImage3d(
    image: image ?? this.image,
    fit: fit ?? this.fit,
    alignment: alignment ?? this.alignment,
    scale: scale ?? this.scale,
    opacity: opacity ?? this.opacity,
    matchTextDirection: matchTextDirection ?? this.matchTextDirection,
    onError: onError ?? this.onError,
  );

  /// Linearly interpolates between two pictures.
  ///
  /// **One sampler holds one picture**, so this cannot cross-fade between two
  /// different ones the way Flutter's `DecorationImage.lerp` does: when both
  /// ends name different providers the picture changes at the midpoint. What
  /// does interpolate is everything a single picture can do — its opacity as
  /// it appears or disappears, which is the case an implicit animation
  /// actually meets, and its alignment and scale when both ends are the same
  /// picture.
  static DecorationImage3d? lerp(
    DecorationImage3d? a,
    DecorationImage3d? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (t <= 0.0) return a;
    if (t >= 1.0) return b;
    if (a == null) return b!.copyWith(opacity: b.opacity * t);
    if (b == null) return a.copyWith(opacity: a.opacity * (1.0 - t));
    if (a.image != b.image) return t < 0.5 ? a : b;
    return DecorationImage3d(
      image: b.image,
      fit: t < 0.5 ? a.fit : b.fit,
      alignment: AlignmentGeometry.lerp(a.alignment, b.alignment, t)!,
      scale: lerpDouble(a.scale, b.scale, t)!,
      opacity: lerpDouble(a.opacity, b.opacity, t)!.clamp(0.0, 1.0),
      matchTextDirection: t < 0.5 ? a.matchTextDirection : b.matchTextDirection,
      onError: t < 0.5 ? a.onError : b.onError,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DecorationImage3d &&
      other.image == image &&
      other.fit == fit &&
      other.alignment == alignment &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.matchTextDirection == matchTextDirection &&
      other.onError == onError;

  @override
  int get hashCode => Object.hash(
    image,
    fit,
    alignment,
    scale,
    opacity,
    matchTextDirection,
    onError,
  );

  @override
  String toString() => 'DecorationImage3d($image, ${fit ?? BoxFit.scaleDown})';
}

/// A rasterized picture, on its way to the GPU.
///
/// RGBA8888, straight alpha, row-major from the top-left, which is what
/// [Texture2D.fromPixels] takes — the same shape a rasterized glyph atlas
/// arrives in, and for the same reason: everything up to this point runs in
/// `flutter test`.
class ImageTexture3dPixels {
  /// Records the pixels of one picture.
  const ImageTexture3dPixels(this.pixels, this.width, this.height);

  /// The texels, four bytes each.
  final Uint8List pixels;

  /// The picture's extent, in image pixels.
  final int width;
  final int height;
}

/// Uploads a decoded picture to the GPU.
///
/// The one GPU-shaped step in the whole path, kept behind a function so that
/// resolving a provider, decoding it and reading its bytes back can all be
/// tested headlessly. [GlyphAtlasUpload3d] is the same seam for type.
typedef ImageTexture3dUpload = TextureSource? Function(ImageTexture3dPixels);

/// The default uploader: a clamped, mipmapped texture.
///
/// **Clamped**, because a picture is drawn into a rectangle the shader
/// feathers at its edge, and a repeating sampler would wrap that feather onto
/// the opposite side of the image.
///
/// **Mipmapped**, which is the opposite of what a glyph atlas wants and right
/// for the same reason it is wrong there: an atlas packs unrelated letters
/// side by side, while a photograph is one continuous image, and a panel the
/// viewer walks away from minifies it. The cost is a mip chain built on the
/// CPU at upload, which for a camera-sized photograph is real — hand the
/// provider to Flutter's own `ResizeImage` when the picture is much bigger
/// than the panel it is drawn on.
TextureSource? uploadImageTexture(ImageTexture3dPixels pixels) =>
    Texture2D.fromPixels(
      pixels.pixels,
      pixels.width,
      pixels.height,
      sampling: const TextureSampling(
        addressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );

/// One picture, arriving.
///
/// The image half of the same bargain the glyph atlas strikes: a provider
/// resolves asynchronously, a decoded image has to be read back and uploaded,
/// and a layout pass cannot wait for any of it. So a box asks for this
/// synchronously, gets an object with nothing in it, and is told twice —
/// **once when the size is known, and once when the texture is**, because
/// those two answers have different customers. [Image3d] sizes itself to the
/// first; the painter binds the second.
///
/// It is deliberately **not** a counter, which is where this diverges from
/// [GlyphAtlas3d]. An atlas needs `generation`, `revision` and
/// `outlineRevision` because it is one texture whose contents keep changing
/// under meshes already baked from it, so a renderer cannot tell by looking
/// whether its letters are still in there. A picture's arrival is a value: a
/// texture that was null and now is not, a size that was unknown and now is.
/// Comparing the value is the whole answer.
///
/// Shared through [ImageTexture3dCache], so two boxes drawing the same
/// picture decode and upload it once.
class ImageTexture3d extends ChangeNotifier {
  /// Starts resolving [provider] against [configuration].
  ///
  /// Prefer [ImageTexture3dCache.acquire], which shares one of these between
  /// every box drawing the same picture. Constructing one directly is for a
  /// caller that wants a picture nothing else can reach.
  ImageTexture3d({
    required this.provider,
    this.configuration = ImageConfiguration.empty,
    ImageTexture3dUpload upload = uploadImageTexture,
  }) : _upload = upload {
    _resolve();
  }

  /// Where the pixels come from.
  final ImageProvider provider;

  /// What the provider was resolved against.
  final ImageConfiguration configuration;

  final ImageTexture3dUpload _upload;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _disposed = false;

  Size? _pixelSize;
  double _scale = 1.0;
  TextureSource? _texture;
  Object? _error;

  final Map<ImageErrorListener, int> _errorListeners =
      <ImageErrorListener, int>{};

  /// The picture's extent in image pixels, or null until the provider has
  /// produced a frame.
  ///
  /// This is what arrives *first*, and it is the answer a box that sizes
  /// itself to its picture is waiting for.
  Size? get pixelSize => _pixelSize;

  /// How many image pixels there are to a logical pixel, from the provider.
  ///
  /// One until a frame arrives. `ImageInfo.scale`, which is how a `2.0x`
  /// asset comes out the size the `1.0x` one would have been.
  double get scale => _scale;

  /// The picture's extent in logical pixels, or null until it has arrived.
  Size? get size {
    final pixels = _pixelSize;
    return pixels == null ? null : pixels / _scale;
  }

  /// The uploaded texture, or null until the pixels have been read back.
  TextureSource? get texture => _texture;

  /// Whether the picture has been drawn at all yet.
  bool get isReady => _texture != null;

  /// What went wrong, or null.
  Object? get error => _error;

  /// Adds a listener for a failure to load this picture.
  ///
  /// Called immediately when the picture has already failed, which is what
  /// keeps a box that arrives late from missing the only notice. The same
  /// listener added twice is called once — two boxes built from one
  /// `DecorationImage3d` hand over the same closure, and a failure they share
  /// is one failure.
  void addErrorListener(ImageErrorListener listener) {
    final count = _errorListeners[listener];
    _errorListeners[listener] = (count ?? 0) + 1;
    final error = _error;
    if (count == null && error != null) listener(error, null);
  }

  /// Removes a listener added by [addErrorListener].
  void removeErrorListener(ImageErrorListener listener) {
    final count = _errorListeners[listener];
    if (count == null) return;
    if (count <= 1) {
      _errorListeners.remove(listener);
    } else {
      _errorListeners[listener] = count - 1;
    }
  }

  void _resolve() {
    final stream = _stream = provider.resolve(configuration);
    final listener = _listener = ImageStreamListener(
      _handleImage,
      onError: _handleError,
    );
    stream.addListener(listener);
  }

  void _handleImage(ImageInfo info, bool synchronous) {
    // **The first frame and no more.** An animated image delivers a frame on
    // every tick of its own clock, and a texture upload per frame is exactly
    // the cost the decoration design exists to avoid. Dropping the listener
    // here is what stops a GIF from doing that; it draws its first frame and
    // stands still.
    _stopListening();
    if (_disposed) {
      info.dispose();
      return;
    }
    _pixelSize = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    _scale = info.scale;
    // The size is an answer of its own, and a box waiting to be laid out
    // wants it now rather than when the pixels have been read back.
    notifyListeners();
    _read(info);
  }

  Future<void> _read(ImageInfo info) async {
    try {
      final texture = await _decode(info.image);
      if (_disposed) return;
      _texture = texture;
      notifyListeners();
    } catch (exception, stack) {
      _handleError(exception, stack);
    } finally {
      info.dispose();
    }
  }

  Future<TextureSource?> _decode(ui.Image image) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) {
      throw StateError('A picture could not be read back for the GPU.');
    }
    return _upload(
      ImageTexture3dPixels(
        bytes.buffer.asUint8List(),
        image.width,
        image.height,
      ),
    );
  }

  void _handleError(Object exception, StackTrace? stack) {
    _stopListening();
    if (_disposed) return;
    _error = exception;
    if (_errorListeners.isEmpty) {
      // Nobody asked to hear about it, so it is reported the way Flutter
      // reports an image that fails under a widget with no `errorBuilder`: a
      // picture that quietly does not appear is a bad afternoon.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'flutter_scene_layout3d',
          context: ErrorDescription('while loading $provider'),
        ),
      );
    } else {
      for (final listener in _errorListeners.keys.toList()) {
        listener(exception, stack);
      }
    }
    notifyListeners();
  }

  void _stopListening() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _listener = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    _stream = null;
    _texture = null;
    _errorListeners.clear();
    super.dispose();
  }

  @override
  String toString() =>
      'ImageTexture3d($provider, ${_pixelSize ?? 'unresolved'}'
      '${_texture == null ? '' : ', uploaded'})';
}

/// The pictures an application has, one per provider.
///
/// A list of fifty rows showing the same avatar should decode it once and
/// upload it once, and the box that asks for it does not know about the other
/// forty-nine — so the sharing lives here, exactly as a glyph atlas's does in
/// [GlyphAtlasCache3d].
///
/// **Reference counted**, unlike the atlas cache: a picture is much bigger
/// than an alphabet and an application scrolls through many of them, so the
/// last box to let go of one is what drops it. [acquire] and [release] come
/// in pairs; a box acquires when it is first laid out or painted and releases
/// when it is disposed.
class ImageTexture3dCache {
  /// Creates a cache whose pictures are uploaded with [upload].
  ImageTexture3dCache({this.upload = uploadImageTexture});

  /// The cache every box shares unless told otherwise.
  static final ImageTexture3dCache shared = ImageTexture3dCache();

  /// How a decoded picture reaches the GPU. See [ImageTexture3dUpload].
  final ImageTexture3dUpload upload;

  final Map<(ImageProvider, ImageConfiguration), _PictureEntry> _entries =
      <(ImageProvider, ImageConfiguration), _PictureEntry>{};

  /// How many distinct pictures are alive.
  int get length => _entries.length;

  /// The picture for [provider], starting to load it if this is the first box
  /// to ask.
  ///
  /// The configuration is stripped of the two fields that must not split the
  /// cache — the box's own size, and the text direction, which decides how a
  /// picture is *placed* rather than which pixels it has. A right-to-left
  /// screen and a left-to-right one share one upload.
  ImageTexture3d acquire(
    ImageProvider provider, [
    ImageConfiguration configuration = ImageConfiguration.empty,
  ]) {
    final key = (provider, keyConfigurationOf(configuration));
    final entry = _entries[key];
    if (entry != null) {
      entry.users++;
      return entry.picture;
    }
    final picture = ImageTexture3d(
      provider: provider,
      configuration: key.$2,
      upload: upload,
    );
    _entries[key] = _PictureEntry(picture);
    return picture;
  }

  /// Gives up one use of [picture], disposing it when nothing is left.
  void release(ImageTexture3d picture) {
    final key = (picture.provider, picture.configuration);
    final entry = _entries[key];
    if (entry == null || !identical(entry.picture, picture)) return;
    entry.users--;
    if (entry.users > 0) return;
    _entries.remove(key);
    entry.picture.dispose();
  }

  /// Drops every picture, and the textures they hold.
  ///
  /// A box still pointing at one keeps drawing it until it asks again.
  void clear() {
    for (final entry in _entries.values) {
      entry.picture.dispose();
    }
    _entries.clear();
  }

  /// The part of [configuration] that decides *which pixels* a provider
  /// yields, which is what a picture is keyed by.
  static ImageConfiguration keyConfigurationOf(
    ImageConfiguration configuration,
  ) => ImageConfiguration(
    bundle: configuration.bundle,
    devicePixelRatio: configuration.devicePixelRatio,
    locale: configuration.locale,
    platform: configuration.platform,
  );
}

class _PictureEntry {
  _PictureEntry(this.picture);

  final ImageTexture3d picture;
  int users = 1;
}

/// Where a picture lands on a box, resolved against everything that decides
/// it: the fit, the alignment, the direction and the unit contract.
///
/// The arithmetic half of drawing a picture, separated out for the reason
/// every other piece of arithmetic here is: it is checkable in `flutter test`
/// against Flutter's own `applyBoxFit` and `Alignment.inscribe`, while the
/// drawing needs a GPU.
///
/// [destination] is in **world units**, in the box's own frame with the
/// origin at its corner — the same frame the clip planes and the ripple are
/// measured in. [source] is in texture coordinates. Either rectangle may
/// reach outside its own space: a `BoxFit.cover` picture is drawn wider than
/// the box and cut by the outline, exactly as Flutter clips a decoration
/// image to its rounded rectangle.
class ImageUniforms3d {
  /// Records a resolved placement.
  const ImageUniforms3d({
    required this.destination,
    required this.source,
    required this.opacity,
  });

  /// Nothing to draw.
  static const ImageUniforms3d none = ImageUniforms3d(
    destination: Rect.zero,
    source: Rect.zero,
    opacity: 0.0,
  );

  /// Resolves where [image] lands on a box of [size].
  ///
  /// [pixelSize] and [imageScale] are the picture's own extent and scale, as
  /// [ImageTexture3d] reports them; null means the picture has not arrived,
  /// and the answer is [none].
  ///
  /// This is `paintImage` in three dimensions, and the order is Flutter's:
  /// the picture's logical size is its pixels over the scale, `applyBoxFit`
  /// gives the fitted source and destination, the destination is placed in
  /// the box by the alignment and the source is taken from the picture by the
  /// same alignment. The one conversion Flutter does not have is the last
  /// one: everything above is in logical pixels, because that is what a
  /// [BoxFit.none] or a [BoxFit.scaleDown] compares, and the destination is
  /// turned into world units at the end.
  factory ImageUniforms3d.resolve({
    required DecorationImage3d image,
    required Size3d size,
    required Layout3dMetrics metrics,
    Size? pixelSize,
    double imageScale = 1.0,
    TextDirection? textDirection,
  }) {
    if (pixelSize == null ||
        pixelSize.isEmpty ||
        image.opacity <= 0.0 ||
        size.width <= 0.0 ||
        size.height <= 0.0) {
      return none;
    }
    final units = metrics.unitsPerLogicalPixel;
    final output = Size(
      metrics.toLogicalPixels(size.width),
      metrics.toLogicalPixels(size.height),
    );
    final scale = image.scale * imageScale;
    final fit = image.fit ?? BoxFit.scaleDown;
    final FittedSizes fitted = applyBoxFit(fit, pixelSize / scale, output);
    final destinationSize = fitted.destination;
    final sourceSize = fitted.source * scale;
    if (destinationSize.isEmpty || sourceSize.isEmpty) return none;

    final alignment = image.alignment.resolve(textDirection);
    final halfWidth = (output.width - destinationSize.width) / 2.0;
    final halfHeight = (output.height - destinationSize.height) / 2.0;
    // Flutter negates the alignment's x for a mirrored picture and then flips
    // the canvas about the rectangle's centre, which puts the destination
    // back where the unmirrored alignment asked for it. So the destination is
    // the same either way and only the source runs backwards — see [source].
    final destination = Rect.fromLTWH(
      (halfWidth + alignment.x * halfWidth) * units,
      (halfHeight + alignment.y * halfHeight) * units,
      destinationSize.width * units,
      destinationSize.height * units,
    );

    final sourceRect = alignment.inscribe(sourceSize, Offset.zero & pixelSize);
    final left = sourceRect.left / pixelSize.width;
    final right = sourceRect.right / pixelSize.width;
    final mirror =
        image.matchTextDirection && textDirection == TextDirection.rtl;
    return ImageUniforms3d(
      destination: destination,
      source: Rect.fromLTRB(
        mirror ? right : left,
        sourceRect.top / pixelSize.height,
        mirror ? left : right,
        sourceRect.bottom / pixelSize.height,
      ),
      opacity: image.opacity,
    );
  }

  /// Where the picture is drawn, in world units in the box's own frame.
  final Rect destination;

  /// Which part of the picture lands there, in texture coordinates.
  ///
  /// A [Rect] whose right is less than its left is a mirrored picture, which
  /// is how [DecorationImage3d.matchTextDirection] is expressed: the shader
  /// interpolates from left to right across the destination whatever order
  /// the two are in.
  final Rect source;

  /// How much of the picture to draw. Zero is none, and is what a picture
  /// that has not arrived resolves to.
  final double opacity;

  /// Whether this draws anything.
  bool get isNone => opacity <= 0.0 || destination.isEmpty;

  @override
  String toString() => isNone
      ? 'ImageUniforms3d.none'
      : 'ImageUniforms3d($destination from $source at $opacity)';
}
