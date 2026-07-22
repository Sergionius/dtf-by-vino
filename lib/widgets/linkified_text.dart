import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../util/external_link.dart';

/// Renders text that may contain HTML `<a href>` links and/or bare URLs,
/// turning every link into a tappable blue span.
class LinkifiedText extends StatefulWidget {
  final String html;
  final TextStyle style;
  final int? maxLines;

  const LinkifiedText(this.html, {super.key, required this.style, this.maxLines});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkSegment {
  final String text;
  final String? url;
  const _LinkSegment(this.text, [this.url]);
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<_LinkSegment> _segments = const [];

  static final _anchorRe = RegExp(r'''<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''',
      caseSensitive: false, dotAll: true);
  static final _urlRe = RegExp(r'(https?://[^\s<]+|www\.[^\s<]+)', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _parse(widget.html);
  }

  @override
  void didUpdateWidget(covariant LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) _parse(widget.html);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  String _decode(String s) => s
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n')
      .replaceAll('</p>', '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&laquo;', '«')
      .replaceAll('&raquo;', '»')
      .replaceAll('&mdash;', '—');

  void _addPlainSegments(List<_LinkSegment> segments, String text) {
    var last = 0;
    for (final match in _urlRe.allMatches(text)) {
      if (match.start > last) {
        segments.add(_LinkSegment(text.substring(last, match.start)));
      }
      final url = match.group(0)!;
      segments.add(_LinkSegment(url, url));
      last = match.end;
    }
    if (last < text.length) segments.add(_LinkSegment(text.substring(last)));
  }

  void _parse(String html) {
    _disposeRecognizers();
    final segments = <_LinkSegment>[];
    var last = 0;

    for (final match in _anchorRe.allMatches(html)) {
      if (match.start > last) {
        _addPlainSegments(
            segments, _decode(html.substring(last, match.start)));
      }
      final href = match.group(1)!;
      final label = _decode(match.group(2)!).trim();
      segments.add(_LinkSegment(label.isEmpty ? href : label, href));
      last = match.end;
    }
    if (last < html.length) {
      _addPlainSegments(segments, _decode(html.substring(last)));
    }

    _segments = segments;
    for (final segment in _segments) {
      final url = segment.url;
      if (url == null) continue;
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => openExternalUrl(url),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(color: Theme.of(context).colorScheme.primary);
    var recognizerIndex = 0;
    final spans = <InlineSpan>[];

    for (final segment in _segments) {
      final url = segment.url;
      if (url == null) {
        spans.add(TextSpan(text: segment.text));
      } else {
        spans.add(TextSpan(
          text: segment.text,
          style: linkStyle,
          recognizer: _recognizers[recognizerIndex++],
        ));
      }
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}
