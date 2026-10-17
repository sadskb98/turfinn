import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/sources/remote/dio_client.dart';

class _ChatMessage {
  final String id;
  final String senderID;
  final String senderName;
  final String content;
  final DateTime sentAt;
  final bool isMe;

  const _ChatMessage({
    required this.id,
    required this.senderID,
    required this.senderName,
    required this.content,
    required this.sentAt,
    required this.isMe,
  });
}

class MatchChatScreen extends ConsumerStatefulWidget {
  const MatchChatScreen({
    super.key,
    required this.matchId,
    required this.myUserId,
    required this.opponentTeamName,
  });

  final String matchId;
  final String myUserId;
  final String opponentTeamName;

  @override
  ConsumerState<MatchChatScreen> createState() => _MatchChatScreenState();
}

class _MatchChatScreenState extends ConsumerState<MatchChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _loading = true;

  String get _channelName => 'match:${widget.matchId}';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _connectWS();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/matchmaking/${widget.matchId}/messages');
      final list = resp.data['data'] as List<dynamic>;
      final history = list.reversed.map((j) {
        final m = j as Map<String, dynamic>;
        return _ChatMessage(
          id: m['id'] as String,
          senderID: m['sender_id'] as String,
          senderName: m['sender_name'] as String? ?? '',
          content: m['content'] as String,
          sentAt: DateTime.parse(m['sent_at'] as String),
          isMe: m['sender_id'] == widget.myUserId,
        );
      }).toList();
      if (mounted) setState(() { _messages.addAll(history); _loading = false; });
      _scrollToBottom();
    } on DioException {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectWS() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty) return;

    // Derive WS URL from Dio base URL
    final dio = ref.read(dioProvider);
    final base = (dio.options.baseUrl)
        .replaceFirst('/api/v1', '')
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    final uri = Uri.parse('$base/ws?token=$token');
    _channel = WebSocketChannel.connect(uri);

    // Join the match channel
    _channel!.sink.add(jsonEncode({
      'type': 'join_channel',
      'channel': _channelName,
      'payload': {},
    }));

    _sub = _channel!.stream.listen((raw) {
      try {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        if (msg['type'] == 'chat_message' && msg['channel'] == _channelName) {
          final p = msg['payload'] as Map<String, dynamic>;
          final cm = _ChatMessage(
            id: p['id'] as String,
            senderID: p['sender_id'] as String,
            senderName: p['sender_name'] as String? ?? '',
            content: p['content'] as String,
            sentAt: DateTime.tryParse(p['sent_at']?.toString() ?? '') ?? DateTime.now(),
            isMe: p['sender_id'] == widget.myUserId,
          );
          if (mounted) setState(() => _messages.add(cm));
          _scrollToBottom();
        }
      } catch (_) {}
    }, onError: (_) {}, onDone: () {});
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'chat_message',
      'channel': _channelName,
      'payload': {'content': text},
    }));
    _controller.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Match Chat',
                style: GoogleFonts.nunito(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('vs ${widget.opponentTeamName}',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                    ? Center(
                        child: Text('No messages yet. Say hi!',
                            style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                      ),
          ),
          _InputBar(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isMe = msg.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : const Color(0xFF04404A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && msg.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(msg.senderName,
                    style: GoogleFonts.dmSans(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            Text(msg.content,
                style: GoogleFonts.dmSans(
                    color: isMe ? Colors.black : Colors.white, fontSize: 14)),
            const SizedBox(height: 3),
            Text(_formatTime(msg.sentAt),
                style: GoogleFonts.dmSans(
                    color: isMe ? Colors.black54 : Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF033640),
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.dmSans(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Agree on terms, venue, time…',
                hintStyle: GoogleFonts.dmSans(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
