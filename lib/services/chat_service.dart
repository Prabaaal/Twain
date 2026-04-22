import 'dart:typed_data';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../models/message.dart';

class ChatService {
  static const _uuid = Uuid();
  RealtimeChannel? _msgChannel;
  RealtimeChannel? _presenceChannel;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  String get currentUserId => supabase.auth.currentUser!.id;

  // ── Fetch all messages (latest 100) ──
  Future<List<Message>> fetchMessages() async {
    final data = await supabase
        .from('messages')
        .select('*, reactions:message_reactions(*)')
        .order('created_at', ascending: true)
        .limit(100);
    return _sortAndDeduplicate(
      (data as List).map((e) => Message.fromJson(e)).toList(),
    );
  }

  // ── Fetch the other user's profile ──
  Future<Profile?> fetchPartnerProfile() async {
    final partnerId = await _getPartnerId();
    if (partnerId == null) return null;
    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', partnerId)
        .maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }

  Future<String?> _getPartnerId() async {
    final row = await supabase.from('app_pair').select('user_a, user_b').maybeSingle();
    if (row == null) return null;
    final a = row['user_a'] as String?;
    final b = row['user_b'] as String?;
    if (a == null || b == null) return null;
    if (a == currentUserId) return b;
    if (b == currentUserId) return a;
    return null;
  }

  // ── Send a text message ──
  Future<Message> sendMessage(String content, {String? replyToId}) async {
    final data = await supabase.from('messages').insert({
      'id': _uuid.v4(),
      'sender_id': currentUserId,
      'content': content.trim(),
      'reply_to_id': replyToId,
    }).select('*, reactions:message_reactions(*)').single();
    final message = Message.fromJson(data);
    unawaited(_notifyPartner(message));
    return message;
  }

  // ── Upload media and send message ──
  Future<Message> sendMedia(Uint8List bytes, String mediaType, {String? replyToId}) async {
    final ext = mediaType == 'image' ? 'webp' : 'ogg';
    final fileName = '${_uuid.v4()}.$ext';
    final path = '$currentUserId/$fileName';

    await supabase.storage.from('media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: mediaType == 'image' ? 'image/webp' : 'audio/ogg',
      ),
    );

    final data = await supabase.from('messages').insert({
      'id': _uuid.v4(),
      'sender_id': currentUserId,
      'media_path': path,
      'media_type': mediaType,
      'reply_to_id': replyToId,
    }).select('*, reactions:message_reactions(*)').single();
    final message = Message.fromJson(data);
    unawaited(_notifyPartner(message));
    return message;
  }

  // ── Add reaction to a message ──
  Future<void> addReaction(String messageId, String emoji) async {
    await supabase.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': currentUserId,
      'emoji': emoji,
    });
  }

  // ── Send a sticker message ──
  Future<Message> sendSticker(String url, {String? replyToId}) async {
    final data = await supabase.from('messages').insert({
      'id': _uuid.v4(),
      'sender_id': currentUserId,
      'media_url': url,
      'media_type': 'sticker',
      'reply_to_id': replyToId,
    }).select('*, reactions:message_reactions(*)').single();
    final message = Message.fromJson(data);
    unawaited(_notifyPartner(message));
    return message;
  }

  // ── Presence & Typing Status ──
  void initPresence(void Function(Map<String, dynamic>) onPresenceChange) {
    _presenceChannel = supabase.channel('presence:chat');
    
    _presenceChannel!.onPresenceSync((_) {
      final state = _presenceChannel!.presenceState();
      // Find partner's presence
      final partnerState = state.cast<SinglePresenceState?>().firstWhere(
        (s) => s != null && s.key != currentUserId,
        orElse: () => null,
      );
      if (partnerState != null && partnerState.presences.isNotEmpty) {
        final partnerPresence = partnerState.presences.first;
        onPresenceChange(partnerPresence.payload);
      } else {
        onPresenceChange({'status': 'offline'});
      }
    }).subscribe();

    updatePresenceStatus('online');
  }

  Future<void> updatePresenceStatus(String status) async {
    await _presenceChannel?.track({
      'user_id': currentUserId,
      'status': status,
      'last_seen': DateTime.now().toIso8601String(),
    });
    
    // Also update periodic last_seen in database
    await updateLastSeen();
  }

  Message createOptimisticMessage({
    String? content,
    String? mediaUrl,
    String? mediaType,
    String? replyToId,
  }) {
    return Message(
      id: 'temp-${_uuid.v4()}',
      senderId: currentUserId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      replyToId: replyToId,
      createdAt: DateTime.now(),
      deliveryStatus: MessageDeliveryStatus.sending,
    );
  }

  Future<Message?> fetchMessageById(String messageId) async {
    final data = await supabase
        .from('messages')
        .select('*, reactions:message_reactions(*)')
        .eq('id', messageId)
        .maybeSingle();
    if (data == null) {
      return null;
    }
    return Message.fromJson(data);
  }

  // ── Subscribe to realtime messages & reactions ──
  void subscribe(void Function(dynamic) onEvent) {
    _msgChannel?.unsubscribe();
    _msgChannel = supabase
        .channel('public:chat')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.insert) {
              final messageId = payload.newRecord['id'] as String?;
              if (messageId == null) {
                return;
              }
              final message = await fetchMessageById(messageId);
              if (message != null) {
                onEvent(message);
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            onEvent(payload);
          },
        )
        .onBroadcast(
          event: 'nudge',
          callback: (payload) {
            if (payload['to'] == currentUserId) {
              onEvent({'type': 'nudge', 'from': payload['from']});
            }
          },
        )
        .subscribe((status, [_]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _reconnectAttempt = 0;
            _reconnectTimer?.cancel();
            return;
          }
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            _scheduleReconnect(onEvent);
          }
        });
  }

  List<Message> mergeMessages(List<Message> current, List<Message> incoming) {
    return _sortAndDeduplicate([...current, ...incoming]);
  }

  List<Message> _sortAndDeduplicate(List<Message> messages) {
    final byId = <String, Message>{};
    for (final message in messages) {
      final existing = byId[message.id];
      if (existing == null ||
          existing.deliveryStatus == MessageDeliveryStatus.sending ||
          existing.deliveryStatus == MessageDeliveryStatus.failed) {
        byId[message.id] = message;
      }
    }

    final sorted = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted;
  }

  void _scheduleReconnect(void Function(dynamic) onEvent) {
    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    final seconds = _reconnectAttempt > 5 ? 5 : _reconnectAttempt;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      subscribe(onEvent);
    });
  }

  Future<void> _notifyPartner(Message message) async {
    try {
      await supabase.functions.invoke(
        'notify-partner',
        body: {
          'message_id': message.id,
          'preview': _buildNotificationPreview(message),
          'kind': message.mediaType ?? 'text',
        },
      );
    } catch (_) {
      // Push is best-effort. Messaging should not fail if notification delivery does.
    }
  }

  String _buildNotificationPreview(Message message) {
    final text = message.content?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
    switch (message.mediaType) {
      case 'image':
        return 'Sent a photo';
      case 'sticker':
        return 'Sent a sticker';
      case 'voice':
        return 'Sent a voice note';
      default:
        return 'New message';
    }
  }

  // ── Mark messages as read ──
  Future<void> markAsRead() async {
    await supabase
        .from('messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .neq('sender_id', currentUserId)
        .isFilter('read_at', null);
  }

  // ── Send Nudge (Realtime Broadcast) ──
  Future<void> sendNudge(String partnerId) async {
    await _msgChannel?.sendBroadcastMessage(
      event: 'nudge',
      payload: {'to': partnerId, 'from': currentUserId},
    );
  }

  // ── Update last seen in DB ──
  Future<void> updateLastSeen() async {
    await supabase
        .from('profiles')
        .update({'last_seen': DateTime.now().toIso8601String()})
        .eq('id', currentUserId);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _msgChannel?.unsubscribe();
    _presenceChannel?.unsubscribe();
  }
}
