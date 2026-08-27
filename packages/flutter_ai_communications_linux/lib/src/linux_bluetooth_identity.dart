import 'dart:io';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:logging/logging.dart';

/// Cached Bluetooth identities. Denial or failure yields an empty list.
abstract class BluetoothIdentitySource {
  /// Last identities. Empty when denied or unavailable.
  List<BluetoothIdentity> current();

  /// Enumerate BlueZ remembered/connected devices. No extra OS prompt.
  Future<void> prepare();
}

/// No Bluetooth data. Pulse names only.
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
  if (Platform.isLinux) {
    return BlueZBluetoothIdentitySource();
  }
  return const EmptyBluetoothIdentitySource();
}

/// Maps a Bluetooth Class of Device to a form factor.
EndpointFormFactor linuxFormFactorFromClassOfDevice(int classOfDevice) =>
    formFactorFromBluetoothClassOfDevice(classOfDevice);

/// Brand token from a Bluetooth SIG company identifier.
String? manufacturerHintFromCompanyId(int companyId) => switch (companyId) {
  0x004C => 'Apple',
  0x012D => 'Sony',
  0x00E0 => 'Google',
  0x0075 => 'Samsung',
  0x005A => 'JBL',
  0x0026 => 'Jabra',
  0x0094 => 'Sennheiser',
  _ => null,
};

/// Parses `busctl get-property` string values (`s "Alias"`).
String parseBusctlString(String raw) {
  final trimmed = raw.trim();
  final match = RegExp(r'^s\s+"(.*)"\s*$', dotAll: true).firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!.replaceAll(r'\"', '"');
  }
  if (trimmed == 's ""' || trimmed == 's') {
    return '';
  }
  return '';
}

/// Parses `busctl get-property` uint32 values (`u 1056`).
int parseBusctlUint(String raw) {
  final match = RegExp(r'^u\s+(0x[0-9a-fA-F]+|\d+)').firstMatch(raw.trim());
  if (match == null) {
    return 0;
  }
  final token = match.group(1)!;
  return token.startsWith('0x') || token.startsWith('0X')
      ? int.parse(token.substring(2), radix: 16)
      : int.parse(token);
}

/// Company identifiers from BlueZ `ManufacturerData` GVariant text.
List<int> parseBluezManufacturerCompanyIds(String raw) {
  final ids = <int>[];
  for (final match in RegExp(r'(\d+)\s*<').allMatches(raw)) {
    ids.add(int.parse(match.group(1)!));
  }
  return ids;
}

/// BlueZ remembered/connected devices via `busctl`. No radio inquiry.
final class BlueZBluetoothIdentitySource implements BluetoothIdentitySource {
  /// Creates a source.
  BlueZBluetoothIdentitySource({
    Future<List<BluetoothIdentity>> Function()? enumerate,
  }) : _enumerate = enumerate ?? enumerateBluezDevices;

  final Future<List<BluetoothIdentity>> Function() _enumerate;

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
    try {
      _cache = await _enumerate();
    } on Object catch (error, stack) {
      _log.fine('BlueZ identity enumerate failed', error, stack);
      _cache = const [];
    }
  }

  static final _log = Logger('LinuxBluetoothIdentity');
}

/// Remembered BlueZ devices. Missing bluetoothd yields an empty list.
Future<List<BluetoothIdentity>> enumerateBluezDevices({
  Future<ProcessResult> Function(List<String> args)? runBusctl,
}) async {
  final run =
      runBusctl ??
      (args) => Process.run('busctl', args, stdoutEncoding: systemEncoding);
  final tree = await run(['--system', 'tree', '--list', 'org.bluez']);
  if (tree.exitCode != 0) {
    return const [];
  }
  final paths = tree.stdout
      .toString()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.contains('/dev_'))
      .toList();
  if (paths.isEmpty) {
    return const [];
  }
  final items = <BluetoothIdentity>[];
  for (final path in paths) {
    final identity = await _deviceAt(run, path);
    if (identity != null) {
      items.add(identity);
    }
  }
  return items;
}

Future<BluetoothIdentity?> _deviceAt(
  Future<ProcessResult> Function(List<String> args) run,
  String path,
) async {
  final result = await run([
    '--system',
    'get-property',
    'org.bluez',
    path,
    'org.bluez.Device1',
    'Alias',
    'Name',
    'Address',
    'Class',
    'ManufacturerData',
  ]);
  if (result.exitCode != 0) {
    return null;
  }
  final blocks = result.stdout.toString().split(RegExp(r'\r?\n'));
  var alias = '';
  var name = '';
  var address = '';
  var classOfDevice = 0;
  final hints = <String>[];
  for (final line in blocks) {
    final trimmed = line.trim();
    if (trimmed.startsWith('s ')) {
      final value = parseBusctlString(trimmed);
      if (alias.isEmpty) {
        alias = value;
      } else if (name.isEmpty) {
        name = value;
      } else if (address.isEmpty) {
        address = value;
      }
    } else if (trimmed.startsWith('u ')) {
      classOfDevice = parseBusctlUint(trimmed);
    } else if (trimmed.startsWith('a{qv}')) {
      for (final id in parseBluezManufacturerCompanyIds(trimmed)) {
        final hint = manufacturerHintFromCompanyId(id);
        if (hint != null && !hints.contains(hint)) {
          hints.add(hint);
        }
      }
    }
  }
  final advertised = alias.isNotEmpty ? alias : name;
  if (advertised.isEmpty && address.isEmpty) {
    return null;
  }
  return BluetoothIdentity(
    name: advertised,
    classOfDevice: classOfDevice,
    address: address,
    hints: hints,
  );
}
