import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/giphy_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Opens the GIF picker. Resolves to the chosen [GifResult], or null if cancelled.
Future<GifResult?> showGifPicker(BuildContext context) {
  return showModalBottomSheet<GifResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _GifPickerSheet(),
  );
}

class _GifPickerSheet extends StatefulWidget {
  const _GifPickerSheet();

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final _searchController = TextEditingController();
  List<GifResult> _results = [];
  bool _loading = true;
  bool _showingRecent = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadRecentOrTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadRecentOrTrending() {
    final recent = context.read<SettingsService>().recentGifs;
    if (recent.isNotEmpty) {
      setState(() {
        _showingRecent = true;
        _results = recent.map((m) => GifResult.fromStored(m)).toList();
        _loading = false;
      });
    } else {
      _search('');
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String query) async {
    setState(() { _loading = true; _showingRecent = false; });
    final results = await GiphyService.search(query);
    if (!mounted) return;
    setState(() { _results = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Поиск GIF в GIPHY',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    filled: true,
                    fillColor: AppColors.bgCard,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ]),
          ),
          if (_showingRecent && _results.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Недавние', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('Ничего не найдено', style: TextStyle(color: Colors.grey)))
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final gif = _results[i];
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, gif),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: gif.previewUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(color: AppColors.bgElevated),
                                errorWidget: (_, _, _) => Container(
                                  color: AppColors.bgElevated,
                                  child: const Icon(Icons.gif_box_outlined, color: Colors.grey),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
