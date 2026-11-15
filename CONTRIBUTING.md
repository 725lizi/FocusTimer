# 贡献指南

FocusTimer 是一个轻量鸿蒙应用，用 ArkTS 编写，由学生团队维护。

## 目录结构

```
FocusTimer/
├── entry/                 应用主模块（ArkTS 源码、资源、单测）
│   └── src/test/          本地单元测试（@ohos/hypium）
├── libs/                  本地 HAR 依赖（mindmap-harmony.har）
├── docs/                  说明文档
├── reliability_experiment/实验脚本
└── .github/workflows/     CI 与发版流程
```

## 环境准备

1. 安装 DevEco Studio 26.0.0 及以上（当前验证版本 26.0.0 Release，Build 26.0.0.865）。
2. 安装 HarmonyOS SDK。
3. 安装 Node，用于跑 `reliability_experiment` 下的实验脚本。
4. 克隆仓库：

```bash
git clone https://github.com/725lizi/FocusTimer.git
cd FocusTimer
```

5. 用 DevEco Studio 打开工程根目录，等待同步完成。`entry` 依赖本地 `file:./libs/mindmap-harmony.har`，同步前确认该文件存在。
6. 配置签名：在 DevEco Studio 中打开 Project Structure → Signing Configs，使用你自己的调试签名。签名文件属个人材料，不要提交到仓库。

## 分支与提交规范

- 从 `main` 拉个人分支，不要直接向 `main` 推送。
- 分支命名建议：`feat/xxx`、`fix/xxx`。
- Commit message 用 `type: subject` 形式，例如 `feat: 增加计时暂停按钮`。
- 可用 type：`feat`、`fix`、`docs`、`test`、`refactor`、`chore`。

## 协作流程

1. 在个人分支上开发。
2. 本地自测：构建通过 + 单测通过。
3. 提 PR，写清改动目的和验证方式。
4. 代码评审。
5. Squash 合并。
6. 合并后个人分支先保留，项目结束再统一清理。

## 提交前自检清单

- [ ] 构建通过。
- [ ] 单测通过。
- [ ] 不提交 build 产物与 oh_modules。
- [ ] 不提交签名与密钥文件。
- [ ] 不破坏盲审要求。
- [ ] 新增源文件在文件头标注负责模型（本项目约定）。

## 单测怎么跑

在 DevEco Studio 中打开 `entry/src/test` 下的测试文件，直接运行。纯逻辑测试不依赖设备。

## 提问与反馈

走 GitHub Issues，不要私信。
