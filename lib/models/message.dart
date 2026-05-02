import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Content type for messages
enum ContentType {
  text,
  audio,
  image,
  file,
  contact,
  profile_update,
  call_signal,
  block_notification;

  String toJson() => name;
  
  static ContentType fromJson(String? value) {
    if (value == null || value.isEmpty) return ContentType.text;
    return ContentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ContentType.text,
    );
  }
}

/// Delivery status for offline message queue
enum DeliveryStatus {
  pending,   // Waiting to be sent to node
  sent,      // Successfully stored on node
  delivered, // Retrieved by recipient (future feature)
  failed;    // Sending failed

  String toJson() => name;
  
  static DeliveryStatus fromJson(String value) {
    return DeliveryStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DeliveryStatus.pending,
    );
  }
}

/// Message model für P2P Communication
/// Entspricht dem Format aus APP_INTEGRATION.MD
class Message extends Equatable {
  final String id; // UUID
  final String senderPeerID; // PeerID des Senders
  final String targetPeerID; // PeerID des Empfängers
  final DateTime timestamp; // Erstellungszeit
  final DateTime expiresAt; // Timestamp + TTL
  final Uint8List ciphertext; // E2E verschlüsselter Content
  final Uint8List signature; // Signatur über signable data
  final Uint8List nonce; // Replay-Protection
  final Uint8List? senderPublicKey; // Sender's public key (for decryption)
  final String? targetHomeNode; // Recipient's known home node multiaddr (for cross-node forwarding)
  final String? senderHomeNode; // Sender's current home node multiaddr (self-healing routing)
  final ContentType contentType; // Message content type
  final Map<String, String>? contentMeta; // Metadata (duration, filename, size, etc.)

  // Reply functionality
  final String? replyToMessageId; // ID of message being replied to
  final String? replyToPreviewText; // Preview text of original message
  final ContentType? replyToContentType; // Content type of original message

  // Local only - nicht über Netzwerk
  final String? plaintext; // Nach Decrypt
  final bool isRead; // UI State
  final DeliveryStatus deliveryStatus; // Offline queue status
  final String networkId; // Which network this message belongs to ("public" or KM-Node PeerID)

  const Message({
    required this.id,
    required this.senderPeerID,
    required this.targetPeerID,
    required this.timestamp,
    required this.expiresAt,
    required this.ciphertext,
    required this.signature,
    required this.nonce,
    this.senderPublicKey,
    this.targetHomeNode,
    this.senderHomeNode,
    this.contentType = ContentType.text,
    this.contentMeta,
    this.replyToMessageId,
    this.replyToPreviewText,
    this.replyToContentType,
    this.plaintext,
    this.isRead = false,
    this.deliveryStatus = DeliveryStatus.sent, // Default: already sent
    this.networkId = 'public', // Default to public network for backward compatibility
  });

  /// Daten für Signatur (muss mit Go Server übereinstimmen: Unix seconds)
  String get signableData =>
      '$id:$senderPeerID:$targetPeerID:${timestamp.toUtc().millisecondsSinceEpoch ~/ 1000}';

  /// JSON Serialization (für Relay-Protocol)
  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_peer_id': senderPeerID,
        'target_peer_id': targetPeerID,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'ciphertext': base64Encode(ciphertext),
        'signature': base64Encode(signature),
        'nonce': base64Encode(nonce),
        if (senderPublicKey != null) 'sender_public_key': base64Encode(senderPublicKey!),
        if (targetHomeNode != null) 'target_home_node': targetHomeNode,
        if (senderHomeNode != null) 'sender_home_node': senderHomeNode,
        if (contentType != ContentType.text) 'content_type': contentType.toJson(),
        if (contentMeta != null && contentMeta!.isNotEmpty) 'content_meta': contentMeta,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (replyToPreviewText != null) 'reply_to_preview_text': replyToPreviewText,
        if (replyToContentType != null) 'reply_to_content_type': replyToContentType!.toJson(),
        'network_id': networkId, // Network separation field
      };

  /// Local storage JSON (includes plaintext and isRead)
  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'sender_peer_id': senderPeerID,
        'target_peer_id': targetPeerID,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'ciphertext': base64Encode(ciphertext),
        'signature': base64Encode(signature),
        'nonce': base64Encode(nonce),
        if (senderPublicKey != null) 'sender_public_key': base64Encode(senderPublicKey!),
        if (targetHomeNode != null) 'target_home_node': targetHomeNode,
        if (senderHomeNode != null) 'sender_home_node': senderHomeNode,
        if (contentType != ContentType.text) 'content_type': contentType.toJson(),
        if (contentMeta != null && contentMeta!.isNotEmpty) 'content_meta': contentMeta,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (replyToPreviewText != null) 'reply_to_preview_text': replyToPreviewText,
        if (replyToContentType != null) 'reply_to_content_type': replyToContentType!.toJson(),
        if (plaintext != null) 'plaintext': plaintext,
        'isRead': isRead,
        'deliveryStatus': deliveryStatus.toJson(),
        'network_id': networkId, // Network separation field
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        senderPeerID: json['sender_peer_id'] as String,
        targetPeerID: json['target_peer_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        ciphertext: base64Decode(json['ciphertext'] as String),
        signature: base64Decode(json['signature'] as String),
        nonce: base64Decode(json['nonce'] as String),
        senderPublicKey: json['sender_public_key'] != null ? base64Decode(json['sender_public_key'] as String) : null,
        targetHomeNode: json['target_home_node'] as String?,
        senderHomeNode: json['sender_home_node'] as String?,
        contentType: ContentType.fromJson(json['content_type'] as String?),
        contentMeta: json['content_meta'] != null ? Map<String, String>.from(json['content_meta'] as Map) : null,
        replyToMessageId: json['reply_to_message_id'] as String?,
        replyToPreviewText: json['reply_to_preview_text'] as String?,
        replyToContentType: json['reply_to_content_type'] != null ? ContentType.fromJson(json['reply_to_content_type'] as String?) : null,
        networkId: json['network_id'] as String? ?? 'public', // Migration: default to public for legacy messages
      );

  /// Load from local storage (includes plaintext and isRead)
  factory Message.fromLocalJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        senderPeerID: json['sender_peer_id'] as String,
        targetPeerID: json['target_peer_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        ciphertext: base64Decode(json['ciphertext'] as String),
        signature: base64Decode(json['signature'] as String),
        nonce: base64Decode(json['nonce'] as String),
        senderPublicKey: json['sender_public_key'] != null ? base64Decode(json['sender_public_key'] as String) : null,
        targetHomeNode: json['target_home_node'] as String?,
        senderHomeNode: json['sender_home_node'] as String?,
        contentType: ContentType.fromJson(json['content_type'] as String?),
        contentMeta: json['content_meta'] != null ? Map<String, String>.from(json['content_meta'] as Map) : null,
        replyToMessageId: json['reply_to_message_id'] as String?,
        replyToPreviewText: json['reply_to_preview_text'] as String?,
        replyToContentType: json['reply_to_content_type'] != null ? ContentType.fromJson(json['reply_to_content_type'] as String?) : null,
        plaintext: json['plaintext'] as String?,
        deliveryStatus: json['deliveryStatus'] != null 
            ? DeliveryStatus.fromJson(json['deliveryStatus'] as String)
            : DeliveryStatus.sent,
        isRead: json['isRead'] as bool? ?? false,
        networkId: json['network_id'] as String? ?? 'public', // Migration: default to public for legacy messages
      );

  /// Binary encoding (für Direct P2P Protocol)
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory Message.fromBytes(Uint8List bytes) =>
      Message.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  /// Copy with für Updates
  Message copyWith({
    String? id,
    String? senderPeerID,
    String? targetPeerID,
    DateTime? timestamp,
    DateTime? expiresAt,
    Uint8List? ciphertext,
    Uint8List? signature,
    Uint8List? nonce,
    Uint8List? senderPublicKey,
    String? targetHomeNode,
    String? senderHomeNode,
    ContentType? contentType,
    Map<String, String>? contentMeta,
    String? replyToMessageId,
    String? replyToPreviewText,
    ContentType? replyToContentType,
    String? plaintext,
    bool? isRead,
    DeliveryStatus? deliveryStatus,
    String? networkId,
  }) =>
      Message(
        id: id ?? this.id,
        senderPeerID: senderPeerID ?? this.senderPeerID,
        targetPeerID: targetPeerID ?? this.targetPeerID,
        timestamp: timestamp ?? this.timestamp,
        expiresAt: expiresAt ?? this.expiresAt,
        ciphertext: ciphertext ?? this.ciphertext,
        signature: signature ?? this.signature,
        nonce: nonce ?? this.nonce,
        senderPublicKey: senderPublicKey ?? this.senderPublicKey,
        targetHomeNode: targetHomeNode ?? this.targetHomeNode,
        senderHomeNode: senderHomeNode ?? this.senderHomeNode,
        contentType: contentType ?? this.contentType,
        contentMeta: contentMeta ?? this.contentMeta,
        replyToMessageId: replyToMessageId ?? this.replyToMessageId,
        replyToPreviewText: replyToPreviewText ?? this.replyToPreviewText,
        replyToContentType: replyToContentType ?? this.replyToContentType,
        plaintext: plaintext ?? this.plaintext,
        isRead: isRead ?? this.isRead,
        deliveryStatus: deliveryStatus ?? this.deliveryStatus,
        networkId: networkId ?? this.networkId,
      );

  @override
  List<Object?> get props => [
        id,
        senderPeerID,
        targetPeerID,
        timestamp,
        expiresAt,
        ciphertext,
        signature,
        nonce,
        senderPublicKey,
        targetHomeNode,
        senderHomeNode,
        contentType,
        contentMeta,
        replyToMessageId,
        replyToPreviewText,
        replyToContentType,
        plaintext,
        isRead,
        deliveryStatus,
        networkId,
      ];
}
