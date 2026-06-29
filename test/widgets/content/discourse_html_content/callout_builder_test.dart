import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/callout/callout_builder.dart';

void main() {
  testWidgets('callout 标题无 br 时不吞掉后续段落', (tester) async {
    String? renderedContentHtml;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: buildCalloutBlock(
                context: context,
                theme: Theme.of(context),
                innerHtml:
                    '<p>[!Note]CHANGELOG</p><p>第一段正文</p><p>第二段<br>继续</p>',
                type: 'note',
                title: 'CHANGELOG',
                titleHtml: null,
                foldable: null,
                htmlBuilder: (html, _) {
                  renderedContentHtml = html;
                  return Text(html);
                },
              ),
            );
          },
        ),
      ),
    );

    expect(renderedContentHtml, isNotNull);
    expect(renderedContentHtml, isNot(contains('[!Note]')));
    expect(renderedContentHtml, contains('<p>第一段正文</p>'));
    expect(renderedContentHtml, contains('<p>第二段<br>继续</p>'));
  });
}
