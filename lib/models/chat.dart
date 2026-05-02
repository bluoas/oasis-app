import 'package:equatable/equatable.dart';
import 'message.dart';

/// Chat model - Konversation mit einem Kontakt
class Chat extends Equatable {
  final String peerID; // PeerID des Gesprächspartners
  final String name; // Name des Kontakts
  final Message? lastMessage; // Letzte Nachricht
  final int unreadCount; // Anzahl ungelesener Nachrichten
  final DateTime lastActivity; // Letzter Zeitstempel

  const Chat({
    required this.peerID,
    required this.name,
    this.lastMessage,
    this.unreadCount = 0,
    required this.lastActivity,
  });

  Chat copyWith({
    String? peerID,
    String? name,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
  }) =>
      Chat(
        peerID: peerID ?? this.peerID,
        name: name ?? this.name,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
        lastActivity: lastActivity ?? this.lastActivity,
      );

  @override
  List<Object?> get props =>
      [peerID, name, lastMessage, unreadCount, lastActivity];
}
