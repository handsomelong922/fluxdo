/// 标题过滤使用的正则安全子集。
///
/// 用 Thompson NFA 执行匹配，复杂度随标题长度和编译状态数线性增长，
/// 不调用 Dart 回溯引擎匹配完整表达式。单字符类仍交由 RegExp 处理，
/// 保持与 Dart 默认（非 Unicode、大小写无关）模式一致的字符语义。
/// 不支持环视、反向引用和命名分组；贪婪/惰性对布尔匹配结果没有区别。
class TopicRegexRules {
  TopicRegexRules._();

  static const maxPatternLength = 2048;
  static const maxRules = 32;
  static const maxStates = 512;
  static const maxTotalStates = 2048;
  static const maxTitleLength = 4096;
  static const maxRepeat = 64;
  static final _cache = <String, SafeTopicRegex>{};
  static int _cachedStates = 0;

  static SafeTopicRegex compile(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    if (source.isEmpty || source.length > maxPatternLength) {
      throw const FormatException('length');
    }
    final root = _Parser(source).parse();
    final compiler = _Compiler();
    final fragment = compiler.compile(root);
    final accept = compiler.add(_State(_Kind.accept));
    compiler.patch(fragment.ends, accept);
    final result = SafeTopicRegex._(compiler.states, fragment.start);
    // 只保留近期规则，避免反复编辑长规则导致缓存无限增长。
    while (_cache.length >= 64 || _cachedStates + compiler.states.length > 4096) {
      final removed = _cache.remove(_cache.keys.first)!;
      _cachedStates -= removed._states.length;
    }
    _cache[source] = result;
    _cachedStates += compiler.states.length;
    return result;
  }

  static void validate(List<String> patterns) {
    if (patterns.length > maxRules) throw const FormatException('count');
    var states = 0;
    for (final pattern in patterns) {
      states += compile(pattern)._states.length;
      if (states > maxTotalStates) throw const FormatException('complexity');
    }
  }

  /// 旧备份或手工修改的偏好可能包含坏规则；读取时跳过而不使页面崩溃。
  static List<SafeTopicRegex> compileValid(Iterable<String> patterns) {
    final result = <SafeTopicRegex>[];
    var states = 0;
    for (final pattern in patterns.take(maxRules)) {
      try {
        final compiled = compile(pattern);
        if (states + compiled._states.length > maxTotalStates) continue;
        states += compiled._states.length;
        result.add(compiled);
      } on FormatException {
        continue;
      }
    }
    return result;
  }
}

class SafeTopicRegex {
  final List<_State> _states;
  final int _start;
  final _matches = <String, bool>{};
  int _cachedCharacters = 0;

  SafeTopicRegex._(this._states, this._start);

  bool hasMatch(String text) {
    // 异常超长标题保留可见，不截断后匹配，以免改变 $ 等锚点的语义。
    if (text.length > TopicRegexRules.maxTitleLength) return false;
    final cached = _matches[text];
    if (cached != null) return cached;
    final result = _match(text);
    // 容纳常见的上千条已加载标题，同时每条规则最多保留 256 Ki 个字符。
    // 64 条编译缓存的标题正文最坏约 32 MiB（UTF-16），通常共享同一标题对象。
    while (_matches.length >= 1024 || _cachedCharacters + text.length > 262144) {
      final removed = _matches.keys.first;
      _matches.remove(removed);
      _cachedCharacters -= removed.length;
    }
    _matches[text] = result;
    _cachedCharacters += text.length;
    return result;
  }

  bool _match(String text) {
    var current = <int>[];
    final visited = List<int>.filled(_states.length, -1);
    var generation = 0;
    for (var position = 0; position <= text.length; position++) {
      // 每个位置都能成为非锚定表达式的起点，合并相同状态避免回溯。
      _closure(_start, position, text, current, visited, generation);
      for (final index in current) {
        if (_states[index].kind == _Kind.accept) return true;
      }
      if (position == text.length) break;
      final next = <int>[];
      generation++;
      final code = text.codeUnitAt(position);
      for (final index in current) {
        final state = _states[index];
        if (state.kind == _Kind.character && state.matches(code)) {
          _closure(state.next, position + 1, text, next, visited, generation);
        }
      }
      current = next;
    }
    return false;
  }

  void _closure(int start, int position, String text, List<int> active,
      List<int> visited, int generation) {
    final pending = <int>[start];
    while (pending.isNotEmpty) {
      final index = pending.removeLast();
      if (visited[index] == generation) continue;
      visited[index] = generation;
      final state = _states[index];
      switch (state.kind) {
        case _Kind.split:
          pending.add(state.next);
          if (state.other >= 0) pending.add(state.other);
        case _Kind.start:
          if (position == 0) pending.add(state.next);
        case _Kind.end:
          if (position == text.length) pending.add(state.next);
        case _Kind.boundary:
        case _Kind.notBoundary:
          final left = position > 0 && _word(text.codeUnitAt(position - 1));
          final right = position < text.length && _word(text.codeUnitAt(position));
          if ((left != right) == (state.kind == _Kind.boundary)) {
            pending.add(state.next);
          }
        case _Kind.character:
        case _Kind.accept:
          active.add(index);
      }
    }
  }

  static bool _word(int code) =>
      (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) || code == 95;
}

enum _Kind { split, character, start, end, boundary, notBoundary, accept }

class _State {
  final _Kind kind;
  final RegExp? character;
  int next = -1;
  int other = -1;
  final _characters = <int, bool>{};
  _State(this.kind, [this.character]);

  bool matches(int code) {
    final cached = _characters[code];
    if (cached != null) return cached;
    final result = character!.hasMatch(String.fromCharCode(code));
    if (_characters.length < 64) _characters[code] = result;
    return result;
  }
}

class _Node {
  final String kind;
  final String? atom;
  final List<_Node> children;
  final int min;
  final int? max;
  _Node(this.kind, {this.atom, this.children = const [], this.min = 0, this.max});
}

class _Parser {
  final String source;
  int position = 0;
  int depth = 0;
  _Parser(this.source);

  _Node parse() {
    final result = _alternative();
    if (position != source.length) throw const FormatException('syntax');
    return result;
  }

  bool _take(String value) {
    if (!source.startsWith(value, position)) return false;
    position += value.length;
    return true;
  }

  _Node _alternative() {
    final children = <_Node>[_sequence()];
    while (_take('|')) {
      children.add(_sequence());
    }
    return children.length == 1 ? children.single : _Node('or', children: children);
  }

  _Node _sequence() {
    final children = <_Node>[];
    while (position < source.length && source[position] != ')' && source[position] != '|') {
      children.add(_repetition());
    }
    return _Node('sequence', children: children);
  }

  _Node _repetition() {
    final atom = _atom();
    int min;
    int? max;
    if (_take('*')) {
      min = 0;
    } else if (_take('+')) {
      min = 1;
    } else if (_take('?')) {
      min = 0;
      max = 1;
    } else if (_take('{')) {
      min = _number();
      if (_take(',')) {
        max = position < source.length && source[position] != '}' ? _number() : null;
      } else {
        max = min;
      }
      if (!_take('}') || (max != null && max < min)) {
        throw const FormatException('syntax');
      }
      if (min > TopicRegexRules.maxRepeat || (max != null && max > TopicRegexRules.maxRepeat)) {
        throw const FormatException('repeat');
      }
    } else {
      return atom;
    }
    if (['start', 'end', 'boundary', 'notBoundary'].contains(atom.kind)) {
      throw const FormatException('syntax');
    }
    _take('?'); // 布尔匹配无需区分贪婪与惰性。
    return _Node('repeat', children: [atom], min: min, max: max);
  }

  int _number() {
    final start = position;
    while (position < source.length && _digit(source.codeUnitAt(position))) {
      position++;
    }
    if (position == start) throw const FormatException('syntax');
    final result = int.tryParse(source.substring(start, position));
    if (result == null) throw const FormatException('repeat');
    return result;
  }

  _Node _atom() {
    if (position >= source.length) throw const FormatException('syntax');
    final start = position;
    final character = source[position++];
    if (character == '(') {
      if (++depth > 32) throw const FormatException('complexity');
      if (_take('?') && !_take(':')) throw const FormatException('unsupported');
      final node = _alternative();
      if (!_take(')')) throw const FormatException('syntax');
      depth--;
      return node;
    }
    if (character == '^') return _Node('start');
    if (character == r'$') return _Node('end');
    if ('*+?{}'.contains(character)) throw const FormatException('syntax');
    if (character == '[') {
      var closed = false;
      while (position < source.length) {
        final next = source[position++];
        if (next == r'\') {
          _escape(inClass: true);
        } else if (next == ']') {
          closed = true;
          break;
        }
      }
      if (!closed) throw const FormatException('syntax');
    } else if (character == r'\') {
      if (position < source.length && source[position] == 'b') {
        position++;
        return _Node('boundary');
      }
      if (position < source.length && source[position] == 'B') {
        position++;
        return _Node('notBoundary');
      }
      _escape();
    }
    final atom = source.substring(start, position);
    // 每个原子仅消耗一个 UTF-16 单元，完整规则永远不会进入回溯引擎。
    try {
      RegExp(atom, caseSensitive: false);
    } on FormatException {
      throw const FormatException('syntax');
    }
    return _Node('character', atom: atom);
  }

  void _escape({bool inClass = false}) {
    if (position >= source.length) throw const FormatException('syntax');
    final escaped = source[position++];
    // 拒绝身份转义、八进制、Unicode 属性等易与用户预期产生歧义的语法。
    if (_digit(escaped.codeUnitAt(0)) || 'kpcP'.contains(escaped)) {
      throw const FormatException('unsupported');
    }
    if (escaped == 'x' || escaped == 'u') {
      final count = escaped == 'x' ? 2 : 4;
      if (position + count > source.length) throw const FormatException('syntax');
      final hex = source.substring(position, position + count);
      if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
        throw const FormatException('syntax');
      }
      position += count;
    } else if (!r'nrtvfdDsSwW\.^$|?*+()[]{}-/'.contains(escaped) &&
        !(inClass && escaped == 'b')) {
      throw const FormatException('unsupported');
    }
  }

  static bool _digit(int code) => code >= 48 && code <= 57;
}

class _Fragment {
  final int start;
  final List<(int, bool)> ends;
  _Fragment(this.start, this.ends);
}

class _Compiler {
  final states = <_State>[];

  int add(_State state) {
    if (states.length >= TopicRegexRules.maxStates) {
      throw const FormatException('complexity');
    }
    states.add(state);
    return states.length - 1;
  }

  void patch(List<(int, bool)> ends, int target) {
    for (final (index, other) in ends) {
      if (other) {
        states[index].other = target;
      } else {
        states[index].next = target;
      }
    }
  }

  _Fragment _empty() {
    final index = add(_State(_Kind.split));
    return _Fragment(index, [(index, false)]);
  }

  _Fragment _concat(_Fragment left, _Fragment right) {
    patch(left.ends, right.start);
    return _Fragment(left.start, right.ends);
  }

  _Fragment compile(_Node node) {
    if (node.kind == 'sequence') {
      var result = _empty();
      for (final child in node.children) {
        result = _concat(result, compile(child));
      }
      return result;
    }
    if (node.kind == 'or') {
      var result = compile(node.children.first);
      for (final child in node.children.skip(1)) {
        final right = compile(child);
        final split = add(_State(_Kind.split)
          ..next = result.start
          ..other = right.start);
        result = _Fragment(split, [...result.ends, ...right.ends]);
      }
      return result;
    }
    if (node.kind == 'repeat') {
      var result = _empty();
      for (var index = 0; index < node.min; index++) {
        result = _concat(result, compile(node.children.single));
      }
      if (node.max == null) {
        final body = compile(node.children.single);
        final split = add(_State(_Kind.split)..next = body.start);
        patch(body.ends, split);
        result = _concat(result, _Fragment(split, [(split, true)]));
      } else {
        for (var index = node.min; index < node.max!; index++) {
          final body = compile(node.children.single);
          final split = add(_State(_Kind.split)..next = body.start);
          result = _concat(result, _Fragment(split, [...body.ends, (split, true)]));
        }
      }
      return result;
    }
    final kind = _Kind.values.byName(node.kind);
    final index = add(_State(kind,
        node.atom == null ? null : RegExp(node.atom!, caseSensitive: false)));
    return _Fragment(index, [(index, false)]);
  }
}
