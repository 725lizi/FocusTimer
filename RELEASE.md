# 发版说明

## 版本规则

采用语义化版本 `主版本.次版本.修订号`：

- 主版本：不兼容的改动。
- 次版本：向下兼容的新功能。
- 修订号：向下兼容的问题修复。

当前版本 v1.0.0，对应已有 tag `v1.0.0`。

## 发版步骤

1. 确认 `main` 通过 CI（`.github/workflows/ci.yml` 仓库规范校验）。
2. 更新 `oh-package.json5` 中的版本号，更新 CHANGELOG。
3. 提交改动。
4. 打 annotated tag：

```bash
git tag -a v1.0.0 -m "v1.0.0"
```

5. 推送 tag：

```bash
git push origin v1.0.0
```

6. 在 GitHub 创建 Release，写清变更说明。`release.yml` 负责发版流程。

## ohpm 组件发布前检查项

组件仓库 mindmap-harmony（MIT，已上架 ohpm 中心仓）发布前确认：

- 版本号已更新。
- LICENSE 存在。
- README 完整。
- `oh-package` 名称与 license 字段正确。
- 构建产物可安装。

## 应用发版产物

HAP 产物在 `entry/build/default/outputs/default/` 下。签名材料不入库，发版时使用本地签名配置。

## 回滚办法

基于历史 tag 重新构建：

```bash
git checkout v1.0.0
```

然后在 DevEco Studio 中重新构建即可。
