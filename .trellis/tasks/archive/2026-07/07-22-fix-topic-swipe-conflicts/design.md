# Technical Design

route 保留现有详情页 PageView 的左右滑动参与，不强制改成一个与 PageView 冲突的独立 gesture arena 认识器。右滑 route 候选在当前 pointer 分发结束后通过微任务延迟激活；后代水平 `Scrollable` 发出 `ScrollStartNotification` 后取消候选。文字选择状态按来源集合计数，代码框/iframe/WebView 通过 `HorizontalPopGestureBlockerRegion` 显式阻断。普通右滑回退、左滑 AI、阈值与动画保持不变。
