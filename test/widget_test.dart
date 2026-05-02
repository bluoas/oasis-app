// Widget Tests for Oasis App
//
// Tests the main app initialization and UI components

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oasis_app/main.dart';

void main() {
  testWidgets('App should build with ProviderScope', (WidgetTester tester) async {
    // Build our app with ProviderScope
    // This is a smoke test that verifies the app structure compiles
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    // Verify that the app builds without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
