/// 新回复的有限重试预算；整体重载后代次递增，旧响应不能再落地。
class TopicNewPostRetry {
  int generation = 0;
  int _failures = 0;

  void reset() {
    generation++;
    succeeded();
  }

  void succeeded() => _failures = 0;

  Duration? failed() {
    _failures++;
    return _failures <= 5
        ? Duration(seconds: 3 << (_failures - 1))
        : null;
  }
}
