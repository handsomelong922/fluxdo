class UrlParseUtils {
  UrlParseUtils._();

  static Uri? tryParseLenient(String url) {
    final trimmed = url.trim();
    return Uri.tryParse(trimmed) ??
        Uri.tryParse(normalizeUrlForParsing(trimmed));
  }

  static String normalizeUrlForParsing(String url) {
    final trimmed = url.trim();
    final fragmentIndex = trimmed.indexOf('#');
    final beforeFragment = fragmentIndex == -1
        ? trimmed
        : trimmed.substring(0, fragmentIndex);
    final fragment = fragmentIndex == -1
        ? ''
        : trimmed.substring(fragmentIndex);
    final queryIndex = beforeFragment.indexOf('?');
    if (queryIndex == -1) return trimmed;

    final beforeQuery = beforeFragment.substring(0, queryIndex);
    final query = beforeFragment.substring(queryIndex + 1);
    final normalizedQuery = query
        .replaceAll(RegExp(r'\s*=\s*'), '=')
        .replaceAll(RegExp(r'\s*&\s*'), '&');
    return '$beforeQuery?$normalizedQuery$fragment';
  }
}
