<!-- 负责模型：DeepSeek -->
# 错误码表（`LlmErrorKind`，8 种）

> 本表**逐条对照真实源码**整理，不新增任何错误码：
> - 类型定义：`entry/src/main/ets/services/ai/ReportStrategy.ets`（`type LlmErrorKind`）
> - 分类实现：`entry/src/main/ets/services/ai/HttpErrorMapper.ets`（`classifyStatus` / `classifyFrameworkError` / `userMessage`）
> - 降级决策：`entry/src/main/ets/services/ai/ReportStrategy.ets`（`shouldFallback`）
> - 「返回为空」的触发点：`AiReportOrchestrator.ets`（`onComplete` 里 `text.length === 0`）
>
> **合成数据声明**：本表是错误码文档，不含任何真实用户数据；表中出现的「用户提示」是源码里的固定文案，
> 不是对真实故障的统计。真实错误分布需在设备上实测采集，本表不预测任何比率。

---

## 1. 八种错误类别

| # | `LlmErrorKind` | 通俗含义 | 触发条件（HTTP / 框架码） | 给用户的提示（源码原文） | 是否降级到规则版 |
|---|---|---|---|---|:---:|
| 1 | `network` | 断网、连不上服务器 | 其余 HTTP 状态码（如 200 却连不上、连接被重置）；其余框架码；以及**没有**任何状态码/框架码的兜底情况 | 网络不可用，已为你切换到本地规则版 | 是 |
| 2 | `timeout` | 等太久，请求超时 | HTTP `408`；框架码 `2300004` / `2300047` / `2300999` | AI 响应超时，已为你切换到本地规则版 | 是 |
| 3 | `unauthorized` | Key 错了 / 失效 / 欠费 / 没权限 | HTTP `401` / `403` | API Key 无效或已欠费，请检查设置 | 是 |
| 4 | `rate_limited` | 请求太频繁，被限流 | HTTP `429` | 请求过于频繁，已为你切换到本地规则版 | 是 |
| 5 | `server` | 服务端自己出错了 | HTTP `≥ 500`（如 500 / 502 / 503） | AI 服务暂时不可用，已为你切换到本地规则版 | 是 |
| 6 | `bad_request` | 请求体写错了 | HTTP `400` / `404` / `422` | 请求格式有误，已为你切换到本地规则版 | 是 |
| 7 | `empty` | 模型返回了空内容 | **不是 HTTP 码**：流式返回累计后 `trim()` 为空（`onComplete` 里判 `text.length === 0`） | AI 返回为空，已为你切换到本地规则版 | 是 |
| 8 | `cancelled` | 用户自己点了取消 | 框架码 `2300089`（请求被取消） | 已取消生成 | **否** |

> 为什么只有 `cancelled` 不降级：用户已经不要这次结果了，再生成一遍没有意义；
> 其余 7 种都自动兜底，保证功能永远有产出（`ReportStrategy.shouldFallback`）。

---

## 2. HTTP 状态码 → 错误类别

对应 `HttpErrorMapper.classifyStatus`，判定顺序即下表自上而下：

| 判定顺序 | HTTP 状态码 | 归一为 |
|---:|---|---|
| 1 | `401` / `403` | `unauthorized` |
| 2 | `429` | `rate_limited` |
| 3 | `400` / `404` / `422` | `bad_request` |
| 4 | `≥ 500` | `server` |
| 5 | `408` | `timeout` |
| 6 | 其余（含 200 等） | `network` |

> 注意顺序：`408` 虽然在 4xx 区间，但它在第 5 步才判，前面几档都不会命中它；
> `>= 500` 在第 4 步，所以 `503` 一定是 `server`。

## 3. 鸿蒙框架码 → 错误类别

对应 `HttpErrorMapper.classifyFrameworkError`：

| 判定顺序 | 框架码 | 归一为 |
|---:|---|---|
| 1 | `2300089` | `cancelled` |
| 2 | `2300004` / `2300047` / `2300999` | `timeout` |
| 3 | 其余（如 `2300099`） | `network` |

---

## 4. 三个使用约定

1. **一次请求只归一类**：先看 HTTP 状态码，没有再退到框架码，两者都没有就按 `network`。
2. **`empty` 与网络错误不同源**：它由「响应内容为空」触发，不来自状态码或框架码；
   所以 `classifyStatus` / `classifyFrameworkError` 永远不会返回 `empty`。
3. **这 8 种是「调用大模型时」的错误码**，与内容解析阶段的错误码是两回事：
   解析阶段（`MindMapExtractErrorCode`）只有 `EMPTY` / `NO_JSON` / `INVALID` 三种，
   属于「拿到了响应但内容不可用」，在日志里记在 `errorKind`（内容类）与 `errorDetail` 上。
   两者不要混用。

---

## 5. 本项目的实际验证方式

- `run_logging.mjs` 里有一组**映射反测**：503→server、429→rate_limited、401→unauthorized、
  403→unauthorized、408→timeout、422→bad_request、200→network、2300089→cancelled、
  2300004→timeout、2300099→network；任一不符即非零退出。
- 同一脚本还有**降级规则反测**：遍历 8 种错误，确认只有 `cancelled` 的 `shouldFallback` 为 `false`。
- 样本库里的 20 条网络类样本各自带 `error_kind`，脚本会用它再核对一遍上面的映射（20/20 一致）。

> 边界：以上都是**离线规则验证**，不是真实网络环境的错误分布统计；
> 真实错误率、p50/p95 延迟必须用真实 API 在设备上实测。
