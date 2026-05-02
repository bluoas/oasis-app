import 'package:equatable/equatable.dart';

/// Scanned Node Model
/// Represents an Oasis Node scanned via QR code during network registration
class ScannedNode extends Equatable {
  final String peerId;
  final String multiaddr;
  final String? name;
  final DateTime scannedAt;

  const ScannedNode({
    required this.peerId,
    required this.multiaddr,
    this.name,
    required this.scannedAt,
  });

  factory ScannedNode.fromJson(Map<String, dynamic> json) {
    return ScannedNode(
      peerId: json['peer_id'] as String,
      multiaddr: json['multiaddr'] as String,
      name: json['name'] as String?,
      scannedAt: DateTime.parse(json['scanned_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'peer_id': peerId,
        'multiaddr': multiaddr,
        if (name != null) 'name': name,
        'scanned_at': scannedAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [peerId, multiaddr, name, scannedAt];
}
