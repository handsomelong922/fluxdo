import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/notion/notion_upload_url_resolver.dart';
import 'package:fluxdo/utils/url_helper.dart';

void main() {
  setUp(() {
    UrlHelper.debugSetOverrides(
      baseUri: '',
      cdnUrl: 'https://cdn.example.com',
      s3CdnUrl: 'https://cdn3.example.com',
      s3BaseUrl: '//uploads.example.com',
    );
  });

  tearDown(() {
    UrlHelper.debugClearOverrides();
  });

  test('分别按图片和附件语义替换 upload 短链', () {
    const markdown = '''
![screenshot|690x200](upload://imagehash.png)

[report.pdf|attachment](upload://filehash.pdf) (12 KB)
''';

    final resolved = replaceNotionUploadShortUrls(markdown, {
      'upload://imagehash.png': const ResolvedUploadUrl(
        url: '/uploads/default/original/1X/screenshot.png',
        shortPath: '/uploads/short-url/screenshot.png',
      ),
      'upload://filehash.pdf': const ResolvedUploadUrl(
        url: '/uploads/default/original/1X/report.pdf',
        shortPath: '/uploads/short-url/report.pdf',
      ),
    }, secureUploads: false);

    expect(
      resolved,
      contains(
        '![screenshot|690x200](https://cdn.example.com/uploads/default/original/1X/screenshot.png)',
      ),
    );
    expect(
      resolved,
      contains('[report.pdf|attachment](/uploads/short-url/report.pdf)'),
    );
    expect(resolved, isNot(contains('[report.pdf|attachment](https://')));
    expect(resolved, isNot(contains('upload://')));
  });

  test('安全附件保留 secure uploads 下载地址', () {
    const markdown = '[secret.pdf|attachment](upload://securehash.pdf)';

    final resolved = replaceNotionUploadShortUrls(markdown, {
      'upload://securehash.pdf': const ResolvedUploadUrl(
        url: '/secure-uploads/default/original/1X/secret.pdf',
        shortPath: '/uploads/short-url/secret.pdf',
      ),
    }, secureUploads: true);

    expect(
      resolved,
      '[secret.pdf|attachment](/secure-uploads/default/original/1X/secret.pdf)',
    );
  });

  test('服务端确认 missing 时保留原始短链', () {
    const markdown = '![missing](upload://missing.png)';

    final resolved = replaceNotionUploadShortUrls(markdown, {
      'upload://missing.png': ResolvedUploadUrl.missing,
    }, secureUploads: false);

    expect(resolved, markdown);
  });

  test('收集 Markdown 中的 upload 短链并去重', () {
    final urls = collectNotionUploadShortUrls(
      '![a](upload://same.png) [b](upload://same.png) '
      '[c](upload://other.pdf)',
    );

    expect(urls, {'upload://same.png', 'upload://other.pdf'});
  });
}
