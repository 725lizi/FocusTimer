# Codex 任务单索引（产品/需求侧产出，不含实现代码）

这里放给 Codex 的实现需求单。每张单子都写清：背景、改动模块、数据契约、纯逻辑抽离要求、单测要点、验收标准、不在范围。实现交给 Codex，本仓库主人负责验收。

| 任务单 | 内容 | 规模 | 建议顺序 | 状态 |
|---|---|---|---|---|
| TASK-A_timer-comment-encapsulation.md | 修正 TimerEngine 过时注释；extractNoteKeywords 收窄 private（同步迁移 5 个单测走 parseDocument） | 小重构 | 先做，低风险热身 | 待派发 |
| TASK-P1-ai-learning-loop.md | P1 体验深点 + 与 AI 串联成学习闭环（P1-1~P1-5） | 一组迭代 | 笔记攒厚（≥20~30 段）后按 P1-1→P1-5 顺序派发 | 待派发 |

## 使用方法
1. 复制对应 md 全文给 Codex，一次只派一个子任务（P1 按 P1-x 逐个派，不要一次全做）。
2. Codex 交付后按单子里的「验收清单」逐条核对：DevEco 完整构建 + entry/src/test 全量单测全绿 + 真机走查该路径。
3. 小步合入，保持每步可回滚；新功能必须在 feature flag 后。

## 配套图
- 「点击开始专注」时序图：博客仓 assets/focustimer-sequence-focus-start-zh.svg（项目内备份在 doc_task/blog/）。
