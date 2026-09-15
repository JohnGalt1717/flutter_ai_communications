/// Clockwise degrees to [Bitmap.postRotate] an ImageReader buffer.
///
/// Same as CameraX `ImageInfo.rotationDegrees` / `JPEG_ORIENTATION` when
/// [displayRotation] is `Display.getRotation()` counterclockwise degrees.
/// Front: sensor + display. Back: sensor − display. Mirror a front selfie
/// *after* this rotation, in the upright buffer.
///
/// Native copy of this table and the sources: Android
/// `CameraBufferRotation`.
int captureRotationDegrees({
  required int sensorOrientation,
  required int displayRotation,
  required bool frontFacing,
}) {
  return frontFacing
      ? (sensorOrientation + displayRotation) % 360
      : (sensorOrientation - displayRotation + 360) % 360;
}

/// Maps [OrientationEventListener] clockwise tilt to `Display.getRotation()`
/// degrees. Same buckets as CameraX `OrientationEventListener` setup.
int displayRotationFromClockwiseTilt(int clockwiseDegrees) {
  final rounded = ((clockwiseDegrees % 360) + 360) % 360;
  if (rounded >= 45 && rounded < 135) {
    return 270;
  }
  if (rounded >= 135 && rounded < 225) {
    return 180;
  }
  if (rounded >= 225 && rounded < 315) {
    return 90;
  }
  return 0;
}

/// Pixel size after [rotationDegrees] is applied to a source frame.
({int width, int height}) captureBufferSize({
  required int sourceWidth,
  required int sourceHeight,
  required int rotationDegrees,
}) {
  final swapped = rotationDegrees % 180 != 0;
  if (swapped) {
    return (width: sourceHeight, height: sourceWidth);
  }
  return (width: sourceWidth, height: sourceHeight);
}
