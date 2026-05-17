class WebViewLoginNavigationDecider {
  const WebViewLoginNavigationDecider({required this.baseUri});

  static const thirdPartyLoginPathPrefixes = {
    '/auth/',
    '/u/auth/',
    '/session/sso',
  };

  final Uri baseUri;

  bool isThirdPartyLoginUri(Uri uri) {
    if (isEmailLoginUri(uri)) {
      return false;
    }

    if (isSameSiteUri(uri)) {
      final normalizedPath = _normalizePath(uri.path);
      return thirdPartyLoginPathPrefixes.any(
        (prefix) => normalizedPath.startsWith(prefix),
      );
    }

    return _looksLikeOAuthUri(uri);
  }

  bool isSameSiteUri(Uri uri) {
    if (uri.scheme != baseUri.scheme || uri.host != baseUri.host) {
      return false;
    }
    if (uri.hasPort != baseUri.hasPort) {
      return false;
    }
    return !uri.hasPort || uri.port == baseUri.port;
  }

  bool isEmailLoginUri(Uri uri) {
    return isSameSiteUri(uri) && uri.path.startsWith('/session/email-login/');
  }

  bool _looksLikeOAuthUri(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.contains('oauth') ||
        path.contains('authorize') ||
        path.contains('/auth/')) {
      return true;
    }

    const oauthParams = {
      'client_id',
      'redirect_uri',
      'response_type',
      'scope',
      'state',
      'oauth_token',
    };
    return uri.queryParameters.keys.any(
      (key) => oauthParams.contains(key.toLowerCase()),
    );
  }

  String _normalizePath(String path) {
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
  }
}
