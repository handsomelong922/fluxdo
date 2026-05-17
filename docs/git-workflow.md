# Git 工作流

这份说明只覆盖当前仓库最常用、最安全的一条线：基于稳定 tag 开分支，按功能提交，需要时再快速回退到稳定版本。

## 1. 从稳定版本切工作分支

当前已知稳定点是 `v0.3.1`，对应分支示例：

```bash
git switch -c codex/rollback-to-v0.3.1 v0.3.1
```

如果已经在稳定分支上继续做功能，直接从当前分支再切新分支：

```bash
git switch -c feat/topic-defaults
```

## 2. 开发时保持小步提交

先看改动，再只提交这次功能相关文件：

```bash
git status
git add lib/... docs/git-workflow.md
git commit -m "feat: improve topic defaults and user blacklist"
```

建议：

- 一个功能点一条 commit。
- 不要把格式化、重构、功能改动混成一条 commit。
- 非明确需要时不要 `git commit --amend`。

## 3. 发布前确认稳定点

查看本地 tag 和最近提交：

```bash
git tag --list
git log --oneline --decorate -n 10
```

如果这次改动验证通过，后续再决定是否补新 tag：

```bash
git tag v0.3.2
```

## 4. 需要回到稳定版本时

不要直接改乱当前工作分支，优先从稳定 tag 新开一个干净分支：

```bash
git switch -c hotfix/from-v0.3.1 v0.3.1
```

如果只是临时查看稳定版本内容：

```bash
git switch --detach v0.3.1
```

看完后再切回自己的工作分支：

```bash
git switch codex/rollback-to-v0.3.1
```

## 5. 合并前最少检查

```bash
git status
git diff --stat
```

确认：

- 没有把无关文件一起带上。
- 验证命令已经实际跑过。
- 当前分支名能表达这次工作的目的。
