# 移除搜索输入前加载

## Goal

点击首页搜索后立即显示并聚焦输入框，不等待论坛最近搜索接口；最近搜索仅保存在本地。

## Requirements

- 空查询 SearchPage 首帧不显示历史 loading spinner，并在首个 post-frame 请求输入焦点。
- 不再进入时调用 `getRecentSearches()`，清空时不再调用 `clearRecentSearches()`。
- 使用 `SharedPreferences` 同步读取本地最近搜索；新提交查询按最新优先去重并限制数量。
- 清空历史立即更新 UI 并删除本地 key；持久化不阻塞搜索请求。
- 只有用户提交非空关键字后才调用论坛搜索 API；程序化 `initialQuery` 保持现有自动搜索语义但不写入人工历史。

## Acceptance Criteria

- [x] 打开空搜索页可立即输入，页面没有等待历史请求的 spinner。
- [x] 本地历史去重、trim、最新优先、上限和清空行为有测试。
- [x] 搜索页源码不再引用云端最近搜索加载/清除方法。
- [x] 提交搜索后结果 loading 仍正常显示，排序/过滤/AI 搜索行为不变。

## Out of Scope

- 禁止论坛自身记录搜索请求，或跨设备同步本地历史。

## Open Questions

- 无。
