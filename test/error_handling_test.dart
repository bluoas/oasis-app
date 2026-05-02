import 'package:flutter_test/flutter_test.dart';
import '../lib/models/app_error.dart';
import '../lib/utils/result.dart';

/// Unit tests for Error Handling Infrastructure
/// 
/// Tests:
/// - AppError types and user messages
/// - Result type operations (map, flatMap, fold)
/// - Result chaining and composition
/// - Error factory
void main() {
  group('AppError', () {
    test('NetworkError should provide user-friendly message', () {
      final error = NetworkError(
        message: 'Connection failed',
        type: NetworkErrorType.noConnection,
      );

      expect(error.userMessage, equals('Keine Internetverbindung'));
      expect(error.message, equals('Connection failed'));
    });

    test('CryptoError should distinguish error types', () {
      final encryptError = CryptoError(
        message: 'Encryption failed',
        type: CryptoErrorType.encryptionFailed,
      );

      final decryptError = CryptoError(
        message: 'Decryption failed',
        type: CryptoErrorType.decryptionFailed,
      );

      expect(encryptError.type, equals(CryptoErrorType.encryptionFailed));
      expect(decryptError.type, equals(CryptoErrorType.decryptionFailed));
    });

    test('AppErrorFactory should map exceptions to AppError', () {
      // Network exception
      final networkError = AppErrorFactory.fromException(
        Exception('SocketException: Connection refused'),
      );
      expect(networkError, isA<NetworkError>());

      // Crypto exception
      final cryptoError = AppErrorFactory.fromException(
        Exception('Encryption failed: invalid key'),
      );
      expect(cryptoError, isA<CryptoError>());

      // Unknown exception
      final unknownError = AppErrorFactory.fromException(
        Exception('Something weird happened'),
      );
      expect(unknownError, isA<UnknownError>());
    });
  });

  group('Result Type', () {
    test('Success should contain value', () {
      final result = Success<int, String>(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, equals(42));
      expect(result.errorOrNull, isNull);
    });

    test('Failure should contain error', () {
      final result = Failure<int, String>('error message');

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, equals('error message'));
    });

    test('map() should transform success value', () {
      final result = Success<int, String>(5);
      final mapped = result.map((v) => v * 2);

      expect(mapped.valueOrNull, equals(10));
    });

    test('map() should preserve failure', () {
      final result = Failure<int, String>('error');
      final mapped = result.map((v) => v * 2);

      expect(mapped.errorOrNull, equals('error'));
    });

    test('flatMap() should chain results', () {
      final result = Success<int, String>(5);
      final chained = result.flatMap((v) {
        if (v > 3) {
          return Success<int, String>(v * 2);
        } else {
          return Failure<int, String>('too small');
        }
      });

      expect(chained.valueOrNull, equals(10));
    });

    test('flatMap() should short-circuit on failure', () {
      final result = Failure<int, String>('initial error');
      final chained = result.flatMap((v) => Success<int, String>(v * 2));

      expect(chained.errorOrNull, equals('initial error'));
    });

    test('fold() should handle both cases', () {
      final success = Success<int, String>(42);
      final failure = Failure<int, String>('error');

      final successResult = success.fold(
        onSuccess: (v) => 'Value: $v',
        onFailure: (e) => 'Error: $e',
      );

      final failureResult = failure.fold(
        onSuccess: (v) => 'Value: $v',
        onFailure: (e) => 'Error: $e',
      );

      expect(successResult, equals('Value: 42'));
      expect(failureResult, equals('Error: error'));
    });

    test('getOrElse() should provide default on failure', () {
      final success = Success<int, String>(42);
      final failure = Failure<int, String>('error');

      expect(success.getOrElse(0), equals(42));
      expect(failure.getOrElse(0), equals(0));
    });

    test('onSuccess() callback should only fire for Success', () {
      var called = false;
      
      final success = Success<int, String>(42);
      success.onSuccess((v) => called = true);
      expect(called, isTrue);

      called = false;
      final failure = Failure<int, String>('error');
      failure.onSuccess((v) => called = true);
      expect(called, isFalse);
    });

    test('onFailure() callback should only fire for Failure', () {
      var called = false;
      
      final failure = Failure<int, String>('error');
      failure.onFailure((e) => called = true);
      expect(called, isTrue);

      called = false;
      final success = Success<int, String>(42);
      success.onFailure((e) => called = true);
      expect(called, isFalse);
    });
  });

  group('Result Async Operations', () {
    test('mapAsync() should transform value asynchronously', () async {
      final result = Success<int, String>(5);
      final mapped = await result.mapAsync((v) async {
        await Future.delayed(Duration(milliseconds: 10));
        return v * 2;
      });

      expect(mapped.valueOrNull, equals(10));
    });

    test('flatMapAsync() should chain async operations', () async {
      final result = Success<int, String>(5);
      final chained = await result.flatMapAsync((v) async {
        await Future.delayed(Duration(milliseconds: 10));
        return Success<int, String>(v * 2);
      });

      expect(chained.valueOrNull, equals(10));
    });
  });

  group('Result Helpers', () {
    test('resultOf() should catch exceptions', () {
      final result = resultOf<int, String>(
        () => throw Exception('error'),
        (e, st) => 'caught: $e',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, contains('caught'));
    });

    test('resultOf() should return success on no exception', () {
      final result = resultOf<int, String>(
        () => 42,
        (e, st) => 'error',
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, equals(42));
    });

    test('resultOfAsync() should handle async exceptions', () async {
      final result = await resultOfAsync<int, String>(
        () async {
          await Future.delayed(Duration(milliseconds: 10));
          throw Exception('async error');
        },
        (e, st) => 'caught: $e',
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('Result Collections', () {
    test('collectSuccesses() should filter success values', () {
      final results = [
        Success<int, String>(1),
        Failure<int, String>('error'),
        Success<int, String>(2),
        Success<int, String>(3),
      ];

      final successes = results.collectSuccesses();

      expect(successes, equals([1, 2, 3]));
    });

    test('collectFailures() should filter error values', () {
      final results = [
        Success<int, String>(1),
        Failure<int, String>('error1'),
        Success<int, String>(2),
        Failure<int, String>('error2'),
      ];

      final failures = results.collectFailures();

      expect(failures, equals(['error1', 'error2']));
    });

    test('allSuccess should check if all are successful', () {
      final allSuccess = [
        Success<int, String>(1),
        Success<int, String>(2),
      ];

      final hasFailure = [
        Success<int, String>(1),
        Failure<int, String>('error'),
      ];

      expect(allSuccess.allSuccess, isTrue);
      expect(hasFailure.allSuccess, isFalse);
    });

    test('sequence() should collect or fail fast', () {
      final allSuccess = [
        Success<int, String>(1),
        Success<int, String>(2),
        Success<int, String>(3),
      ];

      final hasFailure = [
        Success<int, String>(1),
        Failure<int, String>('error'),
        Success<int, String>(3),
      ];

      final successResult = allSuccess.sequence();
      expect(successResult.valueOrNull, equals([1, 2, 3]));

      final failureResult = hasFailure.sequence();
      expect(failureResult.errorOrNull, equals('error'));
    });
  });

  group('Pattern Matching', () {
    test('switch expression should work with Result', () {
      final Result<int, String> success = Success<int, String>(42);
      final Result<int, String> failure = Failure<int, String>('error');

      final successMessage = switch (success) {
        Success(value: final v) => 'Got $v',
        Failure(error: final e) => 'Error: $e',
      };

      final failureMessage = switch (failure) {
        Success(value: final v) => 'Got $v',
        Failure(error: final e) => 'Error: $e',
      };

      expect(successMessage, equals('Got 42'));
      expect(failureMessage, equals('Error: error'));
    });
  });

  group('Real-World Scenarios', () {
    test('chaining crypto and storage operations', () async {
      // Simulate: generate key -> save key -> load key
      final keyResult = await _generateMockKey();
      
      final saveResult = await keyResult.flatMapAsync((key) async {
        return await _saveMockKey(key);
      });
      
      final loadResult = await saveResult.flatMapAsync((_) async {
        return await _loadMockKey();
      });

      expect(loadResult.isSuccess, isTrue);
      expect(loadResult.valueOrNull, equals('mock_key_data'));
    });

    test('handling network errors gracefully', () async {
      final result = await _simulateNetworkRequest(shouldFail: true);

      expect(result.isFailure, isTrue);
      
      final error = result.errorOrNull as NetworkError;
      expect(error.type, equals(NetworkErrorType.timeout));
      expect(error.userMessage, contains('Zeitüberschreitung'));
    });

    test('validation errors before operations', () async {
      final result = await _validateAndProcess('');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ValidationError>());
    });
  });
}

// ==================== Mock Helper Functions ====================

Future<Result<String, AppError>> _generateMockKey() async {
  await Future.delayed(Duration(milliseconds: 10));
  return Success('mock_key_data');
}

Future<Result<void, AppError>> _saveMockKey(String key) async {
  await Future.delayed(Duration(milliseconds: 10));
  return Success(null);
}

Future<Result<String, AppError>> _loadMockKey() async {
  await Future.delayed(Duration(milliseconds: 10));
  return Success('mock_key_data');
}

Future<Result<String, AppError>> _simulateNetworkRequest({
  required bool shouldFail,
}) async {
  await Future.delayed(Duration(milliseconds: 10));
  
  if (shouldFail) {
    return Failure(
      NetworkError(
        message: 'Request timed out',
        type: NetworkErrorType.timeout,
      ),
    );
  }
  
  return Success('response_data');
}

Future<Result<void, AppError>> _validateAndProcess(String input) async {
  if (input.isEmpty) {
    return Failure(
      ValidationError(
        message: 'Input cannot be empty',
        field: 'input',
      ),
    );
  }
  
  return Success(null);
}
