import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/boundary_sync_service.dart';

void main() {
  group('BoundarySyncService.buildReadUrlsForSync', () {
    test('keeps primary url and additional app hosts in order', () {
      final urls = BoundarySyncService.buildReadUrlsForSync(
        'https://credit.linux.do/oauth/callback?code=1&state=2',
        [
          'https://connect.linux.do/oauth2/authorize',
          'https://credit.linux.do',
        ],
      );

      expect(urls, [
        'https://credit.linux.do/oauth/callback?code=1&state=2',
        'https://connect.linux.do/oauth2/authorize',
        'https://credit.linux.do',
      ]);
    });

    test('drops blanks, invalid urls, and duplicates', () {
      final urls = BoundarySyncService.buildReadUrlsForSync(
        'https://cdk.linux.do/callback',
        [
          '',
          'not-a-url',
          'https://cdk.linux.do/callback',
          ' https://connect.linux.do/oauth2/authorize ',
        ],
      );

      expect(urls, [
        'https://cdk.linux.do/callback',
        'https://connect.linux.do/oauth2/authorize',
      ]);
    });
  });
}
