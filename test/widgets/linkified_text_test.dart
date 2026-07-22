import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dtf_app/widgets/linkified_text.dart';

void main() {
  const widgetKey = ValueKey('linkified');

  Future<void> pumpText(WidgetTester tester, String html) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkifiedText(
            html,
            key: widgetKey,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  RichText richText(WidgetTester tester) => tester.widget<RichText>(
        find.descendant(
          of: find.byKey(widgetKey),
          matching: find.byType(RichText),
        ),
      );

  List<TapGestureRecognizer> recognizers(RichText text) {
    final result = <TapGestureRecognizer>[];

    void visit(InlineSpan span) {
      if (span is! TextSpan) return;
      final recognizer = span.recognizer;
      if (recognizer is TapGestureRecognizer) result.add(recognizer);
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }

    visit(text.text);
    return result;
  }

  testWidgets('parses anchor and bare URL segments', (tester) async {
    await pumpText(
      tester,
      'До <a href="https://dtf.ru/1">ссылки</a> и www.example.com',
    );

    final text = richText(tester);
    expect(text.text.toPlainText(), 'До ссылки и www.example.com');
    expect(recognizers(text), hasLength(2));
  });

  testWidgets('reparses text and replaces recognizers when html changes',
      (tester) async {
    await pumpText(tester, '<a href="https://old.example">Старая</a>');
    final oldRecognizer = recognizers(richText(tester)).single;

    await pumpText(
      tester,
      '<a href="https://new.example">Новая</a> и https://second.example',
    );

    final text = richText(tester);
    final updatedRecognizers = recognizers(text);
    expect(text.text.toPlainText(), 'Новая и https://second.example');
    expect(updatedRecognizers, hasLength(2));
    expect(updatedRecognizers, isNot(contains(same(oldRecognizer))));
  });
}
