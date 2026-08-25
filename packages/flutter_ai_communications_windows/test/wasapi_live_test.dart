import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_windows/src/wasapi_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live WASAPI', () {
  test('catalog starts and emits non-zero capture', () async {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
    final logs = <String>[];
    final sub = Logger.root.onRecord.listen((record) {
      logs.add(
        '${record.level.name} ${record.loggerName} '
        '${record.message} ${record.error ?? ''}',
      );
    });
    addTearDown(sub.cancel);

    final backend = WasapiWindowsBackend();
    addTearDown(backend.dispose);
    final catalog = backend.enumerate();
    final summary = [
      for (final endpoint in catalog)
        '${endpoint.routeClass.name}:${endpoint.isCapture ? 'in' : 'out'}:${endpoint.name} pair=${endpoint.pairId}',
    ].join(' | ');

    expect(catalog, isNotEmpty, reason: 'WASAPI catalog was empty. logs=$logs');
    expect(
      catalog.every((endpoint) => !endpoint.pairId.contains('Pointer:')),
      isTrue,
      reason:
          'Pair identity must be a ContainerId GUID, not Pointer.toString: '
          '$summary',
    );
    expect(
      catalog.any((endpoint) => endpoint.isCapture),
      isTrue,
      reason: summary,
    );
    expect(
      catalog.any((endpoint) => !endpoint.isCapture),
      isTrue,
      reason: summary,
    );

    final frames = <Uint8List>[];
    final framesSub = backend.capture.listen(frames.add);
    addTearDown(framesSub.cancel);

    final started = backend.start();
    expect(
      started,
      NativeGraphStart.started,
      reason: 'start failed catalog=$summary logs=$logs',
    );
    expect(backend.observed.captureId, isNotNull, reason: summary);
    expect(backend.observed.renderId, isNotNull, reason: summary);

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    var peak = 0;
    while (DateTime.now().isBefore(deadline) && peak == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final frame in frames) {
        for (final byte in frame) {
          if (byte > peak) {
            peak = byte;
          }
        }
      }
    }
    final observedCapture = backend.observed.captureId;
    final observedRender = backend.observed.renderId;
    backend.stop();

    expect(
      frames.length,
      greaterThan(1),
      reason:
          'no capture frames observed=$observedCapture/$observedRender catalog=$summary logs=$logs',
    );
    expect(
      peak,
      greaterThan(0),
      reason:
          'capture stayed silent frames=${frames.length} '
          'observed=$observedCapture/$observedRender '
          'catalog=$summary logs=$logs',
    );
  });

  test('start of a catalog Pair reports those Observed ids', () async {
    final backend = WasapiWindowsBackend();
    addTearDown(backend.dispose);
    final catalog = backend.enumerate();
    final capture = catalog.where((endpoint) => endpoint.isCapture).firstOrNull;
    expect(capture, isNotNull, reason: 'catalog has no capture Endpoint');
    final render =
        catalog
            .where(
              (endpoint) =>
                  !endpoint.isCapture && endpoint.pairId == capture!.pairId,
            )
            .firstOrNull ??
        catalog.where((endpoint) => !endpoint.isCapture).firstOrNull;
    expect(render, isNotNull, reason: 'catalog has no render Endpoint');

    final frames = <Uint8List>[];
    final framesSub = backend.capture.listen(frames.add);
    addTearDown(framesSub.cancel);

    final started = backend.start(
      captureId: capture!.id,
      renderId: render!.id,
    );
    expect(started, NativeGraphStart.started);
    expect(
      backend.observed.captureId,
      capture.id,
      reason:
          'Observed capture must be the opened catalog id, not a fallback',
    );
    expect(
      backend.observed.renderId,
      render.id,
      reason: 'Observed render must be the opened catalog id, not a fallback',
    );

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    var peak = 0;
    while (DateTime.now().isBefore(deadline) && peak == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final frame in frames) {
        for (final byte in frame) {
          if (byte > peak) {
            peak = byte;
          }
        }
      }
    }
    backend.stop();
    expect(frames.length, greaterThan(1));
    expect(
      peak,
      greaterThan(0),
      reason:
          'selected Pair stayed silent capture=${capture.id} render=${render.id}',
    );
  });

  test('split capture/render stays on those Endpoints', () async {
    final backend = WasapiWindowsBackend();
    addTearDown(backend.dispose);
    final catalog = backend.enumerate();
    final capture = catalog.where((endpoint) => endpoint.isCapture).firstOrNull;
    final splitRender = catalog
        .where(
          (endpoint) =>
              !endpoint.isCapture && endpoint.pairId != capture?.pairId,
        )
        .firstOrNull;
    expect(capture, isNotNull);
    expect(
      splitRender,
      isNotNull,
      reason:
          'need an unpaired render Endpoint to prove split apply. catalog='
          '${[
            for (final endpoint in catalog)
              '${endpoint.routeClass.name}:${endpoint.isCapture ? 'in' : 'out'}:${endpoint.name}',
          ].join(' | ')}',
    );

    final started = backend.start(
      captureId: capture!.id,
      renderId: splitRender!.id,
    );
    expect(
      started,
      NativeGraphStart.started,
      reason: 'split start failed capture=${capture.id} render=${splitRender.id}',
    );
    expect(backend.observed.captureId, capture.id);
    expect(
      backend.observed.renderId,
      splitRender.id,
      reason:
          'split render must not fall back to the capture Pair or default communications',
    );
    backend.stop();
  });

  test('capture-only does not bind render', () async {
    final backend = WasapiWindowsBackend();
    addTearDown(backend.dispose);
    final capture = backend.enumerate().where((e) => e.isCapture).firstOrNull;
    expect(capture, isNotNull);
    final frames = <Uint8List>[];
    final sub = backend.capture.listen(frames.add);
    addTearDown(sub.cancel);
    expect(backend.start(captureId: capture!.id), NativeGraphStart.started);
    expect(backend.observed.captureId, capture.id);
    expect(backend.observed.renderId, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    backend.stop();
    expect(frames.length, greaterThan(1));
  });

  test('playback-only does not bind capture', () async {
    final backend = WasapiWindowsBackend();
    addTearDown(backend.dispose);
    final render = backend.enumerate().where((e) => !e.isCapture).firstOrNull;
    expect(render, isNotNull);
    expect(backend.start(renderId: render!.id), NativeGraphStart.started);
    expect(backend.observed.captureId, isNull);
    expect(backend.observed.renderId, render.id);
    backend.play(Uint8List(480));
    backend.stop();
  });
  }, skip: !Platform.isWindows || Platform.environment['WASAPI_LIVE'] != '1');
}
