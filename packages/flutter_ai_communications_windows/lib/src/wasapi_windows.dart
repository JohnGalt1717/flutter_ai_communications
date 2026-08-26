import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';
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
    // Flutter's runner already initialized STA. RPC_E_CHANGED_MODE is fine.
    final hr = CoInitializeEx(COINIT_APARTMENTTHREADED);
    _comInitialized = hr.isOk;
    try {
      _enumerator = _lifetime.com<IMMDeviceEnumerator>(_mmDeviceEnumerator);
    } on Object catch (error, stack) {
      _log.warning('WASAPI enumerator create failed', error, stack);
      _enumerator = null;
    }
  }

  static final _log = Logger('WasapiWindows');

  var _comInitialized = false;
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
  String? _boundCaptureId;
  String? _boundRenderId;
  NativeFormatReport _nativeFormats = const NativeFormatReport();

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
      final capture = enumerate()
          .where((endpoint) => endpoint.isCapture)
          .firstOrNull;
      if (capture == null) {
        return MicrophonePermission.denied;
      }
      // Capture-only: a render bind failure must not look like mic denial.
      final started = start(captureId: capture.id);
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
    _captureId = _presentId(captureId);
    _renderId = _presentId(renderId);
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
      _captureId = _presentId(captureId);
    }
    if (renderId != null) {
      _renderId = _presentId(renderId);
    }
    if (_running) {
      _startGraph();
    }
  }

  @override
  PairingSnapshot get observed =>
      PairingSnapshot(captureId: _boundCaptureId, renderId: _boundRenderId);

  @override
  NativeFormatReport get nativeFormats => _nativeFormats;

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
    if (_comInitialized) {
      CoUninitialize();
      _comInitialized = false;
    }
  }

  String? _presentId(String? id) => id == null || id.isEmpty ? null : id;

  bool get _wantCapture => _captureId != null || _renderId == null;

  bool get _wantRender => _renderId != null || _captureId == null;

  bool _startGraph() {
    if (_wantCapture) {
      _emitSilence();
    }
    _stopGraph();
    final enumerator = _enumerator;
    if (enumerator == null) {
      return false;
    }
    final graph = Arena();
    try {
      String? boundCapture;
      String? boundRender;
      AudioFormat? captureFormat;
      AudioFormat? renderFormat;
      if (_wantCapture) {
        final opened = _openDevice(
          enumerator,
          _captureId,
          eCapture,
          graph,
          fallback: _captureId == null || _captureId!.isEmpty,
        );
        final device = opened.device;
        if (device == null) {
          return _abortGraph(graph);
        }
        final bound = _bindClient(device, graph);
        if (bound == null) {
          return _abortGraph(graph);
        }
        _captureClient = bound.client;
        _capture = graph.adopt(bound.client.getService<IAudioCaptureClient>());
        boundCapture = opened.id;
        captureFormat = AudioFormat.pcm16le(sampleRate: bound.rate);
      }
      if (_wantRender) {
        final opened = _openDevice(
          enumerator,
          _renderId,
          eRender,
          graph,
          fallback: _renderId == null || _renderId!.isEmpty,
        );
        final device = opened.device;
        if (device == null) {
          return _abortGraph(graph);
        }
        final bound = _bindClient(device, graph);
        if (bound == null) {
          return _abortGraph(graph);
        }
        _renderClient = bound.client;
        _render = graph.adopt(bound.client.getService<IAudioRenderClient>());
        _renderFrames = bound.client.getBufferSize();
        boundRender = opened.id;
        renderFormat = AudioFormat.pcm16le(sampleRate: bound.rate);
      }
      final keepPaused = _paused;
      if (!keepPaused) {
        _captureClient?.start();
        _renderClient?.start();
      }
      if (_wantCapture) {
        _poll = Timer.periodic(const Duration(milliseconds: 10), (_) {
          _pumpCapture();
        });
      }
      _graph = graph;
      _running = true;
      _paused = keepPaused;
      _boundCaptureId = boundCapture;
      _boundRenderId = boundRender;
      _nativeFormats = NativeFormatReport(
        capture: captureFormat,
        playback: renderFormat,
      );
      return true;
    } on Object catch (error, stack) {
      _log.warning('WASAPI graph start failed', error, stack);
      return _abortGraph(graph);
    }
  }

  bool _abortGraph(Arena graph) {
    _graph = graph;
    _stopGraph();
    return false;
  }

  IAudioClient _activateClient(IMMDevice device, Arena graph) {
    try {
      final client = graph.adopt(
        device.activate<IAudioClient2>(CLSCTX_ALL, null),
      );
      final properties = graph<AudioClientProperties>();
      properties.ref
        ..cbSize = sizeOf<AudioClientProperties>()
        ..bIsOffload = false
        ..eCategory = AudioCategory_Communications;
      try {
        client.setClientProperties(properties);
      } on Object {
        // Communications category is best-effort.
      }
      return client;
    } on Object {
      return graph.adopt(device.activate<IAudioClient>(CLSCTX_ALL, null));
    }
  }

  ({IAudioClient client, int rate})? _bindClient(
    IMMDevice device,
    Arena graph,
  ) {
    const rates = [_sampleRate, 48000, 16000];
    final flags = _autoConvertPcm | _srcDefaultQuality;
    for (final rate in rates) {
      try {
        final client = _activateClient(device, graph);
        final format = graph<WAVEFORMATEX>();
        format.ref
          ..wFormatTag = WAVE_FORMAT_PCM
          ..nChannels = 1
          ..nSamplesPerSec = rate
          ..wBitsPerSample = 16
          ..nBlockAlign = 2
          ..nAvgBytesPerSec = rate * 2
          ..cbSize = 0;
        client.initialize(
          AUDCLNT_SHAREMODE_SHARED,
          flags,
          _refTimes20ms,
          0,
          format,
          null,
        );
        return (client: client, rate: rate);
      } on Object {
        continue;
      }
    }
    return null;
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
    _boundCaptureId = null;
    _boundRenderId = null;
    _nativeFormats = const NativeFormatReport();
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

  ({IMMDevice? device, String? id}) _openDevice(
    IMMDeviceEnumerator enumerator,
    String? id,
    EDataFlow flow,
    Arena arena, {
    required bool fallback,
  }) {
    if (id != null && id.isNotEmpty) {
      try {
        final found = enumerator.getDevice(
          PCWSTR(id.toNativeUtf16(allocator: arena)),
        );
        if (found != null) {
          final adopted = arena.adopt(found);
          return (device: adopted, id: _openedId(adopted, requested: id));
        }
      } on Object {
        if (!fallback) {
          return (device: null, id: null);
        }
      }
      if (!fallback) {
        return (device: null, id: null);
      }
    }
    try {
      final fallback = enumerator.getDefaultAudioEndpoint(
        flow,
        eCommunications,
      );
      if (fallback == null) {
        return (device: null, id: null);
      }
      final adopted = arena.adopt(fallback);
      return (device: adopted, id: _openedId(adopted));
    } on Object {
      return (device: null, id: null);
    }
  }

  String? _openedId(IMMDevice device, {String? requested}) {
    try {
      final idPtr = device.getId();
      final openedId = idPtr.toDartString();
      CoTaskMemFree(idPtr);
      if (openedId.isNotEmpty) {
        return openedId;
      }
    } on Object {
      // Fall back to the requested id only when the Endpoint actually opened.
    }
    return requested;
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
        CoTaskMemFree(idPtr);
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

  String _guidText(GUID guid) {
    final bytes = List<int>.generate(8, (i) => guid.Data4[i]);
    String hex(int value, int width) =>
        value.toRadixString(16).padLeft(width, '0');
    return '{${hex(guid.Data1, 8)}-${hex(guid.Data2, 4)}-${hex(guid.Data3, 4)}-'
        '${hex(bytes[0], 2)}${hex(bytes[1], 2)}-'
        '${bytes.sublist(2).map((b) => hex(b, 2)).join()}}';
  }

  String? _guidProp(IPropertyStore store, Pointer<PROPERTYKEY> key) {
    try {
      final value = PropVariant.fromPointer(store.getValue(key));
      if (value.vt == VT_CLSID && value.puuid != nullptr) {
        final text = _guidText(value.puuid.ref);
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
