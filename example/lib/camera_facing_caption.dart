import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host caption for Camera facing. Unspecified is omitted from the tile.
String? cameraFacingCaption(CameraFacing facing) {
  return switch (facing) {
    CameraFacing.user => 'Front',
    CameraFacing.environment => 'Back',
    CameraFacing.external => 'External',
    CameraFacing.unspecified => null,
  };
}
