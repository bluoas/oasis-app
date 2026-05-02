import 'package:equatable/equatable.dart';

/// Result type for operations that can fail
/// 
/// Replaces throwing exceptions with explicit success/failure handling
/// Inspired by Rust's Result<T, E> and Swift's Result<Success, Failure>
/// 
/// Usage:
/// ```dart
/// Future<Result<User, AppError>> login(String email, String password) async {
///   try {
///     final user = await api.login(email, password);
///     return Success(user);
///   } catch (e, stackTrace) {
///     return Failure(AppErrorFactory.fromException(e, stackTrace));
///   }
/// }
/// 
/// // Pattern matching
/// final result = await login(email, password);
/// switch (result) {
///   case Success(value: final user):
///     print('Logged in: ${user.name}');
///   case Failure(error: final error):
///     print('Login failed: ${error.message}');
/// }
/// ```
sealed class Result<T, E> extends Equatable {
  const Result();

  /// Check if this is a success
  bool get isSuccess => this is Success<T, E>;

  /// Check if this is a failure
  bool get isFailure => this is Failure<T, E>;

  /// Get value if success, null otherwise
  T? get valueOrNull => switch (this) {
        Success(value: final v) => v,
        Failure() => null,
      };

  /// Get error if failure, null otherwise
  E? get errorOrNull => switch (this) {
        Success() => null,
        Failure(error: final e) => e,
      };

  /// Get value or throw error
  T get value => switch (this) {
        Success(value: final v) => v,
        Failure(error: final e) => throw Exception('Result is Failure: $e'),
      };

  /// Get error or throw if success
  E get error => switch (this) {
        Success() => throw StateError('Result is Success, not Failure'),
        Failure(error: final e) => e,
      };

  /// Transform success value, keep failure
  Result<U, E> map<U>(U Function(T value) mapper) {
    return switch (this) {
      Success(value: final v) => Success(mapper(v)),
      Failure(error: final e) => Failure(e),
    };
  }

  /// Transform failure error, keep success
  Result<T, F> mapError<F>(F Function(E error) mapper) {
    return switch (this) {
      Success(value: final v) => Success(v),
      Failure(error: final e) => Failure(mapper(e)),
    };
  }

  /// Async map for success value
  Future<Result<U, E>> mapAsync<U>(Future<U> Function(T value) mapper) async {
    return switch (this) {
      Success(value: final v) => Success(await mapper(v)),
      Failure(error: final e) => Failure(e),
    };
  }

  /// Flat map (for chaining results)
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) mapper) {
    return switch (this) {
      Success(value: final v) => mapper(v),
      Failure(error: final e) => Failure(e),
    };
  }

  /// Async flat map
  Future<Result<U, E>> flatMapAsync<U>(
    Future<Result<U, E>> Function(T value) mapper,
  ) async {
    return switch (this) {
      Success(value: final v) => await mapper(v),
      Failure(error: final e) => Failure(e),
    };
  }

  /// Get value or provide default
  T getOrElse(T defaultValue) {
    return switch (this) {
      Success(value: final v) => v,
      Failure() => defaultValue,
    };
  }

  /// Get value or compute from error
  T getOrElseCompute(T Function(E error) computer) {
    return switch (this) {
      Success(value: final v) => v,
      Failure(error: final e) => computer(e),
    };
  }

  /// Execute callback on success
  Result<T, E> onSuccess(void Function(T value) callback) {
    if (this case Success(value: final v)) {
      callback(v);
    }
    return this;
  }

  /// Execute callback on failure
  Result<T, E> onFailure(void Function(E error) callback) {
    if (this case Failure(error: final e)) {
      callback(e);
    }
    return this;
  }

  /// Fold result into single value
  U fold<U>({
    required U Function(T value) onSuccess,
    required U Function(E error) onFailure,
  }) {
    return switch (this) {
      Success(value: final v) => onSuccess(v),
      Failure(error: final e) => onFailure(e),
    };
  }

  @override
  List<Object?> get props => [valueOrNull, errorOrNull];
}

/// Success case of Result
class Success<T, E> extends Result<T, E> {
  final T value;

  const Success(this.value);

  @override
  String toString() => 'Success($value)';
}

/// Failure case of Result
class Failure<T, E> extends Result<T, E> {
  final E error;

  const Failure(this.error);

  @override
  String toString() => 'Failure($error)';
}

// ==================== Convenience Extensions ====================

/// Extension for Future<Result<T, E>>
extension FutureResultExtension<T, E> on Future<Result<T, E>> {
  /// Map success value asynchronously
  Future<Result<U, E>> mapAsync<U>(Future<U> Function(T value) mapper) async {
    final result = await this;
    return result.mapAsync(mapper);
  }

  /// Flat map asynchronously
  Future<Result<U, E>> flatMapAsync<U>(
    Future<Result<U, E>> Function(T value) mapper,
  ) async {
    final result = await this;
    return result.flatMapAsync(mapper);
  }

  /// Get value or null
  Future<T?> get valueOrNull async {
    final result = await this;
    return result.valueOrNull;
  }

  /// Get error or null
  Future<E?> get errorOrNull async {
    final result = await this;
    return result.errorOrNull;
  }

  /// Execute callback on success
  Future<Result<T, E>> onSuccess(void Function(T value) callback) async {
    final result = await this;
    return result.onSuccess(callback);
  }

  /// Execute callback on failure
  Future<Result<T, E>> onFailure(void Function(E error) callback) async {
    final result = await this;
    return result.onFailure(callback);
  }

  /// Fold result
  Future<U> fold<U>({
    required U Function(T value) onSuccess,
    required U Function(E error) onFailure,
  }) async {
    final result = await this;
    return result.fold(onSuccess: onSuccess, onFailure: onFailure);
  }
}

// ==================== Result Builders ====================

/// Try-catch wrapper that returns Result
Result<T, E> resultOf<T, E>(
  T Function() block,
  E Function(dynamic exception, StackTrace stackTrace) errorMapper,
) {
  try {
    return Success(block());
  } catch (e, stackTrace) {
    return Failure(errorMapper(e, stackTrace));
  }
}

/// Async try-catch wrapper that returns Result
Future<Result<T, E>> resultOfAsync<T, E>(
  Future<T> Function() block,
  E Function(dynamic exception, StackTrace stackTrace) errorMapper,
) async {
  try {
    return Success(await block());
  } catch (e, stackTrace) {
    return Failure(errorMapper(e, stackTrace));
  }
}

// ==================== Collection Extensions ====================

/// Extension for List<Result<T, E>>
extension ResultListExtension<T, E> on List<Result<T, E>> {
  /// Collect all successes into list (ignore failures)
  List<T> collectSuccesses() {
    return whereType<Success<T, E>>().map((s) => s.value).toList();
  }

  /// Collect all failures into list (ignore successes)
  List<E> collectFailures() {
    return whereType<Failure<T, E>>().map((f) => f.error).toList();
  }

  /// Check if all results are successful
  bool get allSuccess => every((r) => r.isSuccess);

  /// Check if any result is failure
  bool get anyFailure => any((r) => r.isFailure);

  /// Get first failure, or Success with list of all successes
  Result<List<T>, E> sequence() {
    final successes = <T>[];
    for (final result in this) {
      switch (result) {
        case Success(value: final v):
          successes.add(v);
        case Failure(error: final e):
          return Failure(e);
      }
    }
    return Success(successes);
  }
}
