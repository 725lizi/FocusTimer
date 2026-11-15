# Changelog

本文件格式遵循 Keep a Changelog。

## [1.0.1] - 2026-11-15

### Added

- `tests/verify_scorer.mjs`：评分器确定性回归，8 个构造用例（环比写法识别、方向写反、行动分支干扰、编造数字、编造科目、禁止表述、空响应），不联网，`node tests/verify_scorer.mjs` 一键运行。
- 真实接口下逐条记录 token 用量（prompt / completion），报告 meta 增加 token 汇总与均值；配置单价环境变量后可估算成本。
- 报告 meta 补充模型名、接口主机名（只保留 host）、温度、max_tokens、运行开始时间，便于复现。
- 事实一致性未通过的样本，原始响应落盘到 `report/failed_raw/`，明细中以 `rawFile` 指向，重复运行按 `runN_` 前缀区分。

### Changed

- 延迟改为端到端口径：在响应体完全接收后再计时。此前在响应头到达时就计时，实测 p50 只有约 80ms，明显偏低。
- 方向判定收窄到「总体情况」分支，避免「下周行动：减少中断」这类措辞把环比上涨误判为下降；分支名被改写时按常见别名或第一个一级分支取值。
- 方向写法由「只认增减汉字」扩展为同时识别「环比增长13%」「环比+13%」「环比264%」「环比-13%」；能解析出「环比」后百分数时，以该数值符号与输入环比同号为准。
- CSV 增加 `promptTokens`、`completionTokens` 两列。

### Fixed

- `CHANGELOG` 与 `README` 中的适配器文件名与实际不符（实为 `adapters/mock_adapter.mjs`、`adapters/openai_compat_adapter.mjs`）。

## [1.0.0] - 2026-11-15

### Added

- 数据层：`data/samples.dev.jsonl` 60 条、`data/samples.locked.jsonl` 20 条，全部人工合成（source_type=synthetic），固定种子线性同余生成（dev 20240607、locked 20240608），同机重复运行输出逐字节一致。
- 评分器：四类分列计数（direct / repaired / rule_fallback / failed）、软 Schema 检查、事实一致性检查。评分逻辑复用 `reliability_experiment/reliability_engine.mjs`。
- 适配器：`adapters/mock_adapter.mjs`（规则模板树 + 注入脏数据 + 固定错误表，覆盖 8 类故障）与 `adapters/openai_compat_adapter.mjs`（OpenAI 兼容接口）。
- 入口脚本：`run_bench.mjs`，支持 `--adapter`、`--repeat`、`--dataset` 参数。
- 报告导出：`report/bench_report.json` 与 `report/bench_report.csv`。
