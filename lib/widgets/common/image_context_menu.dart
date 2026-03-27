import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../pages/image_viewer_page.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/quote_builder.dart';
import '../content/discourse_html_content/image_utils.dart';

/// 图片长按上下文菜单
///
/// 提供统一的图片操作菜单，可在内容页和图片查看页复用。
class ImageContextMenu {
  ImageContextMenu._();

  /// 显示图片长按菜单
  ///
  /// [imageUrl] 图片 URL（会自动转换为原图 URL）
  /// [showViewFullImage] 是否显示「查看大图」选项（图片查看页内不需要）
  /// [post] 帖子对象（用于引用功能，为 null 时隐藏引用选项）
  /// [topicId] 话题 ID（用于引用功能）
  /// [onQuoteImage] 引用回调（打开回复框），为 null 时隐藏「引用」选项
  static void show({
    required BuildContext context,
    required String imageUrl,
    bool showViewFullImage = true,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
  }) {
    final originalUrl = DiscourseImageUtils.getOriginalUrl(imageUrl);

    showAppBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showViewFullImage)
                ListTile(
                  leading: const Icon(Icons.zoom_in),
                  title: Text(S.current.image_viewFull),
                  onTap: () {
                    Navigator.pop(ctx);
                    ImageViewerPage.open(
                      context,
                      originalUrl,
                      thumbnailUrl: imageUrl,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(S.current.image_copyImage),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyImage(originalUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(S.current.image_copyLink),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: originalUrl));
                  ToastService.showSuccess(S.current.common_linkCopied);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: Text(S.current.common_shareImage),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareImage(originalUrl);
                },
              ),
              if (post != null && topicId != null && onQuoteImage != null)
                ListTile(
                  leading: const Icon(Icons.format_quote),
                  title: Text(S.current.common_quote),
                  onTap: () {
                    Navigator.pop(ctx);
                    final quote = QuoteBuilder.build(
                      markdown: '![image]($originalUrl)',
                      username: post.username,
                      postNumber: post.postNumber,
                      topicId: topicId,
                    );
                    onQuoteImage(quote, post);
                  },
                ),
              if (post != null && topicId != null)
                ListTile(
                  leading: const Icon(Icons.copy_all),
                  title: Text(S.current.common_copyQuote),
                  onTap: () {
                    Navigator.pop(ctx);
                    final quote = QuoteBuilder.build(
                      markdown: '![image]($originalUrl)',
                      username: post.username,
                      postNumber: post.postNumber,
                      topicId: topicId,
                    );
                    Clipboard.setData(ClipboardData(text: quote));
                    ToastService.showSuccess(S.current.common_quoteCopied);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 复制图片到剪贴板
  static Future<void> _copyImage(String imageUrl) async {
    try {
      final bytes = await DiscourseCacheManager().getImageBytes(imageUrl);
      if (bytes == null || bytes.isEmpty) {
        ToastService.showError(S.current.image_fetchFailed);
        return;
      }
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        ToastService.showError(S.current.common_clipboardUnavailable);
        return;
      }
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      ToastService.showSuccess(S.current.image_copied);
    } catch (e) {
      debugPrint('[ImageContextMenu] copyImage error: $e');
      ToastService.showError(S.current.image_copyFailed);
    }
  }

  /// 分享图片
  static Future<void> _shareImage(String imageUrl) async {
    try {
      final file = await DiscourseCacheManager().getSingleFile(imageUrl);
      final ext = _getExtensionFromUrl(imageUrl);
      final xFile = XFile(file.path, mimeType: 'image/$ext');
      await SharePlus.instance.share(ShareParams(files: [xFile]));
    } catch (e) {
      debugPrint('[ImageContextMenu] shareImage error: $e');
      ToastService.showError(S.current.common_shareFailed);
    }
  }

  /// 从 URL 提取文件扩展名
  static String _getExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'png';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpeg';
    if (path.endsWith('.gif')) return 'gif';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.avif')) return 'avif';
    return 'png';
  }
}
