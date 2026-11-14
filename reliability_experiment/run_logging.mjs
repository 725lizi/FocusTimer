#!/usr/bin/env node
// 负责模型：DeepSeek
// =============================================================================
// run_logging.mjs —— 结构化日志 + 失败案例库（离线、可复现）
//
// 对应指导老师 V2.3：「记录原始模型成功、结构修复成功、规则兜底成功三类结果，
// 建立日志字段、错误码和失败案例库」。
//
// 本脚本做三件事：
//   1) 给 fault_corpus.jsonl 的全部 80 条样本各生成一条**结构化日志**（纯函数 buildRunLog），
//      落盘 run_logs.json；
//   2) 把「非 direct」的案例抽成**失败案例库**，落盘 failure_cases.json + failure_cases.md；
//   3) 跑一组自检（错误码映射反测、降级规则反测、计数核对、案例库反测、日志抽查），
//      任一不符就以非零退出码结束。
//
// 判定逻辑一律来自 reliability_engine.mjs（analyze / buildRuleTree / structuralOk），
// 本文件只负责「把判定结果记成日志」，不重新实现抽取/规整。
//
// 【诚实边界】全部是人工合成数据，不代表真实模型；不计算 p50/p95、不预测真实成功率、
// 不编造因果或效率百分比。真实运行日志要等用户在设备上配 Key 实测才有。
//
// 运行：node run_logging.mjs   （自检通过 → 0；发现矛盾 → 非零）
// 产物：run_logs.json / failure_cases.json / failure_cases.md
//       （错误码表 error_codes.md 是文档，由人读，内容以真实源码为准）
// =============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyze, extract, buildRuleTree, structuralOk } from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = path.join(HERE, 'fault_corpus.jsonl');
const FIXTURE_PATH = path.join(HERE, 'summary_fixture.json');
const OUT_LOGS = path.join(HERE, 'run_logs.json');
const OUT_CASES_JSON = path.join(HERE, 'failure_cases.json');
const OUT_CASES_MD = path.join(HERE, 'failure_cases.md');

// ---------------------------------------------------------------------------
// 1) 错误码映射：逐行对照 services/ai/HttpErrorMapper.ets（不改语义、不新造错误码）
// ---------------------------------------------------------------------------
/** LlmErrorKind 的 8 种取值（与 ReportStrategy.ets 的 type 定义一致） */
const LLM_ERROR_KINDS = ['network', 'timeout', 'unauthorized', 'rate_limited', 'server', 'bad_request', 'empty', 'cancelled'];

/** HTTP 状态码 → LlmErrorKind（同 HttpErrorMapper.classifyStatus） */
function classifyStatus(status) {
  if (status === 401 || status === 403) return 'unauthorized';
  if (status === 429) return 'rate_limited';
  if (status === 400 || status === 404 || status === 422) return 'bad_request';
  if (status >= 500) return 'server';
  if (status === 408) return 'timeout';
  return 'network';
}

/** 鸿蒙框架码 → LlmErrorKind（同 HttpErrorMapper.classifyFrameworkError） */
function classifyFrameworkError(code) {
  if (code === 2300089) return 'cancelled';
  if (code === 2300004 || code === 2300047 || code === 2300999) return 'timeout';
  return 'network';
}

/** 是否降级（同 ReportStrategy.shouldFallback：只有用户主动取消不降级） */
function shouldFallback(kind) {
  return kind !== 'cancelled';
}

/** 网络类样本归一后的错误类别：先看 HTTP，再看框架码，都没有按 network 处理 */
function errorKindOf(sample) {
  if (Number.isInteger(sample.http_status)) return classifyStatus(sample.http_status);
  if (Number.isInteger(sample.framework_code)) return classifyFrameworkError(sample.framework_code);
  return 'network';
}

// ---------------------------------------------------------------------------
// 2) 纯函数：一条样本 → 一条结构化日志
// ---------------------------------------------------------------------------
/**
 * 日志字段（见 run_logs.json 里的 schema 说明）：
 * runId / sampleId / batch / kind / caseType / outcome / finalSource / fallback /
 * hardOk / softOk / errorKind / errorDetail / httpStatus / frameworkCode / rawLength
 *
 * 注意：**不读系统时钟**，runId 由样本 id 确定性派生（log-S01），保证逐字节可复现。
 */
function buildRunLog(sample, fixture) {
  const log = {
    runId: 'log-' + sample.id,
    sampleId: sample.id,
    batch: sample.batch,
    kind: sample.kind,
    caseType: sample.case_type,
    outcome: null,
    finalSource: null,
    fallback: false,
    hardOk: null,
    softOk: null,
    errorKind: null,
    errorDetail: null,
    httpStatus: null,
    frameworkCode: null,
    rawLength: null,
  };

  if (sample.kind === 'content') {
    const judged = analyze(sample.raw);
    log.hardOk = judged.hardOk === true;
    log.softOk = judged.softOk === true;
    log.rawLength = typeof sample.raw === 'string' ? sample.raw.length : null;
    log.errorDetail = judged.extractError || judged.normalizeError || null;
    if (judged.g2_outcome === 'fail') {
      // 云端结果不可用：确认规则树确实能建出来，才算「兜底成功」
      const tree = buildRuleTree(fixture);
      if (tree === null || !structuralOk(tree)) throw new Error(sample.id + ' 规则树构建失败');
      log.outcome = 'rule';
      log.finalSource = 'rule';
      log.fallback = true;
      // 失败类别是解析阶段的真实错误码（EMPTY / NO_JSON / INVALID），不是 8 个 LlmErrorKind 之一
      log.errorKind = judged.extractError || judged.normalizeError || 'INVALID';
    } else if (judged.g2_outcome === 'repaired') {
      log.outcome = 'repaired';
      log.finalSource = 'llm';
    } else {
      log.outcome = 'direct';
      log.finalSource = 'llm';
    }
  } else {
    // 网络类：没有 raw，只有错误码；outcome 由 expect_fallback 决定
    const kind = sample.error_kind;
    log.errorKind = kind;
    log.httpStatus = Number.isInteger(sample.http_status) ? sample.http_status : null;
    log.frameworkCode = Number.isInteger(sample.framework_code) ? sample.framework_code : null;
    if (shouldFallback(kind)) {
      log.outcome = 'rule';
      log.finalSource = 'rule';
      log.fallback = true;
    } else {
      log.outcome = 'cancelled';
      log.finalSource = 'failed';
      log.fallback = false;
    }
  }
  return log;
}

// ---------------------------------------------------------------------------
// 3) 失败案例库：非 direct 才算案例
// ---------------------------------------------------------------------------
function handlingOf(sample, log) {
  if (log.kind === 'network') {
    return log.outcome === 'cancelled'
      ? '用户主动取消，不降级，本次不出结果'
      : `网络/环境错误（${log.errorKind}）→ 已自动降级本地规则树（rule）`;
  }
  if (log.outcome === 'repaired') {
    // 两种「修复」要分开说：抽取阶段去围栏/去口语，还是规整阶段补结构
    const ex = extract(sample.raw);
    const rescuedByExtract = !ex.error && ex.text !== sample.raw;
    return rescuedByExtract
      ? '抽取阶段去掉代码围栏/前后口语后解析成功 → 采用云端结果（llm）'
      : '解析成功但结构有脏数据，规整补齐（补 id / 补 children / 截断文本）后可用 → 采用云端结果（llm）';
  }
  return `云端结果不可用（${log.errorKind}）→ 已降级本地规则树（rule）`;
}

function buildFailureCase(sample, log) {
  const item = {
    sampleId: log.sampleId,
    batch: log.batch,
    kind: log.kind,
    caseType: log.caseType,
    outcome: log.outcome,
    finalSource: log.finalSource,
    fallback: log.fallback,
    errorKind: log.errorKind,
    errorDetail: log.errorDetail,
    httpStatus: log.httpStatus,
    frameworkCode: log.frameworkCode,
    handling: handlingOf(sample, log),
  };
  // 内容类案例附原始 raw，便于人工复核；网络类没有 raw
  if (log.kind === 'content') item.raw = sample.raw;
  return item;
}

// ---------------------------------------------------------------------------
// 4) 自检
// ---------------------------------------------------------------------------
function runSelfChecks(logs, cases, contentLogs, networkLogs, fixture) {
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok: ok === true, detail });

  // ① 错误码映射反测（源码规则）
  const mapCases = [
    ['HTTP 503 → server', classifyStatus(503) === 'server'],
    ['HTTP 429 → rate_limited', classifyStatus(429) === 'rate_limited'],
    ['HTTP 401 → unauthorized', classifyStatus(401) === 'unauthorized'],
    ['HTTP 403 → unauthorized', classifyStatus(403) === 'unauthorized'],
    ['HTTP 408 → timeout', classifyStatus(408) === 'timeout'],
    ['HTTP 422 → bad_request', classifyStatus(422) === 'bad_request'],
    ['HTTP 200 → network（其余归网络）', classifyStatus(200) === 'network'],
    ['框架码 2300089 → cancelled', classifyFrameworkError(2300089) === 'cancelled'],
    ['框架码 2300004 → timeout', classifyFrameworkError(2300004) === 'timeout'],
    ['框架码 2300099 → network', classifyFrameworkError(2300099) === 'network'],
  ];
  check('错误码映射反测', mapCases.every(([, ok]) => ok),
    mapCases.map(([name, ok]) => (ok ? '✓' : '✗') + name).join('，'));

  // ② 降级规则反测：8 种错误里只有 cancelled 不降级
  const fallbackMap = LLM_ERROR_KINDS.map((k) => [k, shouldFallback(k)]);
  check('降级规则反测（只有 cancelled 不降级）',
    fallbackMap.filter(([, v]) => v === false).length === 1 && shouldFallback('cancelled') === false,
    fallbackMap.map(([k, v]) => `${k}:${v}`).join(' '));

  // ③ 网络类样本的错误类别必须与样本自带 error_kind 一致（再证一次映射没写错）
  const networkMismatch = networkLogs.filter((l) => {
    const sample = fixturesById.get(l.sampleId);
    return errorKindOf(sample) !== sample.error_kind;
  });
  check('网络类 error_kind 与样本一致', networkMismatch.length === 0,
    networkMismatch.length === 0 ? '20 条全部一致' : '不一致：' + networkMismatch.map((l) => l.sampleId).join(','));

  // ④ 日志完整性与关键计数
  const countOf = (list, pick) => list.reduce((acc, item) => {
    const k = pick(item);
    acc[k] = (acc[k] || 0) + 1;
    return acc;
  }, {});
  const contentByOutcome = countOf(contentLogs, (l) => l.outcome);
  const networkByOutcome = countOf(networkLogs, (l) => l.outcome);
  check('日志条数 = 80', logs.length === 80, `实际 ${logs.length}`);
  check('内容类 direct 27 / repaired 24 / rule 9 / failed 0',
    contentByOutcome.direct === 27 && contentByOutcome.repaired === 24
    && contentByOutcome.rule === 9 && (contentByOutcome.failed || 0) === 0,
    JSON.stringify(contentByOutcome));
  check('网络类 降级 18 / cancelled 2',
    networkByOutcome.rule === 18 && networkByOutcome.cancelled === 2,
    JSON.stringify(networkByOutcome));

  // ⑤ 案例库反测：不含 direct，总数 53
  check('案例库不含 direct 案例', cases.every((c) => c.outcome !== 'direct'),
    `direct 案例 ${cases.filter((c) => c.outcome === 'direct').length} 条`);
  check('案例库总数 = 53（24+9+18+2）', cases.length === 53, `实际 ${cases.length}`);

  // ⑥ 抽查：内容类 S01（direct）与网络类 S40（cancelled）
  const s01 = logs.find((l) => l.sampleId === 'S01');
  const s40 = logs.find((l) => l.sampleId === 'S40');
  check('抽查内容类 S01', s01 && s01.outcome === 'direct' && s01.finalSource === 'llm'
    && s01.fallback === false && s01.hardOk === true && s01.softOk === true
    && s01.errorKind === null && s01.rawLength > 0,
  s01 ? JSON.stringify({ outcome: s01.outcome, finalSource: s01.finalSource, fallback: s01.fallback, hardOk: s01.hardOk, softOk: s01.softOk, rawLength: s01.rawLength }) : 'missing');
  check('抽查网络类 S40（cancelled）', s40 && s40.outcome === 'cancelled' && s40.finalSource === 'failed'
    && s40.fallback === false && s40.errorKind === 'cancelled' && s40.frameworkCode === 2300089
    && s40.rawLength === null,
  s40 ? JSON.stringify({ outcome: s40.outcome, finalSource: s40.finalSource, fallback: s40.fallback, errorKind: s40.errorKind, frameworkCode: s40.frameworkCode }) : 'missing');

  // ⑦ 顺序：先按 kind，再按 id 字典序
  const expectedOrder = logs.slice().sort((a, b) => (a.kind < b.kind ? -1 : a.kind > b.kind ? 1 : a.sampleId < b.sampleId ? -1 : 1));
  check('日志顺序（kind → id）', JSON.stringify(expectedOrder.map((l) => l.runId)) === JSON.stringify(logs.map((l) => l.runId)),
    '按 kind 再按 id 字典序排好');

  // ⑧ 内容类日志的 hardOk/softOk 必须与 reliability_engine 的判定一致（抽 5 条复核）
  const spot = contentLogs.filter((l) => ['S01', 'S21', 'S28', 'B28', 'B30'].includes(l.sampleId));
  const spotOk = spot.every((l) => {
    const j = analyze(fixturesById.get(l.sampleId).raw);
    return l.hardOk === (j.hardOk === true) && l.softOk === (j.softOk === true);
  });
  check('内容类 hardOk/softOk 与引擎判定一致（抽 5 条）', spot.length === 5 && spotOk, spot.map((l) => l.sampleId).join(','));

  void fixture;
  return checks;
}

// ---------------------------------------------------------------------------
// 5) 主流程
// ---------------------------------------------------------------------------
let fixturesById = new Map();

function main() {
  const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  const lines = fs.readFileSync(CORPUS_PATH, 'utf8').split('\n').filter((l) => l.trim() !== '');
  const samples = lines.map((l) => JSON.parse(l));
  fixturesById = new Map(samples.map((s) => [s.id, s]));

  // 固定顺序：先按 kind（content < network），再按 id 字典序
  samples.sort((a, b) => (a.kind < b.kind ? -1 : a.kind > b.kind ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const logs = samples.map((s) => buildRunLog(s, fixture));
  const byId = new Map(samples.map((s) => [s.id, s]));
  const contentLogs = logs.filter((l) => l.kind === 'content');
  const networkLogs = logs.filter((l) => l.kind === 'network');
  const cases = logs
    .filter((l) => l.outcome !== 'direct')
    .map((l) => buildFailureCase(byId.get(l.sampleId), l));

  const checks = runSelfChecks(logs, cases, contentLogs, networkLogs, fixture);

  // 控制台
  const line = '='.repeat(72);
  const contentByOutcome = logs.filter((l) => l.kind === 'content').reduce((a, l) => { a[l.outcome] = (a[l.outcome] || 0) + 1; return a; }, {});
  const networkByOutcome = logs.filter((l) => l.kind === 'network').reduce((a, l) => { a[l.outcome] = (a[l.outcome] || 0) + 1; return a; }, {});
  console.log(line);
  console.log('结构化日志 + 失败案例库（离线、可复现）—— 合成数据，不代表真实模型');
  console.log(line);
  console.log('口径：日志只记录「判定结果」（direct/repaired/rule/failed），不读真实时钟、不含随机数；');
  console.log('      错误码取自 HttpErrorMapper / ReportStrategy（8 种 LlmErrorKind）；');
  console.log('      不计算 p50/p95、不预测真实成功率。');
  console.log('');
  console.log(`日志总数 ${logs.length} 条（内容类 ${contentLogs.length} / 网络类 ${networkLogs.length}）`);
  console.log(`内容类：direct ${contentByOutcome.direct || 0} / repaired ${contentByOutcome.repaired || 0} / rule ${contentByOutcome.rule || 0} / failed ${contentByOutcome.failed || 0}`);
  console.log(`网络类：降级 ${networkByOutcome.rule || 0} / cancelled ${networkByOutcome.cancelled || 0}`);
  console.log(`失败案例库 ${cases.length} 条（repaired ${contentByOutcome.repaired || 0} + rule ${contentByOutcome.rule || 0} + 网络降级 ${networkByOutcome.rule || 0} + cancelled ${networkByOutcome.cancelled || 0}）`);
  console.log('');
  console.log('自检：');
  for (const c of checks) console.log(`  ${c.ok ? '✓' : '✗'} ${c.name} —— ${c.detail}`);
  console.log('');
  console.log(`已落盘：${path.basename(OUT_LOGS)} / ${path.basename(OUT_CASES_JSON)} / ${path.basename(OUT_CASES_MD)}`);
  console.log('错误码表 error_codes.md 为人工文档，内容对照源码 HttpErrorMapper.ets，不新造错误码。');
  console.log(line);

  writeLogs(logs, contentByOutcome, networkByOutcome);
  writeCases(cases);

  const failedChecks = checks.filter((c) => !c.ok);
  if (failedChecks.length > 0) {
    console.log('');
    console.log('自检失败，以非零退出码结束：');
    for (const c of failedChecks) console.log('  ✗ ' + c.name + ' —— ' + c.detail);
    process.exitCode = 1;
    return;
  }
  process.exitCode = 0;
}

// ---------------------------------------------------------------------------
// 6) 落盘
// ---------------------------------------------------------------------------
function writeLogs(logs, contentByOutcome, networkByOutcome) {
  const payload = {
    _model: 'DeepSeek',
    _declaration: '本文件是离线合成的结构化日志，全部基于人工编写的测试样本；不代表真实模型、不含真实用户数据。真实运行日志需在设备上实测采集。',
    schema: {
      runId: '由样本 id 确定性派生（log-<sampleId>），不含时间戳',
      sampleId: '样本 id（S01–S40 / B01–B40）',
      batch: 'bare / structured',
      kind: 'content / network',
      caseType: '样本场景（clean / fence / timeout / cancelled …）',
      outcome: 'direct（模型直出可用）/ repaired（结构修复后可用）/ rule（规则兜底）/ failed（彻底失败）',
      finalSource: 'llm / rule / failed',
      fallback: '是否发生降级（布尔）',
      hardOk: '内容类：硬逻辑是否通过；网络类 null',
      softOk: '内容类：软 Schema 是否通过；网络类 null',
      errorKind: '内容类失败时为解析错误码（EMPTY/NO_JSON/INVALID），否则 null；网络类为 8 种 LlmErrorKind 之一',
      errorDetail: '内容类：extract/normalize 的错误码；网络类 null',
      httpStatus: '网络类 HTTP 状态码，没有则 null；内容类 null',
      frameworkCode: '网络类鸿蒙框架码，没有则 null；内容类 null',
      rawLength: '内容类 raw 字符长度；网络类 null',
    },
    summary: {
      total: logs.length,
      content: { total: logs.filter((l) => l.kind === 'content').length, ...contentByOutcome },
      network: { total: logs.filter((l) => l.kind === 'network').length, ...networkByOutcome },
    },
    logs,
  };
  fs.writeFileSync(OUT_LOGS, JSON.stringify(payload, null, 2) + '\n', 'utf8');
}

function writeCases(cases) {
  const groups = [
    { key: 'content-repaired', title: '内容类 · 结构修复成功（repaired）', items: cases.filter((c) => c.kind === 'content' && c.outcome === 'repaired') },
    { key: 'content-rule', title: '内容类 · 规则兜底（rule）', items: cases.filter((c) => c.kind === 'content' && c.outcome === 'rule') },
    { key: 'network-fallback', title: '网络类 · 自动降级（rule）', items: cases.filter((c) => c.kind === 'network' && c.outcome === 'rule') },
    { key: 'network-cancelled', title: '网络类 · 用户取消（cancelled）', items: cases.filter((c) => c.kind === 'network' && c.outcome === 'cancelled') },
  ];

  const payload = {
    _model: 'DeepSeek',
    _declaration: '失败案例库：只收录非 direct 的案例（结构修复 / 规则兜底 / 网络降级 / 用户取消），全部来自人工合成样本，不代表真实模型表现。',
    total: cases.length,
    groups: groups.map((g) => ({ key: g.key, title: g.title, count: g.items.length })),
    cases,
  };
  fs.writeFileSync(OUT_CASES_JSON, JSON.stringify(payload, null, 2) + '\n', 'utf8');

  const out = [];
  out.push('<!-- 负责模型：DeepSeek -->');
  out.push('# 失败案例库（离线、可复现）');
  out.push('');
  out.push('> **合成数据声明**：本案例库全部来自 `fault_corpus.jsonl` 的人工合成样本，');
  out.push('> 不代表真实模型的表现，也不含任何真实用户数据；真实失败案例需在设备上实测采集。');
  out.push('');
  out.push(`共 **${cases.length} 条**（repaired ${groups[0].items.length} + rule ${groups[1].items.length} + 网络降级 ${groups[2].items.length} + cancelled ${groups[3].items.length}）。`);
  out.push('`direct`（模型直出就可用）不算失败案例，不收录。');
  out.push('');
  for (const g of groups) {
    out.push(`## ${g.title}（${g.items.length} 条）`);
    out.push('');
    out.push('| 样本 | 批次 | 场景 | 结果 | 来源 | 错误类别 | 处理方式 |');
    out.push('|---|---|---|---|---|---|---|');
    for (const c of g.items) {
      const err = c.errorKind === null ? '—' : c.errorKind + (c.httpStatus !== null ? ` (HTTP ${c.httpStatus})` : c.frameworkCode !== null ? ` (框架码 ${c.frameworkCode})` : '');
      out.push(`| ${c.sampleId} | ${c.batch} | ${c.caseType} | ${c.outcome} | ${c.finalSource} | ${err} | ${c.handling} |`);
    }
    out.push('');
  }
  out.push('## 口径与边界');
  out.push('');
  out.push('1. 案例只覆盖「非 direct」的四种结果，每条都记录是否降级（`fallback`）与最终来源。');
  out.push('2. 内容类的错误类别是解析阶段的真实错误码（`EMPTY / NO_JSON / INVALID`）；');
  out.push('   网络类的错误类别是 8 种 `LlmErrorKind` 之一，两者分属不同层，不要混用。');
  out.push('3. `cancelled` 是用户主动取消，不算失败，但它也不降级，所以收进案例库便于对照。');
  out.push('4. 全部为合成数据，条数是人为编排的测试配额，不能用来估计真实模型的失败率。');
  out.push('');
  fs.writeFileSync(OUT_CASES_MD, out.join('\n') + '\n', 'utf8');
}

main();
