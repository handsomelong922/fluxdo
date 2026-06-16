import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/notion/markdown_to_notion_blocks.dart';
import 'package:fluxdo/utils/url_helper.dart';

void main() {
  setUp(() {
    UrlHelper.debugSetOverrides(baseUri: '');
  });

  tearDown(() {
    UrlHelper.debugClearOverrides();
  });

  test('已上传附件链接转换为 Notion file_upload block', () {
    final blocks = markdownToNotionBlocks(
      '[report.pdf|attachment](/uploads/short-url/report.pdf) (12 KB)',
      uploadedFiles: const {
        'https://linux.do/uploads/short-url/report.pdf': NotionUploadedFile(
          fileUploadId: 'upload-id',
          filename: 'report.pdf',
          sourceUrl: 'https://linux.do/uploads/short-url/report.pdf',
        ),
      },
    );

    expect(blocks, hasLength(1));
    expect(blocks.single['type'], 'file');
    expect(blocks.single['file'], {
      'type': 'file_upload',
      'file_upload': {'id': 'upload-id'},
      'caption': [
        {
          'type': 'text',
          'text': {'content': 'report.pdf'},
        },
      ],
    });
  });

  test('未上传附件保留为普通链接文本', () {
    final blocks = markdownToNotionBlocks(
      '[report.pdf|attachment](/uploads/short-url/report.pdf) (12 KB)',
    );

    expect(blocks.single['type'], 'paragraph');
    final richText = blocks.single['paragraph']['rich_text'] as List<dynamic>;
    expect(richText.first['text']['content'], 'report.pdf|attachment');
    expect(
      richText.first['text']['link']['url'],
      'https://linux.do/uploads/short-url/report.pdf',
    );
  });
}
