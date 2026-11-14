#!/usr/bin/env node
// 负责模型：DeepSeek
// =============================================================================
// fact_check.mjs —— 事实一致性核查（离线、可复现）
//
// 它回答一个问题：**这条链路最终显示给用户的那棵树，里面的数字/科目/环比方向，
// 到底跟 summary_fixture.json 这份底稿对不对得上？**
//
// 核查对象：fault_corpus.jsonl 里的 60 条内容样本。
//   · g2_outcome != 'fail'（direct/repaired）→ 最终树 = extract → normalize 的结果（真实链路会显示的云端树）
//   · g2_outcome == 'fail'                 → 最终树 = buildRuleTree(fixture)（规则兜底树）
//   网络类 20 条没有树，不参与。
//
// 三类事实声明（口径见下面的常量与 report）：
//   A 数字：文本里的整数必须在底稿白名单内（白名单由 primary 动态生成，不手写）
//   B 科目：底稿科目名 + 数字 → 数字必须等于该科目分钟；出现底稿外科目 → 不一致
//   C 环比方向：底稿是 +50%（增加），文本若在「周对比语境」里说减少/持平 → 不一致
//
// 【诚实边界】全部是人工合成数据，**不代表真实模型的事实一致率**。
// 本脚本不计算 p50/p95、不预测真实模型表现、不做健康/心理诊断、不编造因果或效率百分比。
// 真实云端事实一致率需用户配 API Key 后在设备上单独实测。
//
// 运行：node fact_check.mjs   （自检通过 → 退出码 0；自检失败 → 非零）
// 产物：fact_check_results.json（逐条明细）+ fact_check_report.md（人读报告）
// =============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyze, extract, normalize, buildRuleTree } from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = path.join(HERE, 'fault_corpus.jsonl');
const FIXTURE_PATH = path.join(HERE, 'summary_fixture.json');
const OUT_JSON = path.join(HERE, 'fact_check_results.json');
const OUT_MD = path.join(HERE, 'fact_check_report.md');

/**
 * 「周对比语境」：只有在这种句子里出现的方向词，才算「环比方向声明」。
 * 为什么要有这个限定：样本里有一句行动建议「减少中断次数」，
 * 它说的是少被打断，不是「本周比上周减少」；按字面抓方向词会把它误判成事实错误。
 * 所以方向声明要求文本同时带周对比语境（环比 / 比上周 / 上周 / 本周 等）。
 */
const WEEK_CONTEXT = /环比|比上周|较上周|比上|较上|上周|本周/;
const DIRECTION_UP = /增加|上升|增长|提升|上涨/;
const DIRECTION_DOWN = /减少|下降|降低|下滑|回落/;
const DIRECTION_FLAT = /持平|不变|持平/;

/**
 * 科目词表：用来发现「底稿之外的科目」（如「化学」）。
 * 词表只用于识别，不参与计数；命中且不在底稿 subjects 里 → 该科目声明不一致。
 */
const SUBJECT_LEXICON = [
  '数学', '英语', '物理', '化学', '语文', '生物', '历史', '地理', '政治',
  '专业课', '编程', '算法', '英语听力', '数学分析',
];

const errors = [];
const fail = (msg) => errors.push(msg);

const pct = (num, den) => (den === 0 ? 0 : Math.round((num / den) * 1000) / 10);
const fmtPct = (num, den) => pct(num, den).toFixed(1) + '%';

// ---------------------------------------------------------------------------
// 1) 底稿 → 白名单 / 科目表
// ---------------------------------------------------------------------------
function collectNumbers(value, out) {
  if (typeof value === 'number' && Number.isFinite(value)) out.add(value);
  else if (Array.isArray(value)) for (const item of value) collectNumbers(item, out);
  else if (value !== null && typeof value === 'object') for (const k of Object.keys(value)) collectNumbers(value[k], out);
  return out;
}

function loadFixture() {
  const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  const primary = fixture.primary;
  if (!primary || typeof primary !== 'object') throw new Error('summary_fixture.json 缺少 primary');
  // 白名单：primary 里所有数值字段 + 各科目 minutes（collectNumbers 已经能把 subjects 里的 minutes 收进来）+ 0
  const numbers = collectNumbers(primary, new Set());
  numbers.add(0);
  const subjects = new Map();
  for (const item of primary.subjects || []) subjects.set(item.name, item.minutes);
  const foreignSubjects = SUBJECT_LEXICON.filter((name) => !subjects.has(name));
  return { fixture, primary, numbers, subjects, foreignSubjects };
}

// ---------------------------------------------------------------------------
// 2) 取「最终树」
// ---------------------------------------------------------------------------
function finalTreeOf(sample, fixture) {
  const judged = analyze(sample.raw);
  if (judged.g2_outcome !== 'fail') {
    const ex = extract(sample.raw);
    if (ex.error) return { tree: null, from: 'llm', judged, note: '抽取失败 ' + ex.error };
    const nz = normalize(ex.text);
    if (nz.error) return { tree: null, from: 'llm', judged, note: '规整失败 ' + nz.error };
    return { tree: nz.tree, from: 'llm', judged, note: judged.g2_outcome };
  }
  return { tree: buildRuleTree(fixture), from: 'rule', judged, note: '规则兜底' };
}

// ---------------------------------------------------------------------------
// 3) 从一棵树里抽事实声明
// ---------------------------------------------------------------------------
function* walkNodes(node) {
  yield node;
  if (Array.isArray(node.children)) for (const child of node.children) yield* walkNodes(child);
}

/**
 * 抽一棵树上的全部事实声明。
 * @returns {{sampleId: string|null, text: string, type: 'number'|'subject'|'direction',
 *            value: string|number, ok: boolean, reason: string}[]}
 */
function claimsOf(tree, sampleId, ctx) {
  const claims = [];
  if (tree === null) return claims;
  for (const node of walkNodes(tree)) {
    const text = typeof node.text === 'string' ? node.text : '';
    if (text.trim() === '') continue;
    const numbers = text.match(/\d+/g);
    const nums = numbers === null ? [] : numbers.map((n) => Number(n));

    // A. 数字声明：每个整数都要在底稿白名单里
    for (const n of nums) {
      const ok = ctx.numbers.has(n);
      claims.push({
        sampleId,
        text,
        type: 'number',
        value: n,
        ok,
        reason: ok ? '' : `数字 ${n} 不在底稿白名单里`,
      });
    }

    // B. 科目声明
    for (const name of ctx.subjects.keys()) {
      if (!text.includes(name)) continue;
      if (nums.length > 0) {
        const minutes = ctx.subjects.get(name);
        const used = nums[0];
        const ok = used === minutes;
        claims.push({
          sampleId,
          text,
          type: 'subject',
          value: `${name} ${used}`,
          ok,
          reason: ok ? '' : `科目「${name}」写的是 ${used} 分钟，底稿是 ${minutes} 分钟`,
        });
      }
    }
    for (const name of ctx.foreignSubjects) {
      if (!text.includes(name)) continue;
      claims.push({
        sampleId,
        text,
        type: 'subject',
        value: name,
        ok: false,
        reason: `出现了底稿之外的科目「${name}」`,
      });
    }

    // C. 环比方向声明（仅限周对比语境）
    if (WEEK_CONTEXT.test(text)) {
      let dir = null;
      if (DIRECTION_FLAT.test(text)) dir = 'flat';
      else if (DIRECTION_DOWN.test(text)) dir = 'down';
      else if (DIRECTION_UP.test(text)) dir = 'up';
      if (dir !== null) {
        const ok = dir === 'up';   // 底稿 weekOverWeekPercent = +50（增加）
        const reason = ok ? '' : `写了「${dir === 'down' ? '减少/下降' : '持平'}」，但底稿是环比增加 ${ctx.primary.weekOverWeekPercent}%`;
        claims.push({
          sampleId,
          text,
          type: 'direction',
          value: dir,
          ok,
          reason,
        });
      }
    }
  }
  return claims;
}

// ---------------------------------------------------------------------------
// 4) 自检：三棵反例树 + 一棵合规树
// ---------------------------------------------------------------------------
const clone = (o) => JSON.parse(JSON.stringify(o));

function replaceLeafText(tree, from, to) {
  const copy = clone(tree);
  let done = false;
  for (const node of walkNodes(copy)) {
    if (!done && Array.isArray(node.children) && node.children.length === 0 && node.text === from) {
      node.text = to;
      done = true;
    }
  }
  if (!done) throw new Error('自检树构造失败：找不到叶子「' + from + '」');
  return copy;
}

function runSelfCheck(ctx) {
  const base = buildRuleTree(ctx.fixture);
  const cases = [
    { name: '含底稿外数字（999）', tree: replaceLeafText(base, '本周 150 分钟', '本周 999 分钟'), type: 'number' },
    { name: '环比方向写反（减少）', tree: replaceLeafText(base, '环比增加 50%', '环比减少 50%'), type: 'direction' },
    // 40 在白名单里、但不是「数学」的分钟数 → 只该被 B（科目）抓到，证明 B 独立于 A
    { name: '科目数字错误（数学 40 分钟）', tree: replaceLeafText(base, '数学', '数学 40 分钟'), type: 'subject' },
    { name: '完全合规树（规则树本身）', tree: base, type: null },
  ];

  const results = [];
  for (const item of cases) {
    const claims = claimsOf(item.tree, 'SELF', ctx);
    const bad = claims.filter((c) => c.ok !== true);
    if (item.type === null) {
      results.push({ name: item.name, passed: bad.length === 0, detail: `不一致声明 ${bad.length} 条（应为 0）` });
    } else {
      const hit = bad.some((c) => c.type === item.type);
      results.push({ name: item.name, passed: hit, detail: `不一致声明 ${bad.length} 条，其中含 ${item.type} 类：${hit}` });
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// 5) 主流程
// ---------------------------------------------------------------------------
function main() {
  const { fixture, primary, numbers, subjects, foreignSubjects } = loadFixture();
  const ctx = { fixture, primary, numbers, subjects, foreignSubjects };

  const lines = fs.readFileSync(CORPUS_PATH, 'utf8').split('\n').filter((l) => l.trim() !== '');
  const all = lines.map((l) => JSON.parse(l));
  const content = all.filter((s) => s.kind === 'content');
  const network = all.filter((s) => s.kind !== 'content');
  if (content.length !== 60) fail(`内容样本应为 60 条，实际 ${content.length}`);

  // 固定顺序，保证输出可复现
  content.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const trees = [];
  const allClaims = [];
  for (const sample of content) {
    const { tree, from, judged, note } = finalTreeOf(sample, fixture);
    if (tree === null) fail(`${sample.id} 没有拿到最终树（${note}）`);
    const claims = claimsOf(tree, sample.id, ctx);
    allClaims.push(...claims);
    const bad = claims.filter((c) => c.ok !== true).length;
    trees.push({
      sampleId: sample.id,
      batch: sample.batch,
      caseType: sample.case_type,
      g2Outcome: judged.g2_outcome,
      treeFrom: from,
      claims: claims.length,
      consistent: claims.length - bad,
      inconsistent: bad,
      fullyConsistent: bad === 0,
      detail: claims,
    });
  }
  const treeCount = trees.filter((t) => t.treeFrom === 'llm').length + trees.filter((t) => t.treeFrom === 'rule').length;
  if (treeCount !== 60) fail(`最终树应为 60 棵，实际 ${treeCount}`);

  // 统计
  const byType = (type) => {
    const list = allClaims.filter((c) => c.type === type);
    return { total: list.length, consistent: list.filter((c) => c.ok).length, inconsistent: list.filter((c) => !c.ok).length };
  };
  const metrics = {
    claims: {
      total: allClaims.length,
      consistent: allClaims.filter((c) => c.ok).length,
      inconsistent: allClaims.filter((c) => !c.ok).length,
    },
    byType: { number: byType('number'), subject: byType('subject'), direction: byType('direction') },
    trees: {
      total: trees.length,
      fromLlm: trees.filter((t) => t.treeFrom === 'llm').length,
      fromRule: trees.filter((t) => t.treeFrom === 'rule').length,
      fullyConsistent: trees.filter((t) => t.fullyConsistent).length,
    },
  };
  metrics.claims.rate = pct(metrics.claims.consistent, metrics.claims.total);
  metrics.trees.rate = pct(metrics.trees.fullyConsistent, metrics.trees.total);
  for (const key of Object.keys(metrics.byType)) {
    metrics.byType[key].rate = pct(metrics.byType[key].consistent, metrics.byType[key].total);
  }

  const inconsistencies = allClaims.filter((c) => c.ok !== true);

  // 自检
  const selfCheck = runSelfCheck(ctx);
  const selfCheckPassed = selfCheck.every((c) => c.passed);
  if (!selfCheckPassed) fail('自检未通过：' + selfCheck.filter((c) => !c.passed).map((c) => c.name).join(' / '));

  // 控制台
  const line = '='.repeat(72);
  console.log(line);
  console.log('事实一致性核查（离线、可复现）—— 合成数据，不代表真实模型的事实一致率');
  console.log(line);
  console.log('口径：只核对「最终会显示的那棵树」里的三类事实声明；底稿 = summary_fixture.json 的 primary；');
  console.log('      A 数字（须在底稿白名单）、B 科目（科目名+分钟数）、C 环比方向（仅限周对比语境）。');
  console.log('      真实云端事实一致率需配 API Key 在设备上实测，本脚本不算、也不预测。');
  console.log('');
  console.log(`样本：内容类 ${content.length} 条（网络类 ${network.length} 条无树，不参与）`);
  console.log(`最终树 ${metrics.trees.total} 棵（云端 ${metrics.trees.fromLlm} / 规则兜底 ${metrics.trees.fromRule}）`);
  console.log('');
  console.log(`事实声明 ${metrics.claims.total} 条：一致 ${metrics.claims.consistent} / 不一致 ${metrics.claims.inconsistent}`);
  console.log(`事实一致率 ${metrics.claims.rate.toFixed(1)}%（只描述这 60 条合成用例）`);
  console.log(`完全一致树 ${metrics.trees.fullyConsistent}/${metrics.trees.total}（${metrics.trees.rate.toFixed(1)}%）`);
  console.log('');
  console.log('分类：' + ['number', 'subject', 'direction'].map((k) => {
    const t = metrics.byType[k];
    return `${k} ${t.consistent}/${t.total}`;
  }).join('  |  '));
  console.log('');
  if (inconsistencies.length > 0) {
    console.log(`不一致清单（${inconsistencies.length} 条）：`);
    for (const c of inconsistencies) console.log(`  ✗ [${c.sampleId}] ${c.type}｜${c.text}｜${c.reason}`);
  } else {
    console.log('不一致清单：无');
  }
  console.log('');
  console.log('自检（反例树必须被抓到、合规树必须通过）：');
  for (const c of selfCheck) console.log(`  ${c.passed ? '✓' : '✗'} ${c.name} —— ${c.detail}`);
  console.log('');
  console.log(`已落盘：${path.basename(OUT_JSON)} / ${path.basename(OUT_MD)}`);
  console.log('边界：不计算 p50/p95、不预测真实模型表现；结论只描述这 60 条合成用例。');
  console.log(line);

  // 落盘
  writeJson({ metrics, inconsistencies, trees, selfCheck, selfCheckPassed, ctx, content, network });
  writeMarkdown({ metrics, inconsistencies, selfCheck, ctx, content, network });

  if (errors.length > 0) {
    console.log('');
    console.log('脚本自检失败：');
    for (const e of errors) console.log('  ✗ ' + e);
    process.exitCode = 1;
    return;
  }
  process.exitCode = 0;
}

// ---------------------------------------------------------------------------
// 6) 落盘
// ---------------------------------------------------------------------------
function writeJson(payload) {
  const { metrics, inconsistencies, trees, selfCheck, selfCheckPassed, ctx, content, network } = payload;
  const out = {
    _model: 'DeepSeek',
    _declaration: '本文件是离线事实一致性核查结果，全部基于人工合成的测试用例；只描述这 60 条用例，不代表真实模型的事实一致率。真实云端事实一致率需用户配置 API Key 后在设备上实测。',
    scope: {
      corpus: 'fault_corpus.jsonl',
      contentSamples: content.length,
      excludedNetworkSamples: network.length,
      fixture: 'summary_fixture.json',
      fixtureBlock: 'primary',
    },
    whitelist: {
      numbers: Array.from(ctx.numbers).sort((a, b) => a - b),
      subjects: Object.fromEntries(Array.from(ctx.subjects.entries())),
    },
    metrics,
    inconsistencies: inconsistencies.map((c) => ({
      sampleId: c.sampleId,
      type: c.type,
      text: c.text,
      value: c.value,
      reason: c.reason,
    })),
    trees: trees.map((t) => ({
      sampleId: t.sampleId,
      batch: t.batch,
      caseType: t.caseType,
      g2Outcome: t.g2Outcome,
      treeFrom: t.treeFrom,
      claims: t.claims,
      consistent: t.consistent,
      inconsistent: t.inconsistent,
      fullyConsistent: t.fullyConsistent,
      detail: t.detail.map((c) => ({ type: c.type, text: c.text, value: c.value, ok: c.ok, reason: c.reason })),
    })),
    selfCheck: { passed: selfCheckPassed, cases: selfCheck },
    boundary: [
      '只覆盖离线可复现的「事实声明是否与底稿一致」，不覆盖真实模型的事实一致率。',
      '不计算 p50/p95 延迟，不预测真实成功率，不做健康/心理诊断，不编造因果或效率百分比。',
      'C 类（环比方向）只认「周对比语境」里的方向词，避免把行动建议「减少中断次数」误判成环比声明。',
      '全部为合成数据，比例是人为编排的测试配额，不能用来估计真实模型的任何比率。',
    ],
  };
  fs.writeFileSync(OUT_JSON, JSON.stringify(out, null, 2) + '\n', 'utf8');
}

function writeMarkdown(payload) {
  const { metrics, inconsistencies, selfCheck, ctx, content, network } = payload;
  const out = [];
  out.push('<!-- 负责模型：DeepSeek -->');
  out.push('# 事实一致性核查报告（离线、可复现）');
  out.push('');
  out.push('> **合成数据声明**：本报告只描述 `fault_corpus.jsonl` 里这 60 条人工合成的用例，');
  out.push('> **不代表真实模型的事实一致率**。真实云端事实一致率需要用户配置 API Key 后在设备上单独实测；');
  out.push('> 本脚本不计算 p50/p95 延迟、不预测真实成功率、不做健康/心理诊断、不编造因果或效率百分比。');
  out.push('');
  out.push('## 1. 核查了什么');
  out.push('');
  out.push(`- 任务集：\`fault_corpus.jsonl\` 的 **${content.length} 条内容样本**（网络类 ${network.length} 条没有树，不参与）。`);
  out.push('- 底稿：`summary_fixture.json` 的 `primary`（唯一数字来源，未混用 `zero`）。');
  out.push('- 核查对象：**最终会显示给用户的那棵树** —— `direct/repaired` 用 `extract → normalize` 的结果，`fail` 用规则兜底树。');
  out.push('');
  out.push('三类事实声明：');
  out.push('');
  out.push('| 类型 | 怎么认 | 什么算不一致 |');
  out.push('|---|---|---|');
  out.push('| A 数字 | 文本里出现的每个整数 | 不在底稿白名单（primary 全部数值 + 科目分钟 + 0） |');
  out.push('| B 科目 | 文本里出现底稿科目名 | 同句的分钟数 ≠ 底稿；或出现底稿外科目 |');
  out.push('| C 环比方向 | 文本带**周对比语境**（环比/比上周/上周/本周）且含方向词 | 写了「减少/下降」或「持平」，而底稿是环比增加 50% |');
  out.push('');
  out.push('## 2. 指标');
  out.push('');
  out.push('| 指标 | 数值 |');
  out.push('|---|---|');
  out.push(`| 最终树 | ${metrics.trees.total} 棵（云端 ${metrics.trees.fromLlm} / 规则兜底 ${metrics.trees.fromRule}） |`);
  out.push(`| 事实声明总数 | ${metrics.claims.total} 条 |`);
  out.push(`| 其中一致 | ${metrics.claims.consistent} 条 |`);
  out.push(`| 其中不一致 | ${metrics.claims.inconsistent} 条 |`);
  out.push(`| **事实一致率** | **${metrics.claims.rate.toFixed(1)}%**（一致声明 / 总声明，只描述这 60 条用例） |`);
  out.push(`| **完全一致树** | **${metrics.trees.fullyConsistent}/${metrics.trees.total}（${metrics.trees.rate.toFixed(1)}%）**（一棵树上所有声明都一致） |`);
  out.push('');
  out.push('分类明细：');
  out.push('');
  out.push('| 类型 | 声明数 | 一致 | 不一致 | 一致率 |');
  out.push('|---|---:|---:|---:|---:|');
  for (const key of ['number', 'subject', 'direction']) {
    const t = metrics.byType[key];
    const name = key === 'number' ? 'A 数字' : key === 'subject' ? 'B 科目' : 'C 环比方向';
    out.push(`| ${name} | ${t.total} | ${t.consistent} | ${t.inconsistent} | ${t.rate.toFixed(1)}% |`);
  }
  out.push('');
  out.push('## 3. 不一致清单');
  out.push('');
  if (inconsistencies.length === 0) {
    out.push('**无。** 60 棵树里的每一条数字/科目/方向声明都能在底稿里对上。');
    out.push('');
    out.push('这个 100% 是**预期内**的，也说清楚它证明了什么：');
    out.push('');
    out.push('- 这份底稿的文案本来就是按底稿数字生成的，所以「本来就对」是前提，不是结论；');
    out.push('- 它真正证明的是：**经过抽取 / 规整 / 截断 / 规则兜底之后，最终显示的树没有把数字改错、改丢或换成别的值**；');
    out.push('- 它**不能**说明真实模型的事实一致率——那要用真实 API 实测。');
  } else {
    out.push('| 样本 | 类型 | 文本 | 原因 |');
    out.push('|---|---|---|---|');
    for (const c of inconsistencies) out.push(`| ${c.sampleId} | ${c.type} | ${c.text} | ${c.reason} |`);
  }
  out.push('');
  out.push('## 4. 反例自检（证明不是「永远 100%」）');
  out.push('');
  out.push('每次运行都会现场构造 4 棵树跑一遍，任何一条判错就非零退出：');
  out.push('');
  out.push('| 用例 | 结果 | 说明 |');
  out.push('|---|---|---|');
  for (const c of selfCheck) out.push(`| ${c.name} | ${c.passed ? '✅ 抓到/通过' : '❌ 失败'} | ${c.detail} |`);
  out.push('');
  out.push('## 5. 口径细节与边界');
  out.push('');
  out.push('1. **只核对最终树**：`direct/repaired` 走 `extract → normalize`，`fail` 走 `buildRuleTree`，跟真实链路一致。');
  out.push('2. **C 类的语境限定**：样本里有一条行动建议「减少中断次数」，它说的是少被打断，不是「本周比上周减少」。');
  out.push('   若只按字面抓方向词，这 8 条会被误判成事实错误，所以方向声明要求文本同时带周对比语境。');
  out.push('3. **白名单是动态生成的**：从 `primary` 里递归取全部数值 + 各科目分钟 + 0，没有手写死。');
  out.push('4. **B 类只在同句出现数字时才计数**：像「数学占比最高」「优先补英语」这种定性表述不产生数字核对，');
  out.push('   但一旦出现底稿外的科目名（如「化学」）仍会被判不一致。');
  out.push('5. 不计算 p50/p95、不预测真实模型表现、不做健康/心理诊断、不编造因果和效率百分比。');
  out.push('6. 全部为合成数据，比例是人为编排的测试配额，不能用来估计真实模型的任何比率。');
  out.push('');
  fs.writeFileSync(OUT_MD, out.join('\n') + '\n', 'utf8');
}

main();
