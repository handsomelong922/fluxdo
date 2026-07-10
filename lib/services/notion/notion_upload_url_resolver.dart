import '../discourse/discourse_service.dart';

final RegExp _uploadShortUrlPattern = RegExp(r'upload://[^\s\)\]<>"]+');

final RegExp _markdownLinkUploadPattern = RegExp(
  r'(!?)\[([^\]]*)\]\((upload://[^\s\)\]<>"]+)(\s+"[^"]*")?\)',
);

Set<String> collectNotionUploadShortUrls(String markdown) {
  return {
    for (final match in _uploadShortUrlPattern.allMatches(markdown))
      match.group(0)!,
  };
}

String replaceNotionUploadShortUrls(
  String markdown,
  Map<String, ResolvedUploadUrl> resolvedUploads, {
  required bool secureUploads,
}) {
  final withMarkdownLinks = markdown.replaceAllMapped(
    _markdownLinkUploadPattern,
    (match) {
      final original = match.group(0)!;
      final shortUrl = match.group(3)!;
      final resolved = resolvedUploads[shortUrl];
      if (resolved == null || resolved.isMissing) return original;

      final replacement = match.group(1) == '!'
          ? resolved.mediaUrl()
          : resolved.linkUrl(secureUploads: secureUploads);
      return original.replaceFirst(shortUrl, replacement);
    },
  );

  return withMarkdownLinks.replaceAllMapped(_uploadShortUrlPattern, (match) {
    final shortUrl = match.group(0)!;
    final resolved = resolvedUploads[shortUrl];
    if (resolved == null || resolved.isMissing) return shortUrl;
    return resolved.linkUrl(secureUploads: secureUploads);
  });
}
