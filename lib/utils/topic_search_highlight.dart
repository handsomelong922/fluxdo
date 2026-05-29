import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class TopicSearchHighlight {
  static String highlightHtml(String html, String query) {
    final term = query.trim();
    if (term.isEmpty || html.isEmpty) return html;

    final fragment = html_parser.parseFragment(html);
    _highlightChildren(fragment.nodes, term.toLowerCase());
    return fragment.nodes.map(_serializeNode).join();
  }

  static int countPlainTextMatches(String html, String query) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty || html.isEmpty) return 0;

    final text = html_parser.parseFragment(html).text?.toLowerCase() ?? '';
    var count = 0;
    var start = 0;
    while (true) {
      final index = text.indexOf(term, start);
      if (index == -1) return count;
      count += 1;
      start = index + term.length;
    }
  }

  static void _highlightChildren(List<dom.Node> nodes, String lowerTerm) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is dom.Text) {
        final replacements = _highlightTextNode(node, lowerTerm);
        if (replacements == null) continue;
        nodes
          ..removeAt(i)
          ..insertAll(i, replacements);
        i += replacements.length - 1;
      } else if (node is dom.Element && !_shouldSkip(node)) {
        _highlightChildren(node.nodes, lowerTerm);
      }
    }
  }

  static List<dom.Node>? _highlightTextNode(dom.Text node, String lowerTerm) {
    final text = node.text;
    final lowerText = text.toLowerCase();
    if (!lowerText.contains(lowerTerm)) return null;

    final result = <dom.Node>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerTerm, start);
      if (index == -1) {
        if (start < text.length) {
          result.add(dom.Text(text.substring(start)));
        }
        break;
      }
      if (index > start) {
        result.add(dom.Text(text.substring(start, index)));
      }

      final mark = dom.Element.tag('mark')
        ..classes.add('topic-search-highlight')
        ..text = text.substring(index, index + lowerTerm.length);
      result.add(mark);
      start = index + lowerTerm.length;
    }

    return result;
  }

  static bool _shouldSkip(dom.Element element) {
    return switch (element.localName) {
      'script' || 'style' || 'code' || 'pre' || 'mark' => true,
      _ => false,
    };
  }

  static String _serializeNode(dom.Node node) {
    if (node is dom.Element) return node.outerHtml;
    if (node is dom.Text) return node.data;
    return node.text ?? '';
  }
}
