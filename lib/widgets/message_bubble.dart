import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:audioplayers/audioplayers.dart';
import '../models/message.dart';
import '../services/sticker_service.dart';
import '../utils/downloader.dart';
import '../main.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isTop;
  final bool isBottom;
  final Message? replyToMessage;
  final Function(Message)? onReply;
  final Function(Message, String)? onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.isTop = true,
    this.isBottom = true,
    this.replyToMessage,
    this.onReply,
    this.onReact,
  });

  static const _blue = Color(0xFF007AFF);
  static const _grey = Color(0xFFE5E5EA);

  BorderRadius get _bubbleRadius {
    const r = Radius.circular(20);
    const s = Radius.circular(6);
    if (isMine) {
      return BorderRadius.only(
        topLeft: r,
        topRight: isTop ? r : s,
        bottomLeft: r,
        bottomRight: isBottom ? r : s,
      );
    } else {
      return BorderRadius.only(
        topLeft: isTop ? r : s,
        topRight: r,
        bottomLeft: isBottom ? r : s,
        bottomRight: r,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: Container(
          margin: EdgeInsets.only(
            top: isTop ? 10 : 2,
            bottom: isBottom ? 4 : 2,
            left: isMine ? 60 : 0,
            right: isMine ? 0 : 60,
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.replyToId != null && replyToMessage != null)
                _buildReplyPreview(),
              _buildBubble(),
              if (message.reactions != null && message.reactions!.isNotEmpty)
                _buildReactions(),
              if (isBottom) ...[
                const SizedBox(height: 3),
                _buildMeta(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: isMine ? _blue : Colors.grey,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyToMessage!.senderId == message.senderId ? 'You' : 'Partner',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isMine ? _blue : Colors.grey[700],
            ),
          ),
          Text(
            replyToMessage!.content ?? (replyToMessage!.mediaType ?? 'Media'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble() {
    if (message.mediaType == 'sticker' && message.mediaUrl != null) {
      return _StickerBubble(url: message.mediaUrl!, isMine: isMine);
    }
    if (message.mediaType == 'voice' && (message.mediaPath != null || message.mediaUrl != null)) {
      return _SignedMediaBubble(
        path: message.mediaPath,
        fallbackUrl: message.mediaUrl,
        builder: (signedUrl) => _VoiceBubble(url: signedUrl, isMine: isMine, radius: _bubbleRadius),
      );
    }
    if (message.isImage && (message.mediaPath != null || message.mediaUrl != null)) {
      return _SignedMediaBubble(
        path: message.mediaPath,
        fallbackUrl: message.mediaUrl,
        builder: (signedUrl) => _ImageBubble(url: signedUrl, isMine: isMine, radius: _bubbleRadius),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? _blue : _grey,
        borderRadius: _bubbleRadius,
      ),
      child: Text(
        message.content ?? '',
        style: TextStyle(
          fontSize: 16,
          color: isMine ? Colors.white : Colors.black,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildReactions() {
    final reactionCounts = <String, int>{};
    for (var r in message.reactions!) {
      reactionCounts[r.emoji] = (reactionCounts[r.emoji] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: reactionCounts.entries.map((e) {
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              '${e.key} ${e.value > 1 ? e.value : ""}',
              style: const TextStyle(fontSize: 10),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMeta() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeago.format(message.createdAt, allowFromNow: true),
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          if (message.isPending)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.grey[400],
              ),
            )
          else if (message.isFailed)
            const Icon(Icons.error_outline, size: 12, color: Colors.red)
          else
            Text(
              message.readAt != null ? 'Read' : 'Delivered',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
        ],
      ],
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((e) {
                return GestureDetector(
                  onTap: () {
                    onReact?.call(message, e);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 32),
            ListTile(
              leading: Icon(Icons.reply, color: Colors.grey[700]),
              title: const Text('Reply'),
              onTap: () {
                onReply?.call(message);
                Navigator.pop(ctx);
              },
            ),
            if (message.mediaType == 'sticker')
              ListTile(
                leading: Icon(Icons.add_to_photos, color: Colors.grey[700]),
                title: const Text('Save Sticker'),
                onTap: () {
                  StickerService().saveSticker(message.mediaUrl!);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Sticker Saved to Collection')),
                  );
                },
              ),
            if (message.mediaPath != null || message.mediaUrl != null)
              ListTile(
                leading: Icon(Icons.download, color: Colors.grey[700]),
                title: const Text('Save to Device'),
                onTap: () async {
                  final ext = message.mediaType == 'image'
                      ? 'webp'
                      : (message.mediaType == 'voice' ? 'm4a' : 'bin');
                  final filename =
                      'HMS_${DateTime.now().millisecondsSinceEpoch}.$ext';
                  final url = await _resolveDownloadUrl();
                  if (url != null) {
                    await FileDownloader.downloadBlob(url, filename);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _resolveDownloadUrl() async {
    final path = message.mediaPath;
    if (path != null && path.isNotEmpty) {
      final signed = await supabase.storage.from('media').createSignedUrl(path, 60);
      return signed;
    }
    final url = message.mediaUrl;
    if (url != null && url.isNotEmpty) {
      return url;
    }
    return null;
  }
}

class _SignedMediaBubble extends StatelessWidget {
  final String? path;
  final String? fallbackUrl;
  final Widget Function(String url) builder;

  const _SignedMediaBubble({
    required this.path,
    required this.fallbackUrl,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null || p.isEmpty) {
      final url = fallbackUrl;
      if (url == null || url.isEmpty) {
        return const SizedBox.shrink();
      }
      return builder(url);
    }

    return FutureBuilder<String>(
      future: supabase.storage.from('media').createSignedUrl(p, 60),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return const SizedBox(
            width: 220,
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return builder(url);
      },
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String url;
  final bool isMine;
  final BorderRadius radius;

  const _ImageBubble(
      {required this.url, required this.isMine, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url,
        width: 220,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 220,
          height: 160,
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF007AFF),
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) =>
            Icon(Icons.broken_image, color: Colors.grey[400]),
      ),
    );
  }
}

class _StickerBubble extends StatelessWidget {
  final String url;
  final bool isMine;

  const _StickerBubble({required this.url, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('emoji:')) {
      final emoji = url.substring(6);
      return Text(emoji, style: const TextStyle(fontSize: 64));
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 150),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox(width: 60, height: 60),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  final String url;
  final bool isMine;
  final BorderRadius radius;

  const _VoiceBubble(
      {required this.url, required this.isMine, required this.radius});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onDurationChanged.listen((d) => setState(() => _duration = d));
    _player.onPositionChanged.listen((p) => setState(() => _position = p));
    _player.onPlayerComplete.listen((_) => setState(() => _isPlaying = false));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isMine
        ? const Color(0xFF007AFF)
        : const Color(0xFFE5E5EA);
    final iconColor = widget.isMine ? Colors.white : Colors.grey[700]!;
    final sliderActive =
        widget.isMine ? Colors.white : const Color(0xFF007AFF);
    final sliderInactive = widget.isMine
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.grey[400]!;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: bg, borderRadius: widget.radius),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: iconColor,
              size: 32,
            ),
            onPressed: () async {
              if (_isPlaying) {
                await _player.pause();
              } else {
                await _player.play(UrlSource(widget.url));
              }
              setState(() => _isPlaying = !_isPlaying);
            },
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                activeTrackColor: sliderActive,
                inactiveTrackColor: sliderInactive,
                thumbColor: sliderActive,
              ),
              child: Slider(
                value: _position.inMilliseconds.toDouble(),
                max: _duration.inMilliseconds.toDouble() > 0
                    ? _duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: (v) =>
                    _player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
