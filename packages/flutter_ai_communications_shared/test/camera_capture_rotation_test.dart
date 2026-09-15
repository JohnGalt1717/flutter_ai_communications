import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  group('captureRotationDegrees', () {
    // CameraX ImageInfo.rotationDegrees / JPEG_ORIENTATION with
    // Display.getRotation() counterclockwise degrees. See
    // https://developer.android.com/media/camera/camerax/orientation-rotation
    // Example 1: back sensor 90 (Pixel-class phone).
    test('back camera portrait is 90 clockwise', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 90,
          displayRotation: 0,
          frontFacing: false,
        ),
        90,
      );
    });

    test('back camera landscape (ROTATION_90) is 0', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 90,
          displayRotation: 90,
          frontFacing: false,
        ),
        0,
      );
    });

    test('back camera reverse-landscape (ROTATION_270) is 180', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 90,
          displayRotation: 270,
          frontFacing: false,
        ),
        180,
      );
    });

    test('back camera reverse-portrait is 270', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 90,
          displayRotation: 180,
          frontFacing: false,
        ),
        270,
      );
    });

    // Front sensor 270: JPEG / CameraX ImageAnalysis (not the TextureView
    // 360-complement). Portrait 270, landscapes 0/180.
    test('front camera portrait is 270 clockwise', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 270,
          displayRotation: 0,
          frontFacing: true,
        ),
        270,
      );
    });

    test('front camera landscape (ROTATION_90) is 0', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 270,
          displayRotation: 90,
          frontFacing: true,
        ),
        0,
      );
    });

    test('front camera reverse-landscape (ROTATION_270) is 180', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 270,
          displayRotation: 270,
          frontFacing: true,
        ),
        180,
      );
    });

    test('front camera reverse-portrait is 90', () {
      expect(
        captureRotationDegrees(
          sensorOrientation: 270,
          displayRotation: 180,
          frontFacing: true,
        ),
        90,
      );
    });
  });

  group('displayRotationFromClockwiseTilt', () {
    // CameraX OrientationEventListener mapping.
    test('maps clockwise tilt to Display.getRotation degrees', () {
      expect(displayRotationFromClockwiseTilt(0), 0);
      expect(displayRotationFromClockwiseTilt(44), 0);
      expect(displayRotationFromClockwiseTilt(45), 270);
      expect(displayRotationFromClockwiseTilt(90), 270);
      expect(displayRotationFromClockwiseTilt(134), 270);
      expect(displayRotationFromClockwiseTilt(135), 180);
      expect(displayRotationFromClockwiseTilt(180), 180);
      expect(displayRotationFromClockwiseTilt(224), 180);
      expect(displayRotationFromClockwiseTilt(225), 90);
      expect(displayRotationFromClockwiseTilt(270), 90);
      expect(displayRotationFromClockwiseTilt(314), 90);
      expect(displayRotationFromClockwiseTilt(315), 0);
      expect(displayRotationFromClockwiseTilt(359), 0);
    });
  });

  group('captureBufferSize', () {
    test('90 and 270 swap width and height', () {
      expect(
        captureBufferSize(sourceWidth: 1280, sourceHeight: 720, rotationDegrees: 90),
        (width: 720, height: 1280),
      );
      expect(
        captureBufferSize(
          sourceWidth: 1280,
          sourceHeight: 720,
          rotationDegrees: 270,
        ),
        (width: 720, height: 1280),
      );
    });

    test('0 and 180 keep source size', () {
      expect(
        captureBufferSize(sourceWidth: 1280, sourceHeight: 720, rotationDegrees: 0),
        (width: 1280, height: 720),
      );
    });
  });
}
