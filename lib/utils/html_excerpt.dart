final Map<int, String> _htmlExcerptCache = <int, String>{};
const int _htmlExcerptCacheMaxEntries = 512;

String cleanHtmlExcerpt(String html) {
  final key = Object.hash(html.length, html.hashCode);
  final cached = _htmlExcerptCache[key];
  if (cached != null) {
    return cached;
  }

  final cleaned = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&hellip;', '...')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (_htmlExcerptCache.length >= _htmlExcerptCacheMaxEntries) {
    _htmlExcerptCache.remove(_htmlExcerptCache.keys.first);
  }
  _htmlExcerptCache[key] = cleaned;
  return cleaned;
}
