<!-- 负责模型：DeepSeek -->
# 失败案例库（离线、可复现）

> **合成数据声明**：本案例库全部来自 `fault_corpus.jsonl` 的人工合成样本，
> 不代表真实模型的表现，也不含任何真实用户数据；真实失败案例需在设备上实测采集。

共 **53 条**（repaired 24 + rule 9 + 网络降级 18 + cancelled 2）。
`direct`（模型直出就可用）不算失败案例，不收录。

## 内容类 · 结构修复成功（repaired）（24 条）

| 样本 | 批次 | 场景 | 结果 | 来源 | 错误类别 | 处理方式 |
|---|---|---|---|---|---|---|
| B08 | bare | fence | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B09 | bare | fence | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B10 | bare | fence | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B11 | bare | chatter | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B12 | bare | chatter | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B13 | bare | chatter | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| B20 | bare | missing_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B21 | bare | missing_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B22 | bare | duplicate_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B23 | bare | duplicate_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B24 | bare | missing_children | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B25 | bare | missing_children | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B26 | bare | wrong_children_type | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B27 | bare | wrong_children_type | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B29 | bare | long_text | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| B30 | bare | missing_text | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S19 | structured | fence | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| S20 | structured | chatter | repaired | llm | — | 抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm） |
| S24 | structured | missing_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S25 | structured | duplicate_id | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S26 | structured | missing_children | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S27 | structured | wrong_children_type | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S29 | structured | long_text | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |
| S30 | structured | missing_text | repaired | llm | — | 解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm） |

## 内容类 · 规则兜底（rule）（9 条）

| 样本 | 批次 | 场景 | 结果 | 来源 | 错误类别 | 处理方式 |
|---|---|---|---|---|---|---|
| B14 | bare | truncated | rule | rule | INVALID | 云端结果不可用（INVALID）→ 已降级本地规则树（rule） |
| B15 | bare | truncated | rule | rule | INVALID | 云端结果不可用（INVALID）→ 已降级本地规则树（rule） |
| B16 | bare | no_braces | rule | rule | NO_JSON | 云端结果不可用（NO_JSON）→ 已降级本地规则树（rule） |
| B17 | bare | no_braces | rule | rule | NO_JSON | 云端结果不可用（NO_JSON）→ 已降级本地规则树（rule） |
| B18 | bare | empty | rule | rule | EMPTY | 云端结果不可用（EMPTY）→ 已降级本地规则树（rule） |
| B19 | bare | empty | rule | rule | EMPTY | 云端结果不可用（EMPTY）→ 已降级本地规则树（rule） |
| S21 | structured | truncated | rule | rule | INVALID | 云端结果不可用（INVALID）→ 已降级本地规则树（rule） |
| S22 | structured | no_braces | rule | rule | NO_JSON | 云端结果不可用（NO_JSON）→ 已降级本地规则树（rule） |
| S23 | structured | empty | rule | rule | EMPTY | 云端结果不可用（EMPTY）→ 已降级本地规则树（rule） |

## 网络类 · 自动降级（rule）（18 条）

| 样本 | 批次 | 场景 | 结果 | 来源 | 错误类别 | 处理方式 |
|---|---|---|---|---|---|---|
| B31 | bare | offline | rule | rule | network (框架码 2300003) | 网络/环境错误（network）→ 已自动降级本地规则树（rule） |
| B32 | bare | offline | rule | rule | network | 网络/环境错误（network）→ 已自动降级本地规则树（rule） |
| B33 | bare | timeout | rule | rule | timeout (HTTP 408) | 网络/环境错误（timeout）→ 已自动降级本地规则树（rule） |
| B34 | bare | timeout | rule | rule | timeout (框架码 2300004) | 网络/环境错误（timeout）→ 已自动降级本地规则树（rule） |
| B35 | bare | unauthorized | rule | rule | unauthorized (HTTP 401) | 网络/环境错误（unauthorized）→ 已自动降级本地规则树（rule） |
| B36 | bare | unauthorized | rule | rule | unauthorized (HTTP 403) | 网络/环境错误（unauthorized）→ 已自动降级本地规则树（rule） |
| B37 | bare | rate_limited | rule | rule | rate_limited (HTTP 429) | 网络/环境错误（rate_limited）→ 已自动降级本地规则树（rule） |
| B38 | bare | server_error | rule | rule | server (HTTP 500) | 网络/环境错误（server）→ 已自动降级本地规则树（rule） |
| B39 | bare | bad_request | rule | rule | bad_request (HTTP 422) | 网络/环境错误（bad_request）→ 已自动降级本地规则树（rule） |
| S31 | structured | offline | rule | rule | network (框架码 2300003) | 网络/环境错误（network）→ 已自动降级本地规则树（rule） |
| S32 | structured | offline | rule | rule | network | 网络/环境错误（network）→ 已自动降级本地规则树（rule） |
| S33 | structured | timeout | rule | rule | timeout (HTTP 408) | 网络/环境错误（timeout）→ 已自动降级本地规则树（rule） |
| S34 | structured | timeout | rule | rule | timeout (框架码 2300004) | 网络/环境错误（timeout）→ 已自动降级本地规则树（rule） |
| S35 | structured | unauthorized | rule | rule | unauthorized (HTTP 401) | 网络/环境错误（unauthorized）→ 已自动降级本地规则树（rule） |
| S36 | structured | unauthorized | rule | rule | unauthorized (HTTP 403) | 网络/环境错误（unauthorized）→ 已自动降级本地规则树（rule） |
| S37 | structured | rate_limited | rule | rule | rate_limited (HTTP 429) | 网络/环境错误（rate_limited）→ 已自动降级本地规则树（rule） |
| S38 | structured | server_error | rule | rule | server (HTTP 500) | 网络/环境错误（server）→ 已自动降级本地规则树（rule） |
| S39 | structured | bad_request | rule | rule | bad_request (HTTP 422) | 网络/环境错误（bad_request）→ 已自动降级本地规则树（rule） |

## 网络类 · 用户取消（cancelled）（2 条）

| 样本 | 批次 | 场景 | 结果 | 来源 | 错误类别 | 处理方式 |
|---|---|---|---|---|---|---|
| B40 | bare | cancelled | cancelled | failed | cancelled (框架码 2300089) | 用户主动取消，不降级，本次不出结果 |
| S40 | structured | cancelled | cancelled | failed | cancelled (框架码 2300089) | 用户主动取消，不降级，本次不出结果 |

## 口径与边界

1. 案例只覆盖「非 direct」的四种结果，每条都记录是否降级（`fallback`）与最终来源。
2. 内容类的错误类别是解析阶段的真实错误码（`EMPTY / NO_JSON / INVALID`）；
   网络类的错误类别是 8 种 `LlmErrorKind` 之一，两者分属不同层，不要混用。
3. `cancelled` 是用户主动取消，不算失败，但它也不降级，所以收进案例库便于对照。
4. 全部为合成数据，条数是人为编排的测试配额，不能用来估计真实模型的失败率。

