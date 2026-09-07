# Codex 任务单 A：修正 TimerEngine 过时注释 + 收窄 extractNoteKeywords 可见性

> 类型：小步重构（不改变任何运行时行为）
> 预计改动：2 个源文件 + 1 个测试文件
> 硬约束：只做本单列出的两件事，不顺手改别的；改完必须全量单测全绿、DevEco 完整构建通过。

## 背景（为什么做）
阶段 1 重构时把首页计时状态机抽成了纯逻辑类 `TimerEngine`，后来 `Index.ets` 已经全面切换到调用它，但类顶部注释还停留在"尚未切换"的旧说法，注释与代码不一致，面试对照代码时会扣印象分。
另外 `LearningAnalysisService.extractNoteKeywords()` 只被同类的 `parseDocument()` 内部调用，却声明为 `public`，对外暴露了本应隐藏的实现细节，需要收窄。

## 任务 1：更新 TimerEngine 过时注释
文件：`entry/src/main/ets/common/TimerEngine.ets`

- 文件头注释目前写着「当前 Index.ets 尚未切换调用本类，切换后可消除重复实现」，该说法已过时，删除/改写为符合现状的描述：**本类是 FocusTimer3 唯一的计时状态机（纯逻辑、不依赖 UI 与系统 API），`pages/Index.ets` 已全面委托本类；页面只负责 setInterval 每秒心跳驱动、@State 镜像同步与系统副作用（免打扰/久坐/持久化/桌面卡片）。**
- 逐条核对文件头「方法 ↔ Index 方法」映射注释是否仍与 `Index.ets` 现状一致；当前实际对应关系为：
  - `start()` ← `Index.startTimer()`（内部先调引擎 start，再做副作用与心跳）
  - `pause()` ← `Index.pauseTimer()`
  - `reset()` ← `Index.resetTimer()`
  - `tick()` ← `Index.startTimer` 内 `setInterval` 每秒回调
  - `getProgress()/formatTime()` 当前由组件 `TimerRingSection` 用同等公式展示（如未被直接调用，注释里如实说明，不要谎称已调用）
  - `restoreFromCheckpoint()` ← `Index.acceptContinuation()`（跨端/断点接续）
  - `pauseCount` ← `Index.saveCurrentSession()` 组装 StudySession 时读取
- 只改注释与说明文字，**不得改动任何方法签名与逻辑**。

## 任务 2：把 extractNoteKeywords 收窄为类内部方法
文件：`entry/src/main/ets/services/LearningAnalysisService.ets`
测试：`entry/src/test/LearningAnalysisService.test.ets`

现状（已确认，无需再猜）：
- `extractNoteKeywords()` 定义在 222 行，全工程唯一生产调用点是同类 `parseDocument()` 的 283 行；没有任何其它类直接调用它。
- 但测试文件里有 5 处**直接**调用 `service.extractNoteKeywords(...)`（用例：empty / chinese / formula / englishTerms / stopWords）。

要求：
1. 把 `extractNoteKeywords` 的可见性从 `public` 收窄为 `private`，并在其注释中标注「仅由 parseDocument 内部调用」。
2. 因为收窄后测试无法跨文件直接访问 private 方法，请把上述 5 个用例改为**通过公有方法 `parseDocument()` 间接覆盖**：输入同样的文本，断言返回结果 `DocumentParseResult.keywords`（必要时连同 `summary`）仍然满足原 5 个场景的预期——空串/空白返回空、中文高频词提取、公式识别、英文术语提取、停用词被过滤。测试用例名相应改为体现"经由 parseDocument"，但**一个场景都不许丢，覆盖强度不许下降**。
3. 不允许为了让测试能访问而把方法继续留 public；也不允许用 @ts-ignore 之类绕过类型检查。

## 验收标准（逐条自检后再交付）
- [ ] `TimerEngine.ets` 不再出现"尚未切换/切换后"这类过时表述，方法映射注释与真实调用一致。
- [ ] `extractNoteKeywords` 已为 private；全局检索确认除 `parseDocument` 外无生产调用，测试已改走 `parseDocument`，5 个场景仍在。
- [ ] 没有改变任何用户可见行为与计算结果。
- [ ] DevEco 完整构建通过（无新增 ArkTS 编译错误/警告）。
- [ ] `entry/src/test` 全量单元测试全绿，测试总数不减少（改造前后数量对齐，仅用例形态变化）。
- [ ] 小步提交，commit message 建议：`refactor: sync TimerEngine doc with actual usage and narrow extractNoteKeywords to private`。

## 不在本单范围
- 不优化关键词提取算法本身；不改周报/RAG；不动 UI。
