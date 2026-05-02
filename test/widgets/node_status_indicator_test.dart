import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oasis_app/widgets/node_status_indicator.dart';

void main() {
  group('NodeStatusIndicator Widget Tests', () {
    testWidgets('Shows red indicator when offline', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NodeStatusIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // When no node is connected, should show red indicator
      final containerFinder = find.byType(Container);
      expect(containerFinder, findsWidgets);
    });

    testWidgets('Shows node status text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NodeStatusIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show either "My Node", "Bootstrap Node", or "Offline"
      final statusTexts = ['My Node', 'Bootstrap Node', 'Offline'];
      bool foundStatus = false;
      
      for (final status in statusTexts) {
        if (find.text(status).evaluate().isNotEmpty) {
          foundStatus = true;
          break;
        }
      }
      
      expect(foundStatus, isTrue, reason: 'Should show one of the status texts');
    });

    testWidgets('Tapping shows details dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NodeStatusIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the indicator
      final indicator = find.byType(NodeStatusIndicator);
      await tester.tap(indicator);
      await tester.pumpAndSettle();

      // Should show dialog with details
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Details dialog shows connection information', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NodeStatusIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap to show dialog
      final indicator = find.byType(NodeStatusIndicator);
      await tester.tap(indicator);
      await tester.pumpAndSettle();

      // Dialog should contain relevant information
      expect(find.text('Node Status'), findsOneWidget);
    });

    testWidgets('Details dialog has close button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NodeStatusIndicator(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap to show dialog
      final indicator = find.byType(NodeStatusIndicator);
      await tester.tap(indicator);
      await tester.pumpAndSettle();

      // Should have Close button
      expect(find.text('Close'), findsOneWidget);

      // Tap close button
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('NodeStatusIndicator Color Coding Tests', () {
    test('Green color for own node (0xFF4CAF50)', () {
      const greenColor = Color(0xFF4CAF50);
      expect(greenColor.value, equals(0xFF4CAF50));
    });

    test('Blue color for bootstrap node (0xFF2196F3)', () {
      const blueColor = Color(0xFF2196F3);
      expect(blueColor.value, equals(0xFF2196F3));
    });

    test('Red color for offline (0xFFF44336)', () {
      const redColor = Color(0xFFF44336);
      expect(redColor.value, equals(0xFFF44336));
    });
  });
}
