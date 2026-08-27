import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  const classifier = AcousticClassifier();

  Endpoint capture(
    String name, {
    RouteClass routeClass = RouteClass.bluetooth,
    EndpointCapabilities capabilities = const EndpointCapabilities(),
    List<String> identityHints = const [],
    String? id,
  }) {
    return Endpoint(
      id: id ?? 'cap',
      name: name,
      routeClass: routeClass,
      isCapture: true,
      capabilities: capabilities,
      identityHints: identityHints,
    );
  }

  group('known-profile registry', () {
    test('AirPods Pro has hardware noise processing at seed step 3', () {
      final profile = classifier.classify(capture('AirPods Pro'));
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.hardwareNoiseProcessing, isTrue);
      expect(profile.baselineStep, 3);
      expect(profile.confidence, ProfileConfidence.known);
      expect(profile.provenance, ProfileProvenance.knownRegistry);
      expect(profile.matchId, 'airpods-pro');
    });

    test('AirPods without Pro does not claim hardware noise processing', () {
      final profile = classifier.classify(capture('AirPods'));
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 4);
      expect(profile.matchId, 'airpods');
    });

    test('Jabra Evolve2 65 has no hardware ANC so seed step 4', () {
      final profile = classifier.classify(capture('Jabra Evolve2 65'));
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 4);
      expect(profile.matchId, 'jabra-evolve2-65');
    });

    test('Jabra Evolve2 75 has hardware ANC at seed step 3', () {
      final profile = classifier.classify(capture('Jabra Evolve2 75'));
      expect(profile.hardwareNoiseProcessing, isTrue);
      expect(profile.baselineStep, 3);
      expect(profile.matchId, 'jabra-evolve2-anc');
    });

    test('JBL Flip is a Bluetooth speaker without hardware capture NC', () {
      final profile = classifier.classify(capture('JBL Flip 6'));
      expect(profile.family, AcousticFamily.bluetoothSpeaker);
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 4);
      expect(profile.confidence, ProfileConfidence.known);
    });

    test('researched headset advertised names match', () {
      expect(
        classifier.classify(capture('Bose QuietComfort 45')).matchId,
        'bose-quietcomfort',
      );
      expect(
        classifier.classify(capture('Sony WH-1000XM5')).hardwareNoiseProcessing,
        isTrue,
      );
      expect(
        classifier.classify(capture('Beats Fit Pro')).matchId,
        'beats-fit-pro',
      );
      expect(
        classifier.classify(capture('Sennheiser Momentum 4')).matchId,
        'sennheiser-momentum',
      );
      expect(
        classifier.classify(capture('soundcore Space One')).matchId,
        'soundcore-space',
      );
      expect(
        classifier.classify(capture('Poly Voyager Focus 2')).matchId,
        'poly-voyager-focus',
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

    test('Tesla Model Y is a car head unit without capture ANC', () {
      final profile = classifier.classify(capture('Tesla Model Y'));
      expect(profile.family, AcousticFamily.car);
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 5);
      expect(profile.confidence, ProfileConfidence.known);
      expect(profile.matchId, 'tesla-model');
    });

    test('researched car advertised names match', () {
      expect(classifier.classify(capture('BMW 330i')).matchId, 'bmw-identity');
      expect(classifier.classify(capture('Ford SYNC')).matchId, 'ford-sync');
      expect(classifier.classify(capture('Uconnect')).matchId, 'uconnect');
      expect(
        classifier.classify(capture('Rivian Audio')).matchId,
        'rivian-audio',
      );
      expect(
        classifier.classify(capture("James's CarPlay")).matchId,
        'carplay',
      );
    });

    test('invented OEM tokens are not cars', () {
      expect(
        classifier.classify(capture('Honda Civic Headset')).family,
        isNot(AcousticFamily.car),
      );
      expect(
        classifier.classify(capture('Kia Speaker')).family,
        isNot(AcousticFamily.car),
      );
    });

    test('near-match names are not vehicle head units', () {
      expect(
        classifier.classify(capture('Audio Interface')).family,
        isNot(AcousticFamily.car),
      );
      expect(
        classifier.classify(capture('Nokia Headset')).family,
        isNot(AcousticFamily.car),
      );
      expect(
        classifier.classify(capture('Test Lab Speaker')).family,
        isNot(AcousticFamily.car),
      );
    });

    test('Tesla with CarPlay evidence is verified car at seed step 5', () {
      final profile = classifier.classify(
        capture(
          'Tesla Model Y',
          routeClass: RouteClass.car,
          capabilities: const EndpointCapabilities(carConnected: true),
        ),
      );
      expect(profile.family, AcousticFamily.car);
      expect(profile.baselineStep, 5);
      expect(profile.confidence, ProfileConfidence.verified);
      expect(profile.matchId, 'tesla-model');
    });
  });

  group('classification precedence', () {
    test('verified native headset family beats a speaker-like name', () {
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
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 4);
    });

    test('Bluetooth alias applies researched hardware noise processing', () {
      final profile = classifier.classify(
        capture('BT-Audio', identityHints: const ['Sony WH-1000XM5']),
      );
      expect(profile.family, AcousticFamily.communicationsHeadset);
      expect(profile.hardwareNoiseProcessing, isTrue);
      expect(profile.baselineStep, 3);
      expect(profile.confidence, ProfileConfidence.known);
      expect(profile.matchId, 'sony-wh-1000x');
    });

    test('Bluetooth alias Tesla beats a generic audio display name', () {
      final profile = classifier.classify(
        capture('BT-Audio', identityHints: const ['Tesla Model Y']),
      );
      expect(profile.family, AcousticFamily.car);
      expect(profile.hardwareNoiseProcessing, isFalse);
      expect(profile.baselineStep, 5);
      expect(profile.matchId, 'tesla-model');
    });

    test('native car Class of Device beats a speaker-like display name', () {
      final profile = classifier.classify(
        capture(
          'JBL Flip 6',
          capabilities: const EndpointCapabilities(
            formFactor: EndpointFormFactor.car,
          ),
        ),
      );
      expect(profile.family, AcousticFamily.car);
      expect(profile.confidence, ProfileConfidence.verified);
      expect(profile.provenance, ProfileProvenance.nativeCapabilities);
    });

    test('native speaker Class of Device beats a Tesla display name', () {
      final profile = classifier.classify(
        capture(
          'Tesla Model Y',
          capabilities: const EndpointCapabilities(
            formFactor: EndpointFormFactor.speaker,
          ),
        ),
      );
      expect(profile.family, AcousticFamily.bluetoothSpeaker);
      expect(profile.confidence, ProfileConfidence.verified);
    });

    test('unknown bluetooth uses conservative speaker fallback', () {
      final profile = classifier.classify(capture('Wireless-A1'));
      expect(profile.family, AcousticFamily.bluetoothSpeaker);
      expect(profile.hardwareNoiseProcessing, isFalse);
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
    test('hardware noise processing lowers a headset Baseline', () {
      expect(
        BaselinePolicy.stepFor(
          family: AcousticFamily.communicationsHeadset,
          hardwareNoiseProcessing: true,
        ),
        3,
      );
      expect(
        BaselinePolicy.stepFor(
          family: AcousticFamily.communicationsHeadset,
          hardwareNoiseProcessing: false,
        ),
        4,
      );
    });

    test('profileScaled step 5 equals the profile Baseline RMS', () {
      const headset = AcousticProfile(
        family: AcousticFamily.communicationsHeadset,
        baselineStep: 3,
        hardwareNoiseProcessing: true,
        confidence: ProfileConfidence.known,
        provenance: ProfileProvenance.knownRegistry,
      );
      expect(
        BaselinePolicy.rmsFor(profile: headset, scaledStep: 5),
        BaselinePolicy.rmsForStep(3),
      );
    });

    test('higher steps raise the floor', () {
      expect(
        BaselinePolicy.rmsForStep(1),
        lessThan(BaselinePolicy.rmsForStep(5)),
      );
      expect(
        BaselinePolicy.rmsForStep(5),
        lessThan(BaselinePolicy.rmsForStep(10)),
      );
      expect(
        BaselinePolicy.rmsForStep(3),
        lessThan(BaselinePolicy.rmsForStep(8)),
      );
    });
  });
}
