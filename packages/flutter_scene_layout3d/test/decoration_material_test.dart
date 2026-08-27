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
    for (var i = 0; i < Clip3dRegion.maxPlanes; i++) {
      expect(declared, contains('clip_plane_$i'));
    }
  });

  test('it blends, so a corner that is discarded is not a hole', () {
    expect(compiled.material.blending, isNot(FmatBlending.opaque));
    expect(compiled.material.depthWrite, isTrue);
  });
}
