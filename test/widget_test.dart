// Basic smoke test for the onboarding flow's first screen.
//
// This intentionally pumps ApiKeyScreen directly (not the full app/router),
// since the router's redirect logic touches flutter_secure_storage via a
// platform channel that isn't available under `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_language_app/screens/api_key_screen.dart';

void main() {
  testWidgets('ApiKeyScreen shows title and Submit button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ApiKeyScreen()),
      ),
    );

    expect(find.text('Enter your Gemini API Key'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });
}
