enum MessageDeliveryStatus {
  sending,
  sent,
  failed,
}

class Message {
  final String id;
  final String senderId;
  final String? content;
  final String? mediaUrl;
  final String? mediaPath;
  final String? mediaType; // 'image' | 'voice' | 'sticker'
  final String? replyToId;
  final DateTime createdAt;
  final DateTime? readAt;
  final List<MessageReaction>? reactions;
  final MessageDeliveryStatus deliveryStatus;

  const Message({
    required this.id,
    required this.senderId,
    this.content,
    this.mediaUrl,
    this.mediaPath,
    this.mediaType,
    this.replyToId,
    required this.createdAt,
    this.readAt,
    this.reactions,
    this.deliveryStatus = MessageDeliveryStatus.sent,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      mediaPath: json['media_path'] as String?,
      mediaType: json['media_type'] as String?,
      replyToId: json['reply_to_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      reactions: json['reactions'] != null
          ? (json['reactions'] as List)
              .map((e) => MessageReaction.fromJson(e))
              .toList()
          : null,
      deliveryStatus: MessageDeliveryStatus.sent,
    );
  }

  bool get isImage => mediaType == 'image';
  bool get isVoice => mediaType == 'voice';
  bool get isSticker => mediaType == 'sticker';
  bool get isPending => deliveryStatus == MessageDeliveryStatus.sending;
  bool get isFailed => deliveryStatus == MessageDeliveryStatus.failed;

  Message copyWith({
    String? id,
    String? senderId,
    String? content,
    String? mediaUrl,
    String? mediaPath,
    String? mediaType,
    String? replyToId,
    DateTime? createdAt,
    DateTime? readAt,
    List<MessageReaction>? reactions,
    MessageDeliveryStatus? deliveryStatus,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaType: mediaType ?? this.mediaType,
      replyToId: replyToId ?? this.replyToId,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      reactions: reactions ?? this.reactions,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }
}

class MessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;

  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'] as String,
      messageId: json['message_id'] as String,
      userId: json['user_id'] as String,
      emoji: json['emoji'] as String,
    );
  }
}

class Profile {
  final String id;
  final String name;
  final String? avatarUrl;
  final String status;
  final DateTime? lastSeen;

  const Profile({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.status = 'offline',
    this.lastSeen,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      status: json['status'] as String? ?? 'offline',
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }
}
