<!-- 负责模型：DeepSeek -->
# G0–G3 三级容错消融实验（离线、可复现）

> 本表由 `ablation_g0g3.mjs` 生成，数字与 `ablation_results.json` 完全一致。
> 数据来自 `fault_corpus.jsonl` 的 **60 条内容样本**（structured S01–S30 / bare B01–B30）。
> **合成数据**：只描述这 60 条人工编排的用例，**不代表真实模型成功率**；
> 真实成功率与 p50/p95 延迟必须用真实 API 在设备上实测，本表不提供也不预测。
> 口径自检：与样本库写死的 `expect` 逐条比对 **60/60 一致**（与 `validate_corpus.mjs` 共用同一套 `reliability_engine.mjs`）。

## 1. 四级对比表

| 级 | 处理 | structured | bare | 合计 |
|---|---|---|---|---|
| G0 | raw 直接 parse（可用） | 23/30 76.7% | 16/30 53.3% | 39/60 65.0% |
| G1 | + 结构化 Prompt（软 Schema 合规率） | 18/30 60.0% | 7/30 23.3% | 25/60 41.7% |
| G2 | + 抽取/规整/硬逻辑（可用） | 27/30 90.0% | 24/30 80.0% | 51/60 85.0% |
| G3 | + 规则树兜底（最终可用） | 30/30 100.0% | 30/30 100.0% | 60/60 100.0% |

> G1 这一层**不新增任何处理**，所以它没有独立的「可用率」（与 G0 相同）；
> 表里列的是「裸 parse 后天然满足软 Schema」的比例，用来量化结构化 Prompt 本身的贡献。

## 2. G1：结构化 Prompt 把输入变好多少

| 指标 | structured | bare | 差值 |
|---|---|---|---|
| 原始可解析率 | 76.7% | 53.3% | +23.3 pp |
| 软 Schema 合规率 | 60.0% | 23.3% | +36.7 pp |

## 3. G0 失败构成（本层的起点有多差）

- 失败 21 条 = 解析失败 17 + 形态不符（解析出来但没有 children 数组，例如「{root:{...}}」信封写法）4

## 4. G2：本地解析校验救回多少

- 成功 51/60 85.0%：direct 27 + repaired 24
- 修复贡献：**8 条**在 G0 原本失败、被本地修复救回（fence 4 + chatter 4），逐条 id：S19, S20, B08, B09, B10, B11, B12, B13
- 软 Schema 通过率 **47/60 78.3%**（全量口径，与 `validate_corpus.mjs` 打印的一致）；只看 G2 成功树则为 47/51 92.2%
- 仍失败 9 条：truncated 3 / no_braces 3 / empty 3，本层到此为止就是失败

## 5. G3：兜底把最后一段补齐

| 结果 | structured | bare | 合计 | 占比 |
|---|---|---|---|---|
| 云端直用（direct） | 19 | 8 | 27 | 45.0% |
| 云端修好（repaired） | 8 | 16 | 24 | 40.0% |
| 规则兜底（rule） | 3 | 6 | 9 | 15.0% |
| 彻底失败（failed） | 0 | 0 | 0 | 0.0% |

- **最终可用率 100.0%**（60/60）
- **兜底率 15.0%**（9/60）
- 最终来源：llm 51 / rule 9 / failed 0
- 规则树自检：19 节点 / 深度 3 / 硬逻辑 通过 / 软 Schema 通过

## 6. 逐条明细（便于复核）

| id | 批 | 场景 | G0 可用 | G1 软合规 | G2 | G3 |
|---|---|---|---|---|---|---|
| S01 | structured | clean | ✅ | ✅ | direct | direct |
| S02 | structured | clean | ✅ | ✅ | direct | direct |
| S03 | structured | clean | ✅ | ✅ | direct | direct |
| S04 | structured | clean | ✅ | ✅ | direct | direct |
| S05 | structured | clean | ✅ | ✅ | direct | direct |
| S06 | structured | clean | ✅ | ✅ | direct | direct |
| S07 | structured | clean | ✅ | ✅ | direct | direct |
| S08 | structured | clean | ✅ | ✅ | direct | direct |
| S09 | structured | clean | ✅ | ✅ | direct | direct |
| S10 | structured | clean | ✅ | ✅ | direct | direct |
| S11 | structured | clean | ✅ | ✅ | direct | direct |
| S12 | structured | clean | ✅ | ✅ | direct | direct |
| S13 | structured | clean | ✅ | ✅ | direct | direct |
| S14 | structured | clean | ✅ | ✅ | direct | direct |
| S15 | structured | clean | ✅ | ✅ | direct | direct |
| S16 | structured | clean | ✅ | ✅ | direct | direct |
| S17 | structured | envelope | ❌ | ✅ | direct | direct |
| S18 | structured | envelope | ❌ | ✅ | direct | direct |
| S19 | structured | fence | ❌ | ❌ | repaired | repaired |
| S20 | structured | chatter | ❌ | ❌ | repaired | repaired |
| S21 | structured | truncated | ❌ | ❌ | fail | rule |
| S22 | structured | no_braces | ❌ | ❌ | fail | rule |
| S23 | structured | empty | ❌ | ❌ | fail | rule |
| S24 | structured | missing_id | ✅ | ❌ | repaired | repaired |
| S25 | structured | duplicate_id | ✅ | ❌ | repaired | repaired |
| S26 | structured | missing_children | ✅ | ❌ | repaired | repaired |
| S27 | structured | wrong_children_type | ✅ | ❌ | repaired | repaired |
| S28 | structured | wrong_depth | ✅ | ❌ | direct | direct |
| S29 | structured | long_text | ✅ | ❌ | repaired | repaired |
| S30 | structured | missing_text | ✅ | ❌ | repaired | repaired |
| B01 | bare | clean | ✅ | ✅ | direct | direct |
| B02 | bare | clean | ✅ | ✅ | direct | direct |
| B03 | bare | clean | ✅ | ✅ | direct | direct |
| B04 | bare | clean | ✅ | ✅ | direct | direct |
| B05 | bare | clean | ✅ | ✅ | direct | direct |
| B06 | bare | envelope | ❌ | ✅ | direct | direct |
| B07 | bare | envelope | ❌ | ✅ | direct | direct |
| B08 | bare | fence | ❌ | ❌ | repaired | repaired |
| B09 | bare | fence | ❌ | ❌ | repaired | repaired |
| B10 | bare | fence | ❌ | ❌ | repaired | repaired |
| B11 | bare | chatter | ❌ | ❌ | repaired | repaired |
| B12 | bare | chatter | ❌ | ❌ | repaired | repaired |
| B13 | bare | chatter | ❌ | ❌ | repaired | repaired |
| B14 | bare | truncated | ❌ | ❌ | fail | rule |
| B15 | bare | truncated | ❌ | ❌ | fail | rule |
| B16 | bare | no_braces | ❌ | ❌ | fail | rule |
| B17 | bare | no_braces | ❌ | ❌ | fail | rule |
| B18 | bare | empty | ❌ | ❌ | fail | rule |
| B19 | bare | empty | ❌ | ❌ | fail | rule |
| B20 | bare | missing_id | ✅ | ❌ | repaired | repaired |
| B21 | bare | missing_id | ✅ | ❌ | repaired | repaired |
| B22 | bare | duplicate_id | ✅ | ❌ | repaired | repaired |
| B23 | bare | duplicate_id | ✅ | ❌ | repaired | repaired |
| B24 | bare | missing_children | ✅ | ❌ | repaired | repaired |
| B25 | bare | missing_children | ✅ | ❌ | repaired | repaired |
| B26 | bare | wrong_children_type | ✅ | ❌ | repaired | repaired |
| B27 | bare | wrong_children_type | ✅ | ❌ | repaired | repaired |
| B28 | bare | wrong_depth | ✅ | ❌ | direct | direct |
| B29 | bare | long_text | ✅ | ❌ | repaired | repaired |
| B30 | bare | missing_text | ✅ | ❌ | repaired | repaired |

## 7. 边界（必须一起读）

1. 本表只覆盖**离线可复现**的指标：原始可解析率、软 Schema 通过率、最终可用率、兜底率、三类结果分布。
2. **事实一致率**（生成内容与底稿数字是否相符）不在本脚本展开，由独立的核查脚本负责。
3. **p50/p95 延迟、真实模型成功率**必须用真实 API 在设备上实测，本表一律不计算、不预估、不外推。
4. 所有样本都是合成数据，比例是人为编排的测试配额，不能用来估计真实模型的任何比率。

