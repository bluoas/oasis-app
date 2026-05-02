import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Contact model - PeerID mit Username
class Contact extends Equatable {
  final String peerID; // libp2p PeerID (z.B. 12D3KooWABC...)
  final String displayName; // Meine lokale Bezeichnung (editierbar, wird NICHT überschrieben)
  final String userName; // Peer's selbstgewählter Name (read-only, wird auto-updated)
  final String? avatarUrl; // Optional (remote URL)
  final String? profileImagePath; // Local profile image path
  final DateTime addedAt; // Wann hinzugefügt
  final Uint8List? publicKey; // Ed25519 public key for encryption
  final String? connectedNodeMultiaddr; // Multiaddr des Oasis Nodes, mit dem dieser Contact verbunden ist
  final DateTime? lastProfileUpdateSentAt; // Timestamp when last profile update was sent to this contact
  
  // Network Separation (CRITICAL for Privacy)
  final String networkId; // Which network this contact belongs to ("public" or KM-Node PeerID)
  
  // Block functionality
  final bool isBlocked; // Incoming messages from this contact are rejected
  final DateTime? blockedAt; // When contact was blocked
  final bool blockedByOther; // This contact has blocked me (received block notification)
  final DateTime? blockedByOtherAt; // When I was blocked by this contact
  final DateTime? lastReconnectAttemptAt; // Last time "Try Reconnecting" was used
  
  // KM-Node identification
  final bool isKMNodeContact; // True if this is the official Oasis Key Manager contact

  const Contact({
    required this.peerID,
    required this.displayName,
    required this.userName,
    this.avatarUrl,
    this.profileImagePath,
    required this.addedAt,
    this.publicKey,
    this.connectedNodeMultiaddr,
    this.lastProfileUpdateSentAt,
    this.networkId = 'public', // Default to public network for backward compatibility
    this.isBlocked = false,
    this.blockedAt,
    this.blockedByOther = false,
    this.blockedByOtherAt,
    this.lastReconnectAttemptAt,
    this.isKMNodeContact = false,
  });

  /// JSON Serialization für lokale Storage
  Map<String, dynamic> toJson() => {
        'peer_id': peerID,
        'display_name': displayName,
        'user_name': userName,
        'avatar_url': avatarUrl,
        'profile_image_path': profileImagePath,
        'added_at': addedAt.toIso8601String(),
        if (publicKey != null) 'public_key': base64Encode(publicKey!),
        if (connectedNodeMultiaddr != null) 'connected_node_multiaddr': connectedNodeMultiaddr,
        if (lastProfileUpdateSentAt != null) 'last_profile_update_sent_at': lastProfileUpdateSentAt!.toIso8601String(),
        'network_id': networkId, // Network separation field
        'is_blocked': isBlocked,
        if (blockedAt != null) 'blocked_at': blockedAt!.toIso8601String(),
        'blocked_by_other': blockedByOther,
        if (blockedByOtherAt != null) 'blocked_by_other_at': blockedByOtherAt!.toIso8601String(),
        if (lastReconnectAttemptAt != null) 'last_reconnect_attempt_at': lastReconnectAttemptAt!.toIso8601String(),
        'is_km_node_contact': isKMNodeContact,
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    // Migration: Support old 'name' field for backwards compatibility
    final oldName = json['name'] as String?;
    final displayName = json['display_name'] as String? ?? oldName ?? 'Unknown';
    final userName = json['user_name'] as String? ?? oldName ?? 'Unknown';
    
    // Migration: Support legacy contacts without network_id (default to "public")
    final networkId = json['network_id'] as String? ?? 'public';
    
    return Contact(
        peerID: json['peer_id'] as String,
        displayName: displayName,
        userName: userName,
        avatarUrl: json['avatar_url'] as String?,
        profileImagePath: json['profile_image_path'] as String?,
        addedAt: DateTime.parse(json['added_at'] as String),
        connectedNodeMultiaddr: json['connected_node_multiaddr'] as String?,
        publicKey: json['public_key'] != null ? base64Decode(json['public_key'] as String) : null,
        lastProfileUpdateSentAt: json['last_profile_update_sent_at'] != null 
            ? DateTime.parse(json['last_profile_update_sent_at'] as String) 
            : null,
        networkId: networkId,
        isBlocked: json['is_blocked'] as bool? ?? false,
        blockedAt: json['blocked_at'] != null ? DateTime.parse(json['blocked_at'] as String) : null,
        blockedByOther: json['blocked_by_other'] as bool? ?? false,
        blockedByOtherAt: json['blocked_by_other_at'] != null ? DateTime.parse(json['blocked_by_other_at'] as String) : null,
        lastReconnectAttemptAt: json['last_reconnect_attempt_at'] != null ? DateTime.parse(json['last_reconnect_attempt_at'] as String) : null,
        isKMNodeContact: json['is_km_node_contact'] as bool? ?? false,
      );
  }

  Contact copyWith({
    String? peerID,
    String? displayName,
    String? userName,
    String? avatarUrl,
    String? profileImagePath,
    DateTime? addedAt,
    Uint8List? publicKey,
    String? connectedNodeMultiaddr,
    DateTime? lastProfileUpdateSentAt,
    String? networkId,
    bool? isBlocked,
    DateTime? blockedAt,
    bool? blockedByOther,
    DateTime? blockedByOtherAt,
    DateTime? lastReconnectAttemptAt,
    bool? isKMNodeContact,
  }) =>
      Contact(
        peerID: peerID ?? this.peerID,
        displayName: displayName ?? this.displayName,
        userName: userName ?? this.userName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        profileImagePath: profileImagePath ?? this.profileImagePath,
        addedAt: addedAt ?? this.addedAt,
        publicKey: publicKey ?? this.publicKey,
        connectedNodeMultiaddr: connectedNodeMultiaddr ?? this.connectedNodeMultiaddr,
        lastProfileUpdateSentAt: lastProfileUpdateSentAt ?? this.lastProfileUpdateSentAt,
        networkId: networkId ?? this.networkId,
        isBlocked: isBlocked ?? this.isBlocked,
        blockedAt: blockedAt ?? this.blockedAt,
        blockedByOther: blockedByOther ?? this.blockedByOther,
        blockedByOtherAt: blockedByOtherAt ?? this.blockedByOtherAt,
        lastReconnectAttemptAt: lastReconnectAttemptAt ?? this.lastReconnectAttemptAt,
        isKMNodeContact: isKMNodeContact ?? this.isKMNodeContact,
      );

  @override
  List<Object?> get props => [peerID, displayName, userName, avatarUrl, profileImagePath, addedAt, publicKey, connectedNodeMultiaddr, lastProfileUpdateSentAt, networkId, isBlocked, blockedAt, blockedByOther, blockedByOtherAt, lastReconnectAttemptAt, isKMNodeContact];
}
