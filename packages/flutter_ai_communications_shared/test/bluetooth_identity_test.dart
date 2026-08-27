import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  group('Class of Device', () {
    test('hands-free and headphones are headset', () {
      expect(
        formFactorFromBluetoothClassOfDevice(0x408),
        EndpointFormFactor.headset,
      );
      expect(
        formFactorFromBluetoothClassOfDevice(0x418),
        EndpointFormFactor.headset,
      );
    });

    test('loudspeaker is speaker', () {
      expect(
        formFactorFromBluetoothClassOfDevice(0x414),
        EndpointFormFactor.speaker,
      );
    });

    test('car audio is car', () {
      expect(
        formFactorFromBluetoothClassOfDevice(0x420),
        EndpointFormFactor.car,
      );
    });

    test('non-audio majors are unknown', () {
      expect(
        formFactorFromBluetoothClassOfDevice(0x200),
        EndpointFormFactor.unknown,
      );
    });
  });

  group('mergeBluetoothIdentity', () {
    const btAudio = Endpoint(
      id: 'bt-in',
      name: 'BT-Audio',
      routeClass: RouteClass.bluetooth,
      isCapture: true,
      pairId: 'bt',
    );
    const usb = Endpoint(
      id: 'usb-in',
      name: 'USB Headset',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: 'usb',
    );

    test('empty devices leave names unchanged', () {
      expect(mergeBluetoothIdentity([btAudio, usb], const []), [btAudio, usb]);
    });

    test('Tesla Class of Device fills alias and car form factor', () {
      const teslaAudio = Endpoint(
        id: 'bt-in',
        name: 'Headphones (Tesla Model Y)',
        routeClass: RouteClass.bluetooth,
        isCapture: true,
        pairId: 'bt',
      );
      final merged = mergeBluetoothIdentity(
        [teslaAudio, usb],
        const [BluetoothIdentity(name: 'Tesla Model Y', classOfDevice: 0x420)],
      );
      expect(merged[0].identityHints, ['Tesla Model Y']);
      expect(merged[0].capabilities.formFactor, EndpointFormFactor.car);
      expect(merged[1], usb);
    });

    test('denied or unmatched Bluetooth does not rewrite wired Endpoints', () {
      final merged = mergeBluetoothIdentity(
        [usb],
        const [BluetoothIdentity(name: 'Tesla Model Y', classOfDevice: 0x420)],
      );
      expect(merged.single, usb);
    });

    test('address match fills identity when names differ', () {
      const named = Endpoint(
        id: 'bthenum-a1b2c3d4e5f6',
        name: 'Headphones',
        routeClass: RouteClass.bluetooth,
        isCapture: false,
        pairId: 'bt',
      );
      final merged = mergeBluetoothIdentity(
        [named],
        const [
          BluetoothIdentity(
            name: 'Sony WH-1000XM5',
            classOfDevice: 0x418,
            address: 'a1b2c3d4e5f6',
          ),
        ],
      );
      expect(merged.single.identityHints, ['Sony WH-1000XM5']);
      expect(merged.single.capabilities.formFactor, EndpointFormFactor.headset);
    });

    test('Pulse BlueZ ids match addresses that use colons or underscores', () {
      const named = Endpoint(
        id: 'bluez_sink.a1_b2_c3_d4_e5_f6.a2dp_sink',
        name: 'Headphones',
        routeClass: RouteClass.bluetooth,
        isCapture: false,
        pairId: 'bt',
      );
      final merged = mergeBluetoothIdentity(
        [named],
        const [
          BluetoothIdentity(
            name: 'Tesla Model Y',
            classOfDevice: 0x420,
            address: 'A1:B2:C3:D4:E5:F6',
          ),
        ],
      );
      expect(merged.single.identityHints, ['Tesla Model Y']);
      expect(merged.single.capabilities.formFactor, EndpointFormFactor.car);
      expect(merged.single.capabilities.carConnected, isTrue);
    });

    test('manufacturer-data hints join the advertised alias', () {
      const named = Endpoint(
        id: 'bluez_source.a1_b2_c3_d4_e5_f6.headset_head_unit',
        name: 'Headphones',
        routeClass: RouteClass.bluetooth,
        isCapture: true,
        pairId: 'bt',
      );
      final merged = mergeBluetoothIdentity(
        [named],
        const [
          BluetoothIdentity(
            name: 'WH-1000XM5',
            classOfDevice: 0x418,
            address: 'a1b2c3d4e5f6',
            hints: ['Sony'],
          ),
        ],
      );
      expect(merged.single.identityHints, ['WH-1000XM5', 'Sony']);
    });
  });
}
