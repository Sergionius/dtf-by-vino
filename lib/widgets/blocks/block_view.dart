import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/block.dart';
import '../../theme.dart';
import '../../util/external_link.dart';
import '../../util/osnova_image.dart';
import '../linkified_text.dart';
import '../media_view.dart';

/// Renders a single parsed [Block]. One widget per type, exhaustively
/// matched — an unhandled case is a compile error, not a silent blank.
class BlockView extends StatelessWidget {
  final Block block;
  const BlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final b = block;
    return switch (b) {
      TextBlock() => _text(b),
      HeaderBlock() => _header(b),
      MediaBlock() => _media(b),
      QuoteBlock() => _quote(b, accent),
      ListBlock() => _list(b, accent),
      DividerBlock() => _divider(),
      CodeBlock() => _code(b),
      AudioBlock() => _audio(b, accent),
      QuizBlock() => _quiz(b, accent),
      LinkCardBlock() => _linkCard(b, accent),
      UnsupportedBlock() => const SizedBox(),
    };
  }

  Widget _text(TextBlock b) {
    if (b.html.replaceAll(RegExp(r'<[^>]*>'), '').trim().isEmpty) {
      return const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LinkifiedText(
        b.html,
        style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 16, height: 1.65),
      ),
    );
  }

  Widget _header(HeaderBlock b) {
    final text = b.text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3)),
    );
  }

  Widget _media(MediaBlock b) {
    if (b.items.isEmpty) return const SizedBox();
    return Column(
      children: b.items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaView(media: item.raw, maxHeight: 500),
              if (item.caption != null && item.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.caption!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _quote(QuoteBlock b, Color accent) {
    final text =
        b.text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final subtitle =
        (b.subtitle ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        color: const Color(0xFF141414),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  height: 1.5)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('— $subtitle',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _list(ListBlock b, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: b.items.asMap().entries.map((e) {
          final text = e.value.replaceAll(RegExp(r'<[^>]*>'), '');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      b.ordered ? '${e.key + 1}.' : '•',
                      style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(text,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.5)),
                  ),
                ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text('* * *',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 16, letterSpacing: 8)),
      ),
    );
  }

  Widget _code(CodeBlock b) {
    if (b.code.trim().isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.bgElevated),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          b.code,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.4),
        ),
      ),
    );
  }

  Widget _audio(AudioBlock b, Color accent) {
    return GestureDetector(
      onTap: () =>
          openExternalUrl('https://leonardo.osnova.io/audio/${b.uuid}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.bgElevated),
        ),
        child: Row(children: [
          Icon(Icons.play_circle_fill, color: accent, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                b.title?.isNotEmpty == true ? b.title! : 'Аудио',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.open_in_new,
              color: AppColors.textMuted, size: 16),
        ]),
      ),
    );
  }

  Widget _quiz(QuizBlock b, Color accent) {
    if (b.items.isEmpty) return const SizedBox();
    final maxVotes =
        b.items.map((i) => i.votes).fold(0, (a, c) => c > a ? c : a);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bar_chart, color: accent, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  b.title?.isNotEmpty == true ? b.title! : 'Опрос',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          ...b.items.map((item) {
            final fraction =
                maxVotes > 0 ? item.votes / maxVotes : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.text,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  if (maxVotes > 0) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 5,
                        backgroundColor: AppColors.bgElevated,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 2),
          const Text('Открой на сайте, чтобы проголосовать',
              style:
                  TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _linkCard(LinkCardBlock b, Color accent) {
    if ((b.url == null || b.url!.isEmpty) &&
        (b.title == null || b.title!.isEmpty)) {
      return const SizedBox();
    }
    final label = b.title?.isNotEmpty == true
        ? b.title!
        : (b.url ?? _serviceLabel(b.service));
    return GestureDetector(
      onTap: b.url != null ? () => openExternalUrl(b.url!) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.bgElevated),
        ),
        child: Row(children: [
          if (b.thumbUuid != null && b.thumbUuid!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                // Link blocks sometimes give a full favicon URL instead of a uuid.
                imageUrl: b.thumbUuid!.startsWith('http')
                    ? b.thumbUuid!
                    : OsnovaImage(b.thumbUuid).preview(96),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                    width: 48, height: 48, color: AppColors.bgElevated),
                errorWidget: (_, _, _) => Container(
                    width: 48, height: 48, color: AppColors.bgElevated),
              ),
            ),
            const SizedBox(width: 10),
          ] else ...[
            Icon(_serviceIcon(b.service), color: accent, size: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (b.subtitle != null && b.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(b.subtitle!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (b.url != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new,
                color: AppColors.textMuted, size: 16),
          ],
        ]),
      ),
    );
  }

  IconData _serviceIcon(String service) {
    switch (service) {
      case 'tweet':
        return Icons.link;
      case 'telegram':
        return Icons.send;
      case 'spotify':
      case 'yamusic':
        return Icons.music_note;
      case 'game':
        return Icons.sports_esports;
      case 'button':
        return Icons.touch_app;
      case 'person':
        return Icons.person;
      case 'youtube':
        return Icons.play_circle_outline;
      case 'twitch':
        return Icons.videogame_asset;
      default:
        return Icons.link;
    }
  }

  String _serviceLabel(String service) {
    const labels = {
      'tweet': 'Твит',
      'telegram': 'Telegram',
      'spotify': 'Spotify',
      'yamusic': 'Яндекс Музыка',
      'game': 'Игра',
      'button': 'Ссылка',
      'person': 'Профиль',
      'link': 'Ссылка',
    };
    return labels[service] ?? service;
  }
}
