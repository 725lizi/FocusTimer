# FocusBench

FocusBench 是鸿端时计（HarmonyOS 原生专注计时应用）配套的轻量可复现基准，用于评测「专注记录 → 结构化周复盘脑图」这条链路的输出质量。

它不是模型排行榜，也不评测通用能力。

## 为什么需要它

模型返回的周复盘脑图经常是脏的：带代码围栏、缺字段、id 重复、文本超长、前后夹解说。直接统计「有没有输出」会把本地兜底也算成模型能力。

FocusBench 把结果拆成四类分别计数，让「模型直接可用」「修复后可用」「规则兜底」「无产出」互不混淆。评分与规整逻辑直接复用主工程实验目录的 `../reliability_experiment/reliability_engine.mjs`（449 行），不另起一套判定标准，保证基准与线上链路同一口径。

## 快速开始

```bash
# 1. 零 Key、离线跑一遍 mock 适配器
node run_bench.mjs --adapter mock

# 2. 重复两轮，确认计数稳定
node run_bench.mjs --adapter mock --repeat 2

# 3. 跑 locked 集合，只用于最终一次性报告
node run_bench.mjs --adapter mock --dataset locked

# 4. 评分器判定逻辑的确定性回归（不联网）
node tests/verify_scorer.mjs
```

预期看到：终端打印四类计数与软 Schema、事实一致性统计；`report/bench_report.json` 与 `report/bench_report.csv` 生成。

重新生成样例（改配额后必须执行）：

```
node gen_samples.mjs
```

mock 适配器在 dev 60 条上的实测结果为：direct 22（36.67%）、repaired 26（43.33%）、rule_fallback 11（18.33%）、failed 1（1.67%）；软 Schema 通过 44 条（73.33%）；事实一致 59 条（98.33%）；触发禁止表述 0 条。`--repeat 2` 两轮四类计数完全一致。

真实接口（DeepSeek `deepseek-chat`，locked 20 条）实测：20 条全部为 repaired（模型输出需经机械规整后可用，无一条直接可用）；软 Schema 20/20；事实一致 20/20；禁止表述 0 条；端到端延迟 p50≈1.2s、p95≈1.5s；单轮 token 约 7.9k（prompt 5,140 / completion 2,789）。多轮重复运行中事实一致率在 95%–100% 之间波动，原因是模型采样非确定性（temperature 0.4），四类计数不受影响。上述为本地单机、单 key、单时段结果，不代表模型排名。

## 目录结构

FocusBench/
├── README.md                    本文件
├── DATACARD.md                  数据卡
├── CHANGELOG.md                 变更记录
├── LICENSE                      许可证（MIT）
├── package.json                 脚本入口与元信息，无第三方依赖
├── gen_samples.mjs              确定性样例生成脚本
├── run_bench.mjs                入口脚本，解析参数、调度适配器、导出报告
├── scorer.mjs                   评分器，复用引擎判定 direct/repaired/兜底/失败
├── tests/
│   └── verify_scorer.mjs        评分器确定性回归，8 个构造用例，不联网
├── schema/
│   └── sample.schema.json       单条样例的 JSON Schema
├── data/
│   ├── samples.dev.jsonl        开发集 60 条，用于调参
│   └── samples.locked.jsonl     锁定集 20 条，只用于最终一次性报告
├── adapters/
│   ├── mock_adapter.mjs         规则模板树 + 注入脏数据 + 固定错误表
│   └── openai_compat_adapter.mjs  OpenAI 兼容接口适配器
└── report/                      运行产物，不入库
    ├── bench_report.json
    ├── bench_report.csv
    └── failed_raw/              事实一致性未通过样本的原始响应，便于事后核查

## 数据说明

- 全部为人工合成（source_type=synthetic），不含任何真实用户记录。
- 共 80 条：`data/samples.dev.jsonl` 60 条、`data/samples.locked.jsonl` 20 条；两集合的输入互不重复。
- 配额：
  - dev = regular 22 / complex 14 / anomaly 12 / longtext 4 / fault 8
  - locked = regular 8 / complex 6 / anomaly 3 / longtext 1 / fault 2
- 生成方式：固定种子线性同余（dev 20240607、locked 20240608），同机重复运行输出逐字节一致（已验证两次 SHA256 相同）。底稿取自 `../reliability_experiment/bench_fixtures.json` 的 5 份合成周数据。
- 故障类型 8 类全覆盖：network、timeout、unauthorized、rate_limited、server、bad_request、empty、cancelled。
- 用法差异：dev 用于调参和日常回归；locked 只用于最终一次性报告，调参阶段不要看 locked 结果。

## 指标定义

四类必须分列，不合成单一成功率。

| 指标 | 定义 |
| --- | --- |
| direct | 模型原始输出不经修复即可用 |
| repaired | 经 JSON 抽取与机械规整后可用（补 id、补 children、截断超长文本等） |
| rule_fallback | 模型链路失败，由本地规则模板兜底产出 |
| failed | 无产出（含用户取消 cancelled） |
| 软 Schema 通过 | 结构满足软约束的样例条数 |
| 事实一致性 | 检查四项：数字只能取该样例 `fact_checklist.numbers` 白名单（生成时由输入全字段值 + 通用基数 0/1/2/3/4/8/10/16/20/24/60 组成）；不得出现清单外科目；增减方向须与输入环比一致；不得出现禁止表述（效率提升百分比、健康诊断、心理诊断、疾病、治疗建议、模型排名，长文本类另加「过度细节」） |
| 延迟（仅真实接口） | 端到端耗时：从发出请求到响应体完全接收，不含本地评分时间 |
| token 与成本（仅真实接口） | 逐条记录 prompt/completion token，按环境变量里的单价估算成本 |

方向判定说明：只在「总体情况」分支里判断，避免「下周行动：减少中断」这类措辞被误判成环比下降；「环比增长13%」「环比+13%」「环比264%」「环比-13%」四种写法都识别，最终以「环比」后那个百分数的符号与输入同号为准。

## 两种适配器

- `--adapter mock`：零 Key、离线。它用规则模板树生成「理想响应」，并人为注入脏数据（代码围栏、删字段、重复 id、超长文本、前后解说）来覆盖 repaired 分支，用固定错误表覆盖 8 类故障。它不代表任何真实模型的能力，只用于验证基准自身的可运行性与判定口径。
- `--adapter openai`：走 OpenAI 兼容接口。需自行设置环境变量：

| 变量 | 说明 |
| --- | --- |
| `FOCUSBENCH_API_KEY` | 必填，接口密钥 |
| `FOCUSBENCH_BASE_URL` | 可选，接口地址，默认 https://api.deepseek.com |
| `FOCUSBENCH_MODEL` | 可选，默认 deepseek-chat |
| `FOCUSBENCH_PRICE_INPUT` | 可选，输入单价（元 / 百万 token）；不设则不计算成本 |
| `FOCUSBENCH_PRICE_OUTPUT` | 可选，输出单价（元 / 百万 token）；不设则不计算成本 |

未配置密钥时直接报错退出（exit 1），不会静默返回假成功。

不要把 Key 写进仓库，不要提交任何含密钥的文件。

## 报告怎么读

- `report/bench_report.json`：包含运行参数与元信息（适配器、数据集、重复轮次、开始时间、Node 版本、模型名、接口主机名、温度与 max_tokens、token 汇总）、四类计数与占比、软 Schema 通过数、事实一致性条数、禁止表述触发数、延迟分位，以及逐条明细。
- `report/bench_report.csv`：逐条结果，列序为 sample_id、task_type、difficulty、outcome、source、softOk、factConsistent、latencyMs、promptTokens、completionTokens、httpStatus、errorKind，CRLF 换行，可直接用 Excel 打开筛选。
- `report/failed_raw/`：事实一致性未通过的样本会在这里留下原始响应，明细里 `rawFile` 指向对应文件。重复运行时文件名带 `run1_`、`run2_` 前缀，避免相互覆盖。

## 已知限制与不适用场景

- 样本量 80 条，统计波动不可忽略。
- 单一应用场景，只覆盖专注记录到周复盘脑图这一条链路。
- 中文单语。
- 故障为注入而非真实网络抖动。
- 未做人工标注一致性检验。
- 不代表真实模型排名，不用于通用能力比较。

## 与主工程的关系

- 复用 `../reliability_experiment/reliability_engine.mjs` 的评分与规整逻辑。
- 不修改主工程 `entry/src` 下任何文件。
- 基准与线上链路同一判定口径，改动评分逻辑须同步评估对主工程的影响。

## 许可证

MIT。
