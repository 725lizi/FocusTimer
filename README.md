# 鸿蒙多端专注计时本（FocusTimer）

![CI](https://github.com/725lizi/FocusTimer/actions/workflows/ci.yml/badge.svg)

基于 HarmonyOS NEXT 的多端协同专注学习工具——专注计时、笔记流转、端侧学习分析、桌面元服务卡片与数据安全加密，帮你建立可持续的学习节奏。

## ✨ 亮点

- **多端流转**：手机 / 平板 / 穿戴设备间笔记与计时状态无缝接续，分布式数据实时同步，跨设备"选了就流转"
- **端侧学习分析**：基于时长/中断率/规律性三维评分模型，离线生成专注分析与改进建议，结果可解释、可测试
- **桌面元服务卡片**：无需打开 App，桌面小组件实时掌握今日待学与专注进度
- **数据安全**：加密笔记 + 设备白名单 + 流转二次确认，隐私有底线

## 🚀 功能

- **专注计时**：5 / 15 / 25 / 45 / 60 分钟五档 + 自定义时长，计时结束弹窗提醒；专注免打扰模式，环境光线护眼提示
- **笔记流转**：多端笔记编辑、科目分类、一键流转到平板等设备，支持端侧要点解析
- **数据统计**：日 / 周 / 月维度可视化报表，科目学习时长分布一目了然
- **学习分析周报**：本地汇总学习数据，按三维评分模型给出针对性改进建议
- **桌面卡片**：桌面小组件实时显示计时状态与今日目标
- **久坐提醒**：长时间久坐自动提醒，联动穿戴设备
- **数据安全**：加密文件夹、设备白名单、流转二次确认

## 📸 截图

| 专注计时 | 笔记流转 | 多端设备选择 |
| --- | --- | --- |
| ![专注计时](shot-timer.png) | ![笔记流转](shot-notes.png) | ![多端设备选择](shot-transfer.png) |

| 数据统计 | 学习分析周报 | 桌面卡片 |
| --- | --- | --- |
| ![数据统计](shot-stats.png) | ![学习分析周报](shot-report.png) | ![桌面卡片](screenshot_card.png) |

## 🛠️ 快速上手

1. 使用 DevEco Studio 打开本项目
2. 配置应用签名（模拟器可直接运行）
3. 运行 HarmonyOS 模拟器即可体验

## 🤖 CI 与发版说明

> GitHub Actions 云端无法获取 HarmonyOS NEXT API 24 SDK（华为官方仅允许登录开发者中心下载），
> 因此云端 CI 仅执行**仓库规范性校验**（关键文件、配置与测试目录完整性检查）；
> 应用构建与全部 52 个单元测试请在**本地 DevEco Studio** 中执行。

**日常更新**：直接向 `main` 分支提交并推送即可，CI 自动完成仓库规范校验，无需额外操作。

**版本发布**：

1. 在 DevEco Studio 中构建 release HAP（`entry/build/default/outputs/default/` 下的 `.hap` 文件）
2. 运行发版脚本：`.\scripts\New-Release.ps1 -Version v1.1.0`（自动校验工作区、打 tag 并推送）
3. CI 自动创建**草稿 Release** 并生成更新记录；到 [Releases 页面](https://github.com/725lizi/FocusTimer/releases) 把 `.hap` 拖入草稿附件区，点击 **Publish release** 即完成发布

## 🏗️ 技术架构

- **UI 层**：ArkUI 声明式开发 + Stage 模型，页面模块化
- **业务层**：核心 Manager 模块——ContinuationManager（异常接续）、SubjectTagManager（科目标签）、FocusModeManager（免打扰）、SedentaryReminderManager（久坐提醒）、SecurityManager（加密）、DeviceWhitelistManager（白名单）、OfflineCacheManager（离线缓存）
- **数据层**：relationalStore 关系型数据库 + Preferences 首选项 + distributedDataObject 分布式对象 + FormKit 服务卡片
- **分析引擎**：AIAnalysisService 端侧多维评分模型，离线完成学习数据分析与周报生成（不依赖云端，结果确定可测）

## 📄 开源协议

Apache License 2.0，详见 [LICENSE](LICENSE)。
