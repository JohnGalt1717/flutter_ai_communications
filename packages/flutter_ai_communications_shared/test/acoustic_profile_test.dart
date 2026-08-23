import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const classifier = AcousticClassifier();

  Endpoint capture(
    String name, {
    RouteClass routeClass = RouteClass.bluetooth,
    EndpointCapabilities capabilities = const EndpointCapabilities(),
    String? id,
  }) {
    return Endpoint(
      id: id ?? 'cap',
      name: name,
      routeClass: routeClass,
      isCapture: true,
      capabilities: capabilities,
    );
  }

  group('known-profile registry', () {
    test('AirPods is a communications headset at seed step 3', () {
      final profile = classifier.classify(capture('AirPods Pro'));
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.baselineStep, 3);
      expect(profile.confidence, ProfileConfidence.known);
      expect(profile.provenance, ProfileProvenance.knownRegistry);
    });

    test('Jabra Evolve is a communications headset', () {
      final profile = classifier.classify(capture('Jabra Evolve2 65'));
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.baselineStep, 3);
    });

    test('JBL Flip is a Bluetooth speaker at seed step 4', () {
      final profile = classifier.classify(capture('JBL Flip 6'));
      expect(profile.family, AcousticFamily.bluetoothSpeaker);
      expect(profile.baselineStep, 4);
      expect(profile.confidence, ProfileConfidence.known);
    });

    test('known headset families match narrowly', () {
      expect(
        classifier.classify(capture('Bose QuietComfort 45')).family,
        AcousticFamily.communicationsHeadset,
      );
      expect(
        classifier.classify(capture('Sony WH-1000XM5')).family,
        AcousticFamily.communicationsHeadset,
      );
      expect(
        classifier.classify(capture('Beats Fit Pro')).family,
        AcousticFamily.communicationsHeadset,
      );
      expect(
        classifier.classify(capture('Sennheiser Momentum 4')).family,
        AcousticFamily.communicationsHeadset,
      );
      expect(
        classifier.classify(capture('soundcore Space One')).family,
        AcousticFamily.communicationsHeadset,
      );
      expect(
        classifier.classify(capture('Poly Voyager 4320')).family,
        AcousticFamily.communicationsHeadset,
      );
    });

    test('near-match names are not AirPods', () {
      expect(
        classifier.classify(capture('PairPods Pro')).family,
        isNot(AcousticFamily.communicationsHeadset),
      );
      expect(
        classifier.classify(capture('Air Pod Tray')).family,
        isNot(AcousticFamily.communicationsHeadset),
      );
    });

    test('Tesla token without car evidence is not a car profile', () {
      final profile = classifier.classify(capture('Tesla Model Y'));
      expect(profile.family, isNot(AcousticFamily.car));
      expect(profile.confidence, isNot(ProfileConfidence.known));
    });

    test('Tesla with independent car evidence is car at seed step 5', () {
      final profile = classifier.classify(
        capture(
          'Tesla Model Y',
          routeClass: RouteClass.car,
          capabilities: const EndpointCapabilities(carConnected: true),
        ),
      );
      expect(profile.family, AcousticFamily.car);
      expect(profile.baselineStep, 5);
    });
  });

  group('classification precedence', () {
    test('verified native headset capabilities beat a speaker-like name', () {
      final profile = classifier.classify(
        capture(
          'JBL Flip 6',
          capabilities: const EndpointCapabilities(
            aec: true,
            ns: true,
            formFactor: EndpointFormFactor.headset,
          ),
        ),
      );
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.confidence, ProfileConfidence.verified);
      expect(profile.provenance, ProfileProvenance.nativeCapabilities);
      expect(profile.baselineStep, 3);
    });

    test('unknown bluetooth uses conservative speaker fallback', () {
      final profile = classifier.classify(capture('Wireless-A1'));
      expect(profile.family, AcousticFamily.bluetoothSpeaker);
      expect(profile.baselineStep, 4);
      expect(profile.confidence, ProfileConfidence.fallback);
      expect(profile.provenance, ProfileProvenance.routeClass);
    });

    test('handset route fallback is seed step 8', () {
      final profile = classifier.classify(
        capture('Handset', routeClass: RouteClass.handset),
      );
      expect(profile.family, AcousticFamily.handset);
      expect(profile.baselineStep, 8);
      expect(profile.confidence, ProfileConfidence.fallback);
    });

    test('speakerphone route fallback is seed step 6', () {
      final profile = classifier.classify(
        capture('Speakerphone', routeClass: RouteClass.speakerphone),
      );
      expect(profile.family, AcousticFamily.speakerphone);
      expect(profile.baselineStep, 6);
    });
  });

  group('Baseline scale', () {
    test('profileScaled step 5 equals the profile Baseline RMS', () {
      const headset = AcousticProfile(
        family: AcousticFamily.communicationsHeadset,
        baselineStep: 3,
        confidence: ProfileConfidence.known,
        provenance: ProfileProvenance.knownRegistry,
      );
      expect(
        BaselinePolicy.rmsFor(profile: headset, scaledStep: 5),
        BaselinePolicy.rmsForStep(3),
      );
    });

    test('higher steps raise the floor', () {
      expect(BaselinePolicy.rmsForStep(1), lessThan(BaselinePolicy.rmsForStep(5)));
      expect(BaselinePolicy.rmsForStep(5), lessThan(BaselinePolicy.rmsForStep(10)));
      expect(
        BaselinePolicy.rmsForStep(3),
        lessThan(BaselinePolicy.rmsForStep(8)),
      );
    });
  });
}
