import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';

/// Android adapter. Isolation is unavailable on this platform.
final class FlutterAiCommunicationsAndroid
    extends MethodChannelCommunicationsPlatform {
  /// Creates the Android adapter.
  FlutterAiCommunicationsAndroid() : super(platformName: 'android');

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsAndroid();
  }
}
