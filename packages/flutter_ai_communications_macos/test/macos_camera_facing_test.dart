import 'package:flutter_ai_communications_macos/src/macos_camera_facing.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MacBook Pro Camera is user-facing', () {
    expect(macosCameraFacing(name: 'MacBook Pro Camera'), CameraFacing.user);
  });

  test('Logitech BRIO is an external Camera Endpoint', () {
    expect(macosCameraFacing(name: 'Logitech BRIO'), CameraFacing.external);
  });

  test('FaceTime camera is user-facing', () {
    expect(macosCameraFacing(name: 'FaceTime HD Camera'), CameraFacing.user);
  });

  test('overlay fills unspecified MacBook and BRIO facing', () {
    const macbook = CameraEndpoint(
      id: 'mac',
      name: 'MacBook Pro Camera',
      facing: CameraFacing.unspecified,
    );
    const brio = CameraEndpoint(
      id: 'brio',
      name: 'Logitech BRIO',
      facing: CameraFacing.unspecified,
    );
    const front = CameraEndpoint(
      id: 'front',
      name: 'Already front',
      facing: CameraFacing.user,
    );
    final overlaid = overlayMacosCameraFacing(const [macbook, brio, front]);
    expect(overlaid[0].facing, CameraFacing.user);
    expect(overlaid[1].facing, CameraFacing.external);
    expect(overlaid[2].facing, CameraFacing.user);
  });
}
