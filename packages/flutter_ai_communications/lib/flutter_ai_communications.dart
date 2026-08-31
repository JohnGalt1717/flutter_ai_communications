/// Teams/Zoom-class communications Audio manager.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';

import 'src/coverage.dart';
import 'src/session_diagnostics.dart';
import 'src/session_options.dart';
import 'src/session_status.dart';

export 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
export 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

export 'src/coverage.dart';
export 'src/session_diagnostics.dart';
export 'src/session_options.dart';
export 'src/session_status.dart';

part 'src/communications_manager.dart';
part 'src/camera_preview.dart';
part 'src/session.dart';
part 'src/start_result.dart';

/// App-facing entry. Prefer [CommunicationsManager] for Session work.
final class FlutterAiCommunications {
  /// The registered platform adapter's name.
  static String get platformName =>
      FlutterAiCommunicationsPlatform.instance.platformName;
}
