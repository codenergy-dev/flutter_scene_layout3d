// Generates the shader variants the opacity experiment compares.
//
//   dart run tool/make_opacity_variants.dart
//
// The variants are **copies** of the two shaders `flutter_scene_layout3d`
// ships, patched in one place each. They are generated rather than
// hand-written for one reason: the question this experiment asks is "what
// does *this* shader do when it fades", and a hand-copied shader that drifted
// from the original would answer a question about a different shader. The
// generator fails loudly when a patch site is missing, which is what happens
// the day the package's own shader moves.
//
// Nothing here edits the package. The outputs land in this app's own
// `assets/opacity_poc/`, compiled by this app's `hook/build.dart`.

import 'dart:io';

/// Where the shaders being copied live.
const String _packageAssets = '../../packages/flutter_scene_layout3d/assets';

/// Where the copies go.
const String _out = 'assets/opacity_poc';

/// The screen-door discard, inlined into a `Surface()` body.
///
/// It is `ApplyLodFade` out of the engine's own `shaders/lod_fade.glsl`, which
/// is how `flutter_scene` cross-fades between levels of detail — the same Weyl
/// hash it uses for resolve grain and for rotating shadow PCF taps, and whose
/// comment records that `gl_FragCoord` behaves the same on Impeller and on the
/// WebGL2 backend.
///
/// Inlined rather than `#include`d because a `.fmat`'s fragment block is
/// composed into the emitted shader by the engine's emitter, which chooses the
/// includes itself. `lod_fade.glsl` is on its list, so an `#include` would
/// very likely work too; inlining removes the question from an experiment that
/// is not about the build.
///
/// The engine's own `Material.lodFade` is **not** reachable here: it is
/// `@internal`, and its dartdoc says in as many words that only the built-in
/// lit and unlit materials honour it. A `.fmat` gets no `fade` uniform unless
/// it declares one, which is what these variants do.
const String _ditherBlock = '''
    // Screen-door coverage. See tool/make_opacity_variants.dart.
    float poc_fade = material_params.fade;
    if (poc_fade < 1.0) {
      float poc_dither = fract(
          52.9829189 *
          fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
      if (poc_dither >= poc_fade) {
        discard;
      }
    }
''';

/// The same discard, thresholded against an **ordered 4x4 Bayer matrix**
/// instead of against a hash.
///
/// The hash above is the engine's, and it is tuned for what the engine uses it
/// for: foliage and level-of-detail pops, far away, small on screen, and
/// usually resolved by temporal anti-aliasing. A UI panel is the opposite case
/// — hundreds of pixels across, still, and with no TAA in this stack — and a
/// Weyl hash at that scale has visible low-frequency structure, which
/// photographs as diagonal hatching rather than as grain. This is the
/// classical alternative, whose structure is a regular 4x4 cell instead.
///
/// Which of the two looks better is exactly the kind of question that cannot
/// be reasoned about, which is why both are built and photographed.
const String _bayerBlock = '''
    // Ordered screen-door coverage. See tool/make_opacity_variants.dart.
    float poc_fade = material_params.fade;
    if (poc_fade < 1.0) {
      const float poc_bayer[16] = float[16](
           0.0,  8.0,  2.0, 10.0,
          12.0,  4.0, 14.0,  6.0,
           3.0, 11.0,  1.0,  9.0,
          15.0,  7.0, 13.0,  5.0);
      ivec2 poc_cell = ivec2(mod(gl_FragCoord.xy, 4.0));
      float poc_threshold =
          (poc_bayer[poc_cell.y * 4 + poc_cell.x] + 0.5) / 16.0;
      if (poc_threshold >= poc_fade) {
        discard;
      }
    }
''';

/// The parameter the block above reads.
const String _fadeParameter = '''
    // How much of this draw survives, 0..1. The experiment's own uniform: the
    // engine's `Material.lodFade` is internal and unreachable from a `.fmat`.
    { type: float, name: fade, default: 1.0 },
''';

void main() {
  final panel = _read('$_packageAssets/box_decoration3d.fmat');
  final glyph = _read('$_packageAssets/text_glyph3d.fmat');

  Directory(_out).createSync(recursive: true);

  // ── The panels, faded by dithering ─────────────────────────────────────
  //
  // Depth write stays **on**, which is the whole point of these variants: the
  // fragments that survive are the ones that draw, and they order each other
  // through the depth buffer exactly as an unfaded panel does. The two differ
  // only in which threshold decides who survives.
  for (final (String name, String block) in <(String, String)>[
    ('panel_dither.fmat', _ditherBlock),
    ('panel_bayer.fmat', _bayerBlock),
  ]) {
    _write(
      name,
      _patch(panel, <_Patch>[
        _Patch(
          'name: "BoxDecoration3d",',
          'name: "${name == 'panel_bayer.fmat' ? 'PanelBayer3d' : 'PanelDither3d'}",',
        ),
        _Patch(
          '    { type: float, name: metallic,',
          '$_fadeParameter    { type: float, name: metallic,',
        ),
        _Patch(
          '  void Surface(inout MaterialInputs material) {\n',
          '  void Surface(inout MaterialInputs material) {\n$block',
        ),
      ]),
    );
  }

  // ── The panel, faded by alpha, not writing depth ───────────────────────
  //
  // The one-line change the package's own shader argues against in a comment
  // twenty lines long, and which `2026_09_10_a_transparent_slab_that_does_not
  // _erase.md` photographed doing something worse. Here to be photographed
  // again, under a fade rather than under a fully transparent slab.
  _write(
    'panel_nodepth.fmat',
    _patch(panel, <_Patch>[
      _Patch('name: "BoxDecoration3d",', 'name: "PanelNoDepth3d",'),
      _Patch('  depth_write: true,', '  depth_write: false,'),
    ]),
  );

  // ── The glyph, faded by dithering ──────────────────────────────────────
  //
  // The tint's alpha is left alone, so `alpha_cutoff` never sees a faded
  // value and the cliff the naive approach falls off does not exist here.
  for (final (String name, String block) in <(String, String)>[
    ('glyph_dither.fmat', _ditherBlock),
    ('glyph_bayer.fmat', _bayerBlock),
  ]) {
    _write(
      name,
      _patch(glyph, <_Patch>[
        _Patch(
          'name: "TextGlyph3d",',
          'name: "${name == 'glyph_bayer.fmat' ? 'GlyphBayer3d' : 'GlyphDither3d'}",',
        ),
        _Patch(
          '    { type: float, name: alpha_cutoff,',
          '$_fadeParameter    { type: float, name: alpha_cutoff,',
        ),
        _Patch(
          '  void Surface(inout MaterialInputs material) {\n',
          '  void Surface(inout MaterialInputs material) {\n$block',
        ),
      ]),
    );
  }

  // ── The glyph, not writing depth ───────────────────────────────────────
  _write(
    'glyph_nodepth.fmat',
    _patch(glyph, <_Patch>[
      _Patch('name: "TextGlyph3d",', 'name: "GlyphNoDepth3d",'),
      _Patch('  depth_write: true,', '  depth_write: false,'),
    ]),
  );

  stdout.writeln('wrote six variants into $_out/');
}

class _Patch {
  const _Patch(this.from, this.to);
  final String from;
  final String to;
}

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('no shader to copy at ${file.absolute.path}');
  }
  return file.readAsStringSync();
}

/// Applies every patch, insisting each site exists exactly once.
///
/// The insistence is the point. A silently skipped patch produces a variant
/// that is a copy of the original, and an experiment comparing a shader with
/// itself reports that both approaches behave identically — which is a
/// plausible-looking result and a completely false one.
String _patch(String source, List<_Patch> patches) {
  var out = source;
  for (final patch in patches) {
    final count = patch.from.allMatches(out).length;
    if (count != 1) {
      throw StateError(
        'expected exactly one "${patch.from.split('\n').first}" to patch, '
        'found $count — the package shader has moved',
      );
    }
    out = out.replaceFirst(patch.from, patch.to);
  }
  return out;
}

void _write(String name, String contents) {
  const banner = '''
// GENERATED by tool/make_opacity_variants.dart — do not edit.
//
// A copy of one of `flutter_scene_layout3d`'s shipped shaders, patched to try
// one way of fading a subtree. Regenerate rather than editing, and read the
// generator for what was changed and why.

''';
  File('$_out/$name').writeAsStringSync(banner + contents);
  stdout.writeln('  $name');
}
