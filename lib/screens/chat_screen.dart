import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../util/osnova_image.dart';
import '../widgets/avatar.dart';

/// A single direct-message conversation.
///
/// v1 uses REST + light polling for new messages (every few seconds while
/// open). Instant delivery via the Socket.IO `m:{mHash}` channel is a planned
/// follow-up. Swipe a bubble to reply to it.
class ChatScreen extends StatefulWidget {
  final dynamic channel;
  const ChatScreen({super.key, required this.channel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Newest-first (index 0 == newest) so it maps directly onto a reversed list.
  final List<dynamic> _messages = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  bool _sending = false;
  dynamic _replyTo; // the message being replied to, or null

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Timer? _poll;

  int get _channelId => int.tryParse('${widget.channel['id']}') ?? 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final pos = _scroll.position;
      // Reversed list → older messages are near maxScrollExtent (the top).
      if (pos.pixels > pos.maxScrollExtent - 400) _loadOlder();
    });
    _loadLatest();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadLatest() async {
    final settings = context.read<SettingsService>();
    final list = await DtfApi.getMessages(_channelId, settings);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(list.reversed);
      _loading = false;
      _hasOlder = list.isNotEmpty;
    });
    DtfApi.markChannelRead(_channelId, settings);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final settings = context.read<SettingsService>();
    final oldest = _messages.last;
    final before = '${oldest['dtCreated']}';
    final list = await DtfApi.getMessages(_channelId, settings, beforeTime: before);
    if (!mounted) return;
    final existing = _messages.map((m) => m['id']).toSet();
    final older = list.reversed.where((m) => !existing.contains(m['id'])).toList();
    setState(() {
      _messages.addAll(older);
      _hasOlder = older.isNotEmpty;
      _loadingOlder = false;
    });
  }

  Future<void> _pollNew() async {
    if (_loading || _messages.isEmpty) return;
    final settings = context.read<SettingsService>();
    final list = await DtfApi.getMessages(_channelId, settings);
    if (!mounted || list.isEmpty) return;
    final existing = _messages.map((m) => m['id']).toSet();
    final fresh = list.reversed.where((m) => !existing.contains(m['id'])).toList();
    if (fresh.isEmpty) return;
    setState(() => _messages.insertAll(0, fresh));
    DtfApi.markChannelRead(_channelId, settings);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final settings = context.read<SettingsService>();
    setState(() => _sending = true);
    final replyId = _replyTo?['id']?.toString();
    final res = await DtfApi.sendMessage(
      channelId: _channelId,
      text: text,
      replyToId: replyId,
      settings: settings,
    );
    if (!mounted) return;
    if (res.ok) {
      _ctrl.clear();
      setState(() {
        _replyTo = null;
        _sending = false;
      });
      await _pollNew(); // pull the just-sent message back with its real id
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не отправлено: ${res.error ?? 'ошибка'}')),
      );
    }
  }

  bool _isMine(dynamic m) {
    final myId = context.read<SettingsService>().myUserId?.toString();
    return myId != null && m['author']?['id']?.toString() == myId;
  }

  @override
  Widget build(BuildContext context) {
    final pic = widget.channel['pictureData'];
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Avatar(
            uuid: pic?['data']?['uuid'],
            size: 36,
            animated: pic?['data']?['type'] == 'gif',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.channel['title'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Нет сообщений',
                            style: TextStyle(color: AppColors.textMuted)))
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                        itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                  child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))),
                            );
                          }
                          final m = _messages[i];
                          final mine = _isMine(m);
                          final authorId = m['author']?['id']?.toString();
                          // Block bottom = newest of a consecutive same-author run.
                          final isBlockBottom = i == 0 ||
                              _messages[i - 1]['author']?['id']?.toString() !=
                                  authorId;
                          return _MessageBubble(
                            message: m,
                            mine: mine,
                            showAvatar: !mine && isBlockBottom,
                            onReply: () => setState(() => _replyTo = m),
                          );
                        },
                      ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDeep,
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(width: 3, height: 34, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_replyTo['author']?['title'] ?? '',
                            style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(
                          (_replyTo['text'] ?? '📷 Вложение').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textMuted),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ]),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Сообщение…',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.send, color: accent),
                        onPressed: _send,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final dynamic message;
  final bool mine;
  final bool showAvatar;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showAvatar,
    required this.onReply,
  });

  String? _firstMediaUuid() {
    final media = message['media'];
    if (media is List && media.isNotEmpty && media[0] is Map) {
      return media[0]['data']?['uuid'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final text = (message['text'] ?? '').toString();
    final reply = message['replyTo'];
    final uuid = _firstMediaUuid();

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? accent : AppColors.bgCard,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 4),
          bottomRight: Radius.circular(mine ? 4 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reply is Map) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                    left: BorderSide(
                        color: mine ? Colors.white70 : accent, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reply['author']?['title'] ?? '',
                      style: TextStyle(
                          color: mine ? Colors.white : accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  Text(
                    (reply['text'] ?? '📷 Вложение').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: mine
                            ? Colors.white70
                            : AppColors.textMuted,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
          if (uuid != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: OsnovaImage(uuid).preview(600),
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                    height: 160, color: AppColors.bgElevated),
                errorWidget: (_, _, _) => Container(
                    height: 160, color: AppColors.bgElevated),
              ),
            ),
            if (text.isNotEmpty) const SizedBox(height: 6),
          ],
          if (text.isNotEmpty)
            Text(text,
                style: TextStyle(
                    color: mine ? Colors.white : AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.3)),
          const SizedBox(height: 3),
          Text(_time(),
              style: TextStyle(
                  color: mine ? Colors.white70 : AppColors.textMuted,
                  fontSize: 10)),
        ],
      ),
    );

    // Swipe (start→end) to reply; snaps back without dismissing.
    return Dismissible(
      key: ValueKey(message['id']),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.25},
      confirmDismiss: (_) async {
        onReply();
        return false;
      },
      background: const Padding(
        padding: EdgeInsets.only(left: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.reply, color: AppColors.textMuted),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
            top: 2, bottom: 2, left: mine ? 40 : 0, right: mine ? 0 : 40),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine)
              SizedBox(
                width: 30,
                child: showAvatar
                    ? Avatar(
                        uuid: message['author']?['pictureData']?['data']
                            ?['uuid'],
                        size: 28,
                        animated: message['author']?['pictureData']?['data']
                                ?['type'] ==
                            'gif',
                      )
                    : null,
              ),
            if (!mine) const SizedBox(width: 6),
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }

  String _time() {
    final ts = message['dtCreated'];
    if (ts is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
