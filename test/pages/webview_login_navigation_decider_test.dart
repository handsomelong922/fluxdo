import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/webview_login_navigation_decider.dart';

void main() {
  final decider = WebViewLoginNavigationDecider(
    baseUri: Uri.parse('https://linux.do'),
  );

  group('WebViewLoginNavigationDecider.isThirdPartyLoginUri', () {
    test('same-site third-party auth path is recognized', () {
      expect(
        decider.isThirdPartyLoginUri(
          Uri.parse('https://linux.do/auth/google_oauth2'),
        ),
        isTrue,
      );
      expect(
        decider.isThirdPartyLoginUri(
          Uri.parse('https://linux.do/u/auth/github'),
        ),
        isTrue,
      );
      expect(
        decider.isThirdPartyLoginUri(
          Uri.parse('https://linux.do/session/sso_provider'),
        ),
        isTrue,
      );
    });

    test(
      'forum password login and email login are not treated as third-party flow',
      () {
        expect(
          decider.isThirdPartyLoginUri(Uri.parse('https://linux.do/session')),
          isFalse,
        );
        expect(
          decider.isThirdPartyLoginUri(
            Uri.parse('https://linux.do/session/email-login/token-123'),
          ),
          isFalse,
        );
      },
    );

    test('external oauth providers are recognized', () {
      expect(
        decider.isThirdPartyLoginUri(
          Uri.parse(
            'https://accounts.google.com/o/oauth2/auth?client_id=test&redirect_uri=https://linux.do/auth/google',
          ),
        ),
        isTrue,
      );
    });

    test('non-oauth external links are not misclassified', () {
      expect(
        decider.isThirdPartyLoginUri(
          Uri.parse('https://example.com/topics/123'),
        ),
        isFalse,
      );
    });
  });

  group('WebViewLoginNavigationDecider.isEmailLoginUri', () {
    test(
      'only same-site email login links are treated as email login flow',
      () {
        expect(
          decider.isEmailLoginUri(
            Uri.parse('https://linux.do/session/email-login/token-123'),
          ),
          isTrue,
        );
        expect(
          decider.isEmailLoginUri(
            Uri.parse('https://example.com/session/email-login/token-123'),
          ),
          isFalse,
        );
      },
    );
  });
}
