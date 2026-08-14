import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';

/// macOS adapter. Isolation is unavailable on this platform.
final class FlutterAiCommunicationsMacos
    extends MethodChannelCommunicationsPlatform {
  /// Creates the macOS adapter.
  FlutterAiCommunicationsMacos() : super(platformName: 'macos');

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsMacos();
  }
}
