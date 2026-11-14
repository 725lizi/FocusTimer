#!/usr/bin/env node
// 负责模型：DeepSeek
// =============================================================================
// ablation_g0g3.mjs —— G0–G3 三级容错消融实验（离线、可复现、同一任务集）
//
// 目的：在同一份 60 条内容样本上，逐级叠加处理环节，看清楚每一级到底救回了多少、
//       以及「结构化 Prompt」「本地修复」「规则树兜底」各自的边际贡献。
//
//   G0 模型直出       ：raw 直接 JSON.parse，不做抽取/规整/兜底
//   G1 结构化 Prompt  ：仍只裸 parse，对比 structured 批与 bare 批（输入侧约束的价值）
//   G2 加解析校验     ：extract → normalize → 硬逻辑；本层没有兜底，失败就是失败
//   G3 完整三级机制   ：G2 失败的样本交给本地规则树（RuleMindMapBuilder 的移植）
//
// 判定逻辑不在本文件里重复实现，统一 import 自 reliability_engine.mjs，
// 保证与 validate_corpus.mjs、真实工程源码用的是同一套口径。
//
// 【诚实边界】本脚本只计算离线可复现的指标：
//   · 原始可解析率、软 Schema 通过率、最终可用率、兜底率、三类结果分布；
//   · 不计算、不预估：事实一致率（另有独立核查脚本）、p50/p95 延迟、真实模型成功率；
//     这些必须用真实 API 在设备上实测。
//   · 全程使用合成数据，结果只描述这 60 条用例，不代表真实模型表现。
//
// 运行：node ablation_g0g3.mjs
// 产物：控制台对比表 + ablation_results.json（机器可读）+ ablation_table.md（人读）
// =============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyze, buildRuleTree, structuralOk, softSchemaOk, treeShape } from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = path.join(HERE, 'fault_corpus.jsonl');
const FIXTURE_PATH = path.join(HERE, 'summary_fixture.json');
const OUT_JSON = path.join(HERE, 'ablation_results.json');
const OUT_MD = path.join(HERE, 'ablation_table.md');

const BATCHES = ['structured', 'bare'];

// ---------------------------------------------------------------- 工具
const pct = (num, den) => (den === 0 ? 0 : Math.round((num / den) * 1000) / 10);
const fmtPct = (num, den) => pct(num, den).toFixed(1) + '%';
const fmtRate = (num, den) => `${num}/${den} ${fmtPct(num, den)}`;
/** 两个比率之差（百分点），用原始计数算，避免「先四舍五入再相减」的误差 */
const ppDelta = (aOk, aTotal, bOk, bTotal) =>
  Math.round(((aOk / aTotal) - (bOk / bTotal)) * 1000) / 10;
const count = (list, pick) => list.reduce((acc, item) => {
  const key = pick(item);
  acc[key] = (acc[key] || 0) + 1;
  return acc;
}, {});

function readJson(file) {
  if (!fs.existsSync(file)) throw new Error('缺少文件：' + path.basename(file));
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function loadContentSamples() {
  if (!fs.existsSync(CORPUS_PATH)) throw new Error('缺少 fault_corpus.jsonl');
  const lines = fs.readFileSync(CORPUS_PATH, 'utf8').split('\n').filter((line) => line.trim() !== '');
  const all = lines.map((line) => JSON.parse(line));
  const content = all.filter((s) => s.kind === 'content');
  const excluded = all.filter((s) => s.kind !== 'content');
  if (content.length !== 60) throw new Error('内容样本应为 60 条，实际 ' + content.length);
  // 固定顺序：structured 在前、bare 在后，批内按 id 升序（纯字典序，确定性）
  content.sort((a, b) => {
    const ba = BATCHES.indexOf(a.batch);
    const bb = BATCHES.indexOf(b.batch);
    if (ba !== bb) return ba - bb;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return { content, excluded };
}

// ---------------------------------------------------------------- G0
function runG0(sample) {
  let parseOk = true;
  let parsed = null;
  try {
    parsed = JSON.parse(sample.raw);
  } catch (err) {
    parseOk = false;
  }
  const shapeOk = parseOk
    && parsed !== null
    && typeof parsed === 'object'
    && !Array.isArray(parsed)
    && Array.isArray(parsed.children);
  return { parseOk, shapeOk, ok: parseOk && shapeOk };
}

// ---------------------------------------------------------------- 逐条跑四级
function runSample(sample, fixture) {
  const g0 = runG0(sample);
  const judged = analyze(sample.raw);          // 与 validate_corpus.mjs 完全同一套判定
  const g1 = { parseOk: g0.parseOk, softSchemaOk: judged.g1_contract === true };
  const g2 = {
    extractError: judged.extractError,
    normalizeError: judged.normalizeError,
    hardOk: judged.hardOk === true,
    repaired: judged.repaired === true,
    outcome: judged.g2_outcome,
    softSchemaOk: judged.softOk === true,
    rescuedFromG0Fail: judged.g2_outcome === 'repaired' && g0.ok !== true,
  };

  // G3：G2 失败的才兜底；兜底失败就是真正的 failed（正常应为 0）
  let g3;
  if (g2.outcome !== 'fail') {
    g3 = { outcome: g2.outcome, source: 'llm', fallback: false };
  } else {
    let tree = null;
    try {
      tree = buildRuleTree(fixture);
    } catch (err) {
      tree = null;
    }
    if (tree !== null && structuralOk(tree)) {
      g3 = { outcome: 'rule', source: 'rule', fallback: true };
    } else {
      g3 = { outcome: 'failed', source: 'failed', fallback: false };
    }
  }

  return { id: sample.id, batch: sample.batch, case_type: sample.case_type, G0: g0, G1: g1, G2: g2, G3: g3 };
}

// ---------------------------------------------------------------- 汇总
function summarize(rows, fixture) {
  const byBatch = (batch, pick) => rows.filter((r) => r.batch === batch).map(pick);

  // G0
  const g0Ok = (r) => r.G0.ok === true;
  const g0FailRows = rows.filter((r) => g0Ok(r) !== true);
  const g0 = {
    total: { ok: rows.filter(g0Ok).length, total: rows.length },
    structured: { ok: byBatch('structured', g0Ok).filter(Boolean).length, total: 30 },
    bare: { ok: byBatch('bare', g0Ok).filter(Boolean).length, total: 30 },
    failBreakdown: {
      parseError: g0FailRows.filter((r) => r.G0.parseOk !== true).length,
      shapeError: g0FailRows.filter((r) => r.G0.parseOk === true && r.G0.shapeOk !== true).length,
    },
  };
  g0.total.rate = pct(g0.total.ok, g0.total.total);
  g0.structured.rate = pct(g0.structured.ok, g0.structured.total);
  g0.bare.rate = pct(g0.bare.ok, g0.bare.total);

  // G1
  const softOkOnRaw = (r) => r.G1.softSchemaOk === true;
  const g1 = {
    parseRate: { structured: g0.structured.rate, bare: g0.bare.rate, total: g0.total.rate },
    softSchemaRate: {
      structured: { ok: byBatch('structured', softOkOnRaw).filter(Boolean).length, total: 30 },
      bare: { ok: byBatch('bare', softOkOnRaw).filter(Boolean).length, total: 30 },
      total: { ok: rows.filter(softOkOnRaw).length, total: rows.length },
    },
  };
  for (const key of ['structured', 'bare', 'total']) {
    g1.softSchemaRate[key].rate = pct(g1.softSchemaRate[key].ok, g1.softSchemaRate[key].total);
  }
  g1.delta = {
    parsePp: ppDelta(g0.structured.ok, g0.structured.total, g0.bare.ok, g0.bare.total),
    softSchemaPp: ppDelta(g1.softSchemaRate.structured.ok, 30, g1.softSchemaRate.bare.ok, 30),
  };

  // G2
  const g2Ok = (r) => r.G2.outcome !== 'fail';
  const g2Rows = rows.filter(g2Ok);
  const g2 = {
    ok: g2Rows.length,
    direct: rows.filter((r) => r.G2.outcome === 'direct').length,
    repaired: rows.filter((r) => r.G2.outcome === 'repaired').length,
    fail: rows.filter((r) => r.G2.outcome === 'fail').length,
    total: rows.length,
    structured: {
      ok: byBatch('structured', g2Ok).filter(Boolean).length,
      direct: byBatch('structured', (r) => r.G2.outcome === 'direct').filter(Boolean).length,
      repaired: byBatch('structured', (r) => r.G2.outcome === 'repaired').filter(Boolean).length,
      fail: byBatch('structured', (r) => r.G2.outcome === 'fail').filter(Boolean).length,
      total: 30,
    },
    bare: {
      ok: byBatch('bare', g2Ok).filter(Boolean).length,
      direct: byBatch('bare', (r) => r.G2.outcome === 'direct').filter(Boolean).length,
      repaired: byBatch('bare', (r) => r.G2.outcome === 'repaired').filter(Boolean).length,
      fail: byBatch('bare', (r) => r.G2.outcome === 'fail').filter(Boolean).length,
      total: 30,
    },
    softSchemaOnSuccess: {
      ok: g2Rows.filter((r) => r.G2.softSchemaOk === true).length,
      total: g2Rows.length,
    },
    // 全量口径（分母固定 60）：与 validate_corpus.mjs 打印的「软 Schema 通过率」同一口径
    softSchemaOverall: { ok: rows.filter((r) => r.G2.softSchemaOk === true).length, total: rows.length },
    rescuedFromG0Fail: {
      count: rows.filter((r) => r.G2.rescuedFromG0Fail === true).length,
      ids: rows.filter((r) => r.G2.rescuedFromG0Fail === true).map((r) => r.id),
      byCase: count(rows.filter((r) => r.G2.rescuedFromG0Fail === true), (r) => r.case_type),
    },
    failByCase: count(rows.filter((r) => r.G2.outcome === 'fail'), (r) => r.case_type),
  };
  g2.rate = pct(g2.ok, g2.total);
  g2.structured.rate = pct(g2.structured.ok, g2.structured.total);
  g2.bare.rate = pct(g2.bare.ok, g2.bare.total);
  g2.softSchemaOnSuccess.rate = pct(g2.softSchemaOnSuccess.ok, g2.softSchemaOnSuccess.total);
  g2.softSchemaOverall.rate = pct(g2.softSchemaOverall.ok, g2.softSchemaOverall.total);

  // G3
  const g3 = {
    direct: rows.filter((r) => r.G3.outcome === 'direct').length,
    repaired: rows.filter((r) => r.G3.outcome === 'repaired').length,
    rule: rows.filter((r) => r.G3.outcome === 'rule').length,
    failed: rows.filter((r) => r.G3.outcome === 'failed').length,
    total: rows.length,
    llm: rows.filter((r) => r.G3.source === 'llm').length,
    ruleSource: rows.filter((r) => r.G3.source === 'rule').length,
    failedSource: rows.filter((r) => r.G3.source === 'failed').length,
    structured: {
      direct: byBatch('structured', (r) => r.G3.outcome === 'direct').filter(Boolean).length,
      repaired: byBatch('structured', (r) => r.G3.outcome === 'repaired').filter(Boolean).length,
      rule: byBatch('structured', (r) => r.G3.outcome === 'rule').filter(Boolean).length,
      failed: byBatch('structured', (r) => r.G3.outcome === 'failed').filter(Boolean).length,
      total: 30,
    },
    bare: {
      direct: byBatch('bare', (r) => r.G3.outcome === 'direct').filter(Boolean).length,
      repaired: byBatch('bare', (r) => r.G3.outcome === 'repaired').filter(Boolean).length,
      rule: byBatch('bare', (r) => r.G3.outcome === 'rule').filter(Boolean).length,
      failed: byBatch('bare', (r) => r.G3.outcome === 'failed').filter(Boolean).length,
      total: 30,
    },
  };
  g3.usabilityRate = pct(g3.total - g3.failed, g3.total);
  g3.fallbackRate = pct(g3.rule, g3.total);

  // 规则树自检：它自己也必须是一棵合规树（否则「兜底」这级名不副实）
  const ruleTree = buildRuleTree(fixture);
  const ruleShape = treeShape(ruleTree);
  g3.ruleTree = {
    nodes: ruleShape.nodes,
    depth: ruleShape.depth,
    structuralOk: structuralOk(ruleTree),
    softSchemaOk: softSchemaOk(ruleTree),
    sample: ruleTree,
  };

  return { g0, g1, g2, g3 };
}

// ---------------------------------------------------------------- 输出：控制台
function printConsole(summary, meta, crossCheck) {
  const line = '='.repeat(72);
  console.log(line);
  console.log('G0–G3 三级容错消融实验（同一任务集 · 离线可复现）');
  console.log(line);
  console.log(`任务集：${meta.corpus} 的 ${summary.g3.total} 条内容样本（structured S01–S30 / bare B01–B30）`);
  console.log(`排除  ：${meta.excluded} 条网络类样本（网络降级另由样本库与设备实测覆盖）`);
  console.log('口径  ：只算离线可复现指标；真实成功率与 p50/p95 延迟必须设备实测，本脚本不算。');
  console.log('');
  console.log('【G0 模型直出】raw 直接 JSON.parse');
  console.log(`  结构化 ${fmtRate(summary.g0.structured.ok, 30)}   bare ${fmtRate(summary.g0.bare.ok, 30)}   合计 ${fmtRate(summary.g0.total.ok, summary.g0.total.total)}`);
  console.log(`  失败 ${summary.g0.total.total - summary.g0.total.ok} 条：解析失败 ${summary.g0.failBreakdown.parseError} + 形态不符（无 children 数组）${summary.g0.failBreakdown.shapeError}`);
  console.log('');
  console.log('【G1 加结构化 Prompt】输入侧约束的价值（本层不加任何本地处理）');
  console.log(`  原始可解析率    structured ${summary.g0.structured.rate.toFixed(1)}%  bare ${summary.g0.bare.rate.toFixed(1)}%   差值 ${summary.g1.delta.parsePp >= 0 ? '+' : ''}${summary.g1.delta.parsePp.toFixed(1)} pp`);
  console.log(`  软 Schema 合规率 structured ${summary.g1.softSchemaRate.structured.rate.toFixed(1)}%  bare ${summary.g1.softSchemaRate.bare.rate.toFixed(1)}%   差值 ${summary.g1.delta.softSchemaPp >= 0 ? '+' : ''}${summary.g1.delta.softSchemaPp.toFixed(1)} pp`);
  console.log(`  → 同样的判定逻辑，只把提示词换成结构化版本，「解析后天然合规」的比例提升 ${summary.g1.delta.softSchemaPp.toFixed(1)} 个百分点`);
  console.log('');
  console.log('【G2 加解析校验】extract → normalize → 硬逻辑（本层还没有兜底）');
  console.log(`  成功 ${fmtRate(summary.g2.ok, summary.g2.total)}（structured ${fmtRate(summary.g2.structured.ok, 30)} / bare ${fmtRate(summary.g2.bare.ok, 30)}）`);
  console.log(`  其中 direct ${summary.g2.direct} + repaired ${summary.g2.repaired}，失败 ${summary.g2.fail}`);
  console.log(`  软 Schema 通过率 ${fmtRate(summary.g2.softSchemaOverall.ok, summary.g2.softSchemaOverall.total)}（全量口径，与 validate_corpus.mjs 打印的一致）`);
  console.log(`  其中只看 G2 成功树：${fmtRate(summary.g2.softSchemaOnSuccess.ok, summary.g2.softSchemaOnSuccess.total)}`);
  console.log(`  修复贡献：${summary.g2.rescuedFromG0Fail.count} 条在 G0 原本失败、被本地修复救回（${Object.entries(summary.g2.rescuedFromG0Fail.byCase).map(([k, v]) => k + ' ' + v).join(' + ')}）`);
  console.log(`  失败构成：${Object.entries(summary.g2.failByCase).map(([k, v]) => k + ' ' + v).join(' / ')}`);
  console.log('');
  console.log('【G3 加规则树兜底】完整三级机制');
  console.log(`  direct ${summary.g3.direct} / repaired ${summary.g3.repaired} / 规则兜底 ${summary.g3.rule} / failed ${summary.g3.failed}`);
  console.log(`  最终来源 llm ${summary.g3.llm} / rule ${summary.g3.ruleSource}`);
  console.log(`  最终可用率 ${summary.g3.usabilityRate.toFixed(1)}%（${summary.g3.total - summary.g3.failed}/${summary.g3.total}）  兜底率 ${summary.g3.fallbackRate.toFixed(1)}%（${summary.g3.rule}/${summary.g3.total}）`);
  console.log(`  规则树自检：${summary.g3.ruleTree.nodes} 节点 / 深度 ${summary.g3.ruleTree.depth} / 硬逻辑 ${summary.g3.ruleTree.structuralOk ? '通过' : '不通过'} / 软 Schema ${summary.g3.ruleTree.softSchemaOk ? '通过' : '不通过'}`);
  console.log('');
  console.log('【四级对比】');
  console.log('级  处理                                  structured         bare               合计');
  console.log('G0  raw 直接 parse（可用）                ' + pad(fmtRate(summary.g0.structured.ok, 30)) + pad(fmtRate(summary.g0.bare.ok, 30)) + fmtRate(summary.g0.total.ok, summary.g0.total.total));
  console.log('G1  + 结构化 Prompt（软 Schema 合规率）   ' + pad(fmtRate(summary.g1.softSchemaRate.structured.ok, 30)) + pad(fmtRate(summary.g1.softSchemaRate.bare.ok, 30)) + fmtRate(summary.g1.softSchemaRate.total.ok, summary.g1.softSchemaRate.total.total));
  console.log('G2  + 抽取/规整/硬逻辑（可用）            ' + pad(fmtRate(summary.g2.structured.ok, 30)) + pad(fmtRate(summary.g2.bare.ok, 30)) + fmtRate(summary.g2.ok, summary.g2.total));
  console.log('G3  + 规则树兜底（最终可用）              ' + pad(fmtRate(30 - summary.g3.structured.failed, 30)) + pad(fmtRate(30 - summary.g3.bare.failed, 30)) + fmtRate(summary.g3.total - summary.g3.failed, summary.g3.total));
  console.log('');
  console.log('注：G1 本层不新增处理，所以它没有独立的「可用率」（与 G0 相同）；');
  console.log('    表里列的是裸 parse 后天然满足软 Schema 的比例，用来量化结构化 Prompt 本身的贡献。');
  console.log('');
  console.log(`口径自检：与 fault_corpus.jsonl 的 expect 逐条比对 ${crossCheck.ok}/${crossCheck.total} 一致（同一套 reliability_engine.mjs）`);
  console.log(`已落盘：${path.basename(OUT_JSON)} / ${path.basename(OUT_MD)}`);
  console.log('边界：本脚本不计算事实一致率、不计算 p50/p95 延迟、不预测真实模型成功率；');
  console.log('      全部为合成数据，结论只描述这 60 条用例。');
  console.log(line);
}

function pad(text, width = 18) {
  return String(text).padEnd(width, ' ');
}

// ---------------------------------------------------------------- 输出：JSON
function writeJson(summary, rows, meta, crossCheck) {
  const payload = {
    _model: 'DeepSeek',
    _declaration: '本文件是离线消融实验结果，基于人工合成的测试用例；只描述这 60 条用例，不代表真实模型成功率。真实成功率与 p50/p95 延迟必须用真实 API 在设备上实测。',
    crossCheck: {
      against: 'fault_corpus.jsonl 的 expect 标签（与 validate_corpus.mjs 同一套判定）',
      ok: crossCheck.ok,
      total: crossCheck.total,
      mismatched: crossCheck.mismatched,
    },
    taskSet: {
      corpus: meta.corpus,
      kind: 'content',
      total: rows.length,
      structured: rows.filter((r) => r.batch === 'structured').length,
      bare: rows.filter((r) => r.batch === 'bare').length,
      excludedNetwork: meta.excluded,
      excludedNote: '网络类样本不参与本脚本；网络错误的降级由样本库与后续设备实测覆盖',
    },
    levels: {
      G0: {
        definition: 'raw 直接 JSON.parse；成功 = 解析成功且结果是含 children 数组的对象',
        structured: summary.g0.structured,
        bare: summary.g0.bare,
        total: summary.g0.total,
        failBreakdown: summary.g0.failBreakdown,
      },
      G1: {
        definition: '本层不新增处理，对比 structured / bare 两批：原始可解析率 + 裸 parse 后天然满足软 Schema 的比例',
        parseRate: summary.g1.parseRate,
        softSchemaRate: summary.g1.softSchemaRate,
        deltaPp: summary.g1.delta,
      },
      G2: {
        definition: 'extract → normalize → 硬逻辑 structuralOk；本层无兜底，失败即失败',
        structured: summary.g2.structured,
        bare: summary.g2.bare,
        ok: summary.g2.ok,
        direct: summary.g2.direct,
        repaired: summary.g2.repaired,
        fail: summary.g2.fail,
        rate: summary.g2.rate,
        softSchemaOnSuccess: summary.g2.softSchemaOnSuccess,
        softSchemaOverall: summary.g2.softSchemaOverall,
        rescuedFromG0Fail: summary.g2.rescuedFromG0Fail,
        failByCase: summary.g2.failByCase,
      },
      G3: {
        definition: 'G2 失败改由本地规则树兜底（RuleMindMapBuilder 的移植，数字来自 summary_fixture.json）',
        structured: summary.g3.structured,
        bare: summary.g3.bare,
        direct: summary.g3.direct,
        repaired: summary.g3.repaired,
        rule: summary.g3.rule,
        failed: summary.g3.failed,
        source: { llm: summary.g3.llm, rule: summary.g3.ruleSource, failed: summary.g3.failedSource },
        usabilityRate: summary.g3.usabilityRate,
        fallbackRate: summary.g3.fallbackRate,
        ruleTree: {
          nodes: summary.g3.ruleTree.nodes,
          depth: summary.g3.ruleTree.depth,
          structuralOk: summary.g3.ruleTree.structuralOk,
          softSchemaOk: summary.g3.ruleTree.softSchemaOk,
        },
      },
    },
    samples: rows.map((r) => ({
      id: r.id,
      batch: r.batch,
      case_type: r.case_type,
      G0: { parseOk: r.G0.parseOk, shapeOk: r.G0.shapeOk, ok: r.G0.ok },
      G1: { parseOk: r.G1.parseOk, softSchemaOk: r.G1.softSchemaOk },
      G2: {
        extractError: r.G2.extractError,
        normalizeError: r.G2.normalizeError,
        hardOk: r.G2.hardOk,
        repaired: r.G2.repaired,
        outcome: r.G2.outcome,
        softSchemaOk: r.G2.softSchemaOk,
        rescuedFromG0Fail: r.G2.rescuedFromG0Fail,
      },
      G3: { outcome: r.G3.outcome, source: r.G3.source, fallback: r.G3.fallback },
    })),
  };
  fs.writeFileSync(OUT_JSON, JSON.stringify(payload, null, 2) + '\n', 'utf8');
  return payload;
}

// ---------------------------------------------------------------- 输出：Markdown
function writeMarkdown(summary, rows, crossCheck) {
  const out = [];
  out.push('<!-- 负责模型：DeepSeek -->');
  out.push('# G0–G3 三级容错消融实验（离线、可复现）');
  out.push('');
  out.push('> 本表由 `ablation_g0g3.mjs` 生成，数字与 `ablation_results.json` 完全一致。');
  out.push('> 数据来自 `fault_corpus.jsonl` 的 **60 条内容样本**（structured S01–S30 / bare B01–B30）。');
  out.push('> **合成数据**：只描述这 60 条人工编排的用例，**不代表真实模型成功率**；');
  out.push('> 真实成功率与 p50/p95 延迟必须用真实 API 在设备上实测，本表不提供也不预测。');
  out.push(`> 口径自检：与样本库写死的 \`expect\` 逐条比对 **${crossCheck.ok}/${crossCheck.total} 一致**（与 \`validate_corpus.mjs\` 共用同一套 \`reliability_engine.mjs\`）。`);
  out.push('');
  out.push('## 1. 四级对比表');
  out.push('');
  out.push('| 级 | 处理 | structured | bare | 合计 |');
  out.push('|---|---|---|---|---|');
  out.push(`| G0 | raw 直接 parse（可用） | ${fmtRate(summary.g0.structured.ok, 30)} | ${fmtRate(summary.g0.bare.ok, 30)} | ${fmtRate(summary.g0.total.ok, summary.g0.total.total)} |`);
  out.push(`| G1 | + 结构化 Prompt（软 Schema 合规率） | ${fmtRate(summary.g1.softSchemaRate.structured.ok, 30)} | ${fmtRate(summary.g1.softSchemaRate.bare.ok, 30)} | ${fmtRate(summary.g1.softSchemaRate.total.ok, summary.g1.softSchemaRate.total.total)} |`);
  out.push(`| G2 | + 抽取/规整/硬逻辑（可用） | ${fmtRate(summary.g2.structured.ok, 30)} | ${fmtRate(summary.g2.bare.ok, 30)} | ${fmtRate(summary.g2.ok, summary.g2.total)} |`);
  out.push(`| G3 | + 规则树兜底（最终可用） | ${fmtRate(30 - summary.g3.structured.failed, 30)} | ${fmtRate(30 - summary.g3.bare.failed, 30)} | ${fmtRate(summary.g3.total - summary.g3.failed, summary.g3.total)} |`);
  out.push('');
  out.push('> G1 这一层**不新增任何处理**，所以它没有独立的「可用率」（与 G0 相同）；');
  out.push('> 表里列的是「裸 parse 后天然满足软 Schema」的比例，用来量化结构化 Prompt 本身的贡献。');
  out.push('');
  out.push('## 2. G1：结构化 Prompt 把输入变好多少');
  out.push('');
  out.push('| 指标 | structured | bare | 差值 |');
  out.push('|---|---|---|---|');
  out.push(`| 原始可解析率 | ${summary.g0.structured.rate.toFixed(1)}% | ${summary.g0.bare.rate.toFixed(1)}% | ${summary.g1.delta.parsePp >= 0 ? '+' : ''}${summary.g1.delta.parsePp.toFixed(1)} pp |`);
  out.push(`| 软 Schema 合规率 | ${summary.g1.softSchemaRate.structured.rate.toFixed(1)}% | ${summary.g1.softSchemaRate.bare.rate.toFixed(1)}% | ${summary.g1.delta.softSchemaPp >= 0 ? '+' : ''}${summary.g1.delta.softSchemaPp.toFixed(1)} pp |`);
  out.push('');
  out.push('## 3. G0 失败构成（本层的起点有多差）');
  out.push('');
  out.push(`- 失败 ${summary.g0.total.total - summary.g0.total.ok} 条 = 解析失败 ${summary.g0.failBreakdown.parseError} + 形态不符（解析出来但没有 children 数组，例如「{root:{...}}」信封写法）${summary.g0.failBreakdown.shapeError}`);
  out.push('');
  out.push('## 4. G2：本地解析校验救回多少');
  out.push('');
  out.push(`- 成功 ${fmtRate(summary.g2.ok, summary.g2.total)}：direct ${summary.g2.direct} + repaired ${summary.g2.repaired}`);
  out.push(`- 修复贡献：**${summary.g2.rescuedFromG0Fail.count} 条**在 G0 原本失败、被本地修复救回（${Object.entries(summary.g2.rescuedFromG0Fail.byCase).map(([k, v]) => k + ' ' + v).join(' + ')}），逐条 id：${summary.g2.rescuedFromG0Fail.ids.join(', ')}`);
  out.push(`- 软 Schema 通过率 **${fmtRate(summary.g2.softSchemaOverall.ok, summary.g2.softSchemaOverall.total)}**（全量口径，与 \`validate_corpus.mjs\` 打印的一致）；只看 G2 成功树则为 ${fmtRate(summary.g2.softSchemaOnSuccess.ok, summary.g2.softSchemaOnSuccess.total)}`);
  out.push(`- 仍失败 ${summary.g2.fail} 条：${Object.entries(summary.g2.failByCase).map(([k, v]) => k + ' ' + v).join(' / ')}，本层到此为止就是失败`);
  out.push('');
  out.push('## 5. G3：兜底把最后一段补齐');
  out.push('');
  out.push('| 结果 | structured | bare | 合计 | 占比 |');
  out.push('|---|---|---|---|---|');
  out.push(`| 云端直用（direct） | ${summary.g3.structured.direct} | ${summary.g3.bare.direct} | ${summary.g3.direct} | ${fmtPct(summary.g3.direct, summary.g3.total)} |`);
  out.push(`| 云端修好（repaired） | ${summary.g3.structured.repaired} | ${summary.g3.bare.repaired} | ${summary.g3.repaired} | ${fmtPct(summary.g3.repaired, summary.g3.total)} |`);
  out.push(`| 规则兜底（rule） | ${summary.g3.structured.rule} | ${summary.g3.bare.rule} | ${summary.g3.rule} | ${fmtPct(summary.g3.rule, summary.g3.total)} |`);
  out.push(`| 彻底失败（failed） | ${summary.g3.structured.failed} | ${summary.g3.bare.failed} | ${summary.g3.failed} | ${fmtPct(summary.g3.failed, summary.g3.total)} |`);
  out.push('');
  out.push(`- **最终可用率 ${summary.g3.usabilityRate.toFixed(1)}%**（${summary.g3.total - summary.g3.failed}/${summary.g3.total}）`);
  out.push(`- **兜底率 ${summary.g3.fallbackRate.toFixed(1)}%**（${summary.g3.rule}/${summary.g3.total}）`);
  out.push(`- 最终来源：llm ${summary.g3.llm} / rule ${summary.g3.ruleSource} / failed ${summary.g3.failedSource}`);
  out.push(`- 规则树自检：${summary.g3.ruleTree.nodes} 节点 / 深度 ${summary.g3.ruleTree.depth} / 硬逻辑 ${summary.g3.ruleTree.structuralOk ? '通过' : '不通过'} / 软 Schema ${summary.g3.ruleTree.softSchemaOk ? '通过' : '不通过'}`);
  out.push('');
  out.push('## 6. 逐条明细（便于复核）');
  out.push('');
  out.push('| id | 批 | 场景 | G0 可用 | G1 软合规 | G2 | G3 |');
  out.push('|---|---|---|---|---|---|---|');
  for (const r of rows) {
    out.push(`| ${r.id} | ${r.batch} | ${r.case_type} | ${r.G0.ok ? '✅' : '❌'} | ${r.G1.softSchemaOk ? '✅' : '❌'} | ${r.G2.outcome} | ${r.G3.outcome} |`);
  }
  out.push('');
  out.push('## 7. 边界（必须一起读）');
  out.push('');
  out.push('1. 本表只覆盖**离线可复现**的指标：原始可解析率、软 Schema 通过率、最终可用率、兜底率、三类结果分布。');
  out.push('2. **事实一致率**（生成内容与底稿数字是否相符）不在本脚本展开，由独立的核查脚本负责。');
  out.push('3. **p50/p95 延迟、真实模型成功率**必须用真实 API 在设备上实测，本表一律不计算、不预估、不外推。');
  out.push('4. 所有样本都是合成数据，比例是人为编排的测试配额，不能用来估计真实模型的任何比率。');
  out.push('');
  fs.writeFileSync(OUT_MD, out.join('\n') + '\n', 'utf8');
}

// ---------------------------------------------------------------- 主流程
function main() {
  const fixture = readJson(FIXTURE_PATH);
  const { content, excluded } = loadContentSamples();
  const rows = content.map((sample) => runSample(sample, fixture));
  const summary = summarize(rows, fixture);
  const meta = { corpus: path.basename(CORPUS_PATH), excluded: excluded.length };

  // 与样本库里写死的 expect 对一遍：证明消融脚本和 validate_corpus.mjs 走的是同一套判定
  const mismatched = content.filter((sample) => {
    const judged = analyze(sample.raw);
    const e = sample.expect || {};
    return judged.g0_parse !== e.g0_parse
      || judged.g1_contract !== e.g1_contract
      || judged.g2_outcome !== e.g2_outcome
      || judged.g3_source !== e.g3_source;
  }).map((sample) => sample.id);
  const crossCheck = { ok: content.length - mismatched.length, total: content.length, mismatched };

  printConsole(summary, meta, crossCheck);
  writeJson(summary, rows, meta, crossCheck);
  writeMarkdown(summary, rows, crossCheck);

  // 自检：任何一条判定自相矛盾就非零退出，避免把错数据写进结果文件
  const problems = [];
  if (crossCheck.mismatched.length > 0) {
    problems.push('与样本库 expect 不一致：' + crossCheck.mismatched.join(', '));
  }
  for (const r of rows) {
    if (r.G3.source === 'llm' && r.G2.outcome === 'fail') problems.push(r.id + '：G2 失败却标成 llm');
    if (r.G3.source === 'rule' && r.G2.outcome !== 'fail') problems.push(r.id + '：G2 成功却标成 rule');
    if (r.G3.outcome === 'rule' && r.G3.fallback !== true) problems.push(r.id + '：规则兜底但 fallback 标记不对');
    if (r.G2.outcome === 'direct' && r.G2.hardOk !== true) problems.push(r.id + '：direct 但硬逻辑未通过');
  }
  if (problems.length > 0) {
    console.log('自检失败：');
    for (const p of problems) console.log('  ✗ ' + p);
    process.exitCode = 1;
    return;
  }
  process.exitCode = 0;
}

main();
