import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Card-style settings, matching the Figma "Settings" screen. Customization is
/// accent-color-only (AMOLED / custom photo background were removed).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _section('Внешний вид'),
          _accentColorTile(context, settings),
          _section('Комментарии'),
          _toggle(
            'Показывать удалённые комментарии',
            'Удалённые комменты будут видны со специальной пометкой',
            settings.showDeletedComments,
            (v) => settings.setShowDeletedComments(v),
          ),
          _toggle(
            'Автоматически раскрывать комментарии',
            'Основные ветки раскрываются при открытии поста',
            settings.autoExpandComments,
            (v) => settings.setAutoExpandComments(v),
          ),
          _section('Ленты'),
          _toggle(
            'Автоматически сворачивать просмотренные посты',
            'Посты, которые ты уже открывал, будут свёрнуты в ленте',
            settings.autoCollapseViewed,
            (v) => settings.setAutoCollapseViewed(v),
          ),
          _batchSizeTile(context, settings),
          _section('Фильтры'),
          _toggle(
            'Скрывать посты компаний',
            'Посты блогов с чёрной галочкой (компании) не появятся в ленте',
            settings.hideCompanyPosts,
            (v) => settings.setHideCompanyPosts(v),
          ),
          _filterKeywordsTile(context, settings),
          _section('Заметки о пользователях'),
          _userNotesTile(context, settings),
          _section('Кеш'),
          const _CacheTile(),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          title,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
      );

  /// Rounded card wrapper used for every settings row.
  static Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      );

  Widget _toggle(String title, String subtitle, bool value,
          void Function(bool) onChanged) =>
      _card(
        child: SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          value: value,
          onChanged: onChanged,
        ),
      );

  Widget _accentColorTile(BuildContext context, SettingsService settings) {
    final accent = settings.accentColor;
    const defaultAccent = Color(0xFF5B82F2);
    final isDefault = accent.toARGB32() == defaultAccent.toARGB32();

    return _card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: const Text('Цвет акцента',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        subtitle: const Text('Кнопки, ссылки, активные элементы',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDefault)
              GestureDetector(
                onTap: () => settings.resetAccentColor(),
                child: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child:
                      Icon(Icons.refresh, color: AppColors.textMuted, size: 22),
                ),
              ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              ),
            ),
          ],
        ),
        onTap: () => _showColorPicker(context, settings),
      ),
    );
  }

  void _showColorPicker(BuildContext context, SettingsService settings) {
    Color current = settings.accentColor;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Цвет акцента'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: current,
              onColorChanged: (c) => setState(() => current = c),
              enableAlpha: false,
              labelTypes: const [],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                settings.setAccentColor(current);
                Navigator.pop(ctx);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batchSizeTile(BuildContext context, SettingsService settings) => _card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: const Text('Постов за раз',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          subtitle: const Text('Сколько постов загружается при прокрутке',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          trailing: DropdownButton<int>(
            value: settings.batchSize,
            dropdownColor: AppColors.bgElevated,
            style: const TextStyle(color: AppColors.textPrimary),
            underline: const SizedBox(),
            items: [15, 20, 30, 50]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: (v) {
              if (v != null) settings.setBatchSize(v);
            },
          ),
        ),
      );

  Widget _filterKeywordsTile(BuildContext context, SettingsService settings) =>
      _card(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Скрыть по ключевым словам',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Посты с этими словами не появятся в ленте',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _addKeywordDialog(context, settings),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить', style: TextStyle(fontSize: 14)),
              ),
            ]),
            if (settings.filterKeywords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: settings.filterKeywords
                    .map((kw) => Chip(
                          label: Text(kw,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13)),
                          backgroundColor: AppColors.bgElevated,
                          deleteIcon: const Icon(Icons.close,
                              size: 16, color: AppColors.textMuted),
                          onDeleted: () => settings.removeFilterKeyword(kw),
                          side: BorderSide.none,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      );

  Widget _userNotesTile(BuildContext context, SettingsService settings) {
    if (settings.userNotes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(
          'Пока пусто. Добавить заметку можно через меню в посте или комментарии.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return _card(
      child: Column(
        children: settings.userNotes.entries
            .map((e) => ListTile(
                  title: Text('ID ${e.key}',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                  subtitle: Text(e.value,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.textMuted, size: 20),
                    onPressed: () => settings.setUserNote(e.key, ''),
                  ),
                ))
            .toList(),
      ),
    );
  }

  void _addKeywordDialog(BuildContext context, SettingsService settings) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить фильтр'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Ключевое слово...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              settings.addFilterKeyword(ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}

class _CacheTile extends StatefulWidget {
  const _CacheTile();

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  String _size = '…';
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _calcSize();
  }

  Future<void> _calcSize() async {
    try {
      final tmp = await getTemporaryDirectory();
      int total = 0;
      if (tmp.existsSync()) {
        await for (final e in tmp.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
      if (mounted) setState(() => _size = _fmt(total));
    } catch (_) {
      if (mounted) setState(() => _size = '—');
    }
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final tmp = await getTemporaryDirectory();
      if (tmp.existsSync()) {
        await for (final e in tmp.list()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _size = '…';
    });
    _calcSize();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Кеш очищен')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScreen._card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: const Text('Очистить кеш',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        subtitle: Text('Кешированные картинки, гифки и медиа · $_size',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        trailing: _clearing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.primary),
        onTap: _clearing ? null : _clear,
      ),
    );
  }
}
