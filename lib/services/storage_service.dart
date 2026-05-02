import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message.dart';
import '../models/contact.dart';
import '../models/call.dart';
import '../models/app_error.dart';
import '../models/paginated_result.dart';
import '../utils/result.dart';
import 'interfaces/i_storage_service.dart';
import '../utils/logger.dart';

/// Storage Service - Lokale Persistenz mit Hive
/// 
/// Boxes:
/// - messages: Alle empfangenen/gesendeten Messages
/// - contacts: Kontaktliste (PeerID → Name)
/// - nonces: Replay-Protection (bereits gesehene Nonces)
/// - calls: Call History (gespeicherte Anrufe)
/// 
/// All boxes are encrypted at rest using HiveAesCipher with a 256-bit key
/// stored securely in Flutter Secure Storage
class StorageService implements IStorageService {
  // Singleton pattern removed - now managed by Riverpod
  StorageService();

  static const _messagesBox = 'messages';
  static const _contactsBox = 'contacts';
  static const _noncesBox = 'nonces';
  static const _callsBox = 'calls';
  static const _encryptionKeyStorageKey = 'hive_encryption_key';
  static const _migrationCompleteKey = 'hive_migration_complete';

  final _secureStorage = const FlutterSecureStorage();
  bool _initialized = false;
  
  // Cache to avoid excessive Hive iterations
  Map<String, Message>? _messagesCache;
  Map<String, Contact>? _contactsCache;
  DateTime? _messagesCacheTime;
  DateTime? _contactsCacheTime;
  static const _cacheValidDuration = Duration(seconds: 2);

  /// Get or generate encryption key for Hive boxes
  /// 
  /// Returns a 256-bit (32 byte) key stored securely in Flutter Secure Storage
  Future<Uint8List> _getOrCreateEncryptionKey() async {
    try {
      // Try to load existing key
      final existingKey = await _secureStorage.read(key: _encryptionKeyStorageKey);
      
      if (existingKey != null) {
        final keyBytes = base64Decode(existingKey);
        if (keyBytes.length == 32) {
          Logger.debug('🔐 Loaded existing Hive encryption key');
          return Uint8List.fromList(keyBytes);
        }
        Logger.warning('⚠️ Existing key has invalid length, generating new key');
      }

      // Generate new 256-bit key
      final random = Random.secure();
      final key = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      
      // Store securely
      await _secureStorage.write(
        key: _encryptionKeyStorageKey,
        value: base64Encode(key),
      );
      
      Logger.success('🔐 Generated new Hive encryption key (256-bit)');
      return key;
    } catch (e) {
      throw Exception('Failed to get or create encryption key: $e');
    }
  }

  /// Initialize Hive with encryption
  @override
  Future<Result<void, AppError>> initialize() async {
    return resultOfAsync(
      () async {
        if (_initialized) return;

        await Hive.initFlutter();
        
        // Get or generate encryption key
        final encryptionKey = await _getOrCreateEncryptionKey();
        final encryptionCipher = HiveAesCipher(encryptionKey);
        
        // Check if migration was already completed
        final migrationComplete = await _secureStorage.read(key: _migrationCompleteKey);
        
        if (migrationComplete != 'true') {
          // First time with encryption - migrate data from unencrypted boxes
          Logger.info('🔄 First time with encryption - checking for data to migrate...');
          await _migrateToEncryptedBoxes(encryptionCipher);
          
          // Mark migration as complete
          await _secureStorage.write(key: _migrationCompleteKey, value: 'true');
          Logger.success('✅ Migration complete - future starts will skip migration');
        } else {
          Logger.debug('✓ Migration already completed, opening encrypted boxes...');
        }
        
        // Open boxes with encryption
        if (!Hive.isBoxOpen(_messagesBox)) {
          await Hive.openBox(_messagesBox, encryptionCipher: encryptionCipher);
        }
        if (!Hive.isBoxOpen(_contactsBox)) {
          await Hive.openBox(_contactsBox, encryptionCipher: encryptionCipher);
        }
        if (!Hive.isBoxOpen(_noncesBox)) {
          await Hive.openBox(_noncesBox, encryptionCipher: encryptionCipher);
        }
        if (!Hive.isBoxOpen(_callsBox)) {
          await Hive.openBox(_callsBox, encryptionCipher: encryptionCipher);
        }

        _initialized = true;
        Logger.success('✅ Storage initialized with encryption');
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to initialize storage',
        type: StorageErrorType.initializationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Migrate data from old unencrypted boxes to encrypted boxes
  /// 
  /// This method ONLY runs ONCE on the first start after encryption was added.
  /// It preserves user data by copying from unencrypted boxes to encrypted boxes.
  /// 
  /// CRITICAL: This must NEVER attempt to open already-encrypted boxes without cipher!
  Future<void> _migrateToEncryptedBoxes(HiveAesCipher cipher) async {
    try {
      final boxes = [_messagesBox, _contactsBox, _noncesBox, _callsBox];
      int totalMigrated = 0;
      
      for (final boxName in boxes) {
        // Check if box file exists
        if (!await Hive.boxExists(boxName)) {
          Logger.debug('  Box "$boxName" does not exist - skipping');
          continue;
        }
        
        try {
          Box? oldBox;
          Map<dynamic, dynamic>? oldData;
          bool needsMigration = false;
          
          // SAFE CHECK: Try to open WITHOUT encryption
          // This will ONLY succeed if the box is truly unencrypted
          try {
            oldBox = await Hive.openBox(boxName);
            
            // Successfully opened without cipher = unencrypted box
            needsMigration = true;
            
            if (oldBox.isNotEmpty) {
              Logger.info('📦 Found unencrypted "$boxName" with ${oldBox.length} items');
              
              // Read all data into memory
              oldData = Map<dynamic, dynamic>.from(oldBox.toMap());
            } else {
              Logger.debug('  Box "$boxName" is empty');
            }
            
            // Close the old box
            await oldBox.close();
            
          } catch (openError) {
            // Failed to open without cipher - box is either:
            // 1. Already encrypted (good!)
            // 2. Corrupted (bad, but we'll handle it)
            
            Logger.debug('  Box "$boxName" cannot be opened without cipher (already encrypted or corrupted)');
            needsMigration = false;
          }
          
          if (needsMigration && oldData != null && oldData.isNotEmpty) {
            // Delete old unencrypted box
            await Hive.deleteBoxFromDisk(boxName);
            Logger.debug('🗑️  Deleted old unencrypted "$boxName"');
            
            // Create new encrypted box
            final newBox = await Hive.openBox(boxName, encryptionCipher: cipher);
            
            // Write all data to encrypted box
            await newBox.putAll(oldData);
            
            Logger.success('✅ Migrated ${oldData.length} items to encrypted "$boxName"');
            totalMigrated += oldData.length;
            
          } else if (needsMigration && (oldData == null || oldData.isEmpty)) {
            // Empty unencrypted box - just delete and create encrypted
            await Hive.deleteBoxFromDisk(boxName);
            await Hive.openBox(boxName, encryptionCipher: cipher);
            Logger.debug('  Created new encrypted "$boxName" (was empty)');
          }
          
        } catch (e) {
          Logger.warning('⚠️ Error processing box "$boxName": $e');
          
          // If something went wrong, try to delete corrupted box and create fresh encrypted one
          try {
            if (await Hive.boxExists(boxName)) {
              await Hive.deleteBoxFromDisk(boxName);
            }
            await Hive.openBox(boxName, encryptionCipher: cipher);
            Logger.info('  Created fresh encrypted "$boxName" after error');
          } catch (recoveryError) {
            Logger.error('Failed to recover box "$boxName"', recoveryError);
          }
        }
      }
      
      if (totalMigrated > 0) {
        Logger.success('🎉 Migration complete: $totalMigrated items preserved!');
      } else {
        Logger.info('✓ No data to migrate (fresh install or already migrated)');
      }
      
    } catch (e) {
      Logger.error('Migration failed', e);
    }
  }

  // ==================== MESSAGES ====================

  /// Save message
  @override
  Future<Result<void, AppError>> saveMessage(Message message) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_messagesBox);
        await box.put(message.id, jsonEncode(message.toLocalJson()));
        
        // Invalidate cache
        _messagesCache = null;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to save message',
        type: StorageErrorType.saveFailed,
        details: 'Message ID: ${message.id}, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get message by ID
  @override
  Future<Result<Message?, AppError>> getMessage(String id) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_messagesBox);
        final data = box.get(id);
        if (data == null) return null;
        return Message.fromLocalJson(jsonDecode(data as String) as Map<String, dynamic>);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get message',
        type: StorageErrorType.loadFailed,
        details: 'Message ID: $id, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get all messages for a peer (sorted by timestamp) - Uses cache
  @override
  Future<Result<List<Message>, AppError>> getMessagesForPeer(String peerID) async {
    return resultOfAsync(
      () async {
        // Use cached getAllMessages instead of iterating again
        final result = await getAllMessages();
        final allMessages = result.valueOrNull ?? [];
        
        // Filter for this peer
        final messages = allMessages
            .where((message) =>
                message.senderPeerID == peerID || message.targetPeerID == peerID)
            .toList();

        // Already sorted by getAllMessages
        return messages;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get messages for peer',
        type: StorageErrorType.loadFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get messages for a peer with pagination - Uses cache
  @override
  Future<Result<PaginatedResult<Message>, AppError>> getMessagesForPeerPaginated(
    String peerID, {
    int page = 0,
    int pageSize = 50,
  }) async {
    return resultOfAsync(
      () async {
        // Validate parameters
        if (page < 0) {
          throw ArgumentError('Page must be >= 0, got: $page');
        }
        if (pageSize <= 0) {
          throw ArgumentError('Page size must be > 0, got: $pageSize');
        }

        // Use cached getAllMessages
        final result = await getAllMessages();
        final allMessages = result.valueOrNull ?? [];
        
        // Filter for this peer (and exclude key exchange requests)
        final peerMessages = allMessages
            .where((message) {
              // Skip key exchange requests (not real chat messages)
              try {
                final ciphertextStr = utf8.decode(message.ciphertext);
                if (ciphertextStr == 'KEY_EXCHANGE_REQUEST') return false;
              } catch (_) {
                // Not a key exchange (ciphertext is encrypted), include it
              }
              return message.senderPeerID == peerID || message.targetPeerID == peerID;
            })
            .toList();

        // Total items
        final totalItems = peerMessages.length;

        // Calculate pagination bounds
        final startIndex = page * pageSize;
        final endIndex = (startIndex + pageSize).clamp(0, totalItems);

        // Extract page slice
        final pageItems = startIndex < totalItems
            ? peerMessages.sublist(startIndex, endIndex)
            : <Message>[];

        // Return paginated result
        return PaginatedResult<Message>(
          items: pageItems,
          currentPage: page,
          pageSize: pageSize,
          totalItems: totalItems,
        );
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get paginated messages for peer',
        type: StorageErrorType.loadFailed,
        details: 'Peer ID: $peerID, Page: $page, PageSize: $pageSize, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get all messages (for all chats) - CACHED
  @override
  Future<Result<List<Message>, AppError>> getAllMessages() async {
    return resultOfAsync(
      () async {
        // Check cache
        if (_messagesCache != null && _messagesCacheTime != null) {
          if (DateTime.now().difference(_messagesCacheTime!) < _cacheValidDuration) {
            return _messagesCache!.values.toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          }
        }
        
        // Cache miss or expired - reload
        final box = Hive.box(_messagesBox);
        final messages = <String, Message>{};

        for (final key in box.keys) {
          final data = box.get(key) as String?;
          if (data == null) continue;

          try {
            final message = Message.fromLocalJson(
              jsonDecode(data) as Map<String, dynamic>,
            );
            messages[message.id] = message;
          } catch (e) {
            // Skip invalid messages
            continue;
          }
        }

        // Update cache
        _messagesCache = messages;
        _messagesCacheTime = DateTime.now();

        final result = messages.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return result;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get all messages',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get messages for a specific network (network separation)
  @override
  Future<Result<List<Message>, AppError>> getMessagesForNetwork(String networkId) async {
    return resultOfAsync(
      () async {
        // Get all messages first (uses cache)
        final allMessagesResult = await getAllMessages();
        if (allMessagesResult.isFailure) {
          throw Exception('Failed to load messages: ${allMessagesResult.errorOrNull?.userMessage}');
        }
        
        final allMessages = allMessagesResult.valueOrNull ?? [];
        
        // Filter by networkId
        final filteredMessages = allMessages
            .where((message) => message.networkId == networkId)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return filteredMessages;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get messages for network',
        type: StorageErrorType.loadFailed,
        details: 'Network ID: $networkId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Delete message
  @override
  Future<Result<void, AppError>> deleteMessage(String id) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_messagesBox);
        await box.delete(id);
        
        // Invalidate cache
        _messagesCache?.remove(id);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to delete message',
        type: StorageErrorType.deleteFailed,
        details: 'Message ID: $id, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Mark message as read
  @override
  Future<Result<void, AppError>> markAsRead(String messageId) async {
    return resultOfAsync(
      () async {
        final messageResult = await getMessage(messageId);
        final message = messageResult.valueOrNull;
        if (message == null) return;

        final updated = message.copyWith(isRead: true);
        final saveResult = await saveMessage(updated);
        if (saveResult.isFailure) {
          throw Exception('Failed to save updated message');
        }
        
        // Update cache directly if exists
        if (_messagesCache != null) {
          _messagesCache![messageId] = updated;
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to mark message as read',
        type: StorageErrorType.saveFailed,
        details: 'Message ID: $messageId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get unread count for peer
  @override
  Future<Result<int, AppError>> getUnreadCount(String peerID) async {
    return resultOfAsync(
      () async {
        final messagesResult = await getMessagesForPeer(peerID);
        final messages = messagesResult.valueOrNull ?? [];
        return messages.where((m) => !m.isRead && m.senderPeerID == peerID).length;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get unread count',
        type: StorageErrorType.loadFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== CONTACTS ====================

  /// Save contact
  @override
  Future<Result<void, AppError>> saveContact(Contact contact) async {
    return resultOfAsync(
      () async {
        if (!_initialized) {
          throw StorageError(
            message: 'Storage not initialized',
            type: StorageErrorType.saveFailed,
          );
        }
        
        final box = Hive.box(_contactsBox);
        await box.put(contact.peerID, jsonEncode(contact.toJson()));
        
        // Invalidate cache
        _contactsCache = null;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to save contact',
        type: StorageErrorType.saveFailed,
        details: 'Contact: ${contact.displayName}, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get contact by PeerID
  @override
  Future<Result<Contact?, AppError>> getContact(String peerID) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_contactsBox);
        final data = box.get(peerID);
        if (data == null) return null;
        return Contact.fromJson(jsonDecode(data as String) as Map<String, dynamic>);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get contact',
        type: StorageErrorType.loadFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get all contacts - CACHED
  @override
  Future<Result<List<Contact>, AppError>> getAllContacts() async {
    return resultOfAsync(
      () async {
        // Check cache
        if (_contactsCache != null && _contactsCacheTime != null) {
          if (DateTime.now().difference(_contactsCacheTime!) < _cacheValidDuration) {
            return _contactsCache!.values.toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName));
          }
        }
        
        // Cache miss or expired - reload
        final box = Hive.box(_contactsBox);
        final contacts = <String, Contact>{};

        for (final key in box.keys) {
          final data = box.get(key) as String?;
          if (data == null) continue;

          try {
            final contact = Contact.fromJson(
              jsonDecode(data) as Map<String, dynamic>,
            );
            contacts[contact.peerID] = contact;
          } catch (e) {
            // Skip invalid contacts
            continue;
          }
        }

        // Update cache
        _contactsCache = contacts;
        _contactsCacheTime = DateTime.now();

        // Sort by name
        final result = contacts.values.toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        return result;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get all contacts',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get contacts for a specific network (network separation)
  @override
  Future<Result<List<Contact>, AppError>> getContactsForNetwork(String networkId) async {
    return resultOfAsync(
      () async {
        // Get all contacts first (uses cache)
        final allContactsResult = await getAllContacts();
        if (allContactsResult.isFailure) {
          throw Exception('Failed to load contacts: ${allContactsResult.errorOrNull?.userMessage}');
        }
        
        final allContacts = allContactsResult.valueOrNull ?? [];
        
        // Filter by networkId
        final filteredContacts = allContacts
            .where((contact) => contact.networkId == networkId)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        
        return filteredContacts;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get contacts for network',
        type: StorageErrorType.loadFailed,
        details: 'Network ID: $networkId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Update contact's public key
  Future<Result<void, AppError>> updateContactPublicKey(String peerID, List<int> publicKey) async {
    return resultOfAsync(
      () async {
        final contactResult = await getContact(peerID);
        final contact = contactResult.valueOrNull;
        if (contact == null) {
          throw Exception('Contact not found: $peerID');
        }
        
        final updated = contact.copyWith(publicKey: Uint8List.fromList(publicKey));
        final saveResult = await saveContact(updated);
        if (saveResult.isFailure) {
          throw Exception('Failed to save updated contact');
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to update contact public key',
        type: StorageErrorType.saveFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }
  
  @override
  /// Update contact's profile (name and/or profile image)
  Future<Result<void, AppError>> updateContactProfile(String peerID, {String? displayName, String? userName, String? profileImagePath, bool updateImage = false}) async {
    return resultOfAsync(
      () async {
        final contactResult = await getContact(peerID);
        final contact = contactResult.valueOrNull;
        if (contact == null) {
          throw Exception('Contact not found: $peerID');
        }
        
        final updated = contact.copyWith(
          displayName: displayName ?? contact.displayName,
          userName: userName ?? contact.userName,
          profileImagePath: updateImage ? profileImagePath : contact.profileImagePath,
        );
        final saveResult = await saveContact(updated);
        if (saveResult.isFailure) {
          throw Exception('Failed to save updated contact');
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to update contact profile',
        type: StorageErrorType.saveFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Block contact
  @override
  Future<Result<void, AppError>> blockContact(String peerID) async {
    return resultOfAsync(
      () async {
        final contactResult = await getContact(peerID);
        if (contactResult.isFailure) {
          throw Exception('Contact not found');
        }
        
        final contact = contactResult.valueOrNull;
        if (contact == null) {
          throw Exception('Contact not found');
        }
        
        // Block: Set isBlocked flag and timestamp
        final blockedContact = contact.copyWith(
          isBlocked: true,
          blockedAt: DateTime.now().toUtc(),
        );
        
        final box = Hive.box(_contactsBox);
        await box.put(peerID, jsonEncode(blockedContact.toJson()));
        
        // Invalidate cache
        _contactsCache?.remove(peerID);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to block contact',
        type: StorageErrorType.saveFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }
  
  /// Unblock contact
  @override
  Future<Result<void, AppError>> unblockContact(String peerID) async {
    return resultOfAsync(
      () async {
        final contactResult = await getContact(peerID);
        if (contactResult.isFailure) {
          throw Exception('Contact not found');
        }
        
        final contact = contactResult.valueOrNull;
        if (contact == null) {
          throw Exception('Contact not found');
        }
        
        // Unblock: Clear isBlocked flag
        final unblockedContact = contact.copyWith(
          isBlocked: false,
          blockedAt: null,
        );
        
        final box = Hive.box(_contactsBox);
        await box.put(peerID, jsonEncode(unblockedContact.toJson()));
        
        // Invalidate cache
        _contactsCache?.remove(peerID);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to unblock contact',
        type: StorageErrorType.saveFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Check if contact exists
  Future<Result<bool, AppError>> hasContact(String peerID) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_contactsBox);
        return box.containsKey(peerID);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to check contact existence',
        type: StorageErrorType.loadFailed,
        details: 'Peer ID: $peerID, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== NONCES (Replay Protection) ====================

  /// Check if nonce was already seen
  @override
  Future<Result<bool, AppError>> hasSeenNonce(String nonce) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_noncesBox);
        return box.containsKey(nonce);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to check nonce',
        type: StorageErrorType.loadFailed,
        details: 'Nonce: $nonce, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Mark nonce as seen
  @override
  Future<Result<void, AppError>> markNonceSeen(String nonce) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_noncesBox);
        await box.put(nonce, DateTime.now().millisecondsSinceEpoch);
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to mark nonce as seen',
        type: StorageErrorType.saveFailed,
        details: 'Nonce: $nonce, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Clean old nonces (older than 24h)
  @override
  Future<Result<void, AppError>> cleanOldNonces() async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_noncesBox);
        final now = DateTime.now().millisecondsSinceEpoch;
        final dayInMs = 24 * 60 * 60 * 1000;

        final toDelete = <String>[];
        for (final key in box.keys) {
          final timestamp = box.get(key) as int?;
          if (timestamp != null && now - timestamp > dayInMs) {
            toDelete.add(key as String);
          }
        }

        for (final key in toDelete) {
          await box.delete(key);
        }

        if (toDelete.isNotEmpty) {
          Logger.info('🧹 Cleaned ${toDelete.length} old nonces');
        }
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to clean old nonces',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== CALL HISTORY ====================

  /// Save or update a call in history
  @override
  Future<Result<void, AppError>> saveCall(Call call) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        await box.put(call.id, call.toJson());
        Logger.debug('📞 Call saved to history: ${call.id} (${call.state.name})');
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to save call',
        type: StorageErrorType.saveFailed,
        details: 'Call ID: ${call.id}, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get a specific call by ID
  @override
  Future<Result<Call?, AppError>> getCall(String callId) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        final data = box.get(callId);
        if (data == null) return null;
        return Call.fromJson(Map<String, dynamic>.from(data as Map));
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get call',
        type: StorageErrorType.loadFailed,
        details: 'Call ID: $callId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get all calls sorted by timestamp (newest first)
  @override
  Future<Result<List<Call>, AppError>> getAllCalls() async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        final calls = <Call>[];
        
        for (final key in box.keys) {
          final data = box.get(key);
          if (data != null) {
            try {
              calls.add(Call.fromJson(Map<String, dynamic>.from(data as Map)));
            } catch (e) {
              Logger.warning('Failed to parse call $key: $e');
            }
          }
        }
        
        // Sort by timestamp (newest first)
        calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return calls;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get all calls',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get calls for a specific contact
  @override
  Future<Result<List<Call>, AppError>> getCallsForContact(String contactId) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        final calls = <Call>[];
        
        for (final key in box.keys) {
          final data = box.get(key);
          if (data != null) {
            try {
              final call = Call.fromJson(Map<String, dynamic>.from(data as Map));
              if (call.contactId == contactId) {
                calls.add(call);
              }
            } catch (e) {
              Logger.warning('Failed to parse call $key: $e');
            }
          }
        }
        
        // Sort by timestamp (newest first)
        calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        return calls;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get calls for contact',
        type: StorageErrorType.loadFailed,
        details: 'Contact ID: $contactId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Delete a call from history
  @override
  Future<Result<void, AppError>> deleteCall(String callId) async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        await box.delete(callId);
        Logger.debug('📞 Call deleted from history: $callId');
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to delete call',
        type: StorageErrorType.deleteFailed,
        details: 'Call ID: $callId, Error: $e',
        stackTrace: stackTrace,
      ),
    );
  }

  /// Clear all call history
  @override
  Future<Result<void, AppError>> clearCallHistory() async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_callsBox);
        await box.clear();
        Logger.info('🧹 Call history cleared');
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to clear call history',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // ==================== UTILITY ====================

  /// Clear all data (for testing/reset)
  @override
  Future<Result<void, AppError>> clearAll() async {
    return resultOfAsync(
      () async {
        await Hive.box(_messagesBox).clear();
        await Hive.box(_contactsBox).clear();
        await Hive.box(_noncesBox).clear();
        
        // Clear caches
        _messagesCache = null;
        _contactsCache = null;
        _messagesCacheTime = null;
        _contactsCacheTime = null;
        
        Logger.success('🗑️ All storage cleared');
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to clear all data',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Delete all messages that failed to decrypt (show as [Encrypted])
  @override
  Future<Result<int, AppError>> deleteEncryptedMessages() async {
    return resultOfAsync(
      () async {
        final box = Hive.box(_messagesBox);
        final toDelete = <dynamic>[];
        
        for (var key in box.keys) {
          final data = box.get(key) as String?;
          if (data == null) continue;
          
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (json['plaintext'] == null) {
            toDelete.add(key);
          }
        }
        
        for (var key in toDelete) {
          await box.delete(key);
        }
        
        Logger.info('🗑️ Deleted ${toDelete.length} encrypted messages');
        return toDelete.length;
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to delete encrypted messages',
        type: StorageErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Get storage stats
  Future<Result<Map<String, int>, AppError>> getStats() async {
    return resultOfAsync(
      () async {
        return {
          'messages': Hive.box(_messagesBox).length,
          'contacts': Hive.box(_contactsBox).length,
          'nonces': Hive.box(_noncesBox).length,
        };
      },
      (e, stackTrace) => StorageError(
        message: 'Failed to get storage stats',
        type: StorageErrorType.loadFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }
}
