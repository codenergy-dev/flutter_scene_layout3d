import 'package:flutter/material.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart'
    show initializeMaterial3d;

import 'gallery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The one call a Material application makes. It awaits the engine's static
  // resources — nothing renders until those resolve — and then installs the
  // panel painter, which is what turns a `BoxDecoration3d` from arithmetic
  // that draws nothing into a panel on screen.
  await initializeMaterial3d();
  runApp(const Layout3dGalleryApp());
}

class Layout3dGalleryApp extends StatelessWidget {
  const Layout3dGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_scene_layout3d gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      // The backdrop the scene is drawn over. Deliberately not black:
      // "nothing was drawn" and "something dark was drawn" look identical
      // against black, and telling them apart is most of debugging a scene.
      home: const Scaffold(
        backgroundColor: Color(0xFF101820),
        body: Layout3dGallery(),
      ),
    );
  }
}
