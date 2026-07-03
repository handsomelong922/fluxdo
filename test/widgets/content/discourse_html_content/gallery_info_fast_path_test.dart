import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/content/discourse_html_content/image_utils.dart';

void main() {
  test('GalleryInfo.fromHtml returns empty info without lightbox markup', () {
    final info = GalleryInfo.fromHtml('<p>plain reply without images</p>');

    expect(info.images, isEmpty);
    expect(info.heroTags, isEmpty);
    expect(info.spoilerImageUrls, isEmpty);
  });
}
