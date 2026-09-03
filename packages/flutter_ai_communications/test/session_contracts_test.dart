import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCommunicationsPlatform platform;
  late CommunicationsManager manager;

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    manager = CommunicationsManager(platform: platform);
  });

  tearDown(() async {
    Session.convergenceDeadline = const Duration(seconds: 2);
    Session.maxConvergenceAttempts = 3;
    Session.teardownTimeout = const Duration(seconds: 2);
    await manager.session?.stop();
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  Future<Session> ready({
    SessionPreference preference = const SessionPreference(),
    SessionDirection direction = SessionDirection.duplex,
    String? purpose,
  }) async {
    final result = await manager.start(
      preference: preference,
      direction: direction,
      purpose: purpose,
    );
    return (result as StartReady).session;
  }

  group('Endpoint preference', () {
    test('start resolves bluetooth before speakerphone and handset', () async {
      final session = await ready();
      expect(session.diagnostics.desired.captureId, 'airpods-in');
      expect(session.diagnostics.desired.renderId, 'airpods-out');
      expect(session.diagnostics.preferenceControlled, isTrue);
      expect(platform.selectedCaptureId, 'airpods-in');
    });

    test('host order is resolved top to bottom', () async {
      final session = await ready(
        preference: const SessionPreference(
          endpoints: EndpointPreference(
            entries: [
              EndpointPreferenceEntry(id: 'handset-in'),
              EndpointPreferenceEntry(id: 'speaker-in'),
            ],
          ),
        ),
      );
      expect(session.diagnostics.desired.captureId, 'handset-in');
      expect(session.preference.endpoints.entries.first.id, 'handset-in');
    });

    test(
      'AirPods remaining in the catalog lose when ranked below USB',
      () async {
        platform.catalog = [
          ...FakeCommunicationsPlatform.defaultCatalog,
          const Endpoint(
            id: 'usb-in',
            name: 'USB Audio',
            routeClass: RouteClass.wired,
            isCapture: true,
            pairId: 'usb',
          ),
          const Endpoint(
            id: 'usb-out',
            name: 'USB Audio',
            routeClass: RouteClass.wired,
            isCapture: false,
            pairId: 'usb',
          ),
        ];
        final session = await ready(
          preference: const SessionPreference(
            endpoints: EndpointPreference(
              entries: [
                EndpointPreferenceEntry(id: 'usb-in'),
                EndpointPreferenceEntry(id: 'airpods-in'),
              ],
            ),
          ),
        );
        expect(session.diagnostics.desired.captureId, 'usb-in');
        expect(session.diagnostics.desired.renderId, 'usb-out');
        expect(session.diagnostics.preferenceControlled, isTrue);
        expect(platform.selectedCaptureId, 'usb-in');
        expect(platform.selectedRenderId, 'usb-out');

        platform.osRouteController.add(
          const OsRouteChange(captureId: 'airpods-in', renderId: 'airpods-out'),
        );
        await _microtask();
        expect(session.diagnostics.desired.captureId, 'usb-in');
        expect(session.diagnostics.desired.renderId, 'usb-out');
        expect(session.diagnostics.observed.captureId, 'airpods-in');
        expect(session.diagnostics.observedMatchesDesired, isFalse);
      },
    );

    test(
      'host list uses webcam capture and USB render above AirPods',
      () async {
        platform.catalog = [
          const Endpoint(
            id: 'brio-in',
            name: 'Logitech BRIO',
            routeClass: RouteClass.wired,
            isCapture: true,
            pairId: 'logitech brio',
          ),
          const Endpoint(
            id: 'usb-out',
            name: 'USB Audio',
            routeClass: RouteClass.wired,
            isCapture: false,
            pairId: 'usb audio',
          ),
          ...FakeCommunicationsPlatform.defaultCatalog,
        ];
        final session = await ready(
          preference: const SessionPreference(
            endpoints: EndpointPreference(
              entries: [
                EndpointPreferenceEntry(id: 'brio-in'),
                EndpointPreferenceEntry(id: 'usb-out'),
                EndpointPreferenceEntry(id: 'airpods-in'),
              ],
            ),
          ),
        );
        expect(session.diagnostics.preferenceControlled, isTrue);
        expect(session.diagnostics.desired.captureId, 'brio-in');
        expect(session.diagnostics.desired.renderId, 'usb-out');
        expect(platform.selectedCaptureId, 'brio-in');
        expect(platform.selectedRenderId, 'usb-out');
      },
    );

    test('explicit select overrides preference without rewriting it', () async {
      final session = await ready();
      await session.select(captureId: 'handset-in');
      expect(session.diagnostics.desired.captureId, 'handset-in');
      expect(session.diagnostics.preferenceControlled, isFalse);
      expect(session.preference.endpoints.isEmpty, isTrue);
      expect(session.selectedCaptureId, 'handset-in');
    });

    test('disappeared explicit selection returns to preference', () async {
      final session = await ready();
      await session.select(captureId: 'handset-in');
      platform.publishCatalog(
        platform.catalog
            .where((e) => e.routeClass != RouteClass.handset)
            .toList(),
      );
      await _microtask();
      expect(session.diagnostics.preferenceControlled, isTrue);
      expect(session.diagnostics.desired.captureId, 'airpods-in');
    });

    test(
      'higher-priority appearance promotes only while preference-controlled',
      () async {
        platform.catalog = FakeCommunicationsPlatform.defaultCatalog
            .where((e) => e.pairId != 'airpods')
            .toList();
        final session = await ready();
        expect(session.diagnostics.desired.captureId, 'speaker-in');

        platform.publishCatalog(FakeCommunicationsPlatform.defaultCatalog);
        await _microtask();
        expect(session.diagnostics.desired.captureId, 'airpods-in');

        await session.select(captureId: 'handset-in');
        platform.publishCatalog(
          FakeCommunicationsPlatform.defaultCatalog
              .where((e) => e.routeClass != RouteClass.handset)
              .toList(),
        );
        await _microtask();
        platform.publishCatalog(FakeCommunicationsPlatform.defaultCatalog);
        await _microtask();
        expect(session.diagnostics.desired.captureId, 'airpods-in');
      },
    );

    test(
      'new Session starts from preference, not prior explicit selection',
      () async {
        final first = await ready();
        await first.select(captureId: 'handset-in');
        await first.stop();
        final second = await ready();
        expect(second.diagnostics.desired.captureId, 'airpods-in');
        expect(identical(second, first), isFalse);
      },
    );

    test(
      'unavailable retained ids are not guessed from display name',
      () async {
        final session = await ready(
          preference: const SessionPreference(
            endpoints: EndpointPreference(
              entries: [
                EndpointPreferenceEntry(id: 'ghost-airpods'),
                EndpointPreferenceEntry(id: 'speaker-in'),
              ],
            ),
          ),
        );
        expect(session.diagnostics.desired.captureId, 'speaker-in');
      },
    );

    test(
      'bindPreference ends the live Session and supplies the next start',
      () async {
        await ready();
        await manager.bindPreference(
          const EndpointPreference(
            entries: [EndpointPreferenceEntry(id: 'handset-in')],
          ),
        );
        expect(manager.session, isNull);
        final next = await ready();
        expect(next.diagnostics.desired.captureId, 'handset-in');
      },
    );
  });

  group('directed Sessions', () {
    test('competing start names the active Session purpose', () async {
      await ready(purpose: 'scribe');
      final second = await manager.start(purpose: 'review');
      expect(second, isA<StartAlreadyActive>());
      expect((second as StartAlreadyActive).purpose, 'scribe');
    });

    test('playback-only does not request the microphone', () async {
      platform.permission = MicrophonePermission.denied;
      final result = await manager.start(
        direction: SessionDirection.playbackOnly,
        purpose: 'review',
      );
      expect(result, isA<StartReady>());
      expect(platform.permissionRequests, 0);
      expect(
        (result as StartReady).session.direction,
        SessionDirection.playbackOnly,
      );
    });

    test('capture-only play is a no-op', () async {
      final session = await ready(direction: SessionDirection.captureOnly);
      await session.play(Uint8List.fromList([1, 2, 3, 4]));
      expect(platform.played, isEmpty);
      expect(session.direction, SessionDirection.captureOnly);
    });

    test('capture-only does not acquire unused playback', () async {
      final session = await ready(direction: SessionDirection.captureOnly);
      expect(platform.selectedRenderId, isNull);
      expect(session.diagnostics.desired.renderId, isNull);
      expect(session.diagnostics.nativePlaybackFormat, isNull);
    });

    test('playback-only does not acquire unused capture', () async {
      final session = await ready(direction: SessionDirection.playbackOnly);
      expect(platform.selectedCaptureId, isNull);
      expect(session.diagnostics.desired.captureId, isNull);
      expect(session.diagnostics.nativeCaptureFormat, isNull);
      expect(platform.permissionRequests, 0);
    });

    test('playback-only is playbackReady after the graph is Observed', () async {
      final session = await ready(direction: SessionDirection.playbackOnly);
      expect(session.status.code, SessionStatusCode.playbackReady);
      expect(session.diagnostics.nativePlaybackFormat, isNotNull);
    });

    test('capture-only is captureLive after frames arrive', () async {
      final session = await ready(direction: SessionDirection.captureOnly);
      expect(session.status.code, SessionStatusCode.starting);
      platform.feedCapture(_voiceFrame());
      await _microtask();
      expect(session.status.code, SessionStatusCode.captureLive);
    });
  });

  group('status and diagnostics', () {
    test('late status subscriber receives the current snapshot', () async {
      final session = await ready(purpose: 'scribe');
      expect(session.status.code, SessionStatusCode.starting);
      expect(session.status.severity, StatusSeverity.warning);

      platform.feedCapture(_voiceFrame());
      await _microtask();
      expect(session.status.code, SessionStatusCode.ready);
      expect(session.status.severity, StatusSeverity.success);

      final seen = <SessionStatus>[];
      final sub = session.statuses.listen(seen.add);
      await _microtask();
      expect(seen, isNotEmpty);
      expect(seen.first.code, SessionStatusCode.ready);
      expect(seen.first.purpose, 'scribe');
      await sub.cancel();
    });

    test(
      'diagnostics keep Desired when OS reports a different Observed Pair',
      () async {
        final session = await ready();
        await session.select(captureId: 'airpods-in', renderId: 'speaker-out');
        expect(session.diagnostics.desired.captureId, 'airpods-in');
        expect(session.diagnostics.desired.renderId, 'speaker-out');
        expect(session.diagnostics.applied.renderId, 'speaker-out');

        platform.osRouteController.add(
          const OsRouteChange(captureId: 'airpods-in', renderId: 'airpods-out'),
        );
        await _microtask();
        expect(session.diagnostics.desired.renderId, 'speaker-out');
        expect(session.diagnostics.observed.renderId, 'airpods-out');
        expect(session.diagnostics.observedMatchesDesired, isFalse);
        expect(session.status.code, isNot(SessionStatusCode.ready));
      },
    );

    test('command completion does not mark Observed as matching', () async {
      platform.observeOnApply = false;
      final session = await ready();
      expect(session.diagnostics.desired.captureId, 'airpods-in');
      expect(session.diagnostics.applied.captureId, 'airpods-in');
      expect(session.diagnostics.observed.captureId, isNull);
      expect(session.diagnostics.observedMatchesDesired, isFalse);
      platform.feedCapture(_voiceFrame());
      await _microtask();
      expect(session.status.code, isNot(SessionStatusCode.ready));
    });

    test(
      'OS mismatch reasserts Desired at most three times then faults',
      () async {
        Session.convergenceDeadline = const Duration(milliseconds: 40);
        platform.observeOnApply = false;
        final session = await ready();
        await session.select(captureId: 'airpods-in', renderId: 'speaker-out');
        final before = platform.selectEndpointsCalls;
        platform.osRouteController.add(
          const OsRouteChange(captureId: 'airpods-in', renderId: 'airpods-out'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(session.diagnostics.desired.renderId, 'speaker-out');
        expect(session.diagnostics.preferenceControlled, isFalse);
        expect(session.status.code, SessionStatusCode.routeMismatch);
        expect(session.status.severity, StatusSeverity.error);
        expect(session.status.usability, StatusUsability.unusable);
        expect(session.diagnostics.preferenceControlled, isFalse);
        expect(platform.selectEndpointsCalls - before, lessThanOrEqualTo(3));
        expect(platform.selectEndpointsCalls - before, greaterThan(0));
      },
    );

    test('preference Pair that cannot converge walks downward', () async {
      Session.convergenceDeadline = const Duration(milliseconds: 30);
      platform.observeOnApply = false;
      final session = await ready();
      expect(session.diagnostics.desired.captureId, 'airpods-in');
      platform.osRouteController.add(
        const OsRouteChange(captureId: 'speaker-in', renderId: 'speaker-out'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(session.diagnostics.desired.captureId, isNot('airpods-in'));
      expect(session.diagnostics.preferenceControlled, isTrue);
    });

    test(
      'self-generated Observed matching Desired does not loop select',
      () async {
        final session = await ready();
        final before = platform.selectEndpointsCalls;
        platform.osRouteController.add(
          OsRouteChange(
            captureId: session.diagnostics.desired.captureId,
            renderId: session.diagnostics.desired.renderId,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(platform.selectEndpointsCalls, before);
        expect(session.diagnostics.observedMatchesDesired, isTrue);
      },
    );

    test('diagnostics expose capture cadence without audio bytes', () async {
      final session = await ready();
      final before = session.diagnostics;
      expect(before.captureFrameCount, 0);
      expect(before.edgeCaptureFormat, AudioFormat.pcm16le24k);
      platform.feedCapture(_voiceFrame());
      await _microtask();
      expect(session.diagnostics.captureFrameCount, 1);
      expect(session.diagnostics.recentRms, greaterThan(0));
      expect(session.diagnostics.lastCaptureAt, isNotNull);
    });
  });

  group('pipeline logs', () {
    test(
      'start through capture emits structured codes without audio bytes',
      () async {
        final records = <String>[];
        final sub = PipelineLog.listen((record) => records.add(record.message));
        final session = await ready(purpose: 'scribe');
        platform.feedCapture(_voiceFrame());
        await _microtask();
        await session.play(Uint8List.fromList([1, 2, 3, 4]));
        await session.stop();
        await sub.cancel();

        final codes = records.map((line) => PipelineLog.parse(line)['code']);
        expect(codes, contains(PipelineLog.startRequested));
        expect(codes, contains(PipelineLog.permission));
        expect(codes, contains(PipelineLog.catalog));
        expect(codes, contains(PipelineLog.preferenceResolved));
        expect(codes, contains(PipelineLog.nativeStart));
        expect(codes, contains(PipelineLog.desired));
        expect(codes, contains(PipelineLog.applied));
        expect(codes, contains(PipelineLog.observed));
        expect(codes, contains(PipelineLog.status));
        expect(codes, contains(PipelineLog.isolation));
        expect(codes, contains(PipelineLog.capture));
        expect(codes, contains(PipelineLog.playback));
        expect(codes, contains(PipelineLog.stopped));
        expect(records.any((line) => line.contains('state=required')), isTrue);
        expect(records.any((line) => line.contains('purpose=scribe')), isTrue);
        expect(records.any((line) => line.contains('frames=1')), isTrue);
        expect(
          records.any(
            (line) => line.contains(String.fromCharCodes([1, 2, 3, 4])),
          ),
          isFalse,
        );
      },
    );
  });
}

Future<void> _microtask() => Future<void>.delayed(Duration.zero);

Uint8List _voiceFrame() {
  const sampleRate = 24000;
  const hz = 700.0;
  const amplitude = 14000;
  final count = (sampleRate * 0.05).round();
  final out = Uint8List(count * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < count; i++) {
    final sample = (math.sin(2 * math.pi * hz * i / sampleRate) * amplitude)
        .round()
        .clamp(-32767, 32767);
    data.setInt16(i * 2, sample, Endian.little);
  }
  return out;
}
