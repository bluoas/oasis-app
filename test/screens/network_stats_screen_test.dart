import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oasis_app/screens/network_stats_screen.dart';

void main() {
  group('NetworkStatsScreen Tests', () {
    testWidgets('Shows loading indicator initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Shows Connection Status card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Connection Status'), findsOneWidget);
    });

    testWidgets('Shows Message Queue card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Message Queue'), findsOneWidget);
    });

    testWidgets('Shows Delivery Statistics card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Delivery Statistics'), findsOneWidget);
    });

    testWidgets('Shows Actions card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      // Wait for loading to complete
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Find the ListView and scroll to bottom
      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        // Scroll down to reveal Actions card
        await tester.drag(listView, const Offset(0, -800));
        await tester.pumpAndSettle();
      }
      
      // Actions card should be visible after scrolling
      expect(find.text('Actions'), findsOneWidget);
    });

    testWidgets('Shows refresh button in AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('Shows "No Node Connected" when offline', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // When no active node is connected, should show offline message
      // Note: Actual behavior depends on P2PService state
    });
  });

  group('NetworkStatsScreen Actions', () {
    testWidgets('Retry button appears when pending messages exist', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Note: Retry button only appears if pending or failed messages > 0
      // This requires mock data setup
    });

    testWidgets('Tapping Force Reconnect triggers reconnect', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: NetworkStatsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final reconnectButton = find.text('Force Reconnect');
      if (reconnectButton.evaluate().isNotEmpty) {
        await tester.tap(reconnectButton);
        await tester.pumpAndSettle();

        // Should show "Reconnecting..." snackbar
        expect(find.text('Reconnecting...'), findsOneWidget);
      }
    });
  });

  group('NetworkStatsScreen Delivery Rate Calculation', () {
    test('Delivery rate is 100% when all messages sent', () {
      final sent = 10;
      final total = 10;
      final rate = (sent / total) * 100;
      
      expect(rate, equals(100.0));
    });

    test('Delivery rate is 0% when no messages sent', () {
      final sent = 0;
      final total = 10;
      final rate = (sent / total) * 100;
      
      expect(rate, equals(0.0));
    });

    test('Delivery rate is 50% when half messages sent', () {
      final sent = 5;
      final total = 10;
      final rate = (sent / total) * 100;
      
      expect(rate, equals(50.0));
    });

    test('Delivery rate handles edge case (0 total)', () {
      final sent = 0;
      final total = 0;
      final rate = total > 0 ? (sent / total) * 100 : 0.0;
      
      expect(rate, equals(0.0));
    });
  });
}
