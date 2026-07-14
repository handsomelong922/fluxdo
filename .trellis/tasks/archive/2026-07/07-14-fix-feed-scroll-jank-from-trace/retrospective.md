# Bug Analysis: 树形评论绕过列表虚拟化导致持续掉帧

## 1. Root Cause Category

- **Category**: B / D / E — 跨层合同、测试覆盖缺口与隐式假设。
- **Specific Cause**: `NestedPostList` 的根层使用 Sliver 并不代表整棵树都被虚拟化；根项内部的递归 `Column` 会同步构建并持续挂载全部自动展开后代。每个卡片局部重建又重新分配 scroll index、复制映射，父卡片重绘边界还包住全部后代。

## 2. Why Fixes Failed

1. 平铺列表渐进物化只覆盖 `TopicPostList` segment，没有覆盖独立的树形渲染路径。
2. 早期树形优化只暂停滚动期网络自动加载，没有限制 API 已返回子节点的同步递归 widget 物化。
3. 现有测试覆盖自动加载队列和根分页竞态，但没有断言离屏后代不能自动构建、scroll index 在局部重建时必须稳定。
4. 将 `RepaintBoundary` 放在递归卡片最外层时，隐式假设它只隔离单帖，实际边界包含整棵后代子树。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|---|---|---|---|
| P0 | Architecture | 自动子节点物化必须同时满足 expanded、visible、idle、未到最大深度 | DONE |
| P0 | Architecture | scroll index 按 post number 稳定注册，映射每帧最多发布一次 | DONE |
| P0 | Runtime | 滚动/离屏期间完成的自动网络响应缓冲到再次可用时再应用 | DONE |
| P0 | Paint | 重绘边界只包当前帖子主体，不包递归后代 | DONE |
| P1 | Diagnostics | 记录 `nested:card` build 和 `nested:childrenMaterialized` 帧事件 | DONE |
| P1 | Tests | 覆盖自动工作门禁与稳定索引 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: 任何 Sliver item 内部再用递归 Column/List 生成大量媒体，都可能绕过外层回收；任何 build 中逐项复制累计映射的逻辑都可能退化为 O(n²)。
- **Design Improvement**: 区分逻辑展开状态与实际 widget 物化状态，自动路径由视口驱动，显式用户操作保持即时。
- **Process Improvement**: 列表性能审查必须沿 widget tree 检查到 Sliver item 内部，不能只看到外层 Sliver 就判定已虚拟化。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md` 的树形视口物化合同。
- [x] 新增自动工作门禁和稳定索引回归测试。
- [x] 保留下一版 trace 的树形 card/materialization 精确归因。
- [x] 当前仓库无 `src/templates/markdown/spec/`，无模板同步目标。
