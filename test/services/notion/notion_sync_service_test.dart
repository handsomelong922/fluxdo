import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/notion/markdown_to_notion_blocks.dart';
import 'package:fluxdo/services/notion/notion_sync_service.dart';

void main() {
  test('已上传附件会写入 Notion files 属性 payload', () {
    final files = buildNotionFilesPropertyItems(const [
      NotionUploadedFile(
        fileUploadId: 'upload-id',
        filename: 'report.pdf',
        sourceUrl: 'https://linux.do/uploads/short-url/report.pdf',
      ),
    ]);

    expect(files, [
      {
        'name': 'report.pdf',
        'type': 'file_upload',
        'file_upload': {'id': 'upload-id'},
      },
    ]);
  });
}
