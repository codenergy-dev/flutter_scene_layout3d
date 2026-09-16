// The shipped panel shader, checked against the Dart that drives it.
//
// The GLSL itself needs a GPU to run and `impellerc` to compile, neither of
// which `flutter test` has. What is checkable here is the half that goes
// wrong silently: a parameter renamed on one side of the seam and not the
// other, which produces a panel that draws with a default instead of an
// error. So this parses the material the package ships and asserts that
// every name `BoxDecoration3dUniforms.applyTo` writes is declared in it.

import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FmatCompilation compiled;

  setUpAll(() {
    final source = File('assets/box_decoration3d.fmat').readAsStringSync();
    compiled = compileFmat(source, fileName: 'box_decoration3d.fmat');
  });

  test('the shipped panel material parses and emits GLSL', () {
    expect(compiled.material.name, 'BoxDecoration3d');
    expect(compiled.glsl, contains('Surface'));
  });

  test('it declares every parameter the uniforms write', () {
    final declared = <String>{
      for (final parameter in compiled.material.parameters) parameter.name,
    };
    expect(declared, containsAll(<String>['half_extent', 'corner_radius']));
    expect(
      declared,
      containsAll(<String>['bevel', 'border_width', 'metallic', 'roughness']),
    );
    expect(
      declared,
      containsAll(<String>[
        'color',
        'border_color',
        'state_layer',
        'surface_tint',
      ]),
    );
    expect(declared, containsAll(<String>['ripple_origin', 'ripple']));
    expect(
      declared,
      containsAll(<String>[
        'gradient',
        'gradient_geometry',
        'image_rect',
        'image_source',
        'image_opacity',
      ]),
    );
    for (var i = 0; i < Clip3dRegion.maxPlanes; i++) {
      expect(declared, contains('clip_plane_$i'));
    }
    for (var i = 0; i < 2; i++) {
      expect(declared, contains('gradient_stops_$i'));
    }
    for (var i = 0; i < GradientUniforms3d.maxStops; i++) {
      expect(declared, contains('gradient_color_$i'));
    }
  });

  test('the picture is a sampler, and every panel has the same one', () {
    // A picture reaches the panel as a texture on the *same* material rather
    // than as a quad of its own, which is what puts it inside the signed
    // distance field — so a corner radius cuts a photograph and a press
    // ripples across it. One sampler, which is also why a decoration cannot
    // cross-fade between two pictures.
    final samplers = compiled.material.parameters
        .where((parameter) => parameter.type == FmatType.sampler2d)
        .map((parameter) => parameter.name);
    expect(samplers, <String>['image_texture']);
  });

  test('a gradient stop is not tagged as a source colour', () {
    // The one parameter shape that has to be wrong-looking to be right: these
    // are interpolated in sRGB and decoded afterwards, as Skia does, so
    // tagging them `source_color` — which decodes each stop as it is written
    // — would draw a different ramp from the one the same gradient draws in
    // two dimensions.
    final byName = <String, FmatParameter>{
      for (final parameter in compiled.material.parameters)
        parameter.name: parameter,
    };
    expect(byName['color']!.hint, isNotNull);
    for (var i = 0; i < GradientUniforms3d.maxStops; i++) {
      expect(byName['gradient_color_$i']!.hint, isNull);
    }
  });

  test('the ripple is two floats each, and no colour of its own', () {
    // The design bet of phase 8 stated as a shape: a ripple adds a vec2 for
    // where it is centred and a vec2 for how big and how strong it is, and
    // borrows `state_layer`'s colour. A ripple that grew a colour parameter
    // would be a second wash that could disagree with the first.
    final byName = <String, FmatParameter>{
      for (final parameter in compiled.material.parameters)
        parameter.name: parameter,
    };
    expect(byName['ripple_origin']!.type, FmatType.vec2);
    expect(byName['ripple']!.type, FmatType.vec2);
    expect(byName.keys.where((n) => n.startsWith('ripple')), hasLength(2));
  });

  test('it blends, so a corner that is discarded is not a hole', () {
    expect(compiled.material.blending, isNot(FmatBlending.opaque));
    expect(compiled.material.depthWrite, isTrue);
  });
}
