import 'dart:async';
import 'dart:isolate';

/// 在可终止的隔离区中编译和执行 Dart 原生正则，避免阻塞界面。
///
/// 不限制 SDK 支持的正则语法、不修剪空白，也不截断标题。资源越界、
/// 语法错误、超时或工作隔离区异常都会明确失败，不会悄悄跳过规则。
class TopicRegexRules {
  TopicRegexRules._();

  /// 长度使用 Dart 字符串的 UTF-16 代码单元计数。
  static const maxPatternLength = 65536;
  static const maxTotalPatternLength = 262144;
  static const maxRules = 32;
  static const jobTimeout = Duration(seconds: 2);

  /// 保存前与实际匹配走同一隔离执行路径，主隔离区不编译用户正则。
  static Future<void> validate(List<String> patterns) async {
    await match(patterns, const []).result;
  }

  /// 返回与 [titles] 一一对应的结果；true 表示至少有一条规则匹配。
  /// 调用方应及时处理 [TopicRegexJob.result] 的错误并取消过时任务。
  static TopicRegexJob match(List<String> patterns, List<String> titles) {
    return TopicRegexJob._(patterns, titles);
  }
}

/// 一次批量匹配的句柄。取消会终止工作隔离区，而非仅忽略其结果。
class TopicRegexJob {
  final _completer = Completer<List<bool>>();
  final _clock = Stopwatch()..start();
  ReceivePort? _events;
  Timer? _timer;
  Isolate? _isolate;

  TopicRegexJob._(List<String> patterns, List<String> titles) {
    try {
      // 只执行有界的长度检查和输入快照，绝不在调用线程构造 RegExp。
      if (patterns.length > TopicRegexRules.maxRules) {
        throw const FormatException('count');
      }
      final sources = List<String>.unmodifiable(patterns);
      var total = 0;
      for (final source in sources) {
        if (source.isEmpty ||
            source.length > TopicRegexRules.maxPatternLength) {
          throw const FormatException('length');
        }
        total += source.length;
        if (total > TopicRegexRules.maxTotalPatternLength) {
          throw const FormatException('total');
        }
      }
      final texts = List<String>.unmodifiable(titles);
      final events = ReceivePort();
      _events = events;
      events.listen(_onMessage);
      _timer = Timer(TopicRegexRules.jobTimeout, () {
        _fail(const FormatException('timeout'));
      });
      unawaited(_start(sources, texts, events.sendPort));
    } on FormatException catch (error) {
      _fail(error);
    } catch (error) {
      _fail(FormatException('worker', error.toString()));
    }
  }

  Future<List<bool>> get result => _completer.future;

  /// 可重复调用；已完成的任务保持原有结果。
  void cancel() => _fail(const FormatException('cancelled'));

  Future<void> _start(
    List<String> patterns,
    List<String> titles,
    SendPort port,
  ) async {
    try {
      final isolate = await Isolate.spawn<_TopicRegexRequest>(
        _runTopicRegex,
        _TopicRegexRequest(patterns, titles, port),
        // 先获得终止句柄再启动，覆盖创建途中取消或超时的竞态。
        paused: true,
        errorsAreFatal: true,
        onError: port,
        onExit: port,
        debugName: 'topic-regex',
      );
      if (_completer.isCompleted) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = isolate;
      if (_clock.elapsed >= TopicRegexRules.jobTimeout) {
        _fail(const FormatException('timeout'));
        return;
      }
      isolate.resume(isolate.pauseCapability!);
    } catch (error) {
      _fail(FormatException('worker', error.toString()));
    }
  }

  void _onMessage(dynamic message) {
    if (_completer.isCompleted) return;
    // 即使事件队列使计时器晚于结果送达，也不能接受过期结果。
    if (_clock.elapsed >= TopicRegexRules.jobTimeout) {
      _fail(const FormatException('timeout'));
      return;
    }
    if (message is _TopicRegexResponse) {
      if (message.error != null) {
        _fail(FormatException(message.error!, message.detail, message.offset));
      } else if (message.matches != null) {
        _dispose();
        _completer.complete(List<bool>.unmodifiable(message.matches!));
      } else {
        _fail(const FormatException('worker'));
      }
      return;
    }
    // 未捕获异常通过 onError 发来列表，意外退出通过 onExit 发来 null。
    // 两者都不得被误当作「未匹配」。
    final detail = message is List && message.isNotEmpty
        ? '${message.first}'
        : null;
    _fail(FormatException('worker', detail));
  }

  void _fail(FormatException error) {
    if (_completer.isCompleted) return;
    _dispose();
    _completer.completeError(error);
  }

  void _dispose() {
    _clock.stop();
    _timer?.cancel();
    _timer = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _events?.close();
    _events = null;
  }
}

class _TopicRegexRequest {
  final List<String> patterns;
  final List<String> titles;
  final SendPort port;

  const _TopicRegexRequest(this.patterns, this.titles, this.port);
}

class _TopicRegexResponse {
  final List<bool>? matches;
  final String? error;
  final String? detail;
  final int? offset;

  const _TopicRegexResponse.success(this.matches)
    : error = null,
      detail = null,
      offset = null;

  const _TopicRegexResponse.failure(this.error, [this.detail, this.offset])
    : matches = null;
}

/// 顶层入口避免闭包意外携带 UI 对象；所有用户正则只在此处编译和运行。
void _runTopicRegex(_TopicRegexRequest request) {
  late final _TopicRegexResponse response;
  try {
    // 先编译全部规则，再匹配标题；空标题批次也完整验证每一条规则。
    final rules = [
      for (final source in request.patterns)
        RegExp(source, caseSensitive: false),
    ];
    final matches = <bool>[
      for (final title in request.titles)
        rules.any((rule) => rule.hasMatch(title)),
    ];
    response = _TopicRegexResponse.success(matches);
  } on FormatException catch (error) {
    response = _TopicRegexResponse.failure(
      'syntax',
      error.message,
      error.offset,
    );
  } catch (error) {
    response = _TopicRegexResponse.failure('worker', error.toString());
  }
  // 原子交付结果并退出；正常退出也不会留下空闲隔离区或未关闭的端口。
  Isolate.exit(request.port, response);
}
