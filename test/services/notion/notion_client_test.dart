import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/notion/notion_client.dart';

void main() {
  test('导出数据库模板包含文件与媒体附件列', () {
    final properties = notionExportDatabaseProperties();
    final upgradeable = notionExportUpgradeableProperties();

    expect(properties['Attachments'], {'files': <String, dynamic>{}});
    expect(upgradeable['Attachments'], {'files': <String, dynamic>{}});
  });

  test('页面属性包含 file_upload 时使用新版 Notion API', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.notion.com/v1/'))
      ..httpClientAdapter = adapter;
    final client = NotionClient('secret_test', dio: dio);

    await client.createPage(
      databaseId: 'database_id',
      properties: {
        'Name': {
          'title': [
            {
              'type': 'text',
              'text': {'content': 'title'},
            },
          ],
        },
        'Attachments': {
          'files': [
            {
              'name': 'report.pdf',
              'type': 'file_upload',
              'file_upload': {'id': 'upload-id'},
            },
          ],
        },
      },
    );

    expect(adapter.paths, ['pages']);
    expect(adapter.notionVersions.single, '2026-03-11');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final paths = <String>[];
  final notionVersions = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    notionVersions.add(options.headers['Notion-Version']?.toString());
    return ResponseBody.fromString(
      '{"id":"page-id","url":"https://notion.so/page-id"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
