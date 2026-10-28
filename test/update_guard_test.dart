import 'package:flutter_test/flutter_test.dart';
import 'package:flatsphere/security/update_guard.dart';

void main() {
  test('runWithoutUpdatePrompt returns the action result and rethrows errors', () async {
    expect(await runWithoutUpdatePrompt(() async => 42), 42);
    await expectLater(runWithoutUpdatePrompt<void>(() async => throw StateError('x')), throwsStateError);
  });
}
