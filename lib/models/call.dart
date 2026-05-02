import 'package:equatable/equatable.dart';

/// Call Type - Audio or Video
enum CallType {
  audio,
  video;

  String get displayName {
    switch (this) {
      case CallType.audio:
        return 'Audio Call';
      case CallType.video:
        return 'Video Call';
    }
  }
}

/// Call Direction - Incoming or Outgoing
enum CallDirection {
  incoming,
  outgoing;

  bool get isIncoming => this == CallDirection.incoming;
  bool get isOutgoing => this == CallDirection.outgoing;
}

/// Call State - Lifecycle of a call
enum CallState {
  /// Call is being initiated (outgoing)
  initiating,
  
  /// Call is ringing (incoming/outgoing)
  ringing,
  
  /// Call is being connected (WebRTC negotiation)
  connecting,
  
  /// Call is active (audio/video streaming)
  connected,
  
  /// Call is being terminated
  ending,
  
  /// Call has ended normally
  ended,
  
  /// Call was rejected by remote peer
  rejected,
  
  /// Call was missed (no answer)
  missed,
  
  /// Call failed (network error, etc.)
  failed;

  bool get isActive => this == CallState.connected;
  bool get isRinging => this == CallState.ringing;
  bool get isEnded => this == CallState.ended || 
                      this == CallState.rejected || 
                      this == CallState.missed || 
                      this == CallState.failed;
}

/// Call Model - Represents a voice/video call session
class Call extends Equatable {
  final String id;
  final String contactId; // PeerID of the contact
  final String contactName;
  final CallType type;
  final CallDirection direction;
  final CallState state;
  final DateTime timestamp;
  final Duration? duration;
  final bool isMuted;
  final bool isSpeakerOn;
  
  /// Multiaddr of the Oasis Node to route signals through
  final String? connectedNodeMultiaddr;
  
  /// WebRTC session description (SDP)
  final String? localSDP;
  final String? remoteSDP;
  
  /// ICE Candidates (JSON array)
  final List<Map<String, dynamic>>? iceCandidates;

  const Call({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.type,
    required this.direction,
    required this.state,
    required this.timestamp,
    this.duration,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.connectedNodeMultiaddr,
    this.localSDP,
    this.remoteSDP,
    this.iceCandidates,
  });

  /// Create a new outgoing call
  factory Call.outgoing({
    required String id,
    required String contactId,
    required String contactName,
    required CallType type,
    String? connectedNodeMultiaddr,
  }) {
    return Call(
      id: id,
      contactId: contactId,
      contactName: contactName,
      type: type,
      direction: CallDirection.outgoing,
      state: CallState.initiating,
      timestamp: DateTime.now(),
      connectedNodeMultiaddr: connectedNodeMultiaddr,
    );
  }

  /// Create a new incoming call
  factory Call.incoming({
    required String id,
    required String contactId,
    required String contactName,
    required CallType type,
    String? remoteSDP,
    String? connectedNodeMultiaddr,
  }) {
    return Call(
      id: id,
      contactId: contactId,
      contactName: contactName,
      type: type,
      direction: CallDirection.incoming,
      state: CallState.ringing,
      timestamp: DateTime.now(),
      remoteSDP: remoteSDP,
      connectedNodeMultiaddr: connectedNodeMultiaddr,
    );
  }

  /// Copy with updated fields
  Call copyWith({
    String? id,
    String? contactId,
    String? contactName,
    CallType? type,
    CallDirection? direction,
    CallState? state,
    DateTime? timestamp,
    Duration? duration,
    bool? isMuted,
    bool? isSpeakerOn,
    String? localSDP,
    String? remoteSDP,
    List<Map<String, dynamic>>? iceCandidates,
  }) {
    return Call(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      state: state ?? this.state,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      localSDP: localSDP ?? this.localSDP,
      remoteSDP: remoteSDP ?? this.remoteSDP,
      iceCandidates: iceCandidates ?? this.iceCandidates,
    );
  }

  /// Convert to JSON for persistence/transmission
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactId': contactId,
      'contactName': contactName,
      'type': type.name,
      'direction': direction.name,
      'state': state.name,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration?.inSeconds,
      'isMuted': isMuted,
      'isSpeakerOn': isSpeakerOn,
      'localSDP': localSDP,
      'remoteSDP': remoteSDP,
      'iceCandidates': iceCandidates,
    };
  }

  /// Create from JSON
  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['id'] as String,
      contactId: json['contactId'] as String,
      contactName: json['contactName'] as String,
      type: CallType.values.firstWhere((e) => e.name == json['type']),
      direction: CallDirection.values.firstWhere((e) => e.name == json['direction']),
      state: CallState.values.firstWhere((e) => e.name == json['state']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      duration: json['duration'] != null ? Duration(seconds: json['duration'] as int) : null,
      isMuted: json['isMuted'] as bool? ?? false,
      isSpeakerOn: json['isSpeakerOn'] as bool? ?? false,
      localSDP: json['localSDP'] as String?,
      remoteSDP: json['remoteSDP'] as String?,
      iceCandidates: json['iceCandidates'] != null
          ? (json['iceCandidates'] as List).cast<Map<String, dynamic>>()
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        contactId,
        contactName,
        type,
        direction,
        state,
        timestamp,
        duration,
        isMuted,
        isSpeakerOn,
        localSDP,
        remoteSDP,
        iceCandidates,
      ];
}
