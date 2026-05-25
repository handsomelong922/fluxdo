/// 少量直接回复自动展开；更多回复保留手动展开，避免移动端一次铺开过长。
const int autoExpandReplyThreshold = 4;

bool shouldAutoExpandReplyCount(int replyCount) {
  return replyCount > 0 && replyCount <= autoExpandReplyThreshold;
}
