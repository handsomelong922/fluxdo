import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/discourse_html_content_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('containsInlineCodeMarkup ignores fenced code blocks', () {
    const html = '<pre><code>final value = 1;</code></pre>';

    expect(DiscourseHtmlContent.containsInlineCodeMarkup(html), isFalse);
  });

  test('containsInlineCodeMarkup keeps inline code detection', () {
    const html = '<p>hello <code>world</code></p>';

    expect(DiscourseHtmlContent.containsInlineCodeMarkup(html), isTrue);
  });

  testWidgets('post emoji image has an independent repaint boundary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: Scaffold(
            body: DiscourseHtmlContent(
              html:
                  '<p><img class="emoji" src="https://example.com/wave.webp" '
                  'title=":wave:" width="20" height="20"></p>',
              enableSelectionArea: false,
              enablePanguSpacing: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final imageElement = tester.element(image);
    expect(
      imageElement.findAncestorWidgetOfExactType<RepaintBoundary>(),
      isNotNull,
    );
  });
}
