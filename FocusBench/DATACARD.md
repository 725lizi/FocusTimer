# FocusBench 数据卡

## 数据集名称与版本

- 名称：FocusBench
- 版本：1.0.0

## 语言

中文（单语）。

## 任务类型

结构化生成：由专注记录生成结构化周复盘脑图，并做事实一致性检查。

## 数据来源

规则派生 + 固定种子。全部为人工合成（source_type=synthetic），不含任何真实用户记录。底稿取自 `../reliability_experiment/bench_fixtures.json` 的 5 份合成周数据，用固定种子线性同余生成（dev 20240607、locked 20240608）。同机重复运行输出逐字节一致（已验证两次 SHA256 相同）。

## 规模与划分

共 80 条，两集合输入互不重复。

| 集合 | 文件 | 条数 | regular | complex | anomaly | longtext | fault |
| --- | --- | --- | --- | --- | --- | --- | --- |
| dev | `data/samples.dev.jsonl` | 60 | 22 | 14 | 12 | 4 | 8 |
| locked | `data/samples.locked.jsonl` | 20 | 8 | 6 | 3 | 1 | 2 |

故障类型 8 类全覆盖：network、timeout、unauthorized、rate_limited、server、bad_request、empty、cancelled。

## 字段说明

| 字段 | 说明 | 取值范围 |
| --- | --- | --- |
| id | 样例唯一标识 | 字符串，集合内唯一 |
| source_type | 数据来源标记 | 固定为 synthetic |
| category | 样例类别 | regular / complex / anomaly / longtext / fault |
| input | 输入侧专注记录与周数据 | 结构化对象，字段值随样例而定 |
| fault_type | 注入的故障类型，仅 fault 类样例有值 | network / timeout / unauthorized / rate_limited / server / bad_request / empty / cancelled |
| fact_checklist | 事实一致性检查清单，由输入现算 | 结构化对象，含数字白名单、科目清单、环比方向、禁止表述项 |

## 标签如何产生

`fact_checklist` 由输入现算，不是人工标注。检查四项：数字只能取该样例白名单（输入本身全部字段值 + 通用基数 0/1/2/3/4/8/10/16/20/24/60）；不得出现清单外科目；增减方向词须与输入环比一致；不得出现禁止表述（效率提升百分比、健康诊断、心理诊断、疾病、治疗建议、模型排名，长文本类另加「过度细节」）。

## 允许用途

- 验证「专注记录 → 结构化周复盘脑图」链路的输出质量与修复能力。
- 回归测试评分与规整逻辑，确认判定口径稳定。
- 对比不同适配器在同一口径下的四类计数分布。

## 禁止用途

- 不得用于宣称真实模型排名。
- 不得当作真实用户行为分布。
- 不得用于健康或心理推断。

## 隐私与合规

全部为人工合成数据，无个人信息，不含任何真实用户记录。

## 已知偏差

- 底稿只有 5 份，场景多样性有限。
- 负荷区间偏校园自习。
- 科目池 6 个。

## 维护方式

- 改配额必须同步改配额常量并重跑 gen，保证数据与常量一致。
- `report` 目录不入库。
- 改动评分逻辑须同步评估对主工程 `../reliability_experiment/reliability_engine.mjs` 的影响。
