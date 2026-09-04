import 'dart:io';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';

import 'windows_microphone_consent.dart';

/// Asks Windows for programmatic Graphics Capture. Store/MSIX hosts show
/// a consent UI. Unpackaged Win32 uses Settings → Privacy → Screen capture.
abstract class WindowsScreenConsent {
  /// Blocks until the OS answers. Must not start the screen graph.
  Future<ScreenPermission> request();
}

/// Always allows screen send. Used off Windows and in adapter tests.
final class GrantedWindowsScreenConsent implements WindowsScreenConsent {
  /// Creates a consent object that never prompts.
  const GrantedWindowsScreenConsent();

  @override
  Future<ScreenPermission> request() async => ScreenPermission.granted;
}

/// Creates the screen consent implementation for this host.
WindowsScreenConsent createWindowsScreenConsent() {
  if (Platform.isWindows) {
    return GatedWindowsScreenConsent(
      isPackaged: isWindowsPackagedProcess,
      packaged: WinrtWindowsScreenConsent(),
    );
  }
  return const GrantedWindowsScreenConsent();
}

/// Store/MSIX consent only. Unpackaged Win32 skips WinRT.
final class GatedWindowsScreenConsent implements WindowsScreenConsent {
  /// [packaged] runs only when [isPackaged] is true.
  GatedWindowsScreenConsent({
    required this.isPackaged,
    required this.packaged,
  });

  /// Whether this process has package identity.
  final bool Function() isPackaged;

  /// First-party Store consent UI.
  final WindowsScreenConsent packaged;

  @override
  Future<ScreenPermission> request() async {
    if (!isPackaged()) {
      return ScreenPermission.granted;
    }
    return packaged.request();
  }
}

/// AppCapabilityAccessStatus, including NotDeclaredByApp and UserPromptRequired.
ScreenPermission? screenPermissionFromAppCapabilityStatus(int status) =>
    switch (status) {
      0 => ScreenPermission.restricted,
      1 || 2 => ScreenPermission.denied,
      4 => ScreenPermission.granted,
      _ => null,
    };

/// Packaged-app consent via AppCapability `graphicsCaptureProgrammatic`.
///
/// Required before WGC `CreateForMonitor` / `CreateForWindow` on Store
/// hosts (Windows 10 2104+). Borderless capture is requested best-effort
/// so `IsBorderRequired(false)` can succeed when the host declared it.
final class WinrtWindowsScreenConsent implements WindowsScreenConsent {
  @override
  Future<ScreenPermission> request() async {
    final capability = await requestPackagedAppCapability(
      'graphicsCaptureProgrammatic',
    );
    if (capability == null) {
      // API absent (older Windows). CreateForMonitor still works without
      // the Win11 privacy prompt.
      return ScreenPermission.granted;
    }
    final permission = switch (capability) {
      MicrophonePermission.granted => ScreenPermission.granted,
      MicrophonePermission.denied => ScreenPermission.denied,
      MicrophonePermission.restricted => ScreenPermission.restricted,
    };
    if (permission == ScreenPermission.granted) {
      await requestPackagedAppCapability('graphicsCaptureWithoutBorder');
    }
    return permission;
  }
}
