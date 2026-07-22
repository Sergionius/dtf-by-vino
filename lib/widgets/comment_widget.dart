import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api/dtf_api.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'avatar.dart';
import 'badges.dart';
import 'profile_navigation.dart';
import 'reactions.dart';
import 'media_view.dart';
import 'linkified_text.dart';

class CommentWidget extends StatefulWidget {
  final dynamic comment;
  final VoidCallback? onReply;
  final VoidCallback? onReactionChanged;
  final VoidCallback? onToggleCollapse;
  final bool? branchCollapsed;

  const CommentWidget({
    super.key,
    required this.comment,
    this.onReply,
    this.onReactionChanged,
    this.onToggleCollapse,
    this.branchCollapsed,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _collapsed = false;

  int get _commentId => widget.comment['id'] as int? ?? 0;

  Future<void> _react(int reactionId) async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      _needAuth();
      return;
    }
    final reactions =
        (widget.comment['reactions'] as Map?) ??
            {'counters': [], 'reactionId': 0};
    widget.comment['reactions'] = reactions;
    final snapshot = jsonEncode(reactions);
    final before = (reactions['reactionId'] as int?) ?? 0;
    final now = applyReactionToggle(reactions, reactionId);
    setState(() {});
    final added = now != 0 && now != before;
    if (added) settings.recordReactionUse(reactionId);
    showReactionToast(context, reactionId, added: added);

    final result = await DtfApi.setReaction(
        id: _commentId,
        isComment: true,
        reactionId: reactionId,
        settings: settings);
    if (!mounted) return;
    if (result['ok'] != true) {
      widget.comment['reactions'] = jsonDecode(snapshot);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Реакция: ${result['error'] ?? 'ошибка'}')),
      );
    }
  }

  void _needAuth() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Войди в аккаунт')));
  }

  int? get _postId => widget.comment['entry']?['id'] as int?;
  bool get _isFavorited => widget.comment['isFavorited'] == true;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copyLink() {
    final postId = _postId;
    if (postId == null) {
      _toast('Не удалось получить ссылку');
      return;
    }
    Clipboard.setData(
        ClipboardData(text: 'https://dtf.ru/$postId?comment=$_commentId'));
    _toast('Ссылка скопирована');
  }

  void _copyText() {
    // Strip HTML tags so the clipboard gets clean plain text.
    final raw = (widget.comment['text'] ?? '').toString();
    final text = raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (text.isEmpty) {
      _toast('Пустой комментарий');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _toast('Текст скопирован');
  }

  Future<void> _toggleBookmark() async {
    final settings = context.read<SettingsService>();
    if (!settings.isLoggedIn) {
      _needAuth();
      return;
    }
    final add = !_isFavorited;
    // Optimistic: flip locally, revert on failure. type 2 = comment.
    setState(() => widget.comment['isFavorited'] = add);
    final ok = await DtfApi.toggleFavorite(_commentId, 2, add, settings);
    if (!mounted) return;
    if (ok) {
      _toast(add ? 'Добавлено в закладки' : 'Убрано из закладок');
    } else {
      setState(() => widget.comment['isFavorited'] = !add);
      _toast('Не удалось изменить закладку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final c = widget.comment;

    final isRemoved = c['isRemoved'] == true;
    final isRemovedByMod = c['isRemovedByModerator'] == true;
    final isHidden = c['isHiddenByBan'] == true;
    final author = c['author'];
    final level = (c['level'] ?? 0) as int;
    final authorId = author?['id'] as int?;
    final userNote = context.select<SettingsService, String?>(
        (s) => authorId != null ? s.userNotes[authorId] : null);
    final showDeleted = context.select<SettingsService, bool>(
        (s) => s.showDeletedComments);
    final text =
        (c['text'] ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final isEdited = c['isEdited'] == true;
    final media = c['media'] as List? ?? [];

    // Restored-from-archive data (deleted text recovered via dtfrandomizer).
    final restoredText = c['_restoredText'] as String?;
    final restoredMedia = c['_restoredMedia'] as List?;
    final isRestored = (restoredText != null && restoredText.isNotEmpty) ||
        (restoredMedia != null && restoredMedia.isNotEmpty);
    final editHistory = c['_edits'] as Map?;

    final isDeleted = isRemoved || isRemovedByMod || isHidden;
    // Restored deleted comments are always shown (that's the whole feature),
    // even when "show deleted" is off.
    if (isDeleted && !showDeleted && !isRestored) return const SizedBox();

    final myReaction = (c['reactions']?['reactionId'] as int?) ?? 0;
    final reactions = (c['reactions']?['counters'] as List? ?? [])
        .where((r) => (r['count'] ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          (b['count'] as int).compareTo(a['count'] as int));

    final counterLikes = c['likes']?['counterLikes'] ?? 0;

    Color cardBg;
    if (isRemovedByMod) {
      cardBg = const Color(0xFF2A1010);
    } else if (isRemoved) {
      cardBg = const Color(0xFF1E1A10);
    } else {
      cardBg = AppColors.bgCard;
    }

    return Container(
      margin: EdgeInsets.only(
          left: (level * 12.0).clamp(0, 48), bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: isRestored ? const Color(0xFF1C1012) : cardBg,
          borderRadius: BorderRadius.circular(8),
          border: isRestored
              ? Border.all(color: const Color(0xFFE53935), width: 1.4)
              : level > 0
                  ? Border(
                      left: BorderSide(
                          color: accent.withValues(alpha: 0.6), width: 2))
                  : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Avatar.fromData(
                author?['avatar'],
                size: 24,
                onTap: () => openUserProfile(context, author),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () => openUserProfile(context, author),
                      child: Text(
                        author?['name'] ?? 'Аноним',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  AuthorBadge(author: author, size: 12),
                  if (userNote != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(userNote,
                          style: TextStyle(
                              color: accent, fontSize: 9)),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(_timeAgo(c['date']),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                  if (isEdited) ...[
                    const SizedBox(width: 4),
                    const Text('✎',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                  ],
                ]),
              ),
              if (isRestored)
                const Text('восстановлен',
                    style: TextStyle(color: Color(0xFFE53935), fontSize: 10))
              else if (isRemovedByMod)
                const Text('мод',
                    style: TextStyle(color: Colors.red, fontSize: 10))
              else if (isRemoved)
                const Text('удалён',
                    style: TextStyle(color: Colors.orange, fontSize: 10)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  if (widget.onToggleCollapse != null) {
                    widget.onToggleCollapse!();
                  } else {
                    setState(() => _collapsed = !_collapsed);
                  }
                },
                child: Icon(
                  (widget.branchCollapsed ?? _collapsed)
                      ? Icons.add
                      : Icons.remove,
                  color: widget.branchCollapsed == true
                      ? accent
                      : AppColors.textMuted,
                  size: 16,
                ),
              ),
              // Restored (read-only) comments get no action menu.
              if (!isRestored) ...[
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => _showMenu(context, author),
                  child: const Icon(Icons.more_horiz,
                      color: AppColors.textMuted, size: 16),
                ),
              ],
            ]),

            if (!_collapsed && isRestored) ...[
              // ── Restored deleted comment: read-only text + media ──
              const SizedBox(height: 6),
              if (restoredText != null && restoredText.isNotEmpty)
                LinkifiedText(
                  restoredText,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ...(restoredMedia ?? []).map((m) => MediaView(media: m)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.delete_outline,
                    size: 12, color: Color(0xFFE53935)),
                const SizedBox(width: 4),
                const Text('Удалённый комментарий, восстановлен из архива',
                    style: TextStyle(
                        color: Color(0xFFB05050),
                        fontSize: 10,
                        fontStyle: FontStyle.italic)),
                const Spacer(),
                if (editHistory != null)
                  GestureDetector(
                    onTap: () => _showEditHistory(context, editHistory),
                    child: const Text('История',
                        style: TextStyle(
                            color: Color(0xFFE53935), fontSize: 11)),
                  ),
              ]),
            ] else if (!_collapsed) ...[
              const SizedBox(height: 6),
              if (text.isEmpty && media.isEmpty)
                Text(
                  isRemovedByMod
                      ? '🚫 Удалён модератором'
                      : isHidden
                          ? '🔒 Скрыт'
                          : '🗑 Удалён автором',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontStyle: FontStyle.italic),
                )
              else if (text.isNotEmpty)
                LinkifiedText(
                  (c['text'] ?? '').toString(),
                  style: TextStyle(
                    color: isDeleted
                        ? AppColors.textMuted.withValues(alpha: 0.6)
                        : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),

              ...media.map((m) => MediaView(media: m)),

              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  ...reactions.take(8).map((r) {
                    final mine = r['id'] == myReaction;
                    return BurstTap(
                      onTap: () => _react(r['id'] as int),
                      onLongPress: () =>
                          showReactionPicker(context, _react),
                      burstColor: accent,
                      scale: 0.88,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: mine
                              ? accent.withValues(alpha: 0.18)
                              : AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: mine
                              ? Border.all(
                                  color: accent, width: 1.2)
                              : null,
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReactionIcon(
                                  id: r['id'] as int,
                                  size: 14,
                                  animated: false),
                              const SizedBox(width: 3),
                              Text('${r['count']}',
                                  style:
                                      const TextStyle(fontSize: 12)),
                            ]),
                      ),
                    );
                  }),
                  AddReactionButton(onPick: _react, size: 22),
                ],
              ),

              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.thumb_up_outlined,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Text('$counterLikes',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
                if (editHistory != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showEditHistory(context, editHistory),
                    child: Row(children: [
                      const Icon(Icons.history,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text('изменён', style: TextStyle(
                          color: accent, fontSize: 11)),
                    ]),
                  ),
                ],
                const Spacer(),
                if (widget.onReply != null)
                  GestureDetector(
                    onTap: widget.onReply,
                    child: Text('Ответить',
                        style: TextStyle(
                            color: accent, fontSize: 11)),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // Shows how a comment's text changed over time (archive edit history).
  void _showEditHistory(BuildContext ctx, Map history) {
    final original = history['original'];
    final edits = (history['edits'] as List?) ?? [];
    // Ordered snapshots: the original, then each recorded edit.
    final versions = <Map>[];
    if (original is Map) versions.add(original);
    for (final e in edits) {
      if (e is Map && e['data'] is Map) versions.add(e['data'] as Map);
    }
    if (versions.isEmpty) return;

    String timeOf(dynamic v) {
      final d = v is Map ? v['date'] : null;
      final secs = d is int ? d : int.tryParse('$d');
      if (secs == null) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(dt.day)}.${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    }

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('История изменений',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: versions.length,
                itemBuilder: (_, i) {
                  final v = versions[i];
                  final label = i == 0
                      ? 'Исходная версия'
                      : 'Изменение $i';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border(
                          left: BorderSide(
                              color: i == 0
                                  ? AppColors.textMuted
                                  : Theme.of(ctx).colorScheme.primary,
                              width: 2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(label,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(timeOf(v),
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                        ]),
                        const SizedBox(height: 6),
                        SelectableText(
                          (v['text'] ?? '').toString().isEmpty
                              ? '(пустой текст)'
                              : v['text'].toString(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.35),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Edit dialog for the user's own comment. Sends plain text (the server
  // re-wraps it); existing media is preserved via attachments.
  Future<void> _showEditDialog() async {
    final postId = _postId;
    if (postId == null) return;
    final raw = (widget.comment['text'] ?? '').toString();
    final plain = raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final ctrl = TextEditingController(text: plain);

    final newText = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Редактировать комментарий',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          minLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration:
              const InputDecoration(hintText: 'Текст комментария...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || newText == null || newText.isEmpty || newText == plain) {
      return;
    }

    final settings = context.read<SettingsService>();
    final result = await DtfApi.editComment(
      commentId: _commentId,
      entryId: postId,
      text: newText,
      attachments: widget.comment['media'] as List?,
      settings: settings,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      setState(() {
        final updated = result['comment'];
        widget.comment['text'] = (updated is Map && updated['text'] != null)
            ? updated['text']
            : '<p>$newText</p>';
        widget.comment['isEdited'] = true;
      });
      _toast('Комментарий изменён');
    } else {
      _toast('Не удалось: ${result['error'] ?? 'ошибка'}');
    }
  }

  // I own this comment (its author is the logged-in user).
  bool get _isMyComment {
    final settings = context.read<SettingsService>();
    final authorId = widget.comment['author']?['id'] as int?;
    return settings.myUserId != null && settings.myUserId == authorId;
  }

  // Editing is allowed for a limited time after posting: 1 hour with Plus,
  // 1 minute otherwise (same rule as the official app / site).
  bool get _canEditNow {
    if (!_isMyComment) return false;
    final date = widget.comment['date'];
    if (date is! int) return false;
    final settings = context.read<SettingsService>();
    final ageSec = DateTime.now().millisecondsSinceEpoch ~/ 1000 - date;
    final windowSec = settings.myIsPlus ? 3600 : 60;
    return ageSec >= 0 && ageSec < windowSec;
  }

  void _showMenu(BuildContext ctx, dynamic author) {
    final settings = ctx.read<SettingsService>();
    final authorId = author?['id'] as int?;
    final authorName = author?['name'] ?? '';
    final currentNote =
        authorId != null ? settings.userNotes[authorId] : null;
    final canEdit = _canEditNow;

    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppColors.textPrimary),
                title: const Text('Редактировать комментарий',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog();
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined,
                  color: AppColors.textPrimary),
              title: const Text('Поставить реакцию',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                showReactionPicker(ctx, _react);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined,
                  color: AppColors.textPrimary),
              title: const Text('Кто поставил реакцию',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                showReactionUsers(
                    context: ctx,
                    id: _commentId,
                    isComment: true,
                    settings: settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: AppColors.textPrimary),
              title: const Text('Скопировать ссылку',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _copyLink();
              },
            ),
            ListTile(
              leading: Icon(
                  _isFavorited ? Icons.bookmark : Icons.bookmark_border,
                  color: AppColors.textPrimary),
              title: Text(_isFavorited ? 'Убрать из закладок' : 'В закладки',
                  style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _toggleBookmark();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined,
                  color: AppColors.textPrimary),
              title: const Text('Копировать текст',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _copyText();
              },
            ),
            if (authorId != null)
              ListTile(
                leading: const Icon(Icons.label_outline,
                    color: AppColors.textPrimary),
                title: Text(
                  currentNote != null
                      ? 'Изменить заметку для $authorName'
                      : 'Добавить заметку для $authorName',
                  style:
                      const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showNoteDialog(
                      ctx, settings, authorId, authorName, currentNote);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showNoteDialog(BuildContext ctx, SettingsService settings,
      int userId, String name, String? current) {
    final ctrl = TextEditingController(text: current ?? '');
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text('Заметка для $name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration:
              const InputDecoration(hintText: 'Напиши заметку...'),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () {
                settings.setUserNote(userId, '');
                Navigator.pop(ctx);
              },
              child: const Text('Удалить',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              settings.setUserNote(userId, ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  String _timeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    final date =
        DateTime.fromMillisecondsSinceEpoch((timestamp as int) * 1000);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes}м';
    if (diff.inHours < 24) return '${diff.inHours}ч';
    if (diff.inDays < 30) return '${diff.inDays}д';
    return '${(diff.inDays / 30).floor()}мес';
  }
}
