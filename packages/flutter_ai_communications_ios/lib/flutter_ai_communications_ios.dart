import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';

/// iOS adapter. Isolation detect + open-settings live in native code.
final class FlutterAiCommunicationsIos
    extends MethodChannelCommunicationsPlatform {
  /// Creates the iOS adapter.
  FlutterAiCommunicationsIos() : super(platformName: 'ios');

  /// Registers this class as the default instance.
  static void registerWith() {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsIos();
  }
}
