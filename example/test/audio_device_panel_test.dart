import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/meeting/audio_device_panel.dart';
import 'package:flutter_ai_communications_example/meeting/lobby_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = [
    Endpoint(
      id: 'hdmi-out',
      name: 'DELL U3219Q',
      routeClass: RouteClass.wired,
      isCapture: false,
    ),
    Endpoint(
      id: 'usb-in',
      name: 'Logitech BRIO',
      routeClass: RouteClass.wired,
      isCapture: true,
      osDefault: true,
    ),
    Endpoint(
      id: 'usb-out',
      name: 'Realtek USB2.0 Audio',
      routeClass: RouteClass.wired,
      isCapture: false,
      osDefault: true,
    ),
    Endpoint(
      id: 'built-in-in',
      name: 'MacBook Pro Microphone',
      routeClass: RouteClass.speakerphone,
      isCapture: true,
    ),
    Endpoint(
      id: 'built-in-out',
      name: 'MacBook Pro Speakers',
      routeClass: RouteClass.speakerphone,
      isCapture: false,
    ),
  ];

  Future<void> pumpPanel(
    WidgetTester tester, {
    EndpointPreference preference = const EndpointPreference(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioDevicePanel(
            catalog: catalog,
            preference: preference,
            onSelectEndpoint: (_) {},
          ),
        ),
      ),
    );
  }

  List<String> endpointIds(WidgetTester tester) {
    return tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byKey(const Key('audio-panel')),
            matching: find.byType(ListTile),
          ),
        )
        .map((tile) => (tile.key! as ValueKey<String>).value)
        .toList();
  }

  testWidgets('empty preference puts OS default first and labels Default', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(endpointIds(tester), [
      'endpoint-usb-in',
      'endpoint-built-in-in',
      'endpoint-usb-out',
      'endpoint-hdmi-out',
      'endpoint-built-in-out',
    ]);
    expect(find.byKey(const Key('endpoint-default-usb-in')), findsOneWidget);
    expect(find.byKey(const Key('endpoint-default-usb-out')), findsOneWidget);
    expect(find.text('Default'), findsNWidgets(2));
    expect(find.byKey(const Key('endpoint-default-hdmi-out')), findsNothing);
  });

  testWidgets(
    'host preference lists available ids then remainder and still labels Default',
    (tester) async {
      await pumpPanel(
        tester,
        preference: const EndpointPreference(
          entries: [
            EndpointPreferenceEntry(
              renderId: 'hdmi-out',
              captures: [EndpointPreferenceCapture(id: 'built-in-in')],
            ),
            EndpointPreferenceEntry(
              renderId: 'gone-out',
              captures: [EndpointPreferenceCapture(id: 'gone-in')],
            ),
            EndpointPreferenceEntry(
              renderId: 'usb-out',
              enabled: false,
              captures: [EndpointPreferenceCapture(id: 'usb-in')],
            ),
          ],
        ),
      );

      expect(endpointIds(tester), [
        'endpoint-built-in-in',
        'endpoint-usb-in',
        'endpoint-hdmi-out',
        'endpoint-usb-out',
        'endpoint-built-in-out',
      ]);
      expect(find.byKey(const Key('endpoint-default-usb-in')), findsOneWidget);
      expect(find.byKey(const Key('endpoint-default-usb-out')), findsOneWidget);
    },
  );

  testWidgets(
    'Speakerphone capture stays on-screen in a phone-sized lobby overlay',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const androidCatalog = [
        Endpoint(
          id: 'speaker-in',
          name: 'Speakerphone',
          routeClass: RouteClass.speakerphone,
          isCapture: true,
          pairId: 'speakerphone',
          osDefault: true,
        ),
        Endpoint(
          id: 'handset-in',
          name: 'Handset',
          routeClass: RouteClass.handset,
          isCapture: true,
          pairId: 'handset',
        ),
        Endpoint(
          id: 'speaker-out',
          name: 'Speakerphone',
          routeClass: RouteClass.speakerphone,
          isCapture: false,
          pairId: 'speakerphone',
          osDefault: true,
        ),
        Endpoint(
          id: 'handset-out',
          name: 'Handset',
          routeClass: RouteClass.handset,
          isCapture: false,
          pairId: 'handset',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 360,
            height: 640,
            child: LobbyStage(
              selfView: const ColoredBox(color: Color(0xFF111118)),
              audioButton: const SizedBox(height: 48, width: 80),
              cameraButton: const SizedBox(height: 48, width: 80),
              audioPanel: AudioDevicePanel(
                catalog: androidCatalog,
                onSelectEndpoint: (_) {},
              ),
              onEnter: () {},
              onJoin: () {},
              onLeave: () {},
            ),
          ),
        ),
      );

      final speaker = tester.getRect(
        find.byKey(const Key('endpoint-speaker-in')),
      );
      expect(speaker.top, greaterThanOrEqualTo(0));
      expect(speaker.bottom, lessThanOrEqualTo(640));
      expect(find.text('Speakerphone'), findsWidgets);
    },
  );
}
