import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/loading_state.dart';
import '../../lib/widgets/error_state.dart';
import '../../lib/widgets/empty_state.dart';

void main() {
  group('Shared Widgets Tests', () {
    group('LoadingState', () {
      testWidgets('shows loading indicator without message', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoadingState(),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Loading...'), findsNothing);
      });

      testWidgets('shows loading indicator with message', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoadingState(message: 'Loading data...'),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Loading data...'), findsOneWidget);
      });

      testWidgets('respects custom size', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoadingState(size: 60),
            ),
          ),
        );

        final sizedBox = tester.widget<SizedBox>(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(SizedBox),
          ).first,
        );

        expect(sizedBox.width, 60);
        expect(sizedBox.height, 60);
      });
    });

    group('InlineLoadingIndicator', () {
      testWidgets('shows small loading indicator', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: InlineLoadingIndicator(),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        
        final sizedBox = tester.widget<SizedBox>(
          find.byType(SizedBox),
        );
        expect(sizedBox.width, 20);
        expect(sizedBox.height, 20);
      });

      testWidgets('respects custom size', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: InlineLoadingIndicator(size: 30),
            ),
          ),
        );

        final sizedBox = tester.widget<SizedBox>(
          find.byType(SizedBox),
        );
        expect(sizedBox.width, 30);
        expect(sizedBox.height, 30);
      });
    });

    group('ErrorState', () {
      testWidgets('shows error message and icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ErrorState(
                message: 'Something went wrong',
              ),
            ),
          ),
        );

        expect(find.text('Something went wrong'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byType(ElevatedButton), findsNothing);
      });

      testWidgets('shows retry button when onRetry is provided', (tester) async {
        var retryPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ErrorState(
                message: 'Failed to load',
                onRetry: () => retryPressed = true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check that retry text and refresh icon exist
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);

        // Tap the button
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(retryPressed, true);
      });

      testWidgets('shows custom retry button text', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ErrorState(
                message: 'Error',
                onRetry: () {},
                retryButtonText: 'Try Again',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Try Again'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('respects custom icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ErrorState(
                message: 'Network error',
                icon: Icons.wifi_off,
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.wifi_off), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });
    });

    group('InlineErrorWidget', () {
      testWidgets('shows compact error message', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: InlineErrorWidget(
                message: 'Failed to save',
              ),
            ),
          ),
        );

        expect(find.text('Failed to save'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });

      testWidgets('shows retry button when onRetry provided', (tester) async {
        var retryPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InlineErrorWidget(
                message: 'Error',
                onRetry: () => retryPressed = true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.refresh), findsOneWidget);

        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();

        expect(retryPressed, true);
      });
    });

    group('EmptyState', () {
      testWidgets('shows empty message and icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmptyState(
                message: 'No items',
              ),
            ),
          ),
        );

        expect(find.text('No items'), findsOneWidget);
        expect(find.byIcon(Icons.inbox), findsOneWidget);
        expect(find.byType(ElevatedButton), findsNothing);
      });

      testWidgets('shows action button when provided', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmptyState(
                message: 'No contacts',
                action: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Add Contact'),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check that button text exists
        expect(find.text('Add Contact'), findsOneWidget);
      });

      testWidgets('shows subtitle when provided', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmptyState(
                message: 'No messages',
                subtitle: 'Send the first message',
              ),
            ),
          ),
        );

        expect(find.text('No messages'), findsOneWidget);
        expect(find.text('Send the first message'), findsOneWidget);
      });

      testWidgets('respects custom icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmptyState(
                message: 'No chats',
                icon: Icons.chat_bubble_outline,
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
        expect(find.byIcon(Icons.inbox), findsNothing);
      });
    });

    group('CompactEmptyState', () {
      testWidgets('shows compact empty message', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CompactEmptyState(
                message: 'Nothing here',
              ),
            ),
          ),
        );

        expect(find.text('Nothing here'), findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
      });

      testWidgets('respects custom icon', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CompactEmptyState(
                message: 'Empty',
                icon: Icons.folder_open,
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.folder_open), findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsNothing);
      });
    });
  });
}
