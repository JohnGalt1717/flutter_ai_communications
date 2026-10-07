import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _speexEchoSetSamplingRate = 24;
const _speexPreprocessSetDenoise = 0;
const _speexPreprocessSetAgc = 2;
const _speexPreprocessSetNoiseSuppress = 18;
const _speexPreprocessSetEchoSuppress = 20;
const _speexPreprocessSetEchoSuppressActive = 22;
const _speexPreprocessSetEchoState = 24;

/// Speex AEC / NS / AGC on PCM16 LE mono Native Format frames.
final class SpeexAec {
  SpeexAec._({
    required this._echo,
    required this._pre,
    required this._frameSamples,
    required this._maxPlayBytes,
    required this._rec,
    required this._play,
    required this._out,
    required this._ctl,
    required this._echoPlayback,
    required this._echoCapture,
    required this._echoReset,
    required this._preRun,
    required this._echoDestroy,
    required this._preDestroy,
  });

  final Pointer<Void> _echo;
  final Pointer<Void> _pre;
  final int _frameSamples;
  final int _maxPlayBytes;
  final Pointer<Int16> _rec;
  final Pointer<Int16> _play;
  final Pointer<Int16> _out;
  final Pointer<Int32> _ctl;
  final _SpeexEchoPlayback _echoPlayback;
  final _SpeexEchoCapture _echoCapture;
  final _SpeexEchoReset _echoReset;
  final _SpeexPreprocessRun _preRun;
  final _SpeexEchoDestroy _echoDestroy;
  final _SpeexPreprocessDestroy _preDestroy;
  final BytesBuilder _playAcc = BytesBuilder();
  var _closed = false;

  /// Native Format frame: 10 ms at 24 kHz mono PCM16.
  static const frameSamples = 240;

  /// Bytes in one [frameSamples] frame.
  static const frameBytes = frameSamples * 2;

  /// Native Format rate.
  static const sampleRate = 24000;

  /// Filter covers ~200 ms of air + device delay.
  static const filterSamples = 4800;

  /// True when `libspeexdsp.so.1` loads.
  static bool get available {
    try {
      DynamicLibrary.open('libspeexdsp.so.1');
      return true;
    } on Object {
      return false;
    }
  }

  /// Opens Speex echo + preprocess, or null when the library is missing.
  static SpeexAec? tryStart({
    int frameSamples = SpeexAec.frameSamples,
    int sampleRate = SpeexAec.sampleRate,
    int filterSamples = SpeexAec.filterSamples,
  }) {
    if (frameSamples <= 0 ||
        sampleRate <= 0 ||
        filterSamples < frameSamples ||
        filterSamples % frameSamples != 0) {
      return null;
    }
    late final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open('libspeexdsp.so.1');
    } on Object {
      return null;
    }
    final echoInit = lib.lookupFunction<_SpeexEchoInitNative, _SpeexEchoInit>(
      'speex_echo_state_init',
    );
    final echoDestroy = lib
        .lookupFunction<_SpeexEchoDestroyNative, _SpeexEchoDestroy>(
          'speex_echo_state_destroy',
        );
    final echoPlayback = lib
        .lookupFunction<_SpeexEchoPlaybackNative, _SpeexEchoPlayback>(
          'speex_echo_playback',
        );
    final echoCapture = lib
        .lookupFunction<_SpeexEchoCaptureNative, _SpeexEchoCapture>(
          'speex_echo_capture',
        );
    final echoReset = lib
        .lookupFunction<_SpeexEchoResetNative, _SpeexEchoReset>(
          'speex_echo_state_reset',
        );
    final echoCtl = lib.lookupFunction<_SpeexEchoCtlNative, _SpeexEchoCtl>(
      'speex_echo_ctl',
    );
    final preInit = lib
        .lookupFunction<_SpeexPreprocessInitNative, _SpeexPreprocessInit>(
          'speex_preprocess_state_init',
        );
    final preDestroy = lib
        .lookupFunction<_SpeexPreprocessDestroyNative, _SpeexPreprocessDestroy>(
          'speex_preprocess_state_destroy',
        );
    final preRun = lib
        .lookupFunction<_SpeexPreprocessRunNative, _SpeexPreprocessRun>(
          'speex_preprocess_run',
        );
    final preCtl = lib
        .lookupFunction<_SpeexPreprocessCtlNative, _SpeexPreprocessCtl>(
          'speex_preprocess_ctl',
        );
    final echo = echoInit(frameSamples, filterSamples);
    if (echo == nullptr) {
      return null;
    }
    final pre = preInit(frameSamples, sampleRate);
    if (pre == nullptr) {
      echoDestroy(echo);
      return null;
    }
    final rec = calloc<Int16>(frameSamples);
    final play = calloc<Int16>(frameSamples);
    final out = calloc<Int16>(frameSamples);
    final ctl = calloc<Int32>();
    ctl.value = sampleRate;
    echoCtl(echo, _speexEchoSetSamplingRate, ctl.cast());
    ctl.value = 1;
    preCtl(pre, _speexPreprocessSetDenoise, ctl.cast());
    ctl.value = 1;
    preCtl(pre, _speexPreprocessSetAgc, ctl.cast());
    ctl.value = -25;
    preCtl(pre, _speexPreprocessSetNoiseSuppress, ctl.cast());
    ctl.value = -40;
    preCtl(pre, _speexPreprocessSetEchoSuppress, ctl.cast());
    ctl.value = -15;
    preCtl(pre, _speexPreprocessSetEchoSuppressActive, ctl.cast());
    preCtl(pre, _speexPreprocessSetEchoState, echo.cast());
    return SpeexAec._(
      echo: echo,
      pre: pre,
      frameSamples: frameSamples,
      maxPlayBytes: sampleRate * 2 * 5,
      rec: rec,
      play: play,
      out: out,
      ctl: ctl,
      echoPlayback: echoPlayback,
      echoCapture: echoCapture,
      echoReset: echoReset,
      preRun: preRun,
      echoDestroy: echoDestroy,
      preDestroy: preDestroy,
    );
  }

  /// Feeds far-end PCM16 LE that was written to render.
  ///
  /// Chunks longer than one Native Format frame stay queued. `process`
  /// submits one reference frame per capture call so Speex's reverse
  /// buffer does not overflow.
  void playback(Uint8List bytes) {
    if (_closed || bytes.isEmpty) {
      return;
    }
    _playAcc.add(bytes);
    final acc = _playAcc.takeBytes();
    if (acc.length <= _maxPlayBytes) {
      _playAcc.add(acc);
      return;
    }
    _playAcc.add(Uint8List.sublistView(acc, acc.length - _maxPlayBytes));
  }

  /// Drops queued reverse PCM and resets Speex echo state (barge-in flush).
  void flush() {
    if (_closed) {
      return;
    }
    _playAcc.clear();
    _echoReset(_echo);
  }

  void _feedPlaybackFrame() {
    final frameBytes = _frameSamples * 2;
    final acc = _playAcc.takeBytes();
    if (acc.length < frameBytes) {
      if (acc.isNotEmpty) {
        _playAcc.add(acc);
      }
      return;
    }
    _copyBytes(acc, 0, _play, frameBytes);
    _echoPlayback(_echo, _play);
    if (acc.length > frameBytes) {
      _playAcc.add(Uint8List.sublistView(acc, frameBytes));
    }
  }

  /// Near-end PCM16 LE in, AEC/NS/AGC out. Pass-through if length mismatches.
  Uint8List process(Uint8List rec) {
    final frameBytes = _frameSamples * 2;
    if (_closed || rec.length != frameBytes) {
      return rec;
    }
    _feedPlaybackFrame();
    _copyBytes(rec, 0, _rec, frameBytes);
    _echoCapture(_echo, _rec, _out);
    _preRun(_pre, _out);
    return Uint8List.fromList(_out.cast<Uint8>().asTypedList(frameBytes));
  }

  /// Releases Speex state.
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _preDestroy(_pre);
    _echoDestroy(_echo);
    calloc.free(_rec);
    calloc.free(_play);
    calloc.free(_out);
    calloc.free(_ctl);
  }
}

void _copyBytes(Uint8List src, int offset, Pointer<Int16> dest, int bytes) {
  dest.cast<Uint8>().asTypedList(bytes).setRange(0, bytes, src, offset);
}

typedef _SpeexEchoInitNative = Pointer<Void> Function(Int32, Int32);
typedef _SpeexEchoInit = Pointer<Void> Function(int, int);
typedef _SpeexEchoDestroyNative = Void Function(Pointer<Void>);
typedef _SpeexEchoDestroy = void Function(Pointer<Void>);
typedef _SpeexEchoPlaybackNative = Void Function(Pointer<Void>, Pointer<Int16>);
typedef _SpeexEchoPlayback = void Function(Pointer<Void>, Pointer<Int16>);
typedef _SpeexEchoCaptureNative =
    Void Function(Pointer<Void>, Pointer<Int16>, Pointer<Int16>);
typedef _SpeexEchoCapture =
    void Function(Pointer<Void>, Pointer<Int16>, Pointer<Int16>);
typedef _SpeexEchoResetNative = Void Function(Pointer<Void>);
typedef _SpeexEchoReset = void Function(Pointer<Void>);
typedef _SpeexEchoCtlNative =
    Int32 Function(Pointer<Void>, Int32, Pointer<Void>);
typedef _SpeexEchoCtl = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _SpeexPreprocessInitNative = Pointer<Void> Function(Int32, Int32);
typedef _SpeexPreprocessInit = Pointer<Void> Function(int, int);
typedef _SpeexPreprocessDestroyNative = Void Function(Pointer<Void>);
typedef _SpeexPreprocessDestroy = void Function(Pointer<Void>);
typedef _SpeexPreprocessRunNative =
    Int32 Function(Pointer<Void>, Pointer<Int16>);
typedef _SpeexPreprocessRun = int Function(Pointer<Void>, Pointer<Int16>);
typedef _SpeexPreprocessCtlNative =
    Int32 Function(Pointer<Void>, Int32, Pointer<Void>);
typedef _SpeexPreprocessCtl = int Function(Pointer<Void>, int, Pointer<Void>);
