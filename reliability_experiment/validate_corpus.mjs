#!/usr/bin/env node
// 负责模型：DeepSeek
// =============================================================================
// validate_corpus.mjs —— 「三级容错」故障注入样本库的离线校验脚本
//
// 用途：不联网、不依赖任何 npm 包，只用 Node 内置模块，校验 fault_corpus.jsonl
//       与 summary_fixture.json 是否自洽、是否符合真实代码的判定逻辑。
//
// 判定分两层（这是本脚本的核心，也是 V2.3「最终可用率」与「Schema 通过率」两个指标的来源）：
//
//   第一层 · 硬逻辑 structuralOk（真实系统强制，决定降级与否）
//     真实链路是 extract → normalize → JsonSerializer.deserialize：三步只要不抛错就
//     用云端结果，没有任何深度/节点数/分支/叶子字数的额外校验。所以硬条件只有：
//     节点 id 非空且唯一、text 非空字符串且 ≤ 24、children 是数组、根节点存在。
//     → 决定 g2_outcome / g3_source（是否降到规则树）。
//
//   第二层 · 软 Schema softSchemaOk（理想 Prompt 契约，只统计、不参与降级）
//     根 id/text、四个一级分支顺序、节点 8–20、深度 2–3、每节点三个字段、叶子 ≤ 16 字。
//     它只回答「输出有多接近理想契约」，不回答「能不能用」。
//
// 重要：本脚本只验证「测试用例写对了没有」，验证不了真实模型的成功率；
//       真实成功率必须以后续设备实测为准，本文件不提供、也不预测任何真实概率。
//
// 运行：node validate_corpus.mjs
// 退出：全部通过 → 0；任一项不符 → 1，并逐条打印 id 与原因。
// =============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyze } from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = path.join(HERE, 'fault_corpus.jsonl');
const FIXTURE_PATH = path.join(HERE, 'summary_fixture.json');
const README_PATH = path.join(HERE, 'reliability_experiment_readme.md');

// ---------------------------------------------------------------- 契约常量
const CONTENT_CASES = [
  'clean', 'fence', 'chatter', 'envelope', 'truncated', 'no_braces', 'empty',
  'missing_id', 'duplicate_id', 'missing_children', 'wrong_children_type',
  'wrong_depth', 'long_text', 'missing_text',
];
const NETWORK_CASES = [
  'offline', 'timeout', 'unauthorized', 'rate_limited', 'server_error', 'bad_request', 'cancelled',
];
const ERROR_KINDS = [
  'network', 'timeout', 'unauthorized', 'rate_limited', 'server', 'bad_request', 'empty', 'cancelled',
];
const NETWORK_QUOTA = {
  network: 2, timeout: 2, unauthorized: 2, rate_limited: 1,
  server: 1, bad_request: 1, cancelled: 1,
};
// 两批「直接合规」的编排配额（人为设定，不代表真实模型分布）
const DIRECT_QUOTA = { bare: [6, 8], structured: [18, 20] };

const errors = [];
const warn = (id, msg) => errors.push(`[${id}] ${msg}`);

// ---------------------------------------------------------------- 判定规则实现
// 判定逻辑（抽取 / 规整 / 硬逻辑 / 软 Schema / 规则树）统一由 reliability_engine.mjs 提供，
// 这里不再重复实现，避免两个脚本口径漂移。
// 说明：本脚本只用到 analyze()，它返回四级标签与 hardOk / softOk 两个指标。
/** 网络/环境错误码映射：先看 HTTP 状态码，再看鸿蒙框架码，都没有按 network 处理 */
function mapErrorKind(httpStatus, frameworkCode) {
  if (Number.isInteger(httpStatus)) {
    if (httpStatus === 401 || httpStatus === 403) return 'unauthorized';
    if (httpStatus === 429) return 'rate_limited';
    if (httpStatus === 400 || httpStatus === 404 || httpStatus === 422) return 'bad_request';
    if (httpStatus === 408) return 'timeout';
    if (httpStatus >= 500) return 'server';
    return 'network';
  }
  if (Number.isInteger(frameworkCode)) {
    if (frameworkCode === 2300089) return 'cancelled';
    if (frameworkCode === 2300004 || frameworkCode === 2300047 || frameworkCode === 2300999) return 'timeout';
    return 'network';
  }
  return 'network';
}

/** 递归收集 fixture 里所有数字字面量，构成「允许出现的数字」白名单 */
function collectNumbers(value, out) {
  if (typeof value === 'number' && Number.isFinite(value)) out.add(String(value));
  else if (Array.isArray(value)) for (const item of value) collectNumbers(item, out);
  else if (value !== null && typeof value === 'object') for (const key of Object.keys(value)) collectNumbers(value[key], out);
  return out;
}

/** 抹掉所有 "id":"..." 的值（避免 m0/m12 这类节点序号被当成内容数字），再取数字串 */
function numbersInRaw(raw) {
  const masked = raw.replace(/"id"\s*:\s*"[^"]*/g, '"id":"');
  const found = masked.match(/\d+/g);
  return found === null ? [] : found;
}

const pct = (num, den) => (den === 0 ? '0.0' : (num / den * 100).toFixed(1));

// ---------------------------------------------------------------- 主流程
function readJsonFile(file) {
  if (!fs.existsSync(file)) throw new Error('文件不存在：' + path.basename(file));
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function main() {
  // 1) 文件存在性
  for (const f of [CORPUS_PATH, FIXTURE_PATH, README_PATH]) {
    if (!fs.existsSync(f)) errors.push('[file] 缺少文件：' + path.basename(f));
  }
  if (errors.length > 0) return report();

  const fixture = readJsonFile(FIXTURE_PATH);
  const allowedNumbers = collectNumbers(fixture, new Set());

  const raw = fs.readFileSync(CORPUS_PATH, 'utf8');
  const lines = raw.split('\n').filter((line) => line.trim() !== '');

  // 2) 逐行解析
  const samples = [];
  lines.forEach((line, index) => {
    try {
      samples.push(JSON.parse(line));
    } catch (err) {
      warn('line ' + (index + 1), '不是合法 JSON：' + err.message);
    }
  });

  if (samples.length !== 80) warn('total', '样本总数应为 80，实际 ' + samples.length);

  // 3) 逐条校验
  const ids = new Set();
  let contentCount = 0;
  let networkCount = 0;
  const softFailIds = [];
  const batchSamples = { structured: [], bare: [] };

  for (const s of samples) {
    const id = typeof s.id === 'string' ? s.id : '?';
    if (typeof s.id !== 'string' || !/^[SB]\d{2}$/.test(id)) warn(id, 'id 必须是 S01/B01 这种形式');
    if (ids.has(id)) warn(id, 'id 重复');
    ids.add(id);
    if (s._model !== 'DeepSeek') warn(id, '缺少头部标注字段 _model=DeepSeek');
    if (s.batch !== 'bare' && s.batch !== 'structured') warn(id, 'batch 取值非法：' + s.batch);
    if (s.kind !== 'content' && s.kind !== 'network') warn(id, 'kind 取值非法：' + s.kind);
    if (!batchSamples[s.batch]) batchSamples[s.batch] = [];
    batchSamples[s.batch].push(s);

    if (s.kind === 'content') {
      contentCount += 1;
      if (typeof s.raw !== 'string') { warn(id, 'content 样本缺少字符串 raw'); continue; }
      if (!CONTENT_CASES.includes(s.case_type)) warn(id, 'case_type 非法：' + s.case_type);
      const e = s.expect;
      if (e === null || typeof e !== 'object') { warn(id, '缺少 expect 对象'); continue; }
      if (typeof e.g0_parse !== 'boolean') warn(id, 'expect.g0_parse 必须是布尔');
      if (typeof e.g1_contract !== 'boolean') warn(id, 'expect.g1_contract 必须是布尔');
      if (!['direct', 'repaired', 'fail'].includes(e.g2_outcome)) warn(id, 'expect.g2_outcome 非法：' + e.g2_outcome);
      if (!['llm', 'rule', 'failed'].includes(e.g3_source)) warn(id, 'expect.g3_source 非法：' + e.g3_source);

      // 3.1 标签自洽（注意：direct 只要求 g0_parse 为真；
      //     g1_contract 是「理想软 Schema」，像 wrong_depth 这种「能解析、能直接用、
      //     但不满足理想契约」的样本，g1 为 false、g2 仍可以是 direct）
      if (e.g2_outcome === 'direct' && e.g0_parse !== true) {
        warn(id, 'direct 要求 g0_parse=true（裸 JSON.parse 必须成功）');
      }
      if (e.g2_outcome === 'repaired' && !(e.g3_source === 'llm' && e.g1_contract === false)) {
        warn(id, 'repaired 要求 g3_source=llm 且 g1_contract=false');
      }
      if (e.g2_outcome === 'repaired' && e.g0_parse === true && e.g1_contract === true) {
        warn(id, 'repaired 但 g0/g1 都是 true，说明要么标签错、要么用例没有真正触发修复');
      }
      if (e.g2_outcome === 'fail' && e.g3_source !== 'rule') {
        warn(id, 'fail 的 g3_source 必须是 rule');
      }
      if (e.g2_outcome === 'direct' && e.g3_source !== 'llm') {
        warn(id, 'direct 的 g3_source 必须是 llm');
      }

      // 3.2 逻辑复算：四个标签必须与按真实链路重新推导的结果一致
      const derived = analyze(s.raw);
      for (const key of ['g0_parse', 'g1_contract', 'g2_outcome', 'g3_source']) {
        if (e[key] !== derived[key]) {
          warn(id, `case_type=${s.case_type} 的 ${key} 标为 ${JSON.stringify(e[key])}，复算结果是 ${JSON.stringify(derived[key])}`);
        }
      }
      if (derived.softOk !== true) softFailIds.push(id);

      // 3.3 case_type=clean 的样本必须真的「完全合规」：同时满足硬逻辑与软 Schema
      //     （注意：direct ≠ 软 Schema 通过。wrong_depth 能被真实系统直接用（direct），
      //       但它不满足理想契约，软 Schema 记为不通过——两者是独立指标）
      if (s.case_type === 'clean' && derived.softOk !== true) {
        warn(id, 'clean 样本未通过软 Schema（叶子 16 字 / 节点数 / 深度 / 四分支）');
      }

      // 3.4 数字只能来自 summary_fixture
      for (const n of new Set(numbersInRaw(s.raw))) {
        if (!allowedNumbers.has(n)) {
          warn(id, '出现底稿之外的数字 ' + n + '（允许：' + Array.from(allowedNumbers).join('/') + '）');
        }
      }
    } else {
      networkCount += 1;
      if (!NETWORK_CASES.includes(s.case_type)) warn(id, '网络类 case_type 非法：' + s.case_type);
      if (!ERROR_KINDS.includes(s.error_kind)) warn(id, 'error_kind 非法：' + s.error_kind);
      if (s.http_status !== null && !Number.isInteger(s.http_status)) warn(id, 'http_status 必须是整数或 null');
      if (s.framework_code !== null && !Number.isInteger(s.framework_code)) warn(id, 'framework_code 必须是整数或 null');
      if (typeof s.expect_fallback !== 'boolean') warn(id, 'expect_fallback 必须是布尔');
      if (s.expect_fallback !== (s.error_kind !== 'cancelled')) {
        warn(id, 'expect_fallback 与 error_kind 不匹配（只有 cancelled 不降级）');
      }
      const mapped = mapErrorKind(s.http_status, s.framework_code);
      if (mapped !== s.error_kind) {
        warn(id, `error_kind 标为 ${s.error_kind}，按 HTTP/框架码映射应为 ${mapped}`);
      }
    }
  }

  // 4) 批次配额、场景覆盖、direct 比例
  const stats = {};
  for (const batch of ['bare', 'structured']) {
    const list = batchSamples[batch] || [];
    if (list.length !== 40) warn(batch, '每批应为 40 条，实际 ' + list.length);
    const content = list.filter((s) => s.kind === 'content');
    const network = list.filter((s) => s.kind === 'network');
    if (content.length !== 30) warn(batch, '内容类应为 30 条，实际 ' + content.length);
    if (network.length !== 10) warn(batch, '网络类应为 10 条，实际 ' + network.length);

    const byCase = new Map();
    for (const s of content) byCase.set(s.case_type, (byCase.get(s.case_type) || 0) + 1);
    for (const c of CONTENT_CASES) {
      if (!byCase.has(c)) warn(batch, '缺少内容场景：' + c);
    }

    const direct = content.filter((s) => s.expect.g2_outcome === 'direct').length;
    const [lo, hi] = DIRECT_QUOTA[batch];
    if (direct < lo || direct > hi) warn(batch, `direct 条数 ${direct} 不在配额 ${lo}–${hi} 之间`);

    const kindCount = new Map();
    for (const s of network) kindCount.set(s.error_kind, (kindCount.get(s.error_kind) || 0) + 1);
    for (const kind of Object.keys(NETWORK_QUOTA)) {
      const want = NETWORK_QUOTA[kind];
      const got = kindCount.get(kind) || 0;
      if (got !== want) warn(batch, `网络类 ${kind} 应为 ${want} 条，实际 ${got}`);
    }

    stats[batch] = {
      content: content.length,
      network: network.length,
      byCase,
      direct,
    };
  }

  report({ stats, samples, contentCount, networkCount, softFailIds });
}

// ---------------------------------------------------------------- 输出
function report(ctx) {
  const line = '='.repeat(68);
  console.log(line);
  console.log('「三级容错」故障注入样本库 · 离线校验');
  console.log('判定口径：硬逻辑 structuralOk 决定降级；软 Schema softSchemaOk 只做独立统计。');
  console.log('说明：本样本库是合成测试数据，校验通过只代表用例写对了，');
  console.log('      不代表任何真实模型成功率。');
  console.log(line);

  if (!ctx) {
    console.log('存在致命问题，跳过统计：');
    for (const e of errors) console.log('  ✗ ' + e);
    process.exitCode = 1;
    return;
  }

  const { stats, samples, contentCount, networkCount, softFailIds } = ctx;
  const content = samples.filter((s) => s.kind === 'content');
  const network = samples.filter((s) => s.kind === 'network');
  const countBy = (list, pick) => list.reduce((acc, s) => { const k = pick(s); acc[k] = (acc[k] || 0) + 1; return acc; }, {});
  const outcome = countBy(content, (s) => s.expect.g2_outcome);
  const source = countBy(content, (s) => s.expect.g3_source);
  const fallback = network.filter((s) => s.expect_fallback === true).length;
  const llm = source.llm || 0;
  const rule = source.rule || 0;
  const softPass = contentCount - softFailIds.length;

  console.log(`样本总数            ${samples.length}`);
  for (const batch of ['structured', 'bare']) {
    const b = stats[batch];
    console.log(`  批次 ${batch.padEnd(11)} ${String(b.content + b.network).padStart(3)} 条 = 内容 ${b.content} + 网络 ${b.network}`);
  }
  console.log(`内容类              ${contentCount}（direct ${outcome.direct || 0} / repaired ${outcome.repaired || 0} / fail ${outcome.fail || 0}）`);
  console.log(`内容类最终来源      llm ${llm} / rule ${rule} / failed ${source.failed || 0}`);
  console.log(`最终可用率          ${pct(llm + rule, contentCount)}%（${llm + rule}/${contentCount}：失败一律降级到规则树，链路永远有产出）`);
  console.log(`云端采纳率          ${pct(llm, contentCount)}%（llm ${llm}/${contentCount}，即硬逻辑通过、可原样使用的比例）`);
  console.log(`软 Schema 通过率    ${pct(softPass, contentCount)}%（${softPass}/${contentCount}，独立指标，不参与降级判定）`);
  console.log(`软 Schema 未通过    ${softFailIds.length} 条：${softFailIds.length === 0 ? '无' : softFailIds.join(', ')}`);
  console.log(`网络类              ${networkCount}（应自动降级 ${fallback} / 不降级 ${networkCount - fallback}）`);
  console.log('-'.repeat(68));
  console.log('各批次内容场景条数（含直接合规比例）：');
  console.log('场景'.padEnd(22) + 'structured'.padStart(12) + 'bare'.padStart(10));
  for (const c of CONTENT_CASES) {
    const a = stats.structured.byCase.get(c) || 0;
    const b = stats.bare.byCase.get(c) || 0;
    console.log(c.padEnd(22) + String(a).padStart(12) + String(b).padStart(10));
  }
  console.log('-'.repeat(68));
  console.log(`结构化成对比例控制  structured direct ${stats.structured.direct}（配额 18–20） / bare direct ${stats.bare.direct}（配额 6–8）`);
  console.log('-'.repeat(68));

  if (errors.length === 0) {
    console.log(`全部校验通过：${samples.length} 条样本、${CONTENT_CASES.length} 类内容场景、${NETWORK_CASES.length} 类网络场景，`);
    console.log('四个预期标签均已按「extract → normalize → 硬逻辑」逐条复算一致。');
    process.exitCode = 0;
  } else {
    console.log(`校验失败，共 ${errors.length} 处问题：`);
    for (const e of errors) console.log('  ✗ ' + e);
    process.exitCode = 1;
  }
}

main();
