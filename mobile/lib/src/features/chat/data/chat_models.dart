enum ChatMessageStatus { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isMine,
    required this.createdAt,
    this.senderName = '',
    this.isRead = false,
    this.status = ChatMessageStatus.sent,
    this.clientId,
    this.error = '',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: json['content']?.toString() ?? '',
      isMine: json['is_mine'] == true,
      createdAt: json['created_at']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      isRead: json['is_read'] == true,
    );
  }

  /// Server id; 0 for a message that hasn't been accepted by the server yet.
  final int id;
  final String content;
  final bool isMine;
  final String createdAt;
  final String senderName;
  final bool isRead;
  final ChatMessageStatus status;

  /// Identifies a locally-sent message until the server assigns an id.
  final String? clientId;
  final String error;

  ChatMessage copyWith({ChatMessageStatus? status, String? error}) {
    return ChatMessage(
      id: id,
      content: content,
      isMine: isMine,
      createdAt: createdAt,
      senderName: senderName,
      isRead: isRead,
      status: status ?? this.status,
      clientId: clientId,
      error: error ?? this.error,
    );
  }
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.jobTitle,
    required this.statusLabel,
    required this.otherPartyName,
    required this.otherPartyRole,
    required this.otherPartyPhotoUrl,
    required this.unreadCount,
    this.lastMessage,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final other = json['other_party'] is Map<String, dynamic>
        ? json['other_party'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final last = json['last_message'];
    return ChatConversation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      jobTitle: json['job_title']?.toString() ?? 'Service Request',
      statusLabel: json['status_label']?.toString() ?? '',
      otherPartyName:
          other['name']?.toString() ?? other['username']?.toString() ?? '',
      otherPartyRole: other['role']?.toString() ?? '',
      otherPartyPhotoUrl: other['photo_url']?.toString() ?? '',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: last is Map<String, dynamic>
          ? ChatMessage.fromJson(last)
          : null,
    );
  }

  /// The hire's JobApplication id, used in every chat URL.
  final int id;
  final String jobTitle;
  final String statusLabel;
  final String otherPartyName;
  final String otherPartyRole;
  final String otherPartyPhotoUrl;
  final int unreadCount;
  final ChatMessage? lastMessage;
}
