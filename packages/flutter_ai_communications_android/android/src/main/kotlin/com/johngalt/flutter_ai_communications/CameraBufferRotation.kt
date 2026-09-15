package com.johngalt.flutter_ai_communications

/**
 * Clockwise degrees for [android.graphics.Matrix.postRotate] on an ImageReader
 * YUV frame so the bitmap is upright when blitted to a Flutter
 * [io.flutter.view.TextureRegistry.SurfaceProducer].
 *
 * ## What this pipeline is
 *
 * Camera2 writes **sensor-native** YUV into [android.media.ImageReader]
 * (typically 1280×720 landscape). HAL does not rotate those buffers.
 * Flutter's SurfaceProducer on API 29+ is an ImageReader backend;
 * [io.flutter.view.TextureRegistry.SurfaceProducer.handlesCropAndRotation]
 * is **false**, so crop/rotation metadata is not applied. We rotate pixels,
 * then [android.graphics.Canvas.drawBitmap] onto [getSurface]. The Dart
 * [Texture] widget samples that bitmap 1:1 in the current UI orientation.
 *
 * ## Clockwise amount (JPEG / CameraX ImageAnalysis)
 *
 * ChromeOS camera orientation
 * (https://developer.android.com/develop/devices/chromeos/learn/camera-orientation):
 *
 * > the amount you want to rotate clockwise is
 * > - sensorOrientation − displayRotation for back cameras
 * > - sensorOrientation + displayRotation for front cameras
 *
 * Same numbers as [android.hardware.camera2.CaptureRequest.JPEG_ORIENTATION]
 * and CameraX `ImageInfo.getRotationDegrees` when [displayRotationDegrees]
 * is [android.view.Display.getRotation] mapped to 0/90/180/270
 * **counterclockwise** (the docs say Display.getRotation plugs in as-is).
 *
 * CameraX `ImageUtil.rotateBitmap` is `matrix.postRotate(rotationDegrees)`.
 * That is clockwise, matching [android.graphics.Matrix.postRotate].
 *
 * Typical phone (back SENSOR_ORIENTATION=90, front=270):
 *
 * | facing | Display.getRotation | clockwise postRotate |
 * | ------ | ------------------- | -------------------- |
 * | back   | 0 (portrait)        | 90                   |
 * | back   | 90                  | 0                    |
 * | back   | 270                 | 180                  |
 * | back   | 180                 | 270                  |
 * | front  | 0 (portrait)        | 270                  |
 * | front  | 90                  | 0                    |
 * | front  | 270                 | 180                  |
 * | front  | 180                 | 90                   |
 *
 * ## What this is not
 *
 * **Camera2 preview formula**
 * `rotation = (sensor − display × sign + 360) % 360` (sign 1 front, −1 back)
 * is for a TextureView/SurfaceView transform, or for a Dart [RotatedBox]
 * around an **unrotated** SurfaceProducer (Flutter breaking-change note
 * https://docs.flutter.dev/release/breaking-changes/android-surface-plugins).
 * We already rotated the buffer; using that formula here would be a second
 * transform.
 *
 * **Camera.setDisplayOrientation `(360 − result)` front complement**
 * compensates for OS-mirrored TextureView preview. ImageReader is not
 * OS-mirrored. Applying the complement inverts natural portrait (90 vs 270)
 * while leaving landscape 0/180 unchanged.
 *
 * **OrientationEventListener as the display angle**
 * CameraX uses it when the activity is locked but stills should follow
 * gravity. This Flutter activity rotates with the device. Gravity can report
 * 180 while [Display.getRotation] is still 0; rotating the buffer to 180
 * then makes the camera upside-down relative to the upright UI chrome.
 * Display.getRotation is the angle that matches the Flutter window.
 *
 * ## Front selfie mirror
 *
 * CameraX `SurfaceRequest.TransformationInfo`: mirror **after**
 * `getRotationDegrees`, across the vertical axis of the upright buffer.
 */
internal object CameraBufferRotation {
    /**
     * @param sensorOrientation [android.hardware.camera2.CameraCharacteristics.SENSOR_ORIENTATION]
     * @param displayRotationDegrees [android.view.Display.getRotation] as 0/90/180/270
     * @param frontFacing true for [android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT]
     */
    fun clockwisePostRotate(
        sensorOrientation: Int,
        displayRotationDegrees: Int,
        frontFacing: Boolean,
    ): Int {
        return if (frontFacing) {
            (sensorOrientation + displayRotationDegrees) % 360
        } else {
            (sensorOrientation - displayRotationDegrees + 360) % 360
        }
    }

    fun bufferSize(
        sourceWidth: Int,
        sourceHeight: Int,
        rotationDegrees: Int,
    ): Pair<Int, Int> {
        return if (rotationDegrees % 180 != 0) {
            Pair(sourceHeight, sourceWidth)
        } else {
            Pair(sourceWidth, sourceHeight)
        }
    }
}
