import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Encodes a four-character Core Audio code.
int fourCC(String value) =>
    (value.codeUnitAt(0) << 24) |
    (value.codeUnitAt(1) << 16) |
    (value.codeUnitAt(2) << 8) |
    value.codeUnitAt(3);

/// System object.
const audioObjectSystemObject = 1;

/// Success.
const noErr = 0;

/// UTF-8 for [CFStringGetCString].
const kCFStringEncodingUTF8 = 0x08000100;

/// Property address.
final class AudioObjectPropertyAddress extends Struct {
  @Uint32()
  external int selector;

  @Uint32()
  external int scope;

  @Uint32()
  external int element;
}

/// Linear PCM description.
final class AudioStreamBasicDescription extends Struct {
  @Double()
  external double sampleRate;

  @Uint32()
  external int formatId;

  @Uint32()
  external int formatFlags;

  @Uint32()
  external int bytesPerPacket;

  @Uint32()
  external int framesPerPacket;

  @Uint32()
  external int bytesPerFrame;

  @Uint32()
  external int channelsPerFrame;

  @Uint32()
  external int bitsPerChannel;

  @Uint32()
  external int reserved;
}

/// AudioQueue buffer.
final class AudioQueueBuffer extends Struct {
  @Uint32()
  external int audioDataBytesCapacity;

  external Pointer<Void> audioData;

  @Uint32()
  external int audioDataByteSize;

  external Pointer<Void> userData;

  @Uint32()
  external int packetDescriptionCapacity;

  external Pointer<Void> packetDescriptions;

  @Uint32()
  external int numPacketDescriptions;
}

/// Opaque AudioQueue.
typedef AudioQueueRef = Pointer<Void>;

/// AudioQueue buffer pointer.
typedef AudioQueueBufferRef = Pointer<AudioQueueBuffer>;

/// Input callback native type.
typedef AudioQueueInputNative =
    Void Function(
      Pointer<Void>,
      AudioQueueRef,
      AudioQueueBufferRef,
      Pointer<Void>,
      Uint32,
      Pointer<Void>,
    );

/// Output callback native type.
typedef AudioQueueOutputNative =
    Void Function(Pointer<Void>, AudioQueueRef, AudioQueueBufferRef);

/// Core Audio / AudioToolbox bindings.
final class CoreAudio {
  /// Opens the process libraries.
  CoreAudio() : this._(DynamicLibrary.process());

  CoreAudio._(DynamicLibrary lib)
    : getPropertyDataSize = lib
          .lookupFunction<
            Int32 Function(
              Uint32,
              Pointer<AudioObjectPropertyAddress>,
              Uint32,
              Pointer<Void>,
              Pointer<Uint32>,
            ),
            int Function(
              int,
              Pointer<AudioObjectPropertyAddress>,
              int,
              Pointer<Void>,
              Pointer<Uint32>,
            )
          >('AudioObjectGetPropertyDataSize'),
      getPropertyData = lib
          .lookupFunction<
            Int32 Function(
              Uint32,
              Pointer<AudioObjectPropertyAddress>,
              Uint32,
              Pointer<Void>,
              Pointer<Uint32>,
              Pointer<Void>,
            ),
            int Function(
              int,
              Pointer<AudioObjectPropertyAddress>,
              int,
              Pointer<Void>,
              Pointer<Uint32>,
              Pointer<Void>,
            )
          >('AudioObjectGetPropertyData'),
      runLoopMain = lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'CFRunLoopGetMain',
          ),
      commonModes = lib.lookup<Pointer<Void>>('kCFRunLoopCommonModes').value,
      queueNewInput = lib
          .lookupFunction<
            Int32 Function(
              Pointer<AudioStreamBasicDescription>,
              Pointer<NativeFunction<AudioQueueInputNative>>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<AudioQueueRef>,
            ),
            int Function(
              Pointer<AudioStreamBasicDescription>,
              Pointer<NativeFunction<AudioQueueInputNative>>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<AudioQueueRef>,
            )
          >('AudioQueueNewInput'),
      queueNewOutput = lib
          .lookupFunction<
            Int32 Function(
              Pointer<AudioStreamBasicDescription>,
              Pointer<NativeFunction<AudioQueueOutputNative>>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<AudioQueueRef>,
            ),
            int Function(
              Pointer<AudioStreamBasicDescription>,
              Pointer<NativeFunction<AudioQueueOutputNative>>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<AudioQueueRef>,
            )
          >('AudioQueueNewOutput'),
      queueAllocateBuffer = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef, Uint32, Pointer<AudioQueueBufferRef>),
            int Function(AudioQueueRef, int, Pointer<AudioQueueBufferRef>)
          >('AudioQueueAllocateBuffer'),
      queueEnqueueBuffer = lib
          .lookupFunction<
            Int32 Function(
              AudioQueueRef,
              AudioQueueBufferRef,
              Uint32,
              Pointer<Void>,
            ),
            int Function(AudioQueueRef, AudioQueueBufferRef, int, Pointer<Void>)
          >('AudioQueueEnqueueBuffer'),
      queueStart = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef, Pointer<Void>),
            int Function(AudioQueueRef, Pointer<Void>)
          >('AudioQueueStart'),
      queueStop = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef, Uint8),
            int Function(AudioQueueRef, int)
          >('AudioQueueStop'),
      queuePause = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef),
            int Function(AudioQueueRef)
          >('AudioQueuePause'),
      queueFlush = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef),
            int Function(AudioQueueRef)
          >('AudioQueueFlush'),
      queueReset = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef),
            int Function(AudioQueueRef)
          >('AudioQueueReset'),
      queueDispose = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef, Uint8),
            int Function(AudioQueueRef, int)
          >('AudioQueueDispose'),
      queueSetProperty = lib
          .lookupFunction<
            Int32 Function(AudioQueueRef, Uint32, Pointer<Void>, Uint32),
            int Function(AudioQueueRef, int, Pointer<Void>, int)
          >('AudioQueueSetProperty');

  /// Main CFRunLoop for AudioQueue callbacks.
  final Pointer<Void> Function() runLoopMain;

  /// `kCFRunLoopCommonModes`.
  final Pointer<Void> commonModes;

  /// Property data size.
  final int Function(
    int,
    Pointer<AudioObjectPropertyAddress>,
    int,
    Pointer<Void>,
    Pointer<Uint32>,
  )
  getPropertyDataSize;

  /// Property data.
  final int Function(
    int,
    Pointer<AudioObjectPropertyAddress>,
    int,
    Pointer<Void>,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  getPropertyData;

  /// Creates a capture queue.
  final int Function(
    Pointer<AudioStreamBasicDescription>,
    Pointer<NativeFunction<AudioQueueInputNative>>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<AudioQueueRef>,
  )
  queueNewInput;

  /// Creates a render queue.
  final int Function(
    Pointer<AudioStreamBasicDescription>,
    Pointer<NativeFunction<AudioQueueOutputNative>>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<AudioQueueRef>,
  )
  queueNewOutput;

  /// Allocates a queue buffer.
  final int Function(AudioQueueRef, int, Pointer<AudioQueueBufferRef>)
  queueAllocateBuffer;

  /// Enqueues a queue buffer.
  final int Function(AudioQueueRef, AudioQueueBufferRef, int, Pointer<Void>)
  queueEnqueueBuffer;

  /// Starts a queue.
  final int Function(AudioQueueRef, Pointer<Void>) queueStart;

  /// Stops a queue.
  final int Function(AudioQueueRef, int) queueStop;

  /// Pauses a queue.
  final int Function(AudioQueueRef) queuePause;

  /// Flushes a queue.
  final int Function(AudioQueueRef) queueFlush;

  /// Resets a queue.
  final int Function(AudioQueueRef) queueReset;

  /// Disposes a queue.
  final int Function(AudioQueueRef, int) queueDispose;

  /// Sets a queue property.
  final int Function(AudioQueueRef, int, Pointer<Void>, int) queueSetProperty;

  /// Fills a PCM16 LE mono 24 kHz description.
  void writePcm16(Pointer<AudioStreamBasicDescription> format) {
    format.ref
      ..sampleRate = 24000
      ..formatId = fourCC('lpcm')
      ..formatFlags = 4 | 8
      ..bytesPerPacket = 2
      ..framesPerPacket = 1
      ..bytesPerFrame = 2
      ..channelsPerFrame = 1
      ..bitsPerChannel = 16
      ..reserved = 0;
  }

  /// Reads a CFString property as UTF-8.
  String? stringProperty(int object, int selector) {
    final address = calloc<AudioObjectPropertyAddress>();
    address.ref
      ..selector = selector
      ..scope = fourCC('glob')
      ..element = 0;
    final size = calloc<Uint32>()..value = sizeOf<Pointer>();
    final value = calloc<Pointer<Void>>();
    final status = getPropertyData(
      object,
      address,
      0,
      nullptr,
      size,
      value.cast(),
    );
    calloc.free(address);
    calloc.free(size);
    if (status != noErr || value.value == nullptr) {
      calloc.free(value);
      return null;
    }
    final text = _cfStringToDart(value.value);
    calloc.free(value);
    return text;
  }

  /// Reads a UInt32 property.
  int? uint32Property(int object, int selector, {int? scope}) {
    final address = calloc<AudioObjectPropertyAddress>();
    address.ref
      ..selector = selector
      ..scope = scope ?? fourCC('glob')
      ..element = 0;
    final size = calloc<Uint32>()..value = 4;
    final value = calloc<Uint32>();
    final status = getPropertyData(
      object,
      address,
      0,
      nullptr,
      size,
      value.cast(),
    );
    final result = status == noErr ? value.value : null;
    calloc.free(address);
    calloc.free(size);
    calloc.free(value);
    return result;
  }

  /// Bytes for a property.
  int? propertySize(int object, int selector, {int? scope}) {
    final address = calloc<AudioObjectPropertyAddress>();
    address.ref
      ..selector = selector
      ..scope = scope ?? fourCC('glob')
      ..element = 0;
    final size = calloc<Uint32>();
    final status = getPropertyDataSize(object, address, 0, nullptr, size);
    final result = status == noErr ? size.value : null;
    calloc.free(address);
    calloc.free(size);
    return result;
  }

  /// Reads a UInt32 array property.
  List<int> uint32Array(int object, int selector, {int? scope}) {
    final bytes = propertySize(object, selector, scope: scope);
    if (bytes == null || bytes == 0) {
      return const [];
    }
    final address = calloc<AudioObjectPropertyAddress>();
    address.ref
      ..selector = selector
      ..scope = scope ?? fourCC('glob')
      ..element = 0;
    final size = calloc<Uint32>()..value = bytes;
    final values = calloc<Uint32>(bytes ~/ 4);
    final status = getPropertyData(
      object,
      address,
      0,
      nullptr,
      size,
      values.cast(),
    );
    final items = <int>[];
    if (status == noErr) {
      final count = size.value ~/ 4;
      for (var i = 0; i < count; i++) {
        items.add(values[i]);
      }
    }
    calloc.free(address);
    calloc.free(size);
    calloc.free(values);
    return items;
  }

  String? _cfStringToDart(Pointer<Void> cfString) {
    final lib = DynamicLibrary.process();
    final getLength = lib
        .lookupFunction<
          Int64 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFStringGetLength');
    final getCString = lib
        .lookupFunction<
          Uint8 Function(Pointer<Void>, Pointer<Char>, Int64, Uint32),
          int Function(Pointer<Void>, Pointer<Char>, int, int)
        >('CFStringGetCString');
    final release = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease');
    final length = getLength(cfString);
    if (length <= 0) {
      release(cfString);
      return null;
    }
    final buffer = calloc<Char>(length * 4 + 1);
    final ok = getCString(
      cfString,
      buffer,
      length * 4 + 1,
      kCFStringEncodingUTF8,
    );
    final text = ok != 0 ? buffer.cast<Utf8>().toDartString() : null;
    calloc.free(buffer);
    release(cfString);
    return text;
  }
}
