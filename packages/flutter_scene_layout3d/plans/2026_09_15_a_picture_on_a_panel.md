---
status: completed
created_at: 2026-09-15T20:34:13Z
updated_at: 2026-09-16T14:35:00Z
commit: f38d90cfa966ef82fb9883fd932551662b8053ba
---

# A picture on a panel

The fifth plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the second of the four that map says the first real port will demand.
Right to left went first because another item waited on it; this one goes next
because it is the one every screen has in it — an avatar, a photograph, a logo,
a brand gradient behind a header.

## What is actually missing

- **No image anywhere.** No `ImageProvider` is read by either package, there is
  no `Image3d`, and `BoxDecoration3d` has no `image`.
- **No gradient.** `BoxDecoration3d` carries one `color`.
- **No sampler on the panel shader.** `box_decoration3d.fmat` declares only
  uniforms, so a picture cannot reach a panel without a second material — which
  is what an application does today, by dropping out of the layout into a
  hand-built `NodeBox3d` with a textured material of its own, and losing the
  corner radius, the border, the state layer, the ripple and the clip on the
  way out.
- **No way for a painter to say "paint me again".** `Decoration3dPainter.paint`
  is called after a layout or a state change and at no other time, and a
  decoration whose resource arrives later has nothing to call.

## What Flutter does, checked against the SDK this repository resolves

Flutter 3.47.1, read in the framework source.

- **`BoxDecoration` has both, and paints them in a fixed order**: the `color`,
  or the `gradient` in its place ("if this is specified, `color` has no
  effect"), then the `image` over it, then the border. The image is clipped to
  the decoration's rounded outline.
- **`DecorationImage.createPainter(onChanged)`** returns a painter that resolves
  the provider against the `ImageConfiguration` it is painted with, listens to
  the stream, and calls `onChanged` when a frame arrives. The paint is
  `paintImage(scale: details.scale * info.scale, alignment:
  details.alignment.resolve(configuration.textDirection), flipHorizontally:
  matchTextDirection && rtl, opacity: …)`.
- **`paintImage`** defaults a null fit to `BoxFit.scaleDown`, fits
  `applyBoxFit(fit, imageSize / scale, rect.size)`, places the destination by
  the alignment inside the rect, takes the source by the same alignment inside
  the image, and flips the whole canvas about the rect's centre for
  `flipHorizontally` — which puts the destination where the unflipped alignment
  says and mirrors the pixels.
- **`RenderImage`** sizes to `constraints.constrainSizeAndAttemptToPreserveAspectRatio(
  imageSize / scale)` — `constraints.smallest` while there is no image — and
  reports a minimum intrinsic width of zero when neither `width` nor `height`
  is given.
- **The gradients** resolve their alignments against the painted rect:
  `LinearGradient` from `begin.withinRect` to `end.withinRect`, `RadialGradient`
  at `center.withinRect` with `radius * rect.shortestSide`, `SweepGradient` at
  `center.withinRect` from `startAngle` to `endAngle`, all through the rect's
  text direction; stops default to evenly spaced, and colours interpolate
  unpremultiplied in sRGB.

## The decisions

### An image is a decoration, and `Image3d` is a box that wears one

The map asked which, and here the answer is both with one mechanism — for a
reason Flutter does not have. **A rounded clip does not exist in this package,
and a corner radius is carved by the panel shader.** A photograph drawn as a
separate textured quad would sit square in a rounded card and square inside a
circular avatar, and nothing could cut it. Drawn *by the panel shader*, it
falls inside the same signed distance field as the colour does, so the corner
radius, the border, the surface tint, the state layer, the press ripple and the
clip planes all apply to a picture without a line written for any of them.

So `BoxDecoration3d.image` is the mechanism: one `sampler2d` on the panel
material, bound per box, and a destination and source rectangle as uniforms.
`Image3d` is a `DecoratedBox3d` that builds that decoration from its own fields
and sizes itself to the picture the way `RenderImage` does. A circular avatar is
an `Image3d` with `borderRadius: BorderRadius3d.circular(…)` — the thing a
`ClipOval` does in Flutter, stated where it can be honoured.

`DecorationImage3d` is this package's own type, not Flutter's
`DecorationImage`, because more than half of Flutter's fields would be silently
ignored — `repeat`, `centerSlice`, `colorFilter`, `invertColors`,
`filterQuality`, `isAntiAlias` — and a field silently ignored is a trap. What it
takes is Flutter's vocabulary: `ImageProvider`, `BoxFit`, `AlignmentGeometry`,
`scale`, `opacity`, `matchTextDirection`, `onError`, with Flutter's defaults.

### The asynchronous clock is Flutter's `onChanged`, not a fourth counter

The map said to generalize `GlyphAtlas3d.outlineRevision` rather than invent
another counter. Reading the atlas again, the counters exist because **an atlas
is one texture whose contents keep changing under the meshes baked from it**:
a renderer cannot tell by looking at the texture whether its letters are in
it, so it compares numbers. An image is not that. Its arrival is a *value* — a
texture that did not exist and now does, a size that was unknown and now is —
and a consumer that compares the value it last used with the one available now
needs no counter at all.

What *is* general is the other half of the atlas's answer: something that
arrives late must be able to ask to be drawn again without a relayout. So the
paint request grows Flutter's own `onChanged`, the callback
`Decoration.createBoxPainter` has taken since the beginning for exactly this
reason, and a painter whose resource arrives calls it. The box repaints, the
painter is handed a fresh request, and it binds what has arrived. Any future
painter with a late resource — a video frame, a remote icon — uses the same
callback.

The resource itself is `ImageTexture3d`: one per provider and configuration,
shared through `ImageTexture3dCache.shared` the way an atlas is shared through
`GlyphAtlasCache3d.shared`, reference counted by the boxes using it, and
uploaded through a seam (`ImageTexture3dUpload`) so that everything up to the
GPU runs in `flutter test`. It reports its size as soon as the stream reports
the image, and its texture once the pixels are read back and uploaded — two
moments, because `Image3d` needs the first for layout and the painter needs
the second for a picture.

### A gradient is uniforms, not a texture

A gradient in the shader is two decisions: what `t` a fragment is at, which is
the gradient's geometry, and what colour `t` is, which is its stops. The
geometry is exact arithmetic on the face position the shader already has, at
any aspect ratio — which a gradient rasterized into a texture and stretched
over the box is not, since stretching turns a radial gradient's circle into an
ellipse. The stops could go in a ramp texture of any length, or in uniforms of
a fixed length. **Uniforms**, because a ramp texture is a GPU upload per
distinct set of colours, and a colour animating between two gradients — a
`BoxDecoration3dTween`, a theme change — would upload one per frame. Uniforms
are a parameter write, which is the tier every decoration change here is
promised to be on.

The cost is a ceiling: **eight stops**, which covers every gradient in the
Material guidance and nearly every brand one. A gradient with more is
resampled to eight evenly spaced colours of its own ramp and reported once in a
debug build, rather than refused.

Colours interpolate in **sRGB, unpremultiplied**, as Skia does, and are decoded
to linear afterwards. The rest of the panel mixes in linear light, and a
gradient that did would not match the one the application's Flutter screens
draw — a red-to-green gradient's midpoint is visibly different.

`GradientTransform` and `RadialGradient.focal` are not honoured, and are
reported in a debug build rather than ignored.

### The shadow is not re-litigated

`boxShadow` stays out, for the reason `BoxDecoration3d.elevation` already
documents and `panel_shadow` pins: the panel blends, and the engine keeps
blended materials out of the shadow pass.

## The API

```dart
class DecorationImage3d {
  const DecorationImage3d({
    required ImageProvider image,
    BoxFit? fit,                                   // null is scaleDown, as in Flutter
    AlignmentGeometry alignment = Alignment.center,
    double scale = 1.0,
    double opacity = 1.0,
    bool matchTextDirection = false,
    ImageErrorListener? onError,
  });
  static DecorationImage3d? lerp(a, b, t);
}

BoxDecoration3d(gradient: Gradient?, image: DecorationImage3d?, …)

class ImageTexture3d extends ChangeNotifier {       // one picture, arriving
  Size? get size;                                  // logical pixels, scale applied
  TextureSource? get texture;
  Object? get error;
}
class ImageTexture3dCache { static final shared; acquire(provider, configuration); release(texture); }
typedef ImageTexture3dUpload = TextureSource? Function(ImageTexture3dPixels pixels);

Decoration3dPaintRequest(configuration: ImageConfiguration, onChanged: VoidCallback?)
DecoratedBox3d(configuration: ImageConfiguration)

class Image3d extends DecoratedBox3d {             // sizes to the picture
  Image3d({required ImageProvider image, BoxFit? fit, AlignmentGeometry alignment,
    double scale, double opacity, bool matchTextDirection,
    BorderRadius3d borderRadius, ImageConfiguration configuration, …});
}

// Widgets read createLocalImageConfiguration(context).
SceneDecoratedBox3d(…)
SceneImage3d(image:), SceneImage3d.asset(), .network(), .memory()
```

## The boundary

- **Not the rest of `DecorationImage`**: repeat, centre slicing, colour filters,
  inverted colours, filter quality.
- **Not an animated image's later frames.** The first frame is uploaded and the
  stream is left; a GIF draws still. A texture upload per frame is the cost
  the whole decoration design exists to avoid, and a video-shaped source
  deserves a plan of its own.
- **Not a cross-fade between two different pictures.** One sampler holds one
  picture, so a decoration interpolating from one image to another switches at
  the midpoint. An image appearing or disappearing fades, as Flutter's does.
- **Not a shadow**, see above.
- **Not a rounded clip.** A picture *in* a rounded panel is rounded, because the
  shader draws it; a picture in a box *inside* a rounded panel is not, and that
  wall is still the one the map describes.
- **Not the catalogue.** `CircleAvatar3d` and the image-bearing list tiles
  belong to [the components a screen still needs](2026_09_11_what_a_real_application_still_needs.md#the-components-a-screen-still-needs).

## The work

- [x] The shader: a gradient and an image in `box_decoration3d.fmat`, in
      Flutter's painting order — the fill, the picture over it, then the
      border, the tint, the state layer and the ripple.
- [x] `BoxDecoration3d.gradient` and `.image`, their equality and `lerp`, and
      the uniforms that resolve them (`GradientUniforms3d`, `ImageUniforms3d`).
- [x] `ImageTexture3d`, `ImageTexture3dCache` and `ImageTexture3dUpload`.
- [x] `onChanged` and `configuration` on the paint request; the painter
      acquiring, binding and releasing a picture per box.
- [x] `Image3d`, `SceneImage3d` with Flutter's three constructors, and
      `Constraints3d.constrainSizeAndAttemptToPreserveAspectRatio` under it.
- [x] Tests: 42 in `test/picture_test.dart`, plus the two new ones in
      `decoration_material_test.dart` that keep the shader's parameter names
      and the Dart that writes them in step. The suite is 1175.
- [x] Render probes: `picture_on_a_panel`, `picture_contained`,
      `picture_rounded`, `picture_box`, `linear_gradient_panel` and
      `radial_gradient_panel`, each asserting a channel order. 103 probes.
- [x] The gallery: a gradient header and a circular avatar on every inbox row,
      both photographed.
- [x] The package README, `docs/traps.md`, the changelog, `docs/README.md`,
      `AGENTS.md`, and the map.

## Verification

`flutter test` green in both packages (1175 and 545) and the gallery (4),
`dart analyze` clean, `dart format .`, 103 render probes green on a real GPU,
and the gallery photographed twice — the picture and the gradient are both in
the frame, and the panel turning between the two photographs does not disturb
either.

The oracle for the arithmetic is Flutter's own `applyBoxFit`,
`Alignment.inscribe` and `withinRect`; the oracle for the picture is a
direction — which colour is on which side — never a distance.

## What the reasoning got wrong

**The counter the map asked for should not exist, and finding that out was the
useful part.** The instruction was to generalize `GlyphAtlas3d.outlineRevision`
rather than invent a fourth counter. Reading the atlas again says why it has
three: it is *one texture whose contents keep changing under meshes already
baked from it*, so a renderer cannot tell by looking whether its letters are
still in there. A picture is not that. Its arrival is a value — a texture that
was null and now is not, a size that was unknown and now is — and comparing
the value is the whole answer. What did generalize is the other half, and it
was already Flutter's: `Decoration.createBoxPainter`'s `onChanged`, now
`Decoration3dPaintRequest.onChanged`, which any painter with a late resource
can use.

**The map's three decisions had a fourth one underneath them, and it settled
the first.** "Is an image a decoration or a box?" reads as a taste question
until you remember that this package has no rounded clip: a photograph drawn
as a quad of its own would sit square inside every rounded card and every
circular avatar, and nothing in the stack could cut it. That makes the answer
forced rather than chosen — the picture must be inside the same signed
distance field as the colour — and it turns the map's *rounded clip* seam from
a wall this plan meets into one it goes around.

**A gradient was filed as "cheap in the shader" and the cheap part was not the
one that mattered.** The arithmetic is small either way; the decision worth
making was uniforms against a baked ramp texture, and it turns on animation —
a ramp is a GPU upload per distinct set of colours, which is one per frame for
a decoration interpolating between two gradients, on the one tier this package
promises is a parameter write. The second thing it turns on is colour space:
Skia interpolates a gradient in sRGB, so the decode to linear has to happen
*after* the interpolation, which is why the stop colours are the only
parameter on that material deliberately not tagged `source_color`.

**And the defect this found was not in anything the plan set out to build.** A
slab scaled to exactly zero on an axis has a singular transform and therefore
no normal, and the panel shader is lit — so a zero-depth `DecoratedBox3d` has
always come out **black**. Nothing had ever drawn one: every panel in the
catalogue and every probe takes its depth from a surface with a thickness. An
`Image3d` takes the depth its constraints allow, which in a loose surface is
none, so the first picture ever drawn on its own hit it immediately — and it
looked exactly like a texture that had failed to bind, which is the failure it
would have been mistaken for in an application. `slabTransformFor` holds every
axis to a hundredth of a logical pixel.
