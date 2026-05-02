import '../../models/message.dart';
import '../../models/contact.dart';
import '../../models/call.dart';
import '../../models/app_error.dart';
import '../../models/paginated_result.dart';
import '../../utils/result.dart';

/// Storage Service Interface
/// 
/// Defines the contract for local storage operations
/// Implementations: StorageService (Hive), MockStorageService (for tests)
abstract class IStorageService {
  /// Initialize storage backend
  Future<Result<void, AppError>> initialize();

  // ==================== MESSAGES ====================
  
  /// Save a message to local storage
  Future<Result<void, AppError>> saveMessage(Message message);
  
  /// Get a message by ID
  Future<Result<Message?, AppError>> getMessage(String id);
  
  /// Get all messages for a specific peer (sorted by timestamp)
  Future<Result<List<Message>, AppError>> getMessagesForPeer(String peerID);
  
  /// Get messages for a specific peer with pagination
  /// [page]: 0-based page index
  /// [pageSize]: Number of messages per page
  /// Returns: PaginatedResult containing messages, metadata, and hasMore flag
  Future<Result<PaginatedResult<Message>, AppError>> getMessagesForPeerPaginated(
    String peerID, {
    int page = 0,
    int pageSize = 50,
  });
  
  /// Get all messages across all chats
  Future<Result<List<Message>, AppError>> getAllMessages();
  
  /// Get messages for a specific network (network separation)
  /// [networkId]: "public" for public network, or KM-Node PeerID for private networks
  Future<Result<List<Message>, AppError>> getMessagesForNetwork(String networkId);
  
  /// Delete a message by ID
  Future<Result<void, AppError>> deleteMessage(String id);
  
  /// Mark a message as read
  Future<Result<void, AppError>> markAsRead(String messageId);
  
  /// Get count of unread messages for a peer
  Future<Result<int, AppError>> getUnreadCount(String peerID);
  
  /// Delete all encrypted messages (failed decryption)
  Future<Result<int, AppError>> deleteEncryptedMessages();

  // ==================== CONTACTS ====================
  
  /// Save a contact
  Future<Result<void, AppError>> saveContact(Contact contact);
  
  /// Get a contact by PeerID
  Future<Result<Contact?, AppError>> getContact(String peerID);
  
  /// Get all contacts
  Future<Result<List<Contact>, AppError>> getAllContacts();
  
  /// Get contacts for a specific network (network separation)
  /// [networkId]: "public" for public network, or KM-Node PeerID for private networks
  Future<Result<List<Contact>, AppError>> getContactsForNetwork(String networkId);
  
  /// Block a contact (sets isBlocked flag)
  Future<Result<void, AppError>> blockContact(String peerID);
  
  /// Unblock a contact
  Future<Result<void, AppError>> unblockContact(String peerID);
  
  /// Update contact's public key
  Future<Result<void, AppError>> updateContactPublicKey(String peerID, List<int> publicKey);
  
  /// Update contact's profile (displayName, userName, and/or profile image)
  Future<Result<void, AppError>> updateContactProfile(String peerID, {String? displayName, String? userName, String? profileImagePath, bool updateImage = false});

  // ==================== NONCES ====================
  
  /// Check if a nonce has been seen (replay protection)
  Future<Result<bool, AppError>> hasSeenNonce(String nonceBase64);
  
  /// Mark a nonce as seen
  Future<Result<void, AppError>> markNonceSeen(String nonceBase64);
  
  /// Clean old nonces (older than 24h)
  Future<Result<void, AppError>> cleanOldNonces();

  // ==================== CALL HISTORY ====================
  
  /// Save or update a call in history
  Future<Result<void, AppError>> saveCall(Call call);
  
  /// Get a specific call by ID
  Future<Result<Call?, AppError>> getCall(String callId);
  
  /// Get all calls sorted by timestamp (newest first)
  Future<Result<List<Call>, AppError>> getAllCalls();
  
  /// Get calls for a specific contact
  Future<Result<List<Call>, AppError>> getCallsForContact(String contactId);
  
  /// Delete a call from history
  Future<Result<void, AppError>> deleteCall(String callId);
  
  /// Clear all call history
  Future<Result<void, AppError>> clearCallHistory();

  // ==================== UTILITY ====================
  
  /// Clear all data (for identity reset)
  Future<Result<void, AppError>> clearAll();
}
