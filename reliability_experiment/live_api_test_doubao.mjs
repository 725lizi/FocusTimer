// ============================================================================
// live_api_test_doubao.mjs —— 豆包（火山方舟）真实联网实测脚本
//
// 负责模型：豆包 Doubao（火山方舟 Ark，OpenAI 兼容接口）
//
// 这份脚本是 live_api_test.mjs 的「豆包孪生版」：判定逻辑、Prompt 模板、
// 分类口径、事实核对、p50/p95 算法全部与 DeepSeek 版逐字一致，唯一差别是
// 请求端点、鉴权环境变量与模型名。这样才能在同一张表里做真正的对比。
//
// 用法：
//   $env:ARK_API_KEY = "你的方舟 API Key"
//   $env:DOUBAO_MODEL = "doubao-seed-1.6-250615"   # 以方舟控制台模型广场为准
//   node live_api_test_doubao.mjs
//
// 安全：Key 只从环境变量读，绝不写进任何产物、日志或控制台输出。
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

import {
  analyze,
  extract,
  normalize,
  structuralOk,
  softSchemaOk,
  buildRuleTree,
} from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.join(HERE, 'summary_fixture.json');
const RESULTS_PATH = path.join(HERE, 'live_api_results_doubao.json');
const REPORT_PATH = path.join(HERE, 'live_api_report_doubao.md');

// —— 配置：与应用一致的请求参数（只换端点与模型）——————————————————————
const BASE_URL = process.env.ARK_BASE_URL || 'https://ark.cn-beijing.volces.com/api/v3';
const CHAT_PATH = '/chat/completions';
const MODEL = process.env.DOUBAO_MODEL || 'doubao-seed-1.6-250615';
const TEMPERATURE = 0.4;
const MAX_TOKENS = 900;
const RUNS = 20; // 与 DeepSeek 版保持一致，便于同口径对比

// —— 提示词：逐字移植自 MindMapPromptBuilder.ets，禁止改动一个字 ——————————
const BRANCH_ORDER = '总体情况 / 科目分布 / 专注质量 / 下周行动';
const MAX_LEAF_CHARS = 16;
const MIN_NODE_COUNT = 8;
const MAX_NODE_COUNT = 20;

function buildSystemPrompt() {
  return '你是一名学习数据可视化助手，负责把真实专注统计转成思维导图节点 JSON。'
    + '严格约束：1）只输出一个思维导图节点 JSON 对象，不要 markdown 围栏（不要 ```json）、'
    + '不要代码块、不要任何解释文字、前后不要多余内容；2）JSON 的键和字符串值都必须用双引号，'
    + '数字直接写阿拉伯数字，不要注释、不要尾逗号；3）节点固定为 {id, text, children} 三字段，'
    + 'children 是数组（叶子节点用空数组）；4）根节点固定为 {"id":"root","text":"本周专注复盘","children":[...]}；'
    + `5）一级分支固定四个、顺序固定为：${BRANCH_ORDER}；`
    + `6）总节点数（含根）必须控制在 ${MIN_NODE_COUNT}~${MAX_NODE_COUNT} 个，`
    + '深度固定 2~3 层，且每个节点 id 全局唯一；'
    + `7）每个叶子节点的 text 不超过 ${MAX_LEAF_CHARS} 个汉字，精炼成短句或关键词；`
    + '8）所有数字只能来自用户给出的数据，禁止编造、估算或换算任何新数字；'
    + '9）数据为空时仍要输出完整结构，把鼓励写进节点文字，绝不允许编造数字。';
}

function changeDirectionLabel(p) {
  if (p > 0) return '增加';
  if (p < 0) return '减少';
  return '持平';
}

function sortedTagMinutes(subjects) {
  return [...subjects].sort((a, b) => (b.minutes - a.minutes) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function describeTags(subjects) {
  const top = sortedTagMinutes(subjects).slice(0, 3);
  if (top.length === 0) return '本周暂无科目标签记录';
  return top.map((s) => `${s.name} ${s.minutes} 分钟`).join('，');
}

function buildUserPrompt(s) {
  const lines = [];
  lines.push('以下是我本周的真实专注统计（时长单位：分钟）：');
  lines.push(`- 本周总专注：${s.thisWeekMinutes} 分钟；上周：${s.lastWeekMinutes} 分钟；`
    + `环比${changeDirectionLabel(s.changePercent)} ${Math.abs(s.changePercent)}%`);
  lines.push(`- 专注次数：${s.sessionCount} 次；活跃天数：${s.activeDays} 天；`
    + `平均每次：${s.avgSessionMinutes} 分钟；被中断：${s.interruptedCount} 次`);
  lines.push(`- 各科目时长：${describeTags(s.subjects)}`);
  lines.push('');
  lines.push('请输出思维导图节点 JSON，契约如下：');
  lines.push('1）只输出一个 JSON 对象，不要 markdown 围栏、不要解释文字；');
  lines.push('2）根节点固定为 {"id":"root","text":"本周专注复盘","children":[...]}；');
  lines.push(`3）根下四个一级分支，顺序固定为「${BRANCH_ORDER}」；`);
  lines.push(`4）每个节点形如 {"id":"唯一字符串","text":"不超过 ${MAX_LEAF_CHARS} 个汉字","children":[]}，叶子节点 children 为空数组；`);
  lines.push(`5）总节点数（含根）控制在 ${MIN_NODE_COUNT}~${MAX_NODE_COUNT} 个，深度固定 2~3 层；`);
  lines.push('6）所有数字只能来自上面的数据，不要新增或换算任何数字；');
  lines.push(`7）「下周行动」给 2~3 条具体可执行的建议，每条不超过 ${MAX_LEAF_CHARS} 个汉字。`);
  if (s.thisWeekMinutes === 0) {
    lines.push('重要：本周没有任何专注记录。四个分支仍要齐全，但只做鼓励与起步建议'
      + '（例如「本周还没开始，先来 25 分钟」），不得编造任何数字。');
  }
  lines.push('现在只输出这一个 JSON 对象。');
  return lines.join('\n');
}

// —— 底稿读取与数字白名单（动态生成，不手写常量）—————————————————————
function collectNumbers(value, out) {
  if (typeof value === 'number' && Number.isFinite(value)) out.add(value);
  else if (Array.isArray(value)) for (const v of value) collectNumbers(v, out);
  else if (value !== null && typeof value === 'object') {
    for (const k of Object.keys(value)) collectNumbers(value[k], out);
  }
  return out;
}

function loadFixture() {
  const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, 'utf8'));
  const primary = fixture.primary;
  if (!primary || typeof primary !== 'object') throw new Error('summary_fixture.json 缺少 primary');

  const whitelist = collectNumbers(primary, new Set());
  whitelist.add(0);

  // 自检：动态白名单（含显式补的 0）必须等于预期集合，防止移植时漏字段
  whitelist.add(0);
  const EXPECTED = [0, 1, 2, 3, 30, 40, 50, 80, 100, 150];
  const actual = [...whitelist].sort((a, b) => a - b);
  if (JSON.stringify(actual) !== JSON.stringify(EXPECTED)) {
    throw new Error(`数字白名单不符合预期：得到 ${JSON.stringify(actual)}，预期 ${JSON.stringify(EXPECTED)}`);
  }

  // WeeklyDataSummary 映射
  const summary = {
    thisWeekMinutes: primary.totalMinutes,
    lastWeekMinutes: primary.lastWeekMinutes,
    changePercent: primary.weekOverWeekPercent,
    sessionCount: primary.sessionCount,
    activeDays: primary.activeDays,
    avgSessionMinutes: primary.avgMinutesPerSession,
    interruptedCount: primary.interruptCount,
    subjects: (primary.subjects || []).map((x) => ({ name: x.name, minutes: x.minutes })),
  };

  // 自检：user prompt 里出现的所有整数，必须都在白名单内
  const prompt = buildUserPrompt(summary);
  const stray = [...new Set((prompt.match(/\d+/g) || []).map(Number))].filter((n) => !whitelist.has(n));
  if (stray.length > 0) {
    throw new Error(`user prompt 里出现白名单外的数字：${stray.join(', ')}`);
  }

  return { fixture, primary, summary, whitelist };
}

// —— SSE 流解析 + 计时 ——————————————————————————————————————————————
function parseSSELine(line) {
  if (!line.startsWith('data:')) return null;
  const payload = line.slice(5).trim();
  if (payload === '' || payload === '[DONE]') return payload;
  try {
    const obj = JSON.parse(payload);
    return obj?.choices?.[0]?.delta?.content ?? '';
  } catch {
    return ''; // 非 JSON 的心跳或注释行，忽略
  }
}

async function callOnce(apiKey, messages) {
  const body = {
    model: MODEL,
    messages,
    stream: true,
    temperature: TEMPERATURE,
    max_tokens: MAX_TOKENS,
  };

  const t0 = performance.now();
  const startedAt = new Date().toISOString();
  let res;
  try {
    res = await fetch(BASE_URL + CHAT_PATH, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
        Accept: 'text/event-stream',
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    return {
      startedAt, httpStatus: 0, latencyMs: performance.now() - t0,
      text: '', transportError: String(err && err.message ? err.message : err),
    };
  }

  if (!res.ok) {
    let snippet = '';
    try { snippet = (await res.text()).slice(0, 800); } catch { /* ignore */ }
    return { startedAt, httpStatus: res.status, latencyMs: performance.now() - t0, text: '', snippet };
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buf = '';
  let text = '';
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, idx).replace(/\r$/, '');
      buf = buf.slice(idx + 1);
      const piece = parseSSELine(line);
      if (piece === '[DONE]') { buf = ''; break; }
      if (typeof piece === 'string') text += piece;
    }
  }
  const latencyMs = performance.now() - t0;
  return { startedAt, httpStatus: res.status, latencyMs, text };
}

// —— 后续树与数字事实一致性 ————————————————————————————————————————
function finalTree(result, fixture) {
  const ex = extract(result.text || '');
  if (!ex.error) {
    const nz = normalize(ex.text);
    if (!nz.error && structuralOk(nz.tree)) return nz.tree;
  }
  return buildRuleTree(fixture);
}

function walkNodeText(node, out) {
  if (!node || typeof node !== 'object') return out;
  if (typeof node.text === 'string') out.push(node.text);
  for (const c of node.children || []) walkNodeText(c, out);
  return out;
}

function countNodes(node) {
  if (!node || typeof node !== 'object') return 0;
  return 1 + (node.children || []).reduce((a, c) => a + countNodes(c), 0);
}

function detectSource(result) {
  const ex = extract(result.text || '');
  return ex.error ? 'unknown' : 'llm';
}

// —— nearest-rank 分位数（口径写死）———————————————————————————
function nearestRank(sortedAsc, p) {
  const k = Math.ceil((p / 100) * sortedAsc.length);
  return sortedAsc[Math.max(0, Math.min(sortedAsc.length - 1, k - 1))];
}

// —— 主流程 ————————————————————————————————————————————————————
async function main() {
  const apiKey = process.env.ARK_API_KEY || process.env.DOUBAO_API_KEY || '';
  if (!apiKey) {
    console.error('未检测到 API Key。请先设置环境变量 ARK_API_KEY（火山方舟控制台 → API Key 管理）。');
    process.exit(1);
  }

  const { fixture, primary, summary, whitelist } = loadFixture();
  const messages = [
    { role: 'system', content: buildSystemPrompt() },
    { role: 'user', content: buildUserPrompt(summary) },
  ];

  console.log(`模型=${MODEL}  端点=${BASE_URL}${CHAT_PATH}  次数=${RUNS}`);
  console.log(`temperature=${TEMPERATURE}  max_tokens=${MAX_TOKENS}  数字白名单=${[...whitelist].sort((a, b) => a - b).join(',')}`);

  const runs = [];
  for (let i = 1; i <= RUNS; i += 1) {
    const r = await callOnce(apiKey, messages);
    const verdict = analyze(r.text || '');
    const tree = finalTree(r, fixture);
    const nodeTexts = walkNodeText(tree, []);
    const declared = [];
    for (const t of nodeTexts) {
      for (const m of t.match(/\d+/g) || []) declared.push(Number(m));
    }
    const inconsistent = declared.filter((n) => !whitelist.has(n));

    const record = {
      index: i,
      startedAt: r.startedAt,
      httpStatus: r.httpStatus,
      latencyMs: r.transportError ? null : Math.round(r.latencyMs * 10) / 10,
      transportError: r.transportError || null,
      httpErrorSnippet: r.snippet || null,
      g2_outcome: verdict.g2_outcome,
      g3_source: verdict.g3_source,
      hardOk: verdict.hardOk,
      softOk: verdict.softOk,
      would_fallback: verdict.g2_outcome === 'fail',
      nodeCount: countNodes(tree),
      numbersDeclared: declared.length,
      numbersConsistent: declared.length - inconsistent.length,
      inconsistentNumbers: [...new Set(inconsistent)],
      rawText: r.text || '',
    };
    runs.push(record);
    console.log(`[${i}/${RUNS}] http=${record.httpStatus} ${record.g2_outcome} `
      + `${record.latencyMs === null ? 'n/a' : record.latencyMs + 'ms'} nodes=${record.nodeCount} `
      + `数字一致=${record.numbersConsistent}/${record.numbersDeclared}`);
  }

  const latencies = runs.map((x) => x.latencyMs).filter((x) => typeof x === 'number').sort((a, b) => a - b);
  const countOf = (key, val) => runs.filter((x) => x[key] === val).length;

  const declaredTotal = runs.reduce((a, x) => a + x.numbersDeclared, 0);
  const consistentTotal = runs.reduce((a, x) => a + x.numbersConsistent, 0);

  const summaryOut = {
    model: MODEL,
    runs: RUNS,
    latency: {
      method: 'nearest-rank',
      p50: nearestRank(latencies, 50),
      p95: nearestRank(latencies, 95),
      min: latencies[0] ?? null,
      max: latencies[latencies.length - 1] ?? null,
      sortedAsc: latencies,
    },
    outcomes: {
      direct: countOf('g2_outcome', 'direct'),
      repaired: countOf('g2_outcome', 'repaired'),
      fail: countOf('g2_outcome', 'fail'),
    },
    sources: {
      llm: countOf('g3_source', 'llm'),
      rule: countOf('g3_source', 'rule'),
    },
    factConsistency: {
      declared: declaredTotal,
      consistent: consistentTotal,
      rate: declaredTotal === 0 ? null : Math.round((consistentTotal / declaredTotal) * 1000) / 1000,
    },
    httpErrors: runs.filter((x) => x.httpStatus !== 200).length,
  };

  const payload = {
    _meta: {
      ranAt: new Date().toISOString(),
      nodeVersion: process.version,
      model: MODEL,
      baseUrl: BASE_URL + CHAT_PATH,
      runs: RUNS,
      temperature: TEMPERATURE,
      maxTokens: MAX_TOKENS,
      fixtureId: fixture.fixtureId,
      declaration:
        '真实联网调用豆包（火山方舟）的实测记录；提示词与请求参数逐字对齐应用内 MindMapPromptBuilder；'
        + 'latencyMs 为「发起请求到收完 SSE」的接口级耗时，含网络与模型生成，不含设备端本地抽取/规整/渲染。',
      noKeyStored: true,
    },
    runs,
    summary: summaryOut,
  };
  fs.writeFileSync(RESULTS_PATH, JSON.stringify(payload, null, 2), 'utf8');

  const report = [
    '# 豆包（火山方舟）真实调用实测报告',
    '',
    `- 运行时间：${payload._meta.ranAt}`,
    `- 模型：\`${MODEL}\`，端点 \`${BASE_URL}${CHAT_PATH}\``,
    `- 参数：stream=true，temperature=${TEMPERATURE}，max_tokens=${MAX_TOKENS}，共 ${RUNS} 次真实调用`,
    `- Node 版本：${process.version}`,
    '',
    '## 口径诚实声明',
    '',
    '本次 latencyMs 是「发起请求 → 收完 SSE 流」的**接口级耗时**，包含网络往返、模型生成与传输，',
    '**不含**设备端本地的 JSON 抽取、规整与脑图渲染耗时，因此不等同于设备 UI 端到端延迟。',
    '',
    '## 结果',
    '',
    `- p50 = ${summaryOut.latency.p50} ms，p95 = ${summaryOut.latency.p95} ms（nearest-rank 法）`,
    `- 分类：direct ${summaryOut.outcomes.direct} 次 / repaired ${summaryOut.outcomes.repaired} 次 / fail ${summaryOut.outcomes.fail} 次`,
    `- 来源：llm ${summaryOut.sources.llm} 次 / rule ${summaryOut.sources.rule} 次（fail 即会走本地规则树兜底）`,
    `- 数字事实一致性：${summaryOut.factConsistency.consistent}/${summaryOut.factConsistency.declared}`
      + `（${summaryOut.factConsistency.rate === null ? 'n/a' : (summaryOut.factConsistency.rate * 100).toFixed(1) + '%'}）`,
    `- HTTP 非 200 次数：${summaryOut.httpErrors}`,
    '',
    `排序后耗时数组（ms）：${JSON.stringify(summaryOut.latency.sortedAsc)}`,
    '',
    '## 边界',
    '',
    `本报告只描述这 ${RUNS} 次实测，不外推总体成功率、不估算未测情况、不做因果推论。`,
    '与 DeepSeek 版本的对比，仅在「同一份底稿、同一套提示词、同一批参数」下成立。',
    '',
  ].join('\n');
  fs.writeFileSync(REPORT_PATH, report, 'utf8');

  console.log('');
  console.log(`完成：${RESULTS_PATH}`);
  console.log(`报告：${REPORT_PATH}`);
  console.log(`p50=${summaryOut.latency.p50}ms  p95=${summaryOut.latency.p95}ms`);
  process.exit(0);
}

main().catch((err) => {
  console.error('运行失败：', err && err.message ? err.message : err);
  process.exit(1);
});
