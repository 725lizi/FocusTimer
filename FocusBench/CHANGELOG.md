# Changelog

本文件格式遵循 Keep a Changelog。

## [1.0.0] - 2026-11-15

### Added

- 数据层：`data/samples.dev.jsonl` 60 条、`data/samples.locked.jsonl` 20 条，全部人工合成（source_type=synthetic），固定种子线性同余生成（dev 20240607、locked 20240608），同机重复运行输出逐字节一致。
- 评分器：四类分列计数（direct / repaired / rule_fallback / failed）、软 Schema 检查、事实一致性检查。评分逻辑复用 `reliability_experiment/reliability_engine.mjs`。
- 适配器：`adapters/mock.mjs`（规则模板树 + 注入脏数据 + 固定错误表，覆盖 8 类故障）与 `adapters/openai_compat.mjs`（OpenAI 兼容接口）。
- 入口脚本：`run_bench.mjs`，支持 `--adapter`、`--repeat`、`--dataset` 参数。
- 报告导出：`report/bench_report.json` 与 `report/bench_report.csv`。
