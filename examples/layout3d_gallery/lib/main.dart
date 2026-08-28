import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show Scene;

import 'gallery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nothing renders until the engine's static resources are ready, so wait
  // for them before building anything that puts geometry in a scene.
  await Scene.initializeStaticResources();
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
      home: const Scaffold(body: Layout3dGallery()),
    );
  }
}
