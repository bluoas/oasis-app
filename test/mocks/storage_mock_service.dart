import 'dart:typed_data';
import '../../lib/models/message.dart';
import '../../lib/models/contact.dart';
import '../../lib/models/call.dart';
import '../../lib/models/app_error.dart';
import '../../lib/models/paginated_result.dart';
import '../../lib/utils/result.dart';
import '../../lib/services/interfaces/i_storage_service.dart';

/// Mock Storage Service for Testing
/// 
/// In-memory storage implementation without Hive dependencies
/// All data is stored in memory and cleared on reset
class StorageMockService implements IStorageService {
  final Map<String, Message> _messages = {};
  final Map<String, Contact> _contacts = {};
  final Map<String, Call> _calls = {};
  final Set<String> _readMessages = {};
  
  bool _isInitialized = false;
  
  // Configurable for testing error scenarios
  bool shouldFailInitialize = false;
  bool shouldFailSaveMessage = false;
  bool shouldFailSaveContact = false;
  
  // Track operations for verification
  int saveMessageCallCount = 0;
  int getMessageCallCount = 0;
  int saveContactCallCount = 0;
  int getContactCallCount = 0;

  @override
  Future<Result<void, AppError>> initialize() async {
    return resultOfAsync(
      () async {
        if (shouldFailInitialize) {
          throw Exception('Mock: Failed to initialize storage');
        }
        
        await Future.delayed(const Duration(milliseconds: 10));
        _isInitialized = true;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock initialization failed',
        type: StorageErrorType.initializationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== MESSAGES ====================

  @override
  Future<Result<void, AppError>> saveMessage(Message message) async {
    return resultOfAsync(
      () async {
        saveMessageCallCount++;
        
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        if (shouldFailSaveMessage) {
          throw Exception('Mock: Failed to save message');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        _messages[message.id] = message;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock save message failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<Message?, AppError>> getMessage(String id) async {
    return resultOfAsync(
      () async {
        getMessageCallCount++;
        
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        return _messages[id];
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get message failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Message>, AppError>> getMessagesForPeer(String peerID) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final messages = _messages.values
            .where((m) => m.senderPeerID == peerID || m.targetPeerID == peerID)
            .toList();
        
        // Sort by timestamp (oldest first)
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        return messages;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get messages for peer failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<PaginatedResult<Message>, AppError>> getMessagesForPeerPaginated(
    String peerID, {
    int page = 0,
    int pageSize = 50,
  }) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        // Validate parameters
        if (page < 0) {
          throw ArgumentError('Page must be >= 0');
        }
        if (pageSize <= 0) {
          throw ArgumentError('Page size must be > 0');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final allMessages = _messages.values
            .where((m) => m.senderPeerID == peerID || m.targetPeerID == peerID)
            .toList();
        
        // Sort by timestamp (oldest first)
        allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        final totalItems = allMessages.length;
        final startIndex = page * pageSize;
        final endIndex = (startIndex + pageSize).clamp(0, totalItems);
        
        final pageItems = startIndex < totalItems
            ? allMessages.sublist(startIndex, endIndex)
            : <Message>[];
        
        return PaginatedResult<Message>(
          items: pageItems,
          currentPage: page,
          pageSize: pageSize,
          totalItems: totalItems,
        );
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get paginated messages for peer failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Message>, AppError>> getAllMessages() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final messages = _messages.values.toList();
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        return messages;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get all messages failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Message>, AppError>> getMessagesForNetwork(String networkId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        await Future.delayed(const Duration(milliseconds: 5));
        final messages = _messages.values.toList();
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get messages for network failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> deleteMessage(String id) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        _messages.remove(id);
        _readMessages.remove(id);
      },
      (e, stackTrace) => StorageError(
        message: 'Mock delete message failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> markAsRead(String messageId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 2));
        
        final message = _messages[messageId];
        if (message != null) {
          // Update message to read status
          _messages[messageId] = Message(
            id: message.id,
            senderPeerID: message.senderPeerID,
            targetPeerID: message.targetPeerID,
            timestamp: message.timestamp,
            expiresAt: message.expiresAt,
            ciphertext: message.ciphertext,
            signature: message.signature,
            nonce: message.nonce,
            senderPublicKey: message.senderPublicKey,
            plaintext: message.plaintext,
            isRead: true,
          );
          _readMessages.add(messageId);
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Mock mark as read failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<int, AppError>> getUnreadCount(String peerID) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        
        return _messages.values
            .where((m) => 
                m.senderPeerID == peerID && 
                !m.isRead)
            .length;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get unread count failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<int, AppError>> deleteEncryptedMessages() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        // In the real implementation, encrypted messages are those that failed decryption
        // For mock, we'll just return 0 since we don't track this state
        return 0;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock delete encrypted messages failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== CONTACTS ====================

  @override
  Future<Result<void, AppError>> saveContact(Contact contact) async {
    return resultOfAsync(
      () async {
        saveContactCallCount++;
        
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        if (shouldFailSaveContact) {
          throw Exception('Mock: Failed to save contact');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        _contacts[contact.peerID] = contact;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock save contact failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<Contact?, AppError>> getContact(String peerID) async {
    return resultOfAsync(
      () async {
        getContactCallCount++;
        
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        return _contacts[peerID];
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get contact failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Contact>, AppError>> getAllContacts() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final contacts = _contacts.values.toList();
        
        // Sort by name
        contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        
        return contacts;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get all contacts failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Contact>, AppError>> getContactsForNetwork(String networkId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        await Future.delayed(const Duration(milliseconds: 5));
        final contacts = _contacts.values.toList();
        contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        return contacts;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get contacts for network failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> blockContact(String peerID) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final contact = _contacts[peerID];
        if (contact != null) {
          _contacts[peerID] = contact.copyWith(
            isBlocked: true,
            blockedAt: DateTime.now().toUtc(),
          );
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Mock block contact failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }
  
  @override
  Future<Result<void, AppError>> unblockContact(String peerID) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final contact = _contacts[peerID];
        if (contact != null) {
          _contacts[peerID] = contact.copyWith(
            isBlocked: false,
            blockedAt: null,
          );
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Mock unblock contact failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> updateContactPublicKey(String peerID, List<int> publicKey) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        
        final contact = _contacts[peerID];
        if (contact != null) {
          _contacts[peerID] = contact.copyWith(
            publicKey: Uint8List.fromList(publicKey),
          );
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Mock update contact public key failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> updateContactProfile(String peerID, {String? displayName, String? userName, String? profileImagePath, bool updateImage = false}) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        
        final contact = _contacts[peerID];
        if (contact != null) {
          _contacts[peerID] = contact.copyWith(
            displayName: displayName ?? contact.displayName,
            userName: userName ?? contact.userName,
            profileImagePath: updateImage ? profileImagePath : contact.profileImagePath,
          );
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Mock update contact profile failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== CALL HISTORY ====================

  @override
  Future<Result<void, AppError>> saveCall(Call call) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        _calls[call.id] = call;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock save call failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<Call?, AppError>> getCall(String callId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        return _calls[callId];
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get call failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Call>, AppError>> getAllCalls() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final calls = _calls.values.toList();
        // Sort by timestamp (newest first)
        calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return calls;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get all calls failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<List<Call>, AppError>> getCallsForContact(String contactId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        
        final calls = _calls.values
            .where((c) => c.contactId == contactId)
            .toList();
        // Sort by timestamp (newest first)
        calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return calls;
      },
      (e, stackTrace) => StorageError(
        message: 'Mock get calls for contact failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> deleteCall(String callId) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 3));
        _calls.remove(callId);
      },
      (e, stackTrace) => StorageError(
        message: 'Mock delete call failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> clearCallHistory() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        _calls.clear();
      },
      (e, stackTrace) => StorageError(
        message: 'Mock clear call history failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== NONCES ====================

  final Set<String> _seenNonces = {};

  @override
  Future<Result<bool, AppError>> hasSeenNonce(String nonceBase64) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 2));
        return _seenNonces.contains(nonceBase64);
      },
      (e, stackTrace) => StorageError(
        message: 'Mock has seen nonce failed',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> markNonceSeen(String nonceBase64) async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 2));
        _seenNonces.add(nonceBase64);
      },
      (e, stackTrace) => StorageError(
        message: 'Mock mark nonce seen failed',
        type: StorageErrorType.saveFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> cleanOldNonces() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 5));
        // Mock: In real implementation, would clean nonces older than 24h
        // Here we just clear all for simplicity
        _seenNonces.clear();
      },
      (e, stackTrace) => StorageError(
        message: 'Mock clean old nonces failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== UTILITY ====================

  @override
  Future<Result<void, AppError>> clearAll() async {
    return resultOfAsync(
      () async {
        if (!_isInitialized) {
          throw Exception('Mock: Storage not initialized');
        }
        
        await Future.delayed(const Duration(milliseconds: 10));
        _messages.clear();
        _contacts.clear();
        _calls.clear();
        _readMessages.clear();
        _seenNonces.clear();
      },
      (e, stackTrace) => StorageError(
        message: 'Mock clear all failed',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // Test helper method (not in interface)
  Future<void> close() async {
    await Future.delayed(const Duration(milliseconds: 5));
    _isInitialized = false;
  }
  
  // ==================== Test Helper Methods ====================
  
  /// Check if storage is initialized
  bool get isInitialized => _isInitialized;
  
  /// Get total message count
  int get messageCount => _messages.length;
  
  /// Get total contact count
  int get contactCount => _contacts.length;
  
  /// Reset all state and counters
  void reset() {
    _messages.clear();
    _contacts.clear();
    _calls.clear();
    _readMessages.clear();
    _seenNonces.clear();
    _isInitialized = false;
    
    shouldFailInitialize = false;
    shouldFailSaveMessage = false;
    shouldFailSaveContact = false;
    
    saveMessageCallCount = 0;
    getMessageCallCount = 0;
    saveContactCallCount = 0;
    getContactCallCount = 0;
  }
  
  /// Get all stored message IDs (for verification)
  List<String> get allMessageIds => _messages.keys.toList();
  
  /// Get all stored contact IDs (for verification)
  List<String> get allContactIds => _contacts.keys.toList();
}
