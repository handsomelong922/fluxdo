part of 'discourse_service.dart';

class ResolvedUploadUrl {
  final String url;
  final String? shortPath;

  const ResolvedUploadUrl({required this.url, this.shortPath});

  /// `lookup-urls` 请求成功，但服务端未返回对应短链。
  static const missing = ResolvedUploadUrl(url: '');

  bool get isMissing => url.isEmpty;

  String mediaUrl() {
    if (url.contains('secure-media-uploads') ||
        url.contains('secure-uploads')) {
      return UrlHelper.resolveUrl(url);
    }

    return UrlHelper.resolveUrlWithCdn(url);
  }

  String linkUrl({required bool secureUploads}) {
    if (secureUploads &&
        (url.contains('secure-media-uploads') ||
            url.contains('secure-uploads'))) {
      return url;
    }

    return shortPath ?? url;
  }
}

class _UploadLookupBatchResult {
  const _UploadLookupBatchResult({
    required this.succeeded,
    this.uploads = const [],
  });

  const _UploadLookupBatchResult.failure()
    : succeeded = false,
      uploads = const [];

  final bool succeeded;
  final List<Map<String, dynamic>> uploads;
}

class DownloadedUploadFile {
  const DownloadedUploadFile({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// 上传结果
class UploadResult {
  final String shortUrl;
  final String? url;
  final String originalFilename;
  final int? width;
  final int? height;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final int? filesize;
  final String? humanFilesize;
  final String? extension;

  UploadResult({
    required this.shortUrl,
    this.url,
    required this.originalFilename,
    this.width,
    this.height,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.filesize,
    this.humanFilesize,
    this.extension,
  });

  static final _imageExts = RegExp(
    r'\.(png|webp|jpe?g|gif|svg|ico|heic|heif|avif)$',
    caseSensitive: false,
  );
  static final _videoExts = RegExp(
    r'\.(mov|mp4|webm|m4v|3gp|ogv|avi|mpeg)$',
    caseSensitive: false,
  );
  static final _audioExts = RegExp(
    r'\.(mp3|og[ga]|opus|wav|m4[abpr]|aac|flac)$',
    caseSensitive: false,
  );

  bool get isImage => _imageExts.hasMatch(originalFilename);
  bool get isVideo => _videoExts.hasMatch(originalFilename);
  bool get isAudio => _audioExts.hasMatch(originalFilename);

  /// 生成 Discourse 格式的 Markdown 图片语法
  /// 格式: ![alt|widthxheight](url)
  String toMarkdown({String? alt}) {
    final displayAlt = alt ?? originalFilename;
    // 优先使用缩略图尺寸，否则使用原图尺寸
    final w = thumbnailWidth ?? width;
    final h = thumbnailHeight ?? height;

    if (w != null && h != null) {
      return '![$displayAlt|${w}x$h]($shortUrl)';
    }
    return '![$displayAlt]($shortUrl)';
  }

  /// 根据文件类型自动生成正确的 Markdown
  String toAutoMarkdown({String? alt}) {
    if (isImage) return toMarkdown(alt: alt);
    final name = alt ?? originalFilename;
    if (isVideo) return '![$name|video]($shortUrl)';
    if (isAudio) return '![$name|audio]($shortUrl)';
    // 附件格式: [filename|attachment](short_url) (human_filesize)
    final sizeStr = filesize != null ? formatFileSize(filesize!) : '';
    return '[$originalFilename|attachment]($shortUrl)${sizeStr.isNotEmpty ? ' ($sizeStr)' : ''}';
  }

  /// 客户端本地化文件大小格式化（对齐 Discourse i18n）
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return S.current.common_sizeBytes(bytes.toString());
    }
    if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      final str = kb == kb.roundToDouble()
          ? kb.toInt().toString()
          : kb.toStringAsFixed(1);
      return S.current.common_sizeKB(str);
    }
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      final str = mb == mb.roundToDouble()
          ? mb.toInt().toString()
          : mb.toStringAsFixed(1);
      return S.current.common_sizeMB(str);
    }
    final gb = bytes / (1024 * 1024 * 1024);
    final str = gb == gb.roundToDouble()
        ? gb.toInt().toString()
        : gb.toStringAsFixed(1);
    return S.current.common_sizeGB(str);
  }
}

/// 上传相关
mixin _UploadsMixin on _DiscourseServiceBase {
  static const Duration _uploadLookupBatchWindow = Duration(milliseconds: 8);
  static const int _mobileUploadUrlCacheEntries = 192;
  static const int _desktopUploadUrlCacheEntries = 512;

  final Map<String, Future<ResolvedUploadUrl?>> _activeUploadResolves = {};
  final Map<String, Completer<ResolvedUploadUrl?>> _pendingUploadResolves = {};
  Timer? _uploadLookupBatchTimer;
  int _uploadLookupGeneration = 0;

  int get _maxUploadUrlCacheEntries => Platform.isAndroid || Platform.isIOS
      ? _mobileUploadUrlCacheEntries
      : _desktopUploadUrlCacheEntries;

  bool _hasCachedUpload(String shortUrl) => _urlCache.containsKey(shortUrl);

  ResolvedUploadUrl? _readCachedUpload(String shortUrl) {
    if (!_urlCache.containsKey(shortUrl)) return null;
    final cached = _urlCache.remove(shortUrl)!;
    _urlCache[shortUrl] = cached;
    return cached;
  }

  void _cacheUpload(String shortUrl, ResolvedUploadUrl resolved) {
    _urlCache.remove(shortUrl);
    while (_urlCache.length >= _maxUploadUrlCacheEntries) {
      _urlCache.remove(_urlCache.keys.first);
    }
    _urlCache[shortUrl] = resolved;
  }

  /// 登出/换账号时清空会话级正负缓存，并让旧会话在途结果失效。
  @override
  void resetUploadLookupSessionState({String reason = 'logout'}) {
    _uploadLookupGeneration++;
    _uploadLookupBatchTimer?.cancel();
    _uploadLookupBatchTimer = null;

    final pending = _pendingUploadResolves.values.toList(growable: false);
    _pendingUploadResolves.clear();
    _activeUploadResolves.clear();
    _urlCache.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete(null);
    }
    debugPrint('[DiscourseService] upload lookup 会话状态已复位: $reason');
  }

  /// 获取图片请求头
  Future<Map<String, String>> getHeaders() async {
    final headers = <String, String>{'User-Agent': AppConstants.userAgent};

    final cookies = await _cookieJar.getCookieHeader();
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }

    return headers;
  }

  /// 下载图片
  Future<Uint8List?> downloadImage(String url) async {
    try {
      final isAppHost = CookieJarService.matchesAppHost(Uri.parse(url).host);
      final extra = <String, dynamic>{'skipCsrf': true, 'skipAuthCheck': true};
      if (isAppHost) {
        extra[WebViewHttpAdapter.resourceKindExtraKey] =
            WebViewHttpAdapter.resourceKindImage;
        extra[WebViewHttpAdapter.cookieModeExtraKey] =
            WebViewHttpAdapter.cookieModeReadOnly;
      }

      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes, extra: extra),
      );

      if (response.data is! List<int>) {
        debugPrint(
          '[DiscourseService] Invalid response data type for image: $url',
        );
        return null;
      }

      final bytes = Uint8List.fromList(response.data);

      if (bytes.isEmpty) {
        debugPrint('[DiscourseService] Empty image data: $url');
        return null;
      }

      final contentType = response.headers.value('content-type')?.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) {
        debugPrint(
          '[DiscourseService] Invalid content-type for image: $contentType, url: $url',
        );
        return null;
      }

      if (!_isValidImageData(bytes)) {
        debugPrint(
          '[DiscourseService] Invalid image data (magic bytes check failed): $url',
        );
        return null;
      }

      return bytes;
    } catch (e) {
      debugPrint('[DiscourseService] Download image failed: $e, url: $url');
      return null;
    }
  }

  /// 下载上传附件，供导出/Notion 同步持久化附件使用。
  Future<DownloadedUploadFile?> downloadUploadFile(
    String url, {
    String? suggestedFilename,
    int maxBytes = 20 * 1024 * 1024,
    bool background = false,
  }) async {
    final resolvedUrl = UrlHelper.resolveUrl(url);
    try {
      final response = await _dio.get<List<int>>(
        resolvedUrl,
        options: _backgroundReadOptions(
          background: background,
          options: Options(
            responseType: ResponseType.bytes,
            extra: {
              'skipCsrf': true,
              'skipAuthCheck': true,
              'showErrorToast': false,
            },
          ),
        ),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        debugPrint('[DiscourseService] Empty upload file data: $resolvedUrl');
        return null;
      }
      if (data.length > maxBytes) {
        debugPrint(
          '[DiscourseService] Upload file too large for Notion: '
          '${data.length} bytes, url: $resolvedUrl',
        );
        return null;
      }

      final contentType = response.headers
          .value('content-type')
          ?.split(';')
          .first
          .trim();
      final filename =
          _filenameFromContentDisposition(
            response.headers.value('content-disposition'),
          ) ??
          _sanitizeFilename(suggestedFilename) ??
          _filenameFromUrl(resolvedUrl) ??
          'attachment';

      return DownloadedUploadFile(
        bytes: Uint8List.fromList(data),
        filename: filename,
        contentType: (contentType == null || contentType.isEmpty)
            ? 'application/octet-stream'
            : contentType,
      );
    } catch (e) {
      debugPrint(
        '[DiscourseService] Download upload file failed: '
        '$e, url: $resolvedUrl',
      );
      return null;
    }
  }

  String? _filenameFromContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    final utf8Match = RegExp(
      r'''filename\*=UTF-8''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(header);
    if (utf8Match != null) {
      return _sanitizeFilename(
        Uri.decodeComponent(utf8Match.group(1)!.replaceAll('"', '')),
      );
    }

    final match = RegExp(
      r'''filename="?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(header);
    if (match == null) return null;
    return _sanitizeFilename(match.group(1));
  }

  String? _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri == null || uri.pathSegments.isEmpty
        ? null
        : uri.pathSegments.last;
    return _sanitizeFilename(segment);
  }

  String? _sanitizeFilename(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// 验证图片数据是否有效
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }

    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    // GIF
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }

    // WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }

    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true;
    }

    // ICO
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        bytes[2] == 0x01 &&
        bytes[3] == 0x00) {
      return true;
    }

    return false;
  }

  /// 上传文件（内置速率限制重试，支持图片和附件）
  Future<UploadResult> uploadFile(String filePath) async {
    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final fileName = filePath.split('/').last;

        final formData = FormData.fromMap({
          'upload_type': 'composer',
          'synchronous': true,
          'file': await MultipartFile.fromFile(filePath, filename: fileName),
        });

        final response = await _dio.post(
          '/uploads.json',
          queryParameters: {'client_id': MessageBusService().clientId},
          data: formData,
          options: Options(
            extra: {
              'showErrorToast': attempt >= maxRetries,
              WebViewHttpAdapter.resourceKindExtraKey:
                  WebViewHttpAdapter.resourceKindUpload,
            },
          ), // 仅最后一次尝试才弹 toast
        );

        final data = response.data;
        if (data is Map) {
          final shortUrl = data['short_url'] as String?;
          if (shortUrl != null) {
            return UploadResult(
              shortUrl: shortUrl,
              url: data['url'] as String?,
              originalFilename:
                  data['original_filename'] as String? ?? fileName,
              width: data['width'] as int?,
              height: data['height'] as int?,
              thumbnailWidth: data['thumbnail_width'] as int?,
              thumbnailHeight: data['thumbnail_height'] as int?,
              filesize: data['filesize'] as int?,
              humanFilesize: data['human_filesize'] as String?,
              extension: data['extension'] as String?,
            );
          }
          // 兜底：使用完整 URL
          final url = data['url'] as String?;
          if (url != null) {
            return UploadResult(
              shortUrl: url,
              url: url,
              originalFilename:
                  data['original_filename'] as String? ?? fileName,
              width: data['width'] as int?,
              height: data['height'] as int?,
              thumbnailWidth: data['thumbnail_width'] as int?,
              thumbnailHeight: data['thumbnail_height'] as int?,
              filesize: data['filesize'] as int?,
              humanFilesize: data['human_filesize'] as String?,
              extension: data['extension'] as String?,
            );
          }
        }

        throw Exception(S.current.error_uploadNoUrl);
      } on DioException catch (e) {
        debugPrint('[DiscourseService] Upload image failed: $e');

        // ErrorInterceptor 将 429 throw 为 RateLimitException，
        // Dio 会将其包装在 DioException.error 中
        final innerError = e.error;
        if (innerError is RateLimitException && attempt < maxRetries) {
          final waitSeconds = innerError.retryAfterSeconds ?? 10;
          debugPrint(
            '[DiscourseService] 速率限制，等待 ${waitSeconds}s 后重试 '
            '(${attempt + 1}/$maxRetries)',
          );
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        if (e.response?.statusCode == 413) {
          throw Exception(S.current.error_imageTooBig);
        }
        if (e.response?.statusCode == 422) {
          final data = e.response?.data;
          if (data is Map && data['errors'] != null) {
            throw Exception((data['errors'] as List).join('\n'));
          }
          throw Exception(S.current.error_imageFormatUnsupported);
        }
        rethrow;
      } catch (e) {
        debugPrint('[DiscourseService] Upload image failed: $e');
        rethrow;
      }
    }

    // 不可达，但编译器需要
    throw Exception(S.current.error_uploadNoUrl);
  }

  /// 上传图片（uploadFile 的别名，保持向后兼容）
  Future<UploadResult> uploadImage(String filePath) => uploadFile(filePath);

  Future<_UploadLookupBatchResult> _lookupUrlsWithStatus(
    List<String> shortUrls, {
    int? expectedGeneration,
  }) async {
    final generation = expectedGeneration ?? _uploadLookupGeneration;
    if (generation != _uploadLookupGeneration) {
      return const _UploadLookupBatchResult.failure();
    }

    final uniqueUrls = <String>{
      for (final url in shortUrls)
        if (url.startsWith('upload://')) url,
    };
    final missingUrls = uniqueUrls
        .where((url) => !_hasCachedUpload(url))
        .toList(growable: false);

    if (missingUrls.isEmpty) {
      return const _UploadLookupBatchResult(succeeded: true);
    }

    try {
      final response = await _dio.post(
        '/uploads/lookup-urls',
        data: {'short_urls': missingUrls},
      );

      if (generation != _uploadLookupGeneration || response.data is! List) {
        return const _UploadLookupBatchResult.failure();
      }

      final uploads = response.data as List<dynamic>;
      final result = <Map<String, dynamic>>[];
      final returnedUrls = <String>{};

      for (final item in uploads) {
        if (item is Map) {
          final normalized = Map<String, dynamic>.from(item);
          result.add(normalized);
          final shortUrl = normalized['short_url'] as String?;
          final url = normalized['url'] as String?;
          if (shortUrl != null &&
              url != null &&
              uniqueUrls.contains(shortUrl)) {
            returnedUrls.add(shortUrl);
            _cacheUpload(
              shortUrl,
              ResolvedUploadUrl(
                url: url,
                shortPath: normalized['short_path'] as String?,
              ),
            );
          }
        }
      }

      for (final shortUrl in missingUrls) {
        if (!returnedUrls.contains(shortUrl)) {
          _cacheUpload(shortUrl, ResolvedUploadUrl.missing);
        }
      }
      return _UploadLookupBatchResult(succeeded: true, uploads: result);
    } catch (e) {
      debugPrint('[DiscourseService] lookupUrls failed: $e');
      return const _UploadLookupBatchResult.failure();
    }
  }

  /// 批量解析 short_url。临时失败仍保持历史返回空列表语义，但不会写 missing。
  Future<List<Map<String, dynamic>>> lookupUrls(List<String> shortUrls) async {
    final result = await _lookupUrlsWithStatus(shortUrls);
    return result.uploads;
  }

  void _scheduleUploadLookupFlush() {
    _uploadLookupBatchTimer ??= Timer(_uploadLookupBatchWindow, () {
      _uploadLookupBatchTimer = null;
      unawaited(_flushPendingUploadLookups());
    });
  }

  Future<void> _flushPendingUploadLookups() async {
    if (_pendingUploadResolves.isEmpty) return;

    final generation = _uploadLookupGeneration;
    final pending = Map<String, Completer<ResolvedUploadUrl?>>.from(
      _pendingUploadResolves,
    );
    _pendingUploadResolves.clear();
    final result = await _lookupUrlsWithStatus(
      pending.keys.toList(growable: false),
      expectedGeneration: generation,
    );

    for (final entry in pending.entries) {
      if (entry.value.isCompleted) continue;
      final resolved = result.succeeded && generation == _uploadLookupGeneration
          ? _readCachedUpload(entry.key)
          : null;
      entry.value.complete(resolved);
    }
  }

  /// 解析单个 short_url。同一短链共享 Future，同一短窗口内的多条短链合并 POST。
  Future<ResolvedUploadUrl?> resolveShortUpload(String shortUrl) {
    if (!shortUrl.startsWith('upload://')) {
      return Future.value(
        ResolvedUploadUrl(url: shortUrl, shortPath: shortUrl),
      );
    }

    if (_hasCachedUpload(shortUrl)) {
      return Future.value(_readCachedUpload(shortUrl));
    }

    final active = _activeUploadResolves[shortUrl];
    if (active != null) return active;

    final completer = Completer<ResolvedUploadUrl?>();
    late final Future<ResolvedUploadUrl?> future;
    future = completer.future.whenComplete(() {
      if (identical(_activeUploadResolves[shortUrl], future)) {
        _activeUploadResolves.remove(shortUrl);
      }
    });
    _activeUploadResolves[shortUrl] = future;
    _pendingUploadResolves[shortUrl] = completer;
    _scheduleUploadLookupFlush();
    return future;
  }

  Future<String?> resolveShortUrl(String shortUrl) async {
    if (!shortUrl.startsWith('upload://')) return shortUrl;

    final resolved = await resolveShortUpload(shortUrl);
    if (resolved == null || resolved.isMissing) return null;
    return resolved.mediaUrl();
  }

  Future<String?> resolveShortUrlForLink(String shortUrl) async {
    if (!shortUrl.startsWith('upload://')) return shortUrl;

    final resolved = await resolveShortUpload(shortUrl);
    if (resolved == null || resolved.isMissing) return null;

    final secureUploads =
        PreloadedDataService().siteSettingsSync?['secure_uploads'] == true;
    return resolved.linkUrl(secureUploads: secureUploads);
  }
}
