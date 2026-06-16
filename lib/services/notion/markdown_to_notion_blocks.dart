import 'package:markdown/markdown.dart' as md;

import '../../utils/url_helper.dart';

const int _richTextMaxLength = 1800;

class NotionUploadedFile {
  const NotionUploadedFile({
    required this.fileUploadId,
    required this.filename,
    required this.sourceUrl,
  });

  final String fileUploadId;
  final String filename;
  final String sourceUrl;
}

List<Map<String, dynamic>> markdownToNotionBlocks(
  String source, {
  Map<String, NotionUploadedFile> uploadedFiles = const {},
}) {
  if (source.trim().isEmpty) return const [];
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parseLines(
    source.replaceAll('\r\n', '\n').split('\n'),
  );
  final blocks = <Map<String, dynamic>>[];
  for (final node in nodes) {
    blocks.addAll(_nodeToBlocks(node, uploadedFiles: uploadedFiles));
  }
  return blocks;
}

List<Map<String, dynamic>> _nodeToBlocks(
  md.Node node, {
  required Map<String, NotionUploadedFile> uploadedFiles,
}) {
  if (node is md.Text) {
    return [
      _paragraph([_textRich(node.text)]),
    ];
  }
  if (node is! md.Element) return const [];

  switch (node.tag) {
    case 'h1':
      return [_heading(1, _inlineRich(node.children))];
    case 'h2':
      return [_heading(2, _inlineRich(node.children))];
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      return [_heading(3, _inlineRich(node.children))];
    case 'p':
      return _paragraphToBlocks(node, uploadedFiles: uploadedFiles);
    case 'hr':
      return [
        {'object': 'block', 'type': 'divider', 'divider': <String, dynamic>{}},
      ];
    case 'blockquote':
      return [_quoteBlock(node)];
    case 'pre':
      return [_codeBlockFromPre(node)];
    case 'ul':
      return _listChildrenToBlocks(node, 'bulleted_list_item');
    case 'ol':
      return _listChildrenToBlocks(node, 'numbered_list_item');
    case 'table':
      return [_tableToBlock(node)];
    case 'img':
      final url = node.attributes['src'];
      if (url == null || url.isEmpty) return const [];
      return [_imageBlock(url, alt: node.attributes['alt'])];
    default:
      return [_paragraph(_inlineRich(node.children))];
  }
}

List<Map<String, dynamic>> _paragraphToBlocks(
  md.Element paragraph, {
  required Map<String, NotionUploadedFile> uploadedFiles,
}) {
  final children = paragraph.children ?? const <md.Node>[];
  final hasImage = children.any(
    (node) => node is md.Element && node.tag == 'img',
  );
  final hasUploadedAttachment = children.any(
    (node) => _uploadedAttachmentForNode(node, uploadedFiles) != null,
  );
  if (!hasImage && !hasUploadedAttachment) {
    return [_paragraph(_inlineRich(children))];
  }

  final blocks = <Map<String, dynamic>>[];
  final buffer = <md.Node>[];

  void flushText() {
    if (buffer.isEmpty) return;
    final richText = _inlineRich(List<md.Node>.of(buffer));
    buffer.clear();
    final hasContent = richText.any((item) {
      final text = item['text'];
      if (text is! Map) return false;
      return (text['content']?.toString() ?? '').trim().isNotEmpty;
    });
    if (hasContent) blocks.add(_paragraph(richText));
  }

  for (final node in children) {
    final attachment = _uploadedAttachmentForNode(node, uploadedFiles);
    if (attachment != null) {
      flushText();
      blocks.add(_fileBlock(attachment));
    } else if (node is md.Text &&
        _isAttachmentSizeText(node.textContent) &&
        blocks.isNotEmpty) {
      continue;
    } else if (node is md.Element && node.tag == 'img') {
      flushText();
      final url = node.attributes['src'];
      if (url != null && url.isNotEmpty) {
        blocks.add(_imageBlock(url, alt: node.attributes['alt']));
      }
    } else {
      buffer.add(node);
    }
  }
  flushText();
  return blocks.isEmpty ? [_paragraph(const [])] : blocks;
}

NotionUploadedFile? _uploadedAttachmentForNode(
  md.Node node,
  Map<String, NotionUploadedFile> uploadedFiles,
) {
  if (node is! md.Element || node.tag != 'a') return null;
  if (!node.textContent.contains('|attachment')) return null;
  final href = node.attributes['href'];
  if (href == null || href.isEmpty) return null;
  return uploadedFiles[href] ?? uploadedFiles[UrlHelper.resolveUrl(href)];
}

bool _isAttachmentSizeText(String text) {
  return RegExp(r'^\s*\([^)]+\)\s*$').hasMatch(text);
}

Map<String, dynamic> _quoteBlock(md.Element node) {
  final richText = <Map<String, dynamic>>[];
  for (final child in node.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'p') {
      if (richText.isNotEmpty) richText.add(_textRich('\n'));
      richText.addAll(_inlineRich(child.children));
    } else if (child is md.Text) {
      richText.add(_textRich(child.text));
    }
  }
  return {
    'object': 'block',
    'type': 'quote',
    'quote': {
      'rich_text': richText.isEmpty ? [_textRich('')] : richText,
    },
  };
}

List<Map<String, dynamic>> _listChildrenToBlocks(md.Element list, String type) {
  final blocks = <Map<String, dynamic>>[];
  for (final item in list.children ?? const <md.Node>[]) {
    if (item is! md.Element || item.tag != 'li') continue;
    final richText = <Map<String, dynamic>>[];
    final children = <Map<String, dynamic>>[];
    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Text) {
        richText.add(_textRich(child.text));
      } else if (child is md.Element) {
        if (child.tag == 'p') {
          if (richText.isEmpty) {
            richText.addAll(_inlineRich(child.children));
          } else {
            children.add(_paragraph(_inlineRich(child.children)));
          }
        } else if (child.tag == 'ul' || child.tag == 'ol') {
          children.addAll(
            _listChildrenToBlocks(
              child,
              child.tag == 'ul' ? 'bulleted_list_item' : 'numbered_list_item',
            ),
          );
        } else {
          richText.addAll(_inlineRich([child]));
        }
      }
    }
    blocks.add({
      'object': 'block',
      'type': type,
      type: {
        'rich_text': richText.isEmpty ? [_textRich('')] : richText,
        if (children.isNotEmpty) 'children': children,
      },
    });
  }
  return blocks;
}

Map<String, dynamic> _tableToBlock(md.Element table) {
  final rows = <List<List<Map<String, dynamic>>>>[];
  for (final section in table.children ?? const <md.Node>[]) {
    if (section is! md.Element) continue;
    for (final row in section.children ?? const <md.Node>[]) {
      if (row is! md.Element || row.tag != 'tr') continue;
      final cells = <List<Map<String, dynamic>>>[];
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is md.Element) cells.add(_inlineRich(cell.children));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
  }
  if (rows.isEmpty) return _paragraph(const []);
  final columnCount = rows
      .map((row) => row.length)
      .fold<int>(
        0,
        (previous, current) => current > previous ? current : previous,
      );
  return {
    'object': 'block',
    'type': 'table',
    'table': {
      'table_width': columnCount,
      'has_column_header': true,
      'has_row_header': false,
      'children': [
        for (final row in rows)
          {
            'object': 'block',
            'type': 'table_row',
            'table_row': {
              'cells': [
                for (var i = 0; i < columnCount; i++)
                  i < row.length ? row[i] : [_textRich('')],
              ],
            },
          },
      ],
    },
  };
}

Map<String, dynamic> _codeBlockFromPre(md.Element pre) {
  var language = 'plain text';
  var text = pre.textContent;
  final children = pre.children ?? const <md.Node>[];
  final first = children.isEmpty ? null : children.first;
  if (first is md.Element && first.tag == 'code') {
    text = first.textContent;
    final className = first.attributes['class'];
    final match = className == null
        ? null
        : RegExp(r'language-([\w+#.-]+)').firstMatch(className);
    if (match != null) language = _mapNotionLanguage(match.group(1)!);
  }
  return {
    'object': 'block',
    'type': 'code',
    'code': {'rich_text': _splitRich(text), 'language': language},
  };
}

String _mapNotionLanguage(String input) {
  const aliases = {
    'js': 'javascript',
    'ts': 'typescript',
    'sh': 'shell',
    'bash': 'shell',
    'zsh': 'shell',
    'py': 'python',
    'yml': 'yaml',
    'md': 'markdown',
    'cpp': 'c++',
    'cc': 'c++',
    'cs': 'c#',
    'rs': 'rust',
    'kt': 'kotlin',
    'rb': 'ruby',
  };
  final mapped = aliases[input.toLowerCase()] ?? input.toLowerCase();
  const supported = {
    'abap',
    'arduino',
    'bash',
    'basic',
    'c',
    'clojure',
    'coffeescript',
    'c++',
    'c#',
    'css',
    'dart',
    'diff',
    'docker',
    'elixir',
    'elm',
    'erlang',
    'flow',
    'fortran',
    'f#',
    'gherkin',
    'glsl',
    'go',
    'graphql',
    'groovy',
    'haskell',
    'html',
    'java',
    'javascript',
    'json',
    'julia',
    'kotlin',
    'latex',
    'less',
    'lisp',
    'lua',
    'makefile',
    'markdown',
    'markup',
    'matlab',
    'mermaid',
    'nix',
    'objective-c',
    'ocaml',
    'pascal',
    'perl',
    'php',
    'plain text',
    'powershell',
    'python',
    'r',
    'ruby',
    'rust',
    'sass',
    'scala',
    'scheme',
    'scss',
    'shell',
    'sql',
    'swift',
    'typescript',
    'xml',
    'yaml',
  };
  return supported.contains(mapped) ? mapped : 'plain text';
}

List<Map<String, dynamic>> _inlineRich(List<md.Node>? nodes) {
  if (nodes == null) return const [];
  final richText = <Map<String, dynamic>>[];
  for (final node in nodes) {
    _inlineCollect(node, _Annotations.none, richText, null);
  }
  return richText;
}

void _inlineCollect(
  md.Node node,
  _Annotations annotations,
  List<Map<String, dynamic>> richText,
  String? href,
) {
  if (node is md.Text) {
    for (final chunk in _chunked(node.textContent)) {
      if (chunk.isNotEmpty) {
        richText.add(_richFromText(chunk, annotations, href));
      }
    }
    return;
  }
  if (node is! md.Element) return;
  switch (node.tag) {
    case 'em':
      _withChildren(node, annotations.copyWith(italic: true), richText, href);
      break;
    case 'strong':
      _withChildren(node, annotations.copyWith(bold: true), richText, href);
      break;
    case 'del':
      _withChildren(
        node,
        annotations.copyWith(strikethrough: true),
        richText,
        href,
      );
      break;
    case 'code':
      _withChildren(node, annotations.copyWith(code: true), richText, href);
      break;
    case 'a':
      _withChildren(
        node,
        annotations,
        richText,
        node.attributes['href'] ?? href,
      );
      break;
    case 'br':
      richText.add(_textRich('\n'));
      break;
    case 'img':
      final src = node.attributes['src'];
      final alt = node.attributes['alt'] ?? src ?? '';
      if (src != null) {
        richText.add(_richFromText(alt, annotations, src));
      }
      break;
    default:
      _withChildren(node, annotations, richText, href);
  }
}

void _withChildren(
  md.Element node,
  _Annotations annotations,
  List<Map<String, dynamic>> richText,
  String? href,
) {
  for (final child in node.children ?? const <md.Node>[]) {
    _inlineCollect(child, annotations, richText, href);
  }
}

class _Annotations {
  const _Annotations({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
  });

  static const none = _Annotations();

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  _Annotations copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
  }) {
    return _Annotations(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
    );
  }

  Map<String, dynamic>? toJson() {
    if (!bold && !italic && !strikethrough && !code) return null;
    return {
      if (bold) 'bold': true,
      if (italic) 'italic': true,
      if (strikethrough) 'strikethrough': true,
      if (code) 'code': true,
    };
  }
}

Map<String, dynamic> _richFromText(
  String text,
  _Annotations annotations,
  String? href,
) {
  final link = _normalizeLinkUrl(href);
  return {
    'type': 'text',
    'text': {
      'content': text,
      if (link != null) 'link': {'url': link},
    },
    if (annotations.toJson() != null) 'annotations': annotations.toJson(),
  };
}

String? _normalizeLinkUrl(String? raw) {
  if (raw == null) return null;
  var url = raw.trim();
  if (url.isEmpty || url.startsWith('#') || url.startsWith('upload://')) {
    return null;
  }
  url = UrlHelper.resolveUrl(url);
  const allowed = {'http', 'https', 'mailto', 'tel', 'sms', 'ftp'};
  final scheme = _schemeOf(url);
  if (scheme == null || !allowed.contains(scheme)) return null;
  final encoded = Uri.encodeFull(url);
  return encoded.length > 2000 ? null : encoded;
}

String? _normalizeImageUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty ||
      url.startsWith('upload://') ||
      url.startsWith('data:') ||
      url.startsWith('blob:')) {
    return null;
  }
  url = UrlHelper.resolveUrlWithCdn(url);
  if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return null;
  final encoded = Uri.encodeFull(url);
  return encoded.length > 2000 ? null : encoded;
}

String? _schemeOf(String url) {
  final colon = url.indexOf(':');
  if (colon <= 0) return null;
  final scheme = url.substring(0, colon).toLowerCase();
  return RegExp(r'^[a-z][a-z0-9+\-.]*$').hasMatch(scheme) ? scheme : null;
}

Map<String, dynamic> _textRich(String text) =>
    _richFromText(text, _Annotations.none, null);

List<Map<String, dynamic>> _splitRich(String text) {
  return [for (final chunk in _chunked(text)) _textRich(chunk)];
}

Iterable<String> _chunked(String text) sync* {
  if (text.length <= _richTextMaxLength) {
    yield text;
    return;
  }
  for (var i = 0; i < text.length; i += _richTextMaxLength) {
    final end = (i + _richTextMaxLength).clamp(0, text.length);
    yield text.substring(i, end);
  }
}

Map<String, dynamic> _paragraph(List<Map<String, dynamic>> richText) {
  return {
    'object': 'block',
    'type': 'paragraph',
    'paragraph': {
      'rich_text': richText.isEmpty ? [_textRich('')] : richText,
    },
  };
}

Map<String, dynamic> _heading(int level, List<Map<String, dynamic>> richText) {
  final type = 'heading_$level';
  return {
    'object': 'block',
    'type': type,
    type: {
      'rich_text': richText.isEmpty ? [_textRich('')] : richText,
    },
  };
}

Map<String, dynamic> _imageBlock(String url, {String? alt}) {
  final normalized = _normalizeImageUrl(url);
  if (normalized == null) {
    final label = alt != null && alt.isNotEmpty ? '[image] $alt' : '[image]';
    return _paragraph([_richFromText(label, _Annotations.none, url.trim())]);
  }
  return {
    'object': 'block',
    'type': 'image',
    'image': {
      'type': 'external',
      'external': {'url': normalized},
      if (alt != null && alt.isNotEmpty) 'caption': [_textRich(alt)],
    },
  };
}

Map<String, dynamic> _fileBlock(NotionUploadedFile file) {
  return {
    'object': 'block',
    'type': 'file',
    'file': {
      'type': 'file_upload',
      'file_upload': {'id': file.fileUploadId},
      'caption': [_textRich(file.filename)],
    },
  };
}
