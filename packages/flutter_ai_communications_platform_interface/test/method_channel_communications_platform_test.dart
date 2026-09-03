import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('flutter_ai_communications/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannelCommunicationsPlatform platform;
  final calls = <MethodCall>[];

  setUp(() {
    FlutterAiCommunicationsPlatform.debugReset();
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'enumerateEndpoints' => [
          {
            'id': 'handset-in',
            'name': 'Handset',
            'routeClass': 'handset',
            'isCapture': true,
            'pairId': 'handset',
          },
          {
            'id': 'speaker-out',
            'name': 'Speakerphone',
            'routeClass': 'speakerphone',
            'isCapture': false,
            'pairId': 'speakerphone',
          },
          {
            'id': 'bt-in',
            'name': 'BT-Audio',
            'routeClass': 'bluetooth',
            'isCapture': true,
            'pairId': 'bt',
            'identityHints': ['Tesla Model Y'],
            'capabilities': {
              'formFactor': 'car',
              'aec': false,
              'ns': false,
              'agc': false,
              'carConnected': false,
            },
          },
        ],
        'requestMicrophonePermission' => 'denied',
        'startNative' => 'started',
        _ => null,
      };
    });
    platform = MethodChannelCommunicationsPlatform(platformName: 'ios');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(methods, null);
    await platform.dispose();
    FlutterAiCommunicationsPlatform.debugReset();
  });

  test('catalog includes handset and speakerphone from native maps', () async {
    final catalog = await platform.enumerateEndpoints();
    expect(catalog.any((e) => e.routeClass == RouteClass.handset), isTrue);
    expect(catalog.any((e) => e.routeClass == RouteClass.speakerphone), isTrue);
  });

  test(
    'catalog forwards Bluetooth identityHints and car form factor',
    () async {
      final catalog = await platform.enumerateEndpoints();
      final tesla = catalog.firstWhere((e) => e.id == 'bt-in');
      expect(tesla.identityHints, ['Tesla Model Y']);
      expect(tesla.capabilities.formFactor, EndpointFormFactor.car);
    },
  );

  test('denied permission is a value, not an exception', () async {
    expect(
      await platform.requestMicrophonePermission(),
      MicrophonePermission.denied,
    );
  });

  test(
    'startNative and selectEndpoints keep the same capture stream',
    () async {
      final capture = platform.nativeCapture;
      expect(
        await platform.startNative(captureId: 'handset-in'),
        NativeGraphStart.started,
      );
      await platform.selectEndpoints(
        captureId: 'handset-in',
        renderId: 'speaker-out',
      );
      expect(identical(platform.nativeCapture, capture), isTrue);
      expect(calls.any((c) => c.method == 'startNative'), isTrue);
      expect(calls.any((c) => c.method == 'selectEndpoints'), isTrue);
    },
  );

  test('openIsolationSettings is forwarded', () async {
    await platform.openIsolationSettings();
    expect(calls.any((c) => c.method == 'openIsolationSettings'), isTrue);
  });

  test('startNative forwards noiseCancelling', () async {
    await platform.startNative(noiseCancelling: false);
    final call = calls.singleWhere((c) => c.method == 'startNative');
    expect((call.arguments as Map)['noiseCancelling'], isFalse);
  });

  test(
    'startNative map reports Native Formats, not the requested edge',
    () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'startNative') {
          return {
            'status': 'started',
            'nativeCaptureFormat': {
              'encoding': 'pcm16le',
              'sampleRate': 48000,
              'channels': 1,
            },
            'nativePlaybackFormat': {
              'encoding': 'pcm16le',
              'sampleRate': 44100,
              'channels': 1,
            },
          };
        }
        return null;
      });
      expect(
        await platform.startNative(
          captureFormat: AudioFormat.pcm16le24k,
          playbackFormat: AudioFormat.pcm16le24k,
        ),
        NativeGraphStart.started,
      );
      expect(
        platform.lastNativeFormats.capture,
        const AudioFormat.pcm16le(sampleRate: 48000),
      );
      expect(
        platform.lastNativeFormats.playback,
        const AudioFormat.pcm16le(sampleRate: 44100),
      );
    },
  );

  test('startNative map reports structured Format failures', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'startNative') {
        return {
          'status': 'started',
          'captureFormat': {
            'encoding': 'pcm16le',
            'sampleRate': 48000,
            'channels': 1,
          },
          'playbackFormat': {
            'encoding': 'pcm16le',
            'sampleRate': 48000,
            'channels': 1,
          },
          'formatFailures': [
            {
              'encoding': 'pcm16le',
              'sampleRate': 24000,
              'channels': 1,
              'reason': 'unsupported',
            },
          ],
        };
      }
      return null;
    });
    expect(await platform.startNative(), NativeGraphStart.started);
    expect(platform.lastNativeFormats.failures, [
      const FormatCandidateFailure(
        format: AudioFormat.pcm16le24k,
        reason: 'unsupported',
      ),
    ]);
  });

  test('selectEndpoints map re-adopts Native Formats', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'selectEndpoints') {
        return {
          'status': 'started',
          'nativeCaptureFormat': {
            'encoding': 'pcm16le',
            'sampleRate': 16000,
            'channels': 1,
          },
          'nativePlaybackFormat': {
            'encoding': 'pcm16le',
            'sampleRate': 48000,
            'channels': 1,
          },
        };
      }
      return null;
    });
    await platform.selectEndpoints(captureId: 'usb-in', renderId: 'usb-out');
    expect(
      platform.lastNativeFormats.capture,
      const AudioFormat.pcm16le(sampleRate: 16000),
    );
    expect(
      platform.lastNativeFormats.playback,
      const AudioFormat.pcm16le(sampleRate: 48000),
    );
  });

  test('isolation payload required maps to IsolationState.required', () async {
    await platform.dispose();
    const events = EventChannel('flutter_ai_communications/events');
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, eventSink) {
          sink = eventSink;
        },
      ),
    );
    platform = MethodChannelCommunicationsPlatform(platformName: 'ios');
    final seen = <IsolationEvent>[];
    final sub = platform.isolation.listen(seen.add);
    sink.success({'type': 'isolation', 'payload': 'required'});
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.state, IsolationState.required);
    expect(platform.lastIsolation.state, IsolationState.required);
    await sub.cancel();
    messenger.setMockStreamHandler(events, null);
  });

  test('EventChannel listen waits for the first native call', () async {
    await platform.dispose();
    var listenCount = 0;
    const events = EventChannel('flutter_ai_communications/events');
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, eventSink) {
          listenCount++;
        },
      ),
    );
    platform = MethodChannelCommunicationsPlatform(platformName: 'android');
    expect(listenCount, 0);
    await platform.enumerateEndpoints();
    expect(listenCount, 1);
    messenger.setMockStreamHandler(events, null);
  });

  test('startCameraNative maps failed separately from unavailable', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'startCameraNative') {
        return {'status': 'failed'};
      }
      return null;
    });
    expect(
      await platform.startCameraNative(cameraId: 'cam'),
      NativeGraphStart.failed,
    );
    expect(platform.lastVideoSurface, isNull);

    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'startCameraNative') {
        return {'status': 'unavailable'};
      }
      return null;
    });
    expect(
      await platform.startCameraNative(cameraId: 'cam'),
      NativeGraphStart.unavailable,
    );
  });

  test('route events update last Observed Pair', () async {
    await platform.dispose();
    const events = EventChannel('flutter_ai_communications/events');
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, eventSink) {
          sink = eventSink;
        },
      ),
    );
    platform = MethodChannelCommunicationsPlatform(platformName: 'ios');
    final seen = <OsRouteChange>[];
    final sub = platform.osRouteChanges.listen(seen.add);
    sink.success({
      'type': 'route',
      'payload': {
        'captureId': 'airpods-in',
        'renderId': 'airpods-out',
        'generation': 2,
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.captureId, 'airpods-in');
    expect(seen.single.renderId, 'airpods-out');
    expect(seen.single.generation, 2);
    expect(platform.lastObservedRoute.captureId, 'airpods-in');
    expect(platform.lastObservedRoute.renderId, 'airpods-out');
    await sub.cancel();
    messenger.setMockStreamHandler(events, null);
  });
}
