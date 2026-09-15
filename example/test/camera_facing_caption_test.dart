import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/camera_facing_caption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unspecified facing has no caption', () {
    expect(cameraFacingCaption(CameraFacing.unspecified), isNull);
  });

  test('user, environment, and external have host captions', () {
    expect(cameraFacingCaption(CameraFacing.user), 'Front');
    expect(cameraFacingCaption(CameraFacing.environment), 'Back');
    expect(cameraFacingCaption(CameraFacing.external), 'External');
  });
}
