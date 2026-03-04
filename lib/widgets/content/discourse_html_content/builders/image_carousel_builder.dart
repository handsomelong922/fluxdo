import 'package:flutter/material.dart';
import '../../../../services/discourse_cache_manager.dart';
import '../image_utils.dart';
import 'image_grid_builder.dart';

/// 构建 Discourse 图片轮播 (d-image-grid mode=carousel)
Widget buildImageCarousel({
  required BuildContext context,
  required ThemeData theme,
  required List<GridImageData> images,
  required GalleryInfo galleryInfo,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: _ImageCarousel(
      theme: theme,
      images: images,
      galleryInfo: galleryInfo,
    ),
  );
}

/// 图片轮播组件
/// 参考 Discourse image-carousel.gjs 实现
class _ImageCarousel extends StatefulWidget {
  final ThemeData theme;
  final List<GridImageData> images;
  final GalleryInfo galleryInfo;

  const _ImageCarousel({
    required this.theme,
    required this.images,
    required this.galleryInfo,
  });

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  /// 与 Discourse 一致：超过 10 张时用计数器替代圆点
  static const int _maxDots = 10;

  /// 轮播高度
  static const double _carouselHeight = 300.0;

  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isSingle => widget.images.length < 2;
  bool get _showDots => widget.images.length <= _maxDots;

  void _goToPage(int index) {
    if (index < 0 || index >= widget.images.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openViewer(BuildContext context, int imageIndex, String resolvedFullUrl) {
    final imageData = widget.images[imageIndex];
    final galleryImages = widget.galleryInfo.images;
    final heroTags = widget.galleryInfo.heroTags;
    final globalIndex = widget.galleryInfo.findIndex(imageData.src)
        ?? widget.galleryInfo.findIndex(imageData.fullSrc)
        ?? -1;

    final heroTag = globalIndex >= 0 && globalIndex < heroTags.length
        ? heroTags[globalIndex]
        : 'carousel_${imageData.src.hashCode}';

    final resolvedGalleryImages = galleryImages
        .map((url) => DiscourseImageUtils.getOriginalUrl(url))
        .toList();
    if (globalIndex >= 0 && globalIndex < resolvedGalleryImages.length) {
      resolvedGalleryImages[globalIndex] =
          DiscourseImageUtils.getOriginalUrl(resolvedFullUrl);
    }

    DiscourseImageUtils.openViewer(
      context: context,
      imageUrl: DiscourseImageUtils.getOriginalUrl(resolvedFullUrl),
      heroTag: heroTag,
      thumbnailUrl: resolvedFullUrl,
      galleryImages: resolvedGalleryImages,
      thumbnailUrls: galleryImages,
      heroTags: heroTags,
      initialIndex: globalIndex >= 0 ? globalIndex : 0,
      filenames: widget.galleryInfo.filenames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 轮播轨道
        SizedBox(
          height: _carouselHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // 背景色
                Positioned.fill(
                  child: Container(
                    color: widget.theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                // PageView
                PageView.builder(
                  controller: _pageController,
                  itemCount: widget.images.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return _buildSlide(context, index);
                  },
                ),
                // 导航按钮（仅多张图片时显示）
                if (!_isSingle) ...[
                  // 上一张
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavButton(
                        icon: Icons.chevron_left,
                        onTap: _currentIndex > 0
                            ? () => _goToPage(_currentIndex - 1)
                            : null,
                      ),
                    ),
                  ),
                  // 下一张
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavButton(
                        icon: Icons.chevron_right,
                        onTap: _currentIndex < widget.images.length - 1
                            ? () => _goToPage(_currentIndex + 1)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 指示器（仅多张图片时显示）
        if (!_isSingle) ...[
          const SizedBox(height: 8),
          if (_showDots)
            _DotsIndicator(
              count: widget.images.length,
              currentIndex: _currentIndex,
              onTap: _goToPage,
            )
          else
            Text(
              '${_currentIndex + 1} / ${widget.images.length}',
              style: widget.theme.textTheme.bodySmall?.copyWith(
                color: widget.theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }

  /// 构建单张幻灯片
  Widget _buildSlide(BuildContext context, int index) {
    final imageData = widget.images[index];

    // 处理 upload:// 短链接
    if (DiscourseImageUtils.isUploadUrl(imageData.src)) {
      if (DiscourseImageUtils.isUploadUrlCached(imageData.src)) {
        final resolvedUrl =
            DiscourseImageUtils.getCachedUploadUrl(imageData.src);
        if (resolvedUrl != null) {
          return _buildSlideImage(context, index, resolvedUrl);
        }
        return _buildErrorSlide();
      }

      return FutureBuilder<String?>(
        future: DiscourseImageUtils.resolveUploadUrl(imageData.src),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingSlide();
          }
          if (snapshot.data == null) return _buildErrorSlide();
          return _buildSlideImage(context, index, snapshot.data!);
        },
      );
    }

    return _buildSlideImage(context, index, imageData.src);
  }

  /// 构建幻灯片图片（含 Hero 动画和点击查看）
  Widget _buildSlideImage(BuildContext context, int index, String displayUrl) {
    final imageData = widget.images[index];
    final globalIndex = widget.galleryInfo.findIndex(imageData.src)
        ?? widget.galleryInfo.findIndex(imageData.fullSrc)
        ?? -1;
    final heroTags = widget.galleryInfo.heroTags;
    final heroTag = globalIndex >= 0 && globalIndex < heroTags.length
        ? heroTags[globalIndex]
        : 'carousel_${imageData.src.hashCode}';

    return GestureDetector(
      onTap: () => _openViewer(context, index, displayUrl),
      child: Hero(
        tag: heroTag,
        child: Image(
          image: discourseImageProvider(displayUrl),
          fit: BoxFit.contain,
          width: double.infinity,
          height: _carouselHeight,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.broken_image,
                color: widget.theme.colorScheme.outline,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingSlide() {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildErrorSlide() {
    return Center(
      child: Icon(
        Icons.broken_image,
        color: widget.theme.colorScheme.outline,
      ),
    );
  }
}

/// 导航按钮
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap != null ? 1.0 : 0.3,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 圆点指示器
/// 与 Discourse 一致：活跃的圆点更宽（胶囊状）
class _DotsIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _DotsIndicator({
    required this.count,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == currentIndex;
        return GestureDetector(
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 20.0 : 8.0,
            height: 8.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
        );
      }),
    );
  }
}
