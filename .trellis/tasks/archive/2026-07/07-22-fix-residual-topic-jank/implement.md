# Implementation Plan

1. 先写失败测试，证明远距离分支不能返回普通 staging offset/调用大跨度 jump。
2. 实现有界 index/key 定位并接入三个入口。
3. 运行 topics page 定向测试与 analyze。
4. 独立提交性能修复。
