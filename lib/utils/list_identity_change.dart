/// 可见列表的行身份变化；用于区分真正的锚点变化与过滤器临时复制列表。
enum ListIdentityChange {
  initial,
  unchanged,
  tailAppend,
  contentChanged,
  structural,
}

ListIdentityChange classifyListIdentityChange<T>(
  List<T>? previous,
  List<T> next, {
  required Object Function(T item) identityOf,
}) {
  if (previous == null) return ListIdentityChange.initial;
  if (identical(previous, next)) return ListIdentityChange.unchanged;
  if (next.length < previous.length) return ListIdentityChange.structural;
  var contentChanged = false;
  for (var i = 0; i < previous.length; i++) {
    if (identityOf(previous[i]) != identityOf(next[i])) {
      return ListIdentityChange.structural;
    }
    if (!identical(previous[i], next[i])) contentChanged = true;
  }
  // 同一行的新对象可能改变高度，仍保留原有空闲锚定保护。
  if (contentChanged) {
    return next.length == previous.length
        ? ListIdentityChange.contentChanged
        : ListIdentityChange.structural;
  }
  return next.length == previous.length
      ? ListIdentityChange.unchanged
      : ListIdentityChange.tailAppend;
}
