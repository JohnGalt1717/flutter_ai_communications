import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_shared/src/data/known_profiles.embed.dart';
import 'package:test/test.dart';

void main() {
  test('embedded JSON matches known_profiles.json', () {
    final file = _jsonFile();
    expect(jsonDecode(file.readAsStringSync()), jsonDecode(knownProfilesJson));
  });

  test('every row has an id, alias, family, sources, and NC flag', () {
    final rows = KnownProfileRegistry.load();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.id, isNotEmpty);
      expect(row.aliases, isNotEmpty);
      expect(row.sources, isNotEmpty);
      expect(row.family, isNot(AcousticFamily.unknown));
    }
  });

  test('AirPods Pro is listed before AirPods so Pro is not a no-ANC match', () {
    final ids = KnownProfileRegistry.load().map((row) => row.id).toList();
    expect(ids.indexOf('airpods-pro'), lessThan(ids.indexOf('airpods')));
  });
}

File _jsonFile() {
  const relative = 'lib/src/data/known_profiles.json';
  for (final path in [
    relative,
    'packages/flutter_ai_communications_shared/$relative',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  fail('missing $relative');
}
