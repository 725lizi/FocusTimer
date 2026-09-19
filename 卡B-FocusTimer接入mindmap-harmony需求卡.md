# 卡 B：FocusTimer3 接入 mindmap-harmony 渲染 DeepSeek 复盘脑图（豆包代码模型执行）

## 〇、项目背景包（先读再动手，不要跳过）

1. 两个工程根目录：
   - App 工程（本次改动只在这里）：`C:\Users\qq959\FocusTimer3`
   - 自研组件库工程（HAR，**只读、一个字都不许改**）：`D:\HarmonyOSProjects\MindMap-HarmonyOS\library`
2. 组件库包名 `mindmap-harmony`，从 `'mindmap-harmony'` 可导入：MindMapView、MindTree、MindNode、JsonSerializer、MindMapSerializeError。
   - MindMapView 入参：`@Prop root: MindNode`（必填）、`@Prop refreshTick: number`、可选 selectedId / snapshotId（本需求**不传**后两个，只读渲染）。
   - `JsonSerializer.deserialize(text: string): MindTree`，只吃「裸根节点 {id,text,children}」或完整信封 {format:'mindmap-harmonyos',version,root}；非法输入抛 MindMapSerializeError。
3. App 工程里已有三个**已冻结、只准调用不准改**的纯函数文件，位于 `entry/src/main/ets/services/ai/`：
   - MindMapPromptBuilder：`buildRequest(summary, model): ChatCompletionRequest`（stream:true、temperature 0.4、max_tokens 900）。
   - MindMapJsonExtractor：静态 `extract(raw): string`（剥 ```json 围栏、截取首个 { 到末个 }）、`normalize(json): string`（输出**裸根节点** JSON 字符串；脏输入抛 MindMapExtractError，code 为 EMPTY/NO_JSON/INVALID）。
   - RuleMindMapBuilder：`build(summary): string`（离线规则兜底，输出裸根节点 JSON）。
4. 同目录可复用的现有类（**公开签名不许改**，写法严格对照同目录 AiReportOrchestrator.ets）：
   - DeepSeekClient：`startStream(apiKey, body, {onDelta,onError,onComplete})`、`cancel()`；onComplete 给累计全文。
   - ApiKeyStore.getInstance()：isEnabledSync() / hasApiKeySync() / getApiKeySync() / getModelSync()。
   - NetState.isOnline()；ReportStrategy.decideSource / ruleReason / shouldFallback；ReportPromptBuilder.buildSummary(sessions, date)；HttpErrorMapper.userMessage(kind)。
   - 类型在 AiChatTypes：ReportStatus、ReportSource、ReportStrategyInput、LlmErrorKind、ChatCompletionRequest。
5. 数据：`FocusSessionStore.getInstance().getAllSessions(): Promise<StudySession[]>`；AI 周报真实页面是 pages/Statistics.ets；路由配置 resources/base/profile/main_pages.json（现有 7 个页面）。
6. 硬约束：禁 any、@ts-ignore；不引新三方依赖；页面沿用 router（pushUrl/back 一律 try/catch）；组件库零改动；三个纯函数零改动；既有 AI 类公开签名不动；原 AI 周报功能零回归。

## 一、本地依赖接入

1. 先执行目录联接（跨盘，ohpm 联网在本机不可用，这是既定兜底方案；已存在则跳过）：
   `cmd /c mklink /J "C:\Users\qq959\FocusTimer3\entry\oh_modules\mindmap-harmony" "D:\HarmonyOSProjects\MindMap-HarmonyOS\library"`
2. `entry/oh-package.json5` 的 dependencies 加 `"mindmap-harmony": "1.0.0"`；sync 成功后从 'mindmap-harmony' import。

## 二、新增 entry/src/main/ets/services/ai/MindMapReviewOrchestrator.ets（设备层，结构严格对照 AiReportOrchestrator）

- 回调接口：`MindMapReviewCallbacks { onStatus(status: ReportStatus, source: ReportSource, hint: string): void; onDone(tree: MindTree, source: ReportSource, hint: string): void }`。
- `async generate(sessions: StudySession[], callbacks: MindMapReviewCallbacks): Promise<void>`，settled 守卫保证只结束一次。流程：
  1. `ReportPromptBuilder.buildSummary(sessions, new Date())` 得 summary；`RuleMindMapBuilder.build(summary)` 再经 `MindMapJsonExtractor.normalize` 得到规则兜底 JSON 字符串并缓存（这一步理论上不抛；若抛，走 onStatus('failed',...)）。
  2. ApiKeyStore.getInstance() 收集 isEnabledSync/hasApiKeySync，await NetState.isOnline()，组 ReportStrategyInput 交 ReportStrategy.decideSource；为 'rule' 时 onStatus('succeeded','rule', ReportStrategy.ruleReason(input))，缓存 JSON 用 JsonSerializer.deserialize 成 MindTree 后 onDone。
  3. 否则 onStatus('requesting','llm','')；MindMapPromptBuilder.buildRequest(summary, store.getModelSync())；new DeepSeekClient().startStream(store.getApiKeySync(), request, …)：
     - onDelta：只把状态切 'streaming'（脑图不逐字渲染，不拼 UI）；
     - onError(kind)：ReportStrategy.shouldFallback(kind) 为真则降级规则树（onStatus('fallback','rule', HttpErrorMapper.userMessage(kind)) → onDone 规则树），否则 onStatus('failed','llm', userMessage)；
     - onComplete(fullText)：依次 MindMapJsonExtractor.extract → normalize → JsonSerializer.deserialize；**任一步抛错（MindMapExtractError / MindMapSerializeError / 空文本）都降级缓存规则树**，hint 固定为「AI 返回无法解析，已用本地统计生成」；全部成功才 source='llm'。
- `cancel(): void`：内部 client 非空时调 client.cancel()。

## 三、新增页面 entry/src/main/ets/pages/MindMapReview.ets

- aboutToAppear：FocusSessionStore.getInstance().getAllSessions() 取数后调 orchestrator.generate；@State 维护 status/source/hint、@State tree: MindTree | null、@State refreshTick。
- UI：
  - 顶部标题栏 + 返回（router.back() 包 try/catch）；
  - 状态区：requesting/streaming 显示「正在生成复盘脑图…」；fallback/rule 显示橙色提示文案（hint）；failed 显示红色文案 +「重试」按钮（重新走一遍 generate）；
  - tree 非空时主体渲染 `MindMapView({ root: this.tree.root, refreshTick: this.refreshTick })`，layoutWeight(1) 占满剩余空间；不传 selectedId/snapshotId；
  - 底部「重新生成」按钮；
  - aboutToDisappear 调 orchestrator.cancel()。

## 四、入口与路由

1. resources/base/profile/main_pages.json 的 src 末尾加 `"pages/MindMapReview"`；
2. pages/Statistics.ets 现有 AI 周报区域加按钮「生成复盘脑图」，点击 router.pushUrl({ url: 'pages/MindMapReview' })，包 try/catch、catch 中 console.error；其余逻辑不动。

## 五、验收（逐条给出结果）

1. assembleHap **0 error**；deprecated 告警数量不得比改动前多；
2. 既有全部本地单测数量不减、全绿（含 MindMapAiPure 25 个）；
3. 三条路径手测：配 Key 在线 → AI 树渲染；关网或清空 Key → 直接出规则树且有提示；AI 返回坏 JSON → 不崩、走规则树；
4. 脑图页：首屏整树居中、双击放大/复位、单指可平移；返回再进无请求残留；
5. Statistics 原 AI 周报流式生成、其余 6 个页面零回归。

## 六、不许破坏的边界

- 不改组件库 mindmap-harmony 任何文件；
- 不改三个纯函数与既有 AI 类（DeepSeekClient/ApiKeyStore/ReportStrategy/ReportPromptBuilder/AiReportOrchestrator）的公开签名；
- 不做节点编辑/图片导出/拖拽改层级（非本卡范围）；
- 禁 any、@ts-ignore；不引新三方依赖。
