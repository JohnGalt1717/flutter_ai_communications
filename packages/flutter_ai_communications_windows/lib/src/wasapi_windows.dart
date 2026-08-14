import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:win32/win32.dart';

import 'route_class.dart';
import 'wasapi_backend.dart';

/// Shared-mode WASAPI PCM16 LE conversion flags.
const _autoConvertPcm = 0x80000000;
const _srcDefaultQuality = 0x08000000;
const _refTimes20ms = 20 * 10000;
const _sampleRate = 24000;
const _silenceBytes = 480;

/// CLSID_MMDeviceEnumerator.
final _mmDeviceEnumerator = GUID.fromComponents(
  0xbcde0395,
  0xe52f,
  0x467c,
  Uint8List.fromList(const [0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e]),
);

/// Windows WASAPI capture/render graph.
final class WasapiWindowsBackend implements WasapiBackend {
  /// Creates the backend and initializes COM.
  WasapiWindowsBackend() {
    CoInitializeEx(COINIT_MULTITHREADED);
    try {
      _enumerator = _lifetime.com<IMMDeviceEnumerator>(_mmDeviceEnumerator);
    } on Object {
      _enumerator = null;
    }
  }

  final Arena _lifetime = Arena();
  IMMDeviceEnumerator? _enumerator;
  Arena? _graph;
  IAudioClient? _captureClient;
  IAudioCaptureClient? _capture;
  IAudioClient? _renderClient;
  IAudioRenderClient? _render;
  int _renderFrames = 0;
  Timer? _poll;
  var _running = false;
  var _paused = false;
  String? _captureId;
  String? _renderId;

  final StreamController<Uint8List> _captureOut =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get capture => _captureOut.stream;

  @override
  List<Endpoint> enumerate() {
    final enumerator = _enumerator;
    if (enumerator == null) {
      return const [];
    }
    return [
      ..._collect(enumerator, eCapture, capture: true),
      ..._collect(enumerator, eRender, capture: false),
    ];
  }

  @override
  MicrophonePermission probePermission() {
    try {
      final started = start();
      stop();
      return started == NativeGraphStart.started
          ? MicrophonePermission.granted
          : MicrophonePermission.denied;
    } on Object {
      return MicrophonePermission.denied;
    }
  }

  @override
  NativeGraphStart start({String? captureId, String? renderId}) {
    _captureId = captureId;
    _renderId = renderId;
    return _startGraph() ? NativeGraphStart.started : NativeGraphStart.failed;
  }

  @override
  void stop() {
    _running = false;
    _stopGraph();
  }

  @override
  void pause() {
    _paused = true;
    try {
      _captureClient?.stop();
      _renderClient?.stop();
    } on Object {
      // Pause is best-effort.
    }
  }

  @override
  void resume() {
    _paused = false;
    try {
      _captureClient?.start();
      _renderClient?.start();
    } on Object {
      // Resume is best-effort.
    }
  }

  @override
  void play(Uint8List bytes) {
    final render = _render;
    final client = _renderClient;
    if (render == null || client == null || !_running || _paused) {
      return;
    }
    final frames = bytes.length ~/ 2;
    if (frames == 0) {
      return;
    }
    try {
      final padding = client.getCurrentPadding();
      final available = _renderFrames > padding ? _renderFrames - padding : 0;
      final writeFrames = frames < available ? frames : available;
      if (writeFrames == 0) {
        return;
      }
      final dest = render.getBuffer(writeFrames);
      dest.asTypedList(writeFrames * 2).setRange(0, writeFrames * 2, bytes);
      render.releaseBuffer(writeFrames, 0);
    } on Object {
      // Drop the frame rather than failing the Session.
    }
  }

  @override
  void select({String? captureId, String? renderId}) {
    if (captureId != null) {
      _captureId = captureId;
    }
    if (renderId != null) {
      _renderId = renderId;
    }
    if (_running) {
      _startGraph();
    }
  }

  @override
  void flush() {
    try {
      _renderClient?.stop();
      _renderClient?.reset();
      if (_running && !_paused) {
        _renderClient?.start();
      }
    } on Object {
      // Flush is best-effort.
    }
  }

  @override
  void dispose() {
    stop();
    _lifetime.releaseAll();
    unawaited(_captureOut.close());
  }

  bool _startGraph() {
    _emitSilence();
    _stopGraph();
    final enumerator = _enumerator;
    if (enumerator == null) {
      return false;
    }
    final graph = Arena();
    try {
      final captureDevice = _device(enumerator, _captureId, eCapture, graph);
      final renderDevice = _device(enumerator, _renderId, eRender, graph);
      if (captureDevice == null || renderDevice == null) {
        graph.releaseAll();
        return false;
      }
      final format = graph<WAVEFORMATEX>();
      format.ref
        ..wFormatTag = WAVE_FORMAT_PCM
        ..nChannels = 1
        ..nSamplesPerSec = _sampleRate
        ..wBitsPerSample = 16
        ..nBlockAlign = 2
        ..nAvgBytesPerSec = _sampleRate * 2
        ..cbSize = 0;
      final flags = _autoConvertPcm | _srcDefaultQuality;
      final captureClient = graph.adopt(
        captureDevice.activate<IAudioClient>(CLSCTX_ALL, null),
      );
      captureClient.initialize(
        AUDCLNT_SHAREMODE_SHARED,
        flags,
        _refTimes20ms,
        0,
        format,
        null,
      );
      final capture = graph.adopt(
        captureClient.getService<IAudioCaptureClient>(),
      );
      final renderClient = graph.adopt(
        renderDevice.activate<IAudioClient>(CLSCTX_ALL, null),
      );
      renderClient.initialize(
        AUDCLNT_SHAREMODE_SHARED,
        flags,
        _refTimes20ms,
        0,
        format,
        null,
      );
      final render = graph.adopt(renderClient.getService<IAudioRenderClient>());
      _graph = graph;
      _captureClient = captureClient;
      _capture = capture;
      _renderClient = renderClient;
      _render = render;
      _renderFrames = renderClient.getBufferSize();
      final keepPaused = _paused;
      _running = true;
      _paused = keepPaused;
      if (!keepPaused) {
        captureClient.start();
        renderClient.start();
      }
      _poll = Timer.periodic(const Duration(milliseconds: 10), (_) {
        _pumpCapture();
      });
      return true;
    } on Object {
      graph.releaseAll();
      return false;
    }
  }

  void _stopGraph() {
    _running = false;
    _poll?.cancel();
    _poll = null;
    try {
      _captureClient?.stop();
      _renderClient?.stop();
    } on Object {
      // Teardown is best-effort.
    }
    _graph?.releaseAll();
    _graph = null;
    _captureClient = null;
    _capture = null;
    _renderClient = null;
    _render = null;
    _renderFrames = 0;
  }

  void _pumpCapture() {
    final capture = _capture;
    if (capture == null || !_running || _paused) {
      return;
    }
    using((arena) {
      final data = arena<Pointer<Uint8>>();
      final frames = arena<Uint32>();
      final flags = arena<Uint32>();
      try {
        var packet = capture.getNextPacketSize();
        while (packet > 0 && _running && !_paused) {
          capture.getBuffer(data, frames, flags, null, null);
          final count = frames.value;
          final bytes = Uint8List(count * 2);
          if (flags.value & AUDCLNT_BUFFERFLAGS_SILENT == 0 &&
              data.value != nullptr) {
            bytes.setAll(0, data.value.asTypedList(bytes.length));
          }
          capture.releaseBuffer(count);
          _captureOut.add(bytes);
          packet = capture.getNextPacketSize();
        }
      } on Object {
        // Drop a bad packet rather than ending the Session stream.
      }
    });
  }

  void _emitSilence() {
    _captureOut.add(Uint8List(_silenceBytes));
  }

  IMMDevice? _device(
    IMMDeviceEnumerator enumerator,
    String? id,
    EDataFlow flow,
    Arena arena,
  ) {
    if (id != null && id.isNotEmpty) {
      try {
        final found = enumerator.getDevice(
          PCWSTR(id.toNativeUtf16(allocator: arena)),
        );
        if (found != null) {
          return arena.adopt(found);
        }
      } on Object {
        // Fall back to the default communications Endpoint.
      }
    }
    try {
      final fallback = enumerator.getDefaultAudioEndpoint(
        flow,
        eCommunications,
      );
      return fallback == null ? null : arena.adopt(fallback);
    } on Object {
      return null;
    }
  }

  List<Endpoint> _collect(
    IMMDeviceEnumerator enumerator,
    EDataFlow flow, {
    required bool capture,
  }) {
    final items = <Endpoint>[];
    using((arena) {
      final collection = enumerator.enumAudioEndpoints(
        flow,
        DEVICE_STATE_ACTIVE,
      );
      if (collection == null) {
        return;
      }
      arena.adopt(collection);
      final friendly = arena<PROPERTYKEY>()..ref = PKEY_Device_FriendlyName;
      final enumeratorKey = arena<PROPERTYKEY>()
        ..ref = PKEY_Device_EnumeratorName;
      final containerKey = arena<PROPERTYKEY>()..ref = PKEY_Device_ContainerId;
      final count = collection.getCount();
      for (var i = 0; i < count; i++) {
        final device = collection.item(i);
        if (device == null) {
          continue;
        }
        arena.adopt(device);
        final idPtr = device.getId();
        final id = idPtr.toDartString();
        free(idPtr);
        var name = id;
        var enumeratorName = '';
        var containerId = '';
        try {
          final store = device.openPropertyStore(STGM_READ);
          if (store != null) {
            arena.adopt(store);
            name = _stringProp(store, friendly) ?? name;
            enumeratorName = _stringProp(store, enumeratorKey) ?? '';
            containerId = _guidProp(store, containerKey) ?? '';
          }
        } on Object {
          // Name and pair fall back to the Endpoint id.
        }
        final route = windowsRouteClass(name: name, enumerator: enumeratorName);
        items.add(
          Endpoint(
            id: id,
            name: name,
            routeClass: route,
            isCapture: capture,
            pairId: windowsPairId(
              routeClass: route,
              id: id,
              name: name,
              containerId: containerId,
            ),
          ),
        );
      }
    });
    return items;
  }

  String? _stringProp(IPropertyStore store, Pointer<PROPERTYKEY> key) {
    try {
      final value = PropVariant.fromPointer(store.getValue(key));
      if (value.vt == VT_LPWSTR || value.vt == VT_BSTR) {
        final text = value.pwszVal.toDartString();
        value.free();
        return text;
      }
      value.free();
    } on Object {
      return null;
    }
    return null;
  }

  String? _guidProp(IPropertyStore store, Pointer<PROPERTYKEY> key) {
    try {
      final value = PropVariant.fromPointer(store.getValue(key));
      if (value.vt == VT_CLSID && value.puuid != nullptr) {
        final text = value.puuid.toString();
        value.free();
        return text;
      }
      value.free();
    } on Object {
      return null;
    }
    return null;
  }
}
