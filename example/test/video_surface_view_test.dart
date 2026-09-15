import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/meeting/video_surface_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Texture keeps 16:9 inside a wide short tile', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 220,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 1, width: 1920, height: 1080),
              viewTypePrefix: 'fac-camera',
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.height, 220);
    expect(size.width, closeTo(220 * 16 / 9, 0.5));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('Texture keeps 4:3 when the surface reports it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 220,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 2, width: 640, height: 480),
              viewTypePrefix: 'fac-camera',
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.width / size.height, closeTo(4 / 3, 0.01));
  });

  testWidgets('unbounded height uses width and source aspect', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 640,
            height: 800,
            child: ListView(
              children: const [
                VideoSurfaceView(
                  surface: VideoSurface(handle: 3, width: 1280, height: 720),
                  viewTypePrefix: 'fac-screen',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.width, 640);
    expect(size.height, closeTo(640 * 9 / 16, 0.5));
  });

  testWidgets('Android 16:9 raster stays 16:9 in a portrait slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 800,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 4, width: 1280, height: 720),
              viewTypePrefix: 'fac-camera',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(RotatedBox), findsNothing);
    expect(find.byType(FittedBox), findsNothing);
    final size = tester.getSize(find.byType(Texture));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('iOS 9:16 raster stays 9:16 in a portrait slot', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 800,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 5, width: 720, height: 1280),
              viewTypePrefix: 'fac-camera',
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.width / size.height, closeTo(9 / 16, 0.01));
  });

  testWidgets('camera tile is landscape-wide when the UI is landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 280,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 6, width: 720, height: 1280),
              viewTypePrefix: 'fac-camera',
              followUiOrientation: true,
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.width, greaterThan(size.height));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('screen tile stays 16:9 in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 800,
            child: VideoSurfaceView(
              surface: VideoSurface(handle: 7, width: 1280, height: 720),
              viewTypePrefix: 'fac-screen',
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(Texture));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });
}
