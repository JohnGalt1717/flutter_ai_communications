import 'dart:io';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';

import 'windows_microphone_consent.dart';

/// Asks Windows for camera access. Store/MSIX hosts show a consent UI.
abstract class WindowsCameraConsent {
  /// Blocks until the OS answers. Must not start the camera graph.
  Future<CameraPermission> request();
}

/// Always allows the camera graph. Used off Windows and in adapter tests.
final class GrantedWindowsCameraConsent implements WindowsCameraConsent {
  /// Creates a consent object that never prompts.
  const GrantedWindowsCameraConsent();

  @override
  Future<CameraPermission> request() async => CameraPermission.granted;
}

/// Creates the camera consent implementation for this host.
WindowsCameraConsent createWindowsCameraConsent() {
  if (Platform.isWindows) {
    return GatedWindowsCameraConsent(
      isPackaged: isWindowsPackagedProcess,
      packaged: WinrtWindowsCameraConsent(),
    );
  }
  return const GrantedWindowsCameraConsent();
}

/// Store/MSIX consent only. Unpackaged Win32 skips WinRT.
final class GatedWindowsCameraConsent implements WindowsCameraConsent {
  /// [packaged] runs only when [isPackaged] is true.
  GatedWindowsCameraConsent({
    required this.isPackaged,
    required this.packaged,
  });

  /// Whether this process has package identity.
  final bool Function() isPackaged;

  /// First-party Store consent UI.
  final WindowsCameraConsent packaged;

  @override
  Future<CameraPermission> request() async {
    if (!isPackaged()) {
      return CameraPermission.granted;
    }
    return packaged.request();
  }
}

/// DeviceAccessStatus.Allowed / DeniedByUser / DeniedBySystem.
CameraPermission? cameraPermissionFromDeviceAccessStatus(int status) =>
    switch (status) {
      1 => CameraPermission.granted,
      2 => CameraPermission.denied,
      3 => CameraPermission.restricted,
      _ => null,
    };

/// AppCapabilityAccessStatus, including NotDeclaredByApp and UserPromptRequired.
CameraPermission? cameraPermissionFromAppCapabilityStatus(int status) =>
    switch (status) {
      0 => CameraPermission.restricted,
      1 || 2 => CameraPermission.denied,
      4 => CameraPermission.granted,
      _ => null,
    };

/// Packaged-app consent via AppCapability and DeviceAccessInformation.
final class WinrtWindowsCameraConsent implements WindowsCameraConsent {
  @override
  Future<CameraPermission> request() async {
    final deviceStatus = deviceAccessStatusForClass(_videoCaptureDeviceClass);
    final fromDevice = cameraPermissionFromDeviceAccessStatus(
      deviceStatus ?? -1,
    );
    if (fromDevice == CameraPermission.granted ||
        fromDevice == CameraPermission.denied ||
        fromDevice == CameraPermission.restricted) {
      return fromDevice!;
    }
    final capability = await requestPackagedAppCapability('webcam');
    if (capability != null) {
      return switch (capability) {
        MicrophonePermission.granted => CameraPermission.granted,
        MicrophonePermission.denied => CameraPermission.denied,
        MicrophonePermission.restricted => CameraPermission.restricted,
      };
    }
    return CameraPermission.denied;
  }
}

/// Windows.Devices.Enumeration.DeviceClass.VideoCapture.
const _videoCaptureDeviceClass = 4;
