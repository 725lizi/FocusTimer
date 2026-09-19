# AI 协作任务单 KG-1：专注脑图与个人知识图谱（阶段 1-2：数据底座 + 生成合并链路）

> 目标：先不做 UI、不依赖自研思维导图组件，跑通「一次专注结束 → 笔记文本变成一棵脑图 JSON → 合并进全局个人知识图谱 → 随会话持久化」。
> 分工（严格遵守）：**DeepSeek 负责**树/图数据结构、树合并与节点去重、薄弱点比对、结构化 JSON 契约与解析容错等纯算法/工具函数（这些函数最终运行在端侧、必须可离线单测）；**豆包代码模型负责**Preferences 读写接线、专注结束流程的业务编排、服务与页面之间的数据接线、后续 ArkTS UI。文档与代码中不出现其他模型名称。
> 铁律延续：纯逻辑可离线单测；联网部分永远有本地兜底，任何失败都不得阻断"专注完成"主流程；小步提交、每步全量单测绿；旧数据兼容。

---

## 0. 现状核对（实现前必读，避免改错地方）
- 专注会话 `StudySession` 定义在 `services/LearningAnalysisService.ets:7`；其历史列表由 `common/FocusSessionStore.ets` 以**整包 JSON**存在 Preferences（文件 `study_data`、键 `sessions`），`getAllSessions/appendSession` 为读-改-写。→ 新增可选字段会随 JSON 自动持久化，**本阶段不改关系库表结构**。
- `parseDocument()/extractNoteKeywords()` 位于 `LearningAnalysisService.ets`，且**已被笔记页 `pages/Notes.ets:155` 调用**，不是预留函数。脑图能力**新增独立模块**，不得改动/占用现有要点解析行为。
- AI 编排参照 `services/ai/AiReportOrchestrator.ets`（注意没有 ReportOrchestrator 这个文件）；"联网/离线走哪条路"的决策**复用** `services/ai/ReportStrategy.ets` 与 `NetState/ApiKeyStore`，不新造双引擎。
- RAG 的来源类型 `ChunkSourceType='note'|'focus'` 已存在；本任务的知识图谱与 RAG 并列、后续可互相引用，但本阶段不耦合。

## 1. 数据契约（只定字段与约束，不写实现）

### 1.1 脑图节点 MindNode（DeepSeek 定义模型与校验/归一化算法）
- `id: string`：本地生成的稳定 id（不依赖联网）。
- `label: string`：节点短文本（去空白、长度上限，超长截断）。
- `children: MindNode[]`：子节点，顺序保留。
- 约束常量（集中可配）：最大深度 4、单棵树总节点 ≤ 80、单 label ≤ 30 字；超限时按"保主干、截尾部"归一化，保证不崩、不无限膨胀。

### 1.2 全局个人知识图谱 PersonalKnowledgeGraph（新建 `model/` 或 `services/knowledge/` 下的纯模型）
- 以一个虚拟根"我的知识图谱"挂多棵学科子树（或等价的节点字典 + 父子边，实现方择优，但必须可序列化为 JSON）。
- 每个节点额外维护：`sourceSessionIds: string[]`（由哪些次专注合并而来）、`hitCount`（被合并/命中次数，用于薄弱点与高频点分析）。
- 预留方法壳：`mergeTree(tree)`、`findOrCreateNode(label)`、`toJson()/fromJson()`、节点去重、按科目子树查询。

### 1.3 StudySession 扩展（兼容旧数据）
- 新增 `mindMapJson?: string`（本次脑图小树的 JSON 字符串，可选）。
- 新增 `knowledgeKeywords: string[]`（本次知识点；读取旧数据时若为 undefined 一律补 `[]`）。
- 不删原字段、不改原字段语义。

### 1.4 LearningReport 扩展（`LearningAnalysisService.ets`）
- 新增 `weakKnowledgePoints: string[]`（薄弱知识点，默认 `[]`）。
- 新增 `reviewSuggestion: string`（复习建议文本，默认 `''`）。
- 原有时长、天数、中断、科目分布等统计**全部保留**，新维度是叠加不是替换。

### 1.5 DeepSeek 结构化输出契约（严格 JSON）
- 请求要求模型**只输出 JSON、不带 markdown 代码围栏、不带解释文字**，低温度；形状：
  `{ "mindmap": { "label": string, "children": [...] }, "keywords": string[] }`
- 【DeepSeek】编写本地解析器：剥离可能的代码围栏 → JSON.parse → 用 1.1 约束做校验与归一化 → 产出合法 MindNode 树。
- **失败兜底（必须）**：非法 JSON / 超深 / 超节点 / 空树时，本次 `mindMapJson` 置空、`knowledgeKeywords` 退化为本地 `extractNoteKeywords` 的结果，并标记来源为 rule；专注完成流程照常走完，不弹错、不卡住。

## 2. 阶段 1：数据结构与存储（不联网、不做 UI）
> 主要是 DeepSeek 写纯模型/算法，豆包做 Preferences 接线。
1. 【DeepSeek】MindNode、PersonalKnowledgeGraph 纯模型与树操作：增删查、遍历、深度/节点计数、**树合并 + 节点去重**（归一化 label 后相同则合并、子节点取并集、sourceSessionIds/hitCount 累加）、序列化与反序列化、非法输入容错。全部为给定输入必得相同输出的纯函数。
2. 【豆包】`FocusSessionStore`：
   - appendSession/getAllSessions 兼容新字段（读出旧记录补默认值）；
   - 新增全局图谱的读取/保存（单独 Preferences 键，如 `personal_knowledge_graph`），读不出时返回空图谱；写入做 try/catch，失败不影响主流程。
3. 【豆包】StudySession/LearningReport 新字段在所有构造处补安全默认值。
- **单测（DeepSeek 出算法的同时给齐，Hypium）**：树增删遍历；同节点合并不重复、子树并集正确；sourceSessionIds 累加；往返 toJson/fromJson 一致；坏 JSON/超深/超节点归一化；旧 StudySession（无新字段）读取后为安全默认；全局图谱缺省返回空。
- **退出条件**：不联网、不碰 UI，全量单测绿；现有功能零变化。

## 3. 阶段 2：计时结束生成脑图并合并（服务层打通，先不做可视化页面）
1. 【DeepSeek】新增纯模块 `MindMapExtractor`（命名可议）：
   - 输入一段笔记/小结文本 + 科目 + 会话信息，输出"结构化结果"（合法脑图树 + keywords + 来源标记 llm/rule）；
   - 内含 1.5 的严格解析与兜底；**不直接持有网络客户端**，网络文本由编排层注入，保证本模块可离线单测。
2. 【DeepSeek】薄弱点分析纯逻辑：结合全局图谱 hitCount、本次/历史 keywords、中断情况，产出 `weakKnowledgePoints` 与规则版 `reviewSuggestion` 模板（无 AI 也能出），多分支可单测。
3. 【豆包】专注结束业务编排（在 `Index.onTimerComplete` 既有完成链路里以"非阻塞附加步骤"接入，参照 AiReportOrchestrator 模式）：
   - 取本次笔记/小结文本 → 决策（开关/Key/网络，复用 ReportStrategy 口径）：
     - 可联网：请求 DeepSeek 返回结构化脑图 JSON → MindMapExtractor 解析；
     - 不可联网或失败：走本地兜底（keywords 用现有提取、脑图允许为空）。
   - 将合法小树 `mergeTree` 进全局 PersonalKnowledgeGraph 并保存；把 mindMapJson/keywords 回写本次 StudySession 后再 appendSession；
   - 更新 LearningReport 的薄弱点与复习建议（保留原统计）。
   - 全程异步、异常吞掉只记日志，**绝不让脑图环节拖慢或阻断"专注完成、记录入库、弹完成框"**。
4. 【豆包】埋点（沿用现有风格）：`[KG-Perf]` 记录 DeepSeek 结构化耗时、本地树合并耗时、全局图谱当前节点数，真机留档。
- **单测**：merge 后全局图谱结构正确、同会话重复提交不重复计数；联网失败/返回坏 JSON 时走 rule 且主流程数据完整；LearningReport 新老字段并存正确；空文本不崩。
- **退出条件**：真机走通"专注结束 → 生成/兜底脑图 → 全局图谱变大且含本次来源 → 杀掉重进图谱仍在（Preferences 持久化）"；断网、错 Key、返回脏 JSON 三种异常都安全兜底；全量单测绿。

## 4. 存储演进预案（本阶段只记不做，防止过度设计）
- 全局图谱先存 Preferences；当节点数超过阈值（建议 2000 节点）或序列化 JSON 超过数百 KB 时，再迁移到关系库表或独立 JSON 文件（迁移逻辑可单测、旧数据不丢）。本阶段不提前建表。

## 5. 总验收清单
- [ ] StudySession/LearningReport 新字段对历史数据安全（缺省补默认），现有统计与周报不回归。
- [ ] 树合并/去重/序列化/解析容错/薄弱点均为可离线单测纯函数，新增用例齐全并给出新的单测总数。
- [ ] DeepSeek 严格输出 JSON；脏数据/断网/错 Key 全部本地兜底，专注完成主流程零阻断。
- [ ] 全局图谱可持久化、重启还在、重复专注不产生重复节点。
- [ ] 不改动现有 parseDocument/extractNoteKeywords 的既有行为；复用而非新造双引擎。
- [ ] 小步提交（阶段1、阶段2分开 commit），每步 DevEco 构建通过、全量单测绿。

## 6. 暂不在本单（依赖自研组件，后续另出单）
- 阶段3：Statistics 每条记录查看脑图入口、报告页渲染薄弱点/复习建议、新增 KnowledgeGraphPage 用自研 MindMap-HarmonyOS 组件渲染全局图谱（展开折叠、点节点跳历史记录）——**依赖组件库 MVP（布局算法+渲染）先就绪**。
- 阶段4：架构图/数据流图更新（计时行为数据 + 知识图谱双输入、双引擎切换）、存储读写与树渲染性能基线、简历与面试口述。
