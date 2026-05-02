# Error Handling Infrastructure

Comprehensive error handling system using **sealed classes** and **Result type pattern** for type-safe, exhaustive error handling.

## 📦 Components

### 1. **Error Models** (`lib/models/app_error.dart`)
Sealed class hierarchy for all application errors:

```dart
sealed class AppError {
  String get userMessage;  // User-friendly localized message
  String get technicalDetails;  // Technical details for logging
}
```

**Available Error Types:**
- `NetworkError` - Connection, timeout, relay issues
- `CryptoError` - Encryption, decryption, signature failures
- `StorageError` - Hive/SecureStorage operations
- `IdentityError` - Key management issues
- `P2PError` - libp2p/DHT errors
- `ValidationError` - Input validation
- `UnknownError` - Fallback for unexpected errors

### 2. **Result Type** (`lib/utils/result.dart`)
Functional error handling without exceptions:

```dart
sealed class Result<T, E> {
  Success<T, E>(T value);
  Failure<T, E>(E error);
}
```

**Key Features:**
- Type-safe error handling
- Compiler-enforced error checks
- Chainable operations (`map`, `flatMap`, `fold`)
- Async support
- Collection utilities

### 3. **Error Handler** (`lib/utils/error_handler.dart`)
Global error handler with UI feedback:

```dart
ErrorHandler.handle(error, context, onRetry: () {...});
```

**Features:**
- Automatic logging (console + file)
- User-friendly SnackBars
- Error dialog support
- Retry actions for recoverable errors
- Analytics/Crashlytics integration points

---

## 🎯 Usage Examples

### Basic Pattern

**Old Way (throwing exceptions):**
```dart
Future<User> loadUser(String id) async {
  if (id.isEmpty) {
    throw ValidationException('ID cannot be empty');
  }
  
  try {
    return await api.getUser(id);
  } catch (e) {
    throw NetworkException('Failed: $e');
  }
}

// Caller
try {
  final user = await loadUser(id);
  print('Loaded: ${user.name}');
} catch (e) {
  print('Error: $e');  // Generic, not type-safe
}
```

**New Way (using Result):**
```dart
Future<Result<User, AppError>> loadUser(String id) async {
  if (id.isEmpty) {
    return Failure(ValidationError(
      message: 'ID cannot be empty',
      field: 'id',
    ));
  }
  
  return resultOfAsync(
    () async => await api.getUser(id),
    (e, stackTrace) => NetworkError(
      message: 'Failed to load user',
      type: NetworkErrorType.sendFailed,
      details: e.toString(),
      stackTrace: stackTrace,
    ),
  );
}

// Caller (type-safe pattern matching)
final result = await loadUser(id);
switch (result) {
  case Success(value: final user):
    print('Loaded: ${user.name}');
  case Failure(error: final error):
    if (context.mounted) {
      context.handleError(error);  // Automatic UI feedback!
    }
}
```

---

### In UI Widgets

#### Option 1: Pattern Matching
```dart
Future<void> _loadData() async {
  final result = await ref.read(storageServiceProvider).loadData('key');
  
  if (!mounted) return;
  
  switch (result) {
    case Success(value: final data):
      setState(() => _data = data);
    case Failure(error: final error):
      context.handleError(error);  // Shows SnackBar automatically
  }
}
```

#### Option 2: Using fold()
```dart
await service.loadData('key').fold(
  onSuccess: (data) => setState(() => _data = data),
  onFailure: (error) {
    if (mounted) context.handleError(error);
  },
);
```

#### Option 3: Using Extension (Cleanest)
```dart
await context.handleAsync(
  service.loadData('key'),
  onSuccess: (data) => setState(() => _data = data),
  // Error automatically shown in SnackBar
);
```

#### With Retry Action
```dart
await context.handleAsync(
  service.sendMessage(recipientID, text),
  onSuccess: (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nachricht gesendet!')),
    );
  },
  onRetry: () => _sendMessage(),  // Retry button in SnackBar
);
```

---

### Chaining Operations

```dart
// Chain multiple operations - stops at first failure
Future<Result<String, AppError>> processData() async {
  return await cryptoService
      .generateKeyPair()  // Result<KeyPair, AppError>
      .flatMapAsync((keyPair) async {
        // Only runs if key generation succeeds
        return await storageService.saveKey(keyPair.privateKey);
      })
      .flatMapAsync((_) async {
        // Only runs if save succeeds
        return await storageService.loadKey();
      });
}

// Usage
final result = await processData();
context.handleResult(result);  // Shows error or success
```

---

### Error-Specific Handling

```dart
final result = await service.connectToRelay(relayAddr);

switch (result) {
  case Success():
    print('Connected!');
    
  case Failure(error: NetworkError(type: NetworkErrorType.timeout)):
    // Specific handling for timeout
    showDialog(...);
    
  case Failure(error: NetworkError(type: NetworkErrorType.noConnection)):
    // Specific handling for no connection
    _showOfflineMode();
    
  case Failure(error: final error):
    // Generic fallback
    context.handleError(error);
}
```

---

## 🧪 Testing

Error handling infrastructure is fully tested:

```bash
flutter test test/error_handling_test.dart
```

**26 Tests covering:**
- ✅ Error type creation and user messages
- ✅ Result type operations (map, flatMap, fold)
- ✅ Async operations
- ✅ Error chaining
- ✅ Collection utilities
- ✅ Pattern matching
- ✅ Real-world scenarios

---

## 📋 Migration Checklist

To migrate existing services to use Result type:

### 1. Update Interface
```dart
// Before
abstract class IMyService {
  Future<User> loadUser(String id);
}

// After
abstract class IMyService {
  Future<Result<User, AppError>> loadUser(String id);
}
```

### 2. Wrap Implementation
```dart
Future<Result<User, AppError>> loadUser(String id) async {
  // Validation checks
  if (id.isEmpty) {
    return Failure(ValidationError(...));
  }
  
  // Wrap async operation
  return resultOfAsync(
    () async {
      // Existing implementation here
      return await _fetchUser(id);
    },
    (exception, stackTrace) => AppErrorFactory.fromException(
      exception,
      stackTrace,
    ),
  );
}
```

### 3. Update Callers
```dart
// Before
try {
  final user = await service.loadUser(id);
  _handleSuccess(user);
} catch (e) {
  _handleError(e);
}

// After
await context.handleAsync(
  service.loadUser(id),
  onSuccess: (user) => _handleSuccess(user),
);
```

### 4. Update Tests
```dart
test('loadUser should return success', () async {
  final result = await service.loadUser('123');
  
  expect(result.isSuccess, isTrue);
  expect(result.valueOrNull?.id, equals('123'));
});

test('loadUser should return validation error', () async {
  final result = await service.loadUser('');
  
  expect(result.isFailure, isTrue);
  expect(result.errorOrNull, isA<ValidationError>());
});
```

---

## 🎨 UI Feedback

Error Handler automatically shows appropriate UI:

### SnackBar (Default)
- Color-coded by error type (orange for network, red for crypto)
- Icon based on error type
- Retry button for recoverable errors
- Auto-dismiss after 4 seconds

### Dialog (Critical Errors)
```dart
await context.showErrorDialog(
  error,
  title: 'Kritischer Fehler',
  onRetry: () => _retryOperation(),
);
```

---

## 🔍 Logging

All errors are automatically logged:

```
[ERROR] NetworkError: Connection timeout
Time: 2026-03-12T15:30:45.123Z
Details: SocketException: Connection refused
Stack Trace: #0 ...
```

**Integration Points:**
- Console logging (developer.log)
- File logging (TODO: implement)
- Crashlytics (TODO: uncomment in error_handler.dart)

---

## 🚀 Benefits

### Type Safety
- Compiler enforces error handling
- No silent failures
- Exhaustive pattern matching

### Consistency
- All errors follow same pattern
- Predictable user experience
- Centralized error handling

### Testability
- Easy to test error scenarios
- No try-catch in tests
- Mock-friendly

### Maintainability
- Single source of truth for errors
- Easy to add new error types
- Clear error type hierarchy

---

## 📚 Further Reading

- [Result Type Pattern](https://doc.rust-lang.org/std/result/)
- [Sealed Classes in Dart](https://dart.dev/language/class-modifiers#sealed)
- Migration guide: `lib/utils/result_migration_guide.dart`

---

## 🎯 Next Steps

1. **Migrate Services:**
   - Start with CryptoService (simple)
   - Then StorageService
   - Finally P2PService (more complex)

2. **Enhance UI:**
   - Add toast notifications for non-critical errors
   - Implement error page for fatal errors
   - Add error recovery suggestions

3. **Analytics:**
   - Enable Crashlytics integration
   - Track error rates per type
   - Monitor retry success rates

4. **Logging:**
   - Implement file-based logging
   - Add log rotation
   - Export logs feature for debugging
