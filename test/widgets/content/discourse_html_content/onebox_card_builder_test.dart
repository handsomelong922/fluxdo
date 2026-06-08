import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/builders/onebox_card_builder.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  testWidgets('onebox card delegates taps to injected link handler', (
    tester,
  ) async {
    const url = 'https://linux.do/n/topic/388420?sort=old';
    final fragment = html_parser.parseFragment('''
<aside class="onebox" data-onebox-src="$url">
  <article>
    <h3><a href="$url">引用的话题</a></h3>
    <p>帖子中引用的链接预览</p>
  </article>
</aside>
''');
    final element = fragment.children.single;
    final tappedUrls = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => buildOneboxCard(
              context: context,
              theme: Theme.of(context),
              element: element,
              onLinkTap: (tapUrl) async => tappedUrls.add(tapUrl),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('引用的话题'));
    await tester.pump();

    expect(tappedUrls, <String>[url]);
  });
}
