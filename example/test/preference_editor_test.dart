import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/main.dart';
import 'package:flutter_ai_communications_example/preference_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = [
    Endpoint(
      id: 'airpods-in',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: true,
      pairId: 'airpods',
    ),
    Endpoint(
      id: 'airpods-out',
      name: 'AirPods',
      routeClass: RouteClass.bluetooth,
      isCapture: false,
      pairId: 'airpods',
    ),
    Endpoint(
      id: 'brio-in',
      name: 'Logitech BRIO',
      routeClass: RouteClass.wired,
      isCapture: true,
      pairId: 'logitech brio',
    ),
    Endpoint(
      id: 'usb-out',
      name: 'USB Audio',
      routeClass: RouteClass.wired,
      isCapture: false,
      pairId: 'usb audio',
    ),
  ];

  testWidgets('editor lists complete Pairs and unpaired renders', (
    tester,
  ) async {
    var draft = const EndpointPreference();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreferenceEditor(
            catalog: catalog,
            draft: draft,
            onChanged: (next) => draft = next,
            onApply: () {},
            onReset: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('preference-editor')), findsOneWidget);
    expect(find.byKey(const Key('pref-row-airpods-out')), findsOneWidget);
    expect(find.byKey(const Key('pref-row-usb-out')), findsOneWidget);
    expect(
      find.byKey(const Key('pref-capture-usb-out-brio-in')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('pref-bound-count'))).data,
      '0',
    );
  });

  testWidgets('selecting a capture chip on USB speakers creates a row', (
    tester,
  ) async {
    var draft = const EndpointPreference();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: PreferenceEditor(
                catalog: catalog,
                draft: draft,
                onChanged: (next) => setState(() => draft = next),
                onApply: () {},
                onReset: () {},
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pref-capture-usb-out-brio-in')));
    await tester.pump();
    expect(draft.entries, hasLength(1));
    expect(draft.entries.single.renderId, 'usb-out');
    expect(draft.entries.single.captures.single.id, 'brio-in');
    expect(
      tester.widget<Text>(find.byKey(const Key('pref-bound-count'))).data,
      '1',
    );
  });

  testWidgets('same Brio mic can be selected on AirPods and USB rows', (
    tester,
  ) async {
    var draft = const EndpointPreference();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: PreferenceEditor(
                catalog: catalog,
                draft: draft,
                onChanged: (next) => setState(() => draft = next),
                onApply: () {},
                onReset: () {},
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pref-capture-usb-out-brio-in')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pref-capture-airpods-out-brio-in')));
    await tester.pump();
    expect(draft.entries, hasLength(2));
    expect(
      draft.entries.every(
        (entry) => entry.captures.any((slot) => slot.id == 'brio-in'),
      ),
      isTrue,
    );
  });

  testWidgets('harness shows preference editor keys', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterAiCommunicationsPlatform.debugReset();
    final platform = FakeCommunicationsPlatform();
    FlutterAiCommunicationsPlatform.instance = platform;
    final manager = CommunicationsManager(
      platform: platform,
      coverageSource: const AlwaysOkCoverageSource(),
    );
    addTearDown(() async {
      await manager.session?.stop();
      await platform.dispose();
      FlutterAiCommunicationsPlatform.debugReset();
    });
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ExampleApp(manager: manager));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('preference-editor')),
      80,
    );
    expect(find.byKey(const Key('preference-editor')), findsOneWidget);
    expect(find.byKey(const Key('pref-apply')), findsOneWidget);
    expect(find.byKey(const Key('pref-use-current')), findsOneWidget);
    expect(find.byKey(const Key('pref-reset')), findsOneWidget);
  });
}
