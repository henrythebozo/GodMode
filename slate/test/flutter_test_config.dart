import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: loads the app's real font so text measures
/// as it does on a phone (the default test font draws every glyph as a
/// square, which makes overflow checks meaningless).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('PlusJakartaSans');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
  }
  await loader.load();
  await testMain();
}
