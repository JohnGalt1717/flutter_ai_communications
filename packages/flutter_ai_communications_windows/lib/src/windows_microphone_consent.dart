import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:win32/win32.dart';

/// Asks Windows for microphone access. Store/MSIX hosts show a consent UI.
abstract class WindowsMicrophoneConsent {
  /// Blocks until the OS answers. Must not start the WASAPI graph.
  Future<MicrophonePermission> request();
}

/// Always allows the WASAPI probe. Used off Windows and in adapter tests.
final class GrantedWindowsMicrophoneConsent
    implements WindowsMicrophoneConsent {
  /// Creates a consent object that never prompts.
  const GrantedWindowsMicrophoneConsent();

  @override
  Future<MicrophonePermission> request() async => MicrophonePermission.granted;
}

/// Creates the consent implementation for this host.
WindowsMicrophoneConsent createWindowsMicrophoneConsent() {
  if (Platform.isWindows) {
    return GatedWindowsMicrophoneConsent(
      isPackaged: isWindowsPackagedProcess,
      packaged: WinrtWindowsMicrophoneConsent(),
    );
  }
  return const GrantedWindowsMicrophoneConsent();
}

/// Store/MSIX consent only. Unpackaged Win32 skips WinRT and uses WASAPI.
final class GatedWindowsMicrophoneConsent implements WindowsMicrophoneConsent {
  /// [packaged] runs only when [isPackaged] is true.
  GatedWindowsMicrophoneConsent({
    required this.isPackaged,
    required this.packaged,
  });

  /// Whether this process has package identity.
  final bool Function() isPackaged;

  /// First-party Store consent UI.
  final WindowsMicrophoneConsent packaged;

  @override
  Future<MicrophonePermission> request() async {
    if (!isPackaged()) {
      return MicrophonePermission.granted;
    }
    return packaged.request();
  }
}

/// `GetCurrentPackageFullName` reports package identity.
bool isWindowsPackagedProcess() {
  return using((arena) {
    final length = arena<Uint32>();
    final err = GetCurrentPackageFullName(length, null);
    return err == ERROR_INSUFFICIENT_BUFFER;
  });
}

/// DeviceAccessStatus.Allowed / DeniedByUser / DeniedBySystem.
MicrophonePermission? permissionFromDeviceAccessStatus(int status) =>
    switch (status) {
      1 => MicrophonePermission.granted,
      2 => MicrophonePermission.denied,
      3 => MicrophonePermission.restricted,
      _ => null,
    };

/// AppCapabilityAccessStatus, including NotDeclaredByApp and UserPromptRequired.
MicrophonePermission? permissionFromAppCapabilityStatus(int status) =>
    switch (status) {
      0 => MicrophonePermission.restricted,
      1 || 2 => MicrophonePermission.denied,
      4 => MicrophonePermission.granted,
      _ => null,
    };

/// Packaged-app consent via AppCapability and DeviceAccessInformation.
final class WinrtWindowsMicrophoneConsent implements WindowsMicrophoneConsent {
  static final _log = Logger('WindowsMicrophoneConsent');

  @override
  Future<MicrophonePermission> request() async {
    _ensureWinrt();
    final deviceStatus = _deviceAccessStatus();
    final fromDevice = permissionFromDeviceAccessStatus(deviceStatus ?? -1);
    if (fromDevice == MicrophonePermission.granted ||
        fromDevice == MicrophonePermission.denied ||
        fromDevice == MicrophonePermission.restricted) {
      return fromDevice!;
    }
    final capability = await requestPackagedAppCapability('microphone');
    if (capability != null) {
      return capability;
    }
    // WinRT missing or the host did not declare microphone: fail closed.
    return MicrophonePermission.denied;
  }
}

void _ensureWinrt() {
  try {
    RoInitialize(RO_INIT_SINGLETHREADED);
  } on WindowsException {
    // Already initialized, including RPC_E_CHANGED_MODE.
  }
}

int? _deviceAccessStatus() {
  IUnknown? factory;
  IUnknown? info;
  try {
    factory = _activationFactory(
      'Windows.Devices.Enumeration.DeviceAccessInformation',
      _iidDeviceAccessInformationStatics,
    );
    if (factory == null) {
      return null;
    }
    info = _createFromDeviceClass(factory, 1);
    if (info == null) {
      return null;
    }
    return using((arena) {
      final status = arena<Int32>();
      final hr = HRESULT(_callOutInt32(info!, 8, status));
      if (hr.isError) {
        return null;
      }
      return status.value;
    });
  } on Object catch (error, stack) {
    _logIfNeeded(error, stack);
    return null;
  } finally {
    info?.release();
    factory?.release();
  }
}

/// Packaged-only AppCapability request. Returns null when WinRT is absent.
Future<MicrophonePermission?> requestPackagedAppCapability(String name) async {
  IUnknown? factory;
  IUnknown? capability;
  IUnknown? operation;
  IUnknown? asyncInfo;
  try {
    factory = _activationFactory(
      'Windows.Security.Authorization.AppCapabilityAccess.AppCapability',
      _iidAppCapabilityStatics,
    );
    if (factory == null) {
      return null;
    }
    final hName = name.toHstring();
    try {
      capability = _createAppCapability(factory, hName);
    } finally {
      WindowsDeleteString(hName);
    }
    if (capability == null) {
      return null;
    }
    final checked = using((arena) {
      final status = arena<Int32>();
      final hr = HRESULT(_callOutInt32(capability!, 9, status));
      if (hr.isError) {
        return null;
      }
      return status.value;
    });
    final fromCheck = permissionFromAppCapabilityStatus(checked ?? -1);
    if (fromCheck != null) {
      return fromCheck;
    }
    operation = _requestAccessAsync(capability);
    if (operation == null) {
      return null;
    }
    asyncInfo = _query(operation, _iidAsyncInfo);
    if (asyncInfo == null) {
      return null;
    }
    final completed = await _waitAsync(asyncInfo);
    if (!completed) {
      return MicrophonePermission.denied;
    }
    final result = using((arena) {
      final status = arena<Int32>();
      final hr = HRESULT(_callOutInt32(operation!, 8, status));
      if (hr.isError) {
        return null;
      }
      return status.value;
    });
    return permissionFromAppCapabilityStatus(result ?? -1) ??
        MicrophonePermission.denied;
  } on Object catch (error, stack) {
    _logIfNeeded(error, stack);
    return MicrophonePermission.denied;
  } finally {
    asyncInfo?.release();
    operation?.release();
    capability?.release();
    factory?.release();
  }
}

Future<bool> _waitAsync(IUnknown asyncInfo) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final status = using((arena) {
      final value = arena<Int32>();
      final hr = HRESULT(_callOutInt32(asyncInfo, 7, value));
      if (hr.isError) {
        return -1;
      }
      return value.value;
    });
    if (status == 1) {
      return true;
    }
    if (status == 2 || status == 3 || status < 0) {
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

IUnknown? _activationFactory(String className, GUID iid) {
  final hClass = className.toHstring();
  final iidPtr = iid.toNative();
  final factory = calloc<Pointer>();
  try {
    final hr = HRESULT(_roGetActivationFactory(hClass, iidPtr, factory));
    if (hr.isError || factory.value == nullptr) {
      return null;
    }
    return IUnknown(factory.value.cast());
  } on Object {
    return null;
  } finally {
    WindowsDeleteString(hClass);
    free(iidPtr);
    free(factory);
  }
}

IUnknown? _query(IUnknown object, GUID iid) {
  final iidPtr = iid.toNative();
  final out = calloc<Pointer>();
  try {
    final vtbl = object.ptr.value;
    final fn =
        Pointer<
              NativeFunction<
                Int32 Function(VTablePointer, Pointer<GUID>, Pointer<Pointer>)
              >
            >.fromAddress(vtbl.value)
            .asFunction<
              int Function(VTablePointer, Pointer<GUID>, Pointer<Pointer>)
            >();
    final hr = HRESULT(fn(object.ptr, iidPtr, out));
    if (hr.isError || out.value == nullptr) {
      return null;
    }
    return IUnknown(out.value.cast());
  } finally {
    free(iidPtr);
    free(out);
  }
}

int _callOutInt32(IUnknown object, int slot, Pointer<Int32> out) {
  final fn =
      Pointer<
            NativeFunction<Int32 Function(VTablePointer, Pointer<Int32>)>
          >.fromAddress((object.ptr.value + slot).value)
          .asFunction<int Function(VTablePointer, Pointer<Int32>)>();
  return fn(object.ptr, out);
}

IUnknown? _createFromDeviceClass(IUnknown factory, int deviceClass) {
  final out = calloc<Pointer>();
  try {
    final fn =
        Pointer<
              NativeFunction<
                Int32 Function(VTablePointer, Int32, Pointer<Pointer>)
              >
            >.fromAddress((factory.ptr.value + 8).value)
            .asFunction<int Function(VTablePointer, int, Pointer<Pointer>)>();
    final hr = HRESULT(fn(factory.ptr, deviceClass, out));
    if (hr.isError || out.value == nullptr) {
      return null;
    }
    return IUnknown(out.value.cast());
  } finally {
    free(out);
  }
}

IUnknown? _createAppCapability(IUnknown factory, HSTRING name) {
  final out = calloc<Pointer>();
  try {
    final fn =
        Pointer<
              NativeFunction<
                Int32 Function(VTablePointer, IntPtr, Pointer<Pointer>)
              >
            >.fromAddress((factory.ptr.value + 8).value)
            .asFunction<int Function(VTablePointer, int, Pointer<Pointer>)>();
    final hr = HRESULT(fn(factory.ptr, name.address, out));
    if (hr.isError || out.value == nullptr) {
      return null;
    }
    return IUnknown(out.value.cast());
  } finally {
    free(out);
  }
}

IUnknown? _requestAccessAsync(IUnknown capability) {
  final out = calloc<Pointer>();
  try {
    final fn =
        Pointer<
              NativeFunction<Int32 Function(VTablePointer, Pointer<Pointer>)>
            >.fromAddress((capability.ptr.value + 8).value)
            .asFunction<int Function(VTablePointer, Pointer<Pointer>)>();
    final hr = HRESULT(fn(capability.ptr, out));
    if (hr.isError || out.value == nullptr) {
      return null;
    }
    return IUnknown(out.value.cast());
  } finally {
    free(out);
  }
}

void _logIfNeeded(Object error, StackTrace stack) {
  WinrtWindowsMicrophoneConsent._log.fine(
    'microphone consent WinRT call failed',
    error,
    stack,
  );
}

final _roGetActivationFactory =
    DynamicLibrary.open('api-ms-win-core-winrt-l1-1-0.dll').lookupFunction<
      Int32 Function(Pointer, Pointer<GUID>, Pointer<Pointer>),
      int Function(Pointer, Pointer<GUID>, Pointer<Pointer>)
    >('RoGetActivationFactory');

final _iidDeviceAccessInformationStatics = GUID.fromComponents(
  0x574bd3d3,
  0x5f30,
  0x45cd,
  Uint8List.fromList(const [0x8a, 0x94, 0x72, 0x4f, 0xe5, 0x97, 0x30, 0x84]),
);

final _iidAppCapabilityStatics = GUID.fromComponents(
  0x7c353e2a,
  0x46ee,
  0x44e5,
  Uint8List.fromList(const [0xaf, 0x3d, 0x6a, 0xd3, 0xfc, 0x49, 0xbd, 0x22]),
);

final _iidAsyncInfo = GUID.fromComponents(
  0x00000036,
  0x0000,
  0x0000,
  Uint8List.fromList(const [0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]),
);
