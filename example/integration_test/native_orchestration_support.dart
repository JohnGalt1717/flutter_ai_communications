import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';

import 'native_orchestration_host.dart'
    if (dart.library.io) 'native_orchestration_host_io.dart'
    as host;

final nativeOrchestrationLog = Logger('nativeOrchestration');
final nativeOrchestrationLogs = <String>[];

void installNativeOrchestrationLogging() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final line =
        '${record.level.name} [${record.loggerName}] ${record.message}';
    nativeOrchestrationLogs.add(line);
    // ignore: avoid_print
    print(line);
  });
  binding.reportData = <String, dynamic>{
    'receipts': <Map<String, Object?>>[],
    'logs': nativeOrchestrationLogs,
  };
}

Future<Session> requireReady(
  CommunicationsManager manager, {
  String? purpose,
  SessionPreference preference = const SessionPreference(soundFloor: 0),
  bool cameraSend = false,
}) async {
  final result = await manager.start(
    purpose: purpose,
    cameraSend: cameraSend,
    preference: SessionPreference(
      soundFloor: preference.soundFloor ?? 0,
      endpoints: preference.endpoints,
      captureId: preference.captureId,
      renderId: preference.renderId,
    ),
    bargeInPolicy: BargeInPolicy.remoteVad,
  );
  expect(
    result,
    isA<StartReady>(),
    reason: 'native start must succeed ($result)',
  );
  return (result as StartReady).session;
}

Future<void> waitForCameraStream(
  FlutterAiCommunicationsPlatform platform, {
  int minFrames = 8,
  int minLive = 1,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var frames = 0;
  var live = 0;
  while (DateTime.now().isBefore(deadline)) {
    await platform.pollCameraNative();
    frames = platform.lastCameraFrameCount;
    live = platform.lastCameraLiveFrames;
    if (frames >= minFrames && live >= minLive) {
      nativeOrchestrationLog.info(
        'NATIVE_CAMERA_STREAM frames=$frames live=$live',
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(
    'camera stream not live after 5s frames=$frames live=$live '
    '(need frames>=$minFrames live>=$minLive)',
  );
}

Future<void> waitForCapture(
  Session session, {
  List<Endpoint> catalog = const [],
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  var peakRms = 0.0;
  while (DateTime.now().isBefore(deadline)) {
    final rms = session.diagnostics.recentRms ?? 0;
    if (rms > peakRms) {
      peakRms = rms;
    }
    if (session.diagnostics.captureFrameCount > 1 && peakRms > 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  // Silent mics (emulator, mute-like zeros) still prove the capture graph.
  if (session.diagnostics.captureFrameCount > 1) {
    nativeOrchestrationLog.info(
      'NATIVE_CAPTURE frames=${session.diagnostics.captureFrameCount} '
      'peakRms=$peakRms recentRms=${session.diagnostics.recentRms}',
    );
    return;
  }
  final diagnostics = session.diagnostics;
  final names = [
    for (final endpoint in catalog)
      '${endpoint.routeClass.name}:${endpoint.isCapture ? 'in' : 'out'}:${endpoint.name}',
  ].join(' | ');
  fail(
    'capture stayed dead frames=${diagnostics.captureFrameCount} '
    'rms=${diagnostics.recentRms} '
    'status=${session.status.code.name} '
    'desired=${diagnostics.desired.captureId}/${diagnostics.desired.renderId} '
    'observed=${diagnostics.observed.captureId}/${diagnostics.observed.renderId} '
    'catalog=$names',
  );
}

Future<void> playFixture(Session session) async {
  final fixture = FixturePcm.voiceBand24k();
  const frameBytes = 480;
  for (var offset = 0; offset < fixture.length; offset += frameBytes) {
    final end = offset + frameBytes > fixture.length
        ? fixture.length
        : offset + frameBytes;
    await session.play(Uint8List.sublistView(fixture, offset, end));
  }
}

Future<bool> observedMatches(Session session) async {
  final deadline = DateTime.now().add(Session.convergenceDeadline);
  while (DateTime.now().isBefore(deadline)) {
    if (session.diagnostics.observedMatchesDesired) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

Future<void> assertObserved(Session session) async {
  if (await observedMatches(session)) {
    return;
  }
  final diagnostics = session.diagnostics;
  fail(
    'Observed did not match Desired '
    'desired=${diagnostics.desired.captureId}/${diagnostics.desired.renderId} '
    'applied=${diagnostics.applied.captureId}/${diagnostics.applied.renderId} '
    'observed=${diagnostics.observed.captureId}/${diagnostics.observed.renderId}',
  );
}

Pair? completePair(List<Endpoint> catalog, RouteClass routeClass) {
  for (final capture in catalog.where(
    (endpoint) => endpoint.routeClass == routeClass && endpoint.isCapture,
  )) {
    final render = catalog
        .where(
          (endpoint) =>
              endpoint.pairId == capture.pairId && !endpoint.isCapture,
        )
        .firstOrNull;
    if (render != null) {
      return Pair(id: capture.pairId, capture: capture, render: render);
    }
  }
  return null;
}

Pair? pairForRoute(List<Endpoint> catalog, RouteClass routeClass) {
  final capture = catalog
      .where(
        (endpoint) => endpoint.routeClass == routeClass && endpoint.isCapture,
      )
      .firstOrNull;
  final render = catalog
      .where(
        (endpoint) => endpoint.routeClass == routeClass && !endpoint.isCapture,
      )
      .firstOrNull;
  if (capture == null && render == null) {
    return null;
  }
  return Pair(
    id: capture?.pairId ?? render!.pairId,
    capture: capture,
    render: render,
  );
}

Map<String, Object?> snapshot(Session session, {required String caseName}) {
  final diagnostics = session.diagnostics;
  return {
    'case': caseName,
    'desiredCapture': diagnostics.desired.captureId,
    'desiredRender': diagnostics.desired.renderId,
    'appliedCapture': diagnostics.applied.captureId,
    'appliedRender': diagnostics.applied.renderId,
    'observedCapture': diagnostics.observed.captureId,
    'observedRender': diagnostics.observed.renderId,
    'preferenceControlled': diagnostics.preferenceControlled,
    'generation': diagnostics.selectionGeneration,
    'captureFrames': diagnostics.captureFrameCount,
    'recentRms': diagnostics.recentRms,
    'playbackAccepted': diagnostics.playbackAccepted,
    'playbackQueued': diagnostics.playbackQueued,
    'nativeCaptureFormat': diagnostics.nativeCaptureFormat?.toString(),
    'nativePlaybackFormat': diagnostics.nativePlaybackFormat?.toString(),
    'edgeCaptureFormat': diagnostics.edgeCaptureFormat?.toString(),
    'captureConversionPath': diagnostics.captureConversionPath.name,
    'status': session.status.code.name,
    'isolation': session.lastIsolation.state.name,
    'cameraSend': session.cameraSend,
    'cameraEnabled': session.isCameraEnabled,
    'videoMuted': session.isVideoMuted,
    'videoSurface': session.videoSurface?.handle,
    'nativeVideoFormat': session.nativeVideoFormat?.toString(),
    'videoUnavailableReason': session.videoUnavailableReason,
    'selectedCameraId': session.selectedCameraId,
    'screenSending': session.isScreenSending,
    'screenSurface': session.screenSurface?.handle,
    'screenNativeFormat': session.screenNativeFormat?.toString(),
    'screenUnavailableReason': session.screenUnavailableReason,
    'selectedScreenSourceId': session.selectedScreenSourceId,
    'includeSystemAudio': session.includeSystemAudio,
    'screenMotion': session.isScreenMotion,
    'screenCursor': session.isScreenCursor,
  };
}

Future<void> writeReceipt(Map<String, Object?> body) async {
  final encoded = const JsonEncoder.withIndent('  ').convert(body);
  nativeOrchestrationLog.info('NATIVE_ORCHESTRATION_RECEIPT $encoded');
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  final data = binding.reportData ??= <String, dynamic>{};
  final receipts = data['receipts'];
  if (receipts is List<Map<String, Object?>>) {
    receipts.add(body);
  } else if (receipts is List) {
    receipts.add(body);
  } else {
    data['receipts'] = <Map<String, Object?>>[body];
  }
  data['logs'] = List<String>.of(nativeOrchestrationLogs);
  final name =
      '${body['commit']}-${body['platform']}-${_safe(host.hostHardwareLabel())}.json';
  await host.hostWriteReceiptFile(name, encoded);
}

String catalogSummary(List<Endpoint> catalog) => [
  for (final endpoint in catalog)
    '${endpoint.routeClass.name}:${endpoint.isCapture ? 'in' : 'out'}:${endpoint.name}',
].join(' | ');

String hostCommit() => host.hostGitCommit();

String hostOs() => host.hostOperatingSystem();

String hostOsVersion() => host.hostOperatingSystemVersion();

String hostHardware() => host.hostHardwareLabel();

bool get runningOnWeb => kIsWeb;

String _safe(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
