import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';
import 'package:win32/win32.dart';

import 'windows_microphone_consent.dart';

/// Cached Bluetooth identities. Denial or failure yields an empty list.
abstract class BluetoothIdentitySource {
  /// Last identities. Empty when denied or unavailable.
  List<BluetoothIdentity> current();

  /// Store consent when packaged; unpackaged enumerates with no prompt.
  Future<void> prepare();
}

/// No Bluetooth data. Best-effort WASAPI names only.
final class EmptyBluetoothIdentitySource implements BluetoothIdentitySource {
  /// Creates an empty source.
  const EmptyBluetoothIdentitySource();

  @override
  List<BluetoothIdentity> current() => const [];

  @override
  Future<void> prepare() async {}
}

/// Creates the Bluetooth identity source for this host.
BluetoothIdentitySource createBluetoothIdentitySource() {
  if (Platform.isWindows) {
    return Win32BluetoothIdentitySource();
  }
  return const EmptyBluetoothIdentitySource();
}

/// Maps a Bluetooth Class of Device to a form factor.
EndpointFormFactor windowsFormFactorFromClassOfDevice(int classOfDevice) =>
    formFactorFromBluetoothClassOfDevice(classOfDevice);

/// Win32 remembered/connected devices. Store consent only when packaged.
final class Win32BluetoothIdentitySource implements BluetoothIdentitySource {
  /// Creates a source.
  Win32BluetoothIdentitySource({
    bool Function()? isPackaged,
    Future<MicrophonePermission?> Function(String name)? requestCapability,
    List<BluetoothIdentity> Function()? enumerate,
  }) : _isPackaged = isPackaged ?? isWindowsPackagedProcess,
       _requestCapability = requestCapability ?? requestPackagedAppCapability,
       _enumerate = enumerate ?? enumerateWindowsBluetoothDevices;

  final bool Function() _isPackaged;
  final Future<MicrophonePermission?> Function(String name) _requestCapability;
  final List<BluetoothIdentity> Function() _enumerate;

  List<BluetoothIdentity> _cache = const [];
  var _prepared = false;

  @override
  List<BluetoothIdentity> current() => _cache;

  @override
  Future<void> prepare() async {
    if (_prepared) {
      return;
    }
    _prepared = true;
    if (_isPackaged()) {
      final access = await _requestCapability('bluetooth');
      if (access != null && access != MicrophonePermission.granted) {
        _cache = const [];
        return;
      }
    }
    try {
      _cache = _enumerate();
    } on Object catch (error, stack) {
      _log.fine('Bluetooth identity enumerate failed', error, stack);
      _cache = const [];
    }
  }

  static final _log = Logger('WindowsBluetoothIdentity');
}

/// Remembered and connected Bluetooth devices. No radio inquiry.
List<BluetoothIdentity> enumerateWindowsBluetoothDevices() {
  return using((arena) {
    final search = arena<BLUETOOTH_DEVICE_SEARCH_PARAMS>();
    search.ref
      ..dwSize = sizeOf<BLUETOOTH_DEVICE_SEARCH_PARAMS>()
      ..fReturnAuthenticated = true
      ..fReturnRemembered = true
      ..fReturnUnknown = false
      ..fReturnConnected = true
      ..fIssueInquiry = false
      ..cTimeoutMultiplier = 0;
    final info = arena<BLUETOOTH_DEVICE_INFO>();
    info.ref.dwSize = sizeOf<BLUETOOTH_DEVICE_INFO>();
    final found = BluetoothFindFirstDevice(search, info);
    final handle = found.value;
    if (handle == nullptr) {
      return const <BluetoothIdentity>[];
    }
    final items = <BluetoothIdentity>[];
    try {
      do {
        final name = info.ref.szName.trim();
        if (name.isNotEmpty) {
          items.add(
            BluetoothIdentity(
              name: name,
              classOfDevice: info.ref.ulClassofDevice,
              address: _addressHex(info.ref.Address),
            ),
          );
        }
        info.ref.dwSize = sizeOf<BLUETOOTH_DEVICE_INFO>();
      } while (BluetoothFindNextDevice(handle, info).value);
    } finally {
      BluetoothFindDeviceClose(handle);
    }
    return items;
  });
}

String _addressHex(BLUETOOTH_ADDRESS address) {
  return address.ullLong.toRadixString(16).padLeft(12, '0');
}
