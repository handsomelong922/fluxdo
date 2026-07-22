# Technical Design

远距离 extent 跳转在变高 SliverList 中会沿途 materialize child。本子任务改为 index/key 级直接定位或等价的有界列表重建，让远距离分支只布局顶部和有限可见项；接近顶部时继续执行短动画。统一 helper 负责三个入口，测试观察远距离路径不发出跨 extent jump。
