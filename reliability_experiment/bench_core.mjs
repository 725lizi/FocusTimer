// ============================================================================
// bench_core.mjs —— 模型对比实测共用核心（不联网自身不跑，只被两个 driver 引用）
//
// 职责：加载 bench_fixtures.json（5 份合成底稿）→ 逐底稿拼装与应用完全一致的
// 提示词 → 流式调用 → 复用 reliability_engine 的 analyze / extract / normalize /
// buildRuleTree 做判定 → 数字事实核对 → nearest-rank p50/p95 → 写出 JSON 与报告。
//
// 判定与口径说明：
//   - 分类只有三种：direct（裸文本直接可解析且无需修复）/ repaired（抽取或规整后
//     才可用）/ fail（仍需本地规则树兜底），全部来自 reliability_engine.analyze；
//   - 数字白名单按「每份底稿的所有数值字段 + 0」动态生成，不手写常量；
//   - latencyMs 是「发起请求 → 收完 SSE」的接口级耗时，含网络与模型生成，
//     不含设备端本地抽取/规整/渲染。
//
// 只依赖 Node 内置能力 + 本目录的 reliability_engine.mjs，无第三方依赖。
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
  buildRuleTree,
} from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export const BRANCH_ORDER = '总体情况 / 科目分布 / 专注质量 / 下周行动';
export const MAX_LEAF_CHARS = 16;
export const MIN_NODE_COUNT = 8;
export const MAX_NODE_COUNT = 20;
export const TEMPERATURE = 0.4;
export const MAX_TOKENS = 900;
export const CHAT_PATH = '/chat/completions';

// —— 提示词：逐字移植自 MindMapPromptBuilder.ets，禁止改动 ——————————————————
export function buildSystemPrompt() {
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

export function changeDirectionLabel(p) {
  if (p > 0) return '增加';
  if (p < 0) return '减少';
  return '持平';
}

export function sortedTagMinutes(subjects) {
  return [...subjects].sort(
    (a, b) => (b.minutes - a.minutes) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

export function describeTags(subjects) {
  const top = sortedTagMinutes(subjects).slice(0, 3);
  if (top.length === 0) return '本周暂无科目标签记录';
  return top.map((s) => `${s.name} ${s.minutes} 分钟`).join('，');
}

export function buildUserPrompt(s) {
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

export function buildMessages(summary) {
  return [
    { role: 'system', content: buildSystemPrompt() },
    { role: 'user', content: buildUserPrompt(summary) },
  ];
}

// —— 底稿 → WeeklyDataSummary 映射、白名单与自检 ——————————————————————————
export function collectNumbers(value, out) {
  if (typeof value === 'number' && Number.isFinite(value)) out.add(value);
  else if (Array.isArray(value)) for (const v of value) collectNumbers(v, out);
  else if (value !== null && typeof value === 'object') {
    for (const k of Object.keys(value)) collectNumbers(value[k], out);
  }
  return out;
}

export function mapFixture(f) {
  return {
    thisWeekMinutes: f.totalMinutes,
    lastWeekMinutes: f.lastWeekMinutes,
    changePercent: f.weekOverWeekPercent,
    sessionCount: f.sessionCount,
    activeDays: f.activeDays,
    avgSessionMinutes: f.avgMinutesPerSession,
    interruptedCount: f.interruptCount,
    subjects: (f.subjects || []).map((x) => ({ name: x.name, minutes: x.minutes })),
  };
}

export function loadFixtures(fixturesPath) {
  const raw = JSON.parse(fs.readFileSync(fixturesPath, 'utf8'));
  const list = raw.fixtures;
  if (!Array.isArray(list) || list.length === 0) {
    throw new Error('bench_fixtures.json 缺少 fixtures 数组');
  }
  const out = [];
  for (const f of list) {
    const whitelist = collectNumbers(f, new Set());
    whitelist.add(0);
    const summary = mapFixture(f);
    const userPrompt = buildUserPrompt(summary);

    // 自检 1：数据段（第一段，契约条款之前）里的整数必须都在白名单内。
    // 契约条款本身带 1)~7)、8~20、2~3 层、16 字等模板常量，不属于数据，不参与自检。
    const dataPart = userPrompt.split('\n\n')[0];
    const stray = [...new Set((dataPart.match(/\d+/g) || []).map(Number))]
      .filter((n) => !whitelist.has(n));
    if (stray.length > 0) {
      throw new Error(`${f.id} 的 user prompt 数据段出现白名单外数字：${stray.join(', ')}`);
    }

    // 自检 2：week_a_150 与 summary_fixture.json 的 primary 完全一致
    if (f.id === 'week_a_150') {
      const expected = [0, 1, 2, 3, 30, 40, 50, 80, 100, 150];
      const actual = [...whitelist].sort((a, b) => a - b);
      if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        throw new Error(`week_a_150 白名单不符：${JSON.stringify(actual)}，预期 ${JSON.stringify(expected)}`);
      }
    }

    // 空数据底稿：提示词内嵌的示例数字「25 分钟」按提示词约定允许出现，计入白名单，
    // 其余数字仍严格核对（模型在空数据上编造任何其他数字都会被记为不一致）。
    if (f.totalMinutes === 0) {
      whitelist.add(25);
    }

    out.push({ fixture: f, summary, whitelist, userPrompt });
  }
  return out;
}

// —— SSE 解析与计时 ————————————————————————————————————————————————————
function parseSSELine(line) {
  if (!line.startsWith('data:')) return null;
  const payload = line.slice(5).trim();
  if (payload === '' || payload === '[DONE]') return payload;
  try {
    const obj = JSON.parse(payload);
    return obj?.choices?.[0]?.delta?.content ?? '';
  } catch {
    return '';
  }
}

async function callOnce(cfg, messages) {
  const body = {
    model: cfg.model,
    messages,
    stream: true,
    temperature: TEMPERATURE,
    max_tokens: MAX_TOKENS,
  };
  const t0 = performance.now();
  const startedAt = new Date().toISOString();
  let res;
  try {
    res = await fetch(cfg.baseUrl + CHAT_PATH, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg.apiKey}`,
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
  return { startedAt, httpStatus: res.status, latencyMs: performance.now() - t0, text };
}

// —— 树与事实核对 ———————————————————————————————————————————————————
function finalTree(text, fixture) {
  const ex = extract(text || '');
  if (!ex.error) {
    const nz = normalize(ex.text);
    if (!nz.error && structuralOk(nz.tree)) return nz.tree;
  }
  // 规则树只认 summary_fixture.json 的 primary 形状
  return buildRuleTree({ primary: fixture });
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

function nearestRank(sortedAsc, p) {
  if (sortedAsc.length === 0) return null;
  const k = Math.ceil((p / 100) * sortedAsc.length);
  return sortedAsc[Math.max(0, Math.min(sortedAsc.length - 1, k - 1))];
}

// —— 主流程：runBench(cfg) ————————————————————————————————————————————
// cfg = {
//   modelLabel, model, baseUrl, apiKey, runsPerFixture, outPrefix,
//   fixturesPath?, outDir?   // 默认取本文件同目录的 bench_fixtures.json / 输出到本文件同目录
// }
export async function runBench(cfg) {
  if (!cfg.apiKey) {
    console.error('未检测到 API Key。请先设置环境变量（豆包：ARK_API_KEY；DeepSeek：DEEPSEEK_API_KEY）。');
    process.exit(1);
  }
  const fixturesPath = cfg.fixturesPath || path.join(HERE, 'bench_fixtures.json');
  const outDir = cfg.outDir || HERE;
  const fixtures = loadFixtures(fixturesPath);
  const totalRuns = fixtures.length * cfg.runsPerFixture;

  console.log(`模型=${cfg.modelLabel} (${cfg.model})  端点=${cfg.baseUrl}${CHAT_PATH}`);
  console.log(`底稿=${fixtures.length} 份 × 每份 ${cfg.runsPerFixture} 次 = ${totalRuns} 次真实调用`);

  const runs = [];
  for (const fx of fixtures) {
    const messages = buildMessages(fx.summary);
    for (let i = 1; i <= cfg.runsPerFixture; i += 1) {
      const r = await callOnce(cfg, messages);
      const verdict = analyze(r.text || '');
      const tree = finalTree(r.text || '', fx.fixture);
      const nodeTexts = walkNodeText(tree, []);
      const declared = [];
      for (const t of nodeTexts) {
        for (const m of t.match(/\d+/g) || []) declared.push(Number(m));
      }
      const inconsistent = declared.filter((n) => !fx.whitelist.has(n));
      runs.push({
        index: runs.length + 1,
        fixtureId: fx.fixture.id,
        fixtureLabel: fx.fixture.label,
        runInFixture: i,
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
      });
      console.log(`[${runs.length}/${totalRuns}] ${fx.fixture.id}#${i} http=${r.httpStatus} `
        + `${verdict.g2_outcome} ${r.latencyMs === undefined || r.latencyMs === null ? 'n/a' : r.latencyMs + 'ms'} `
        + `nodes=${countNodes(tree)} 数字=${declared.length - inconsistent.length}/${declared.length}`);
    }
  }

  const latencies = runs.map((x) => x.latencyMs).filter((x) => typeof x === 'number').sort((a, b) => a - b);
  const byFixture = fixtures.map((fx) => {
    const sub = runs.filter((x) => x.fixtureId === fx.fixture.id);
    const subLat = sub.map((x) => x.latencyMs).filter((x) => typeof x === 'number').sort((a, b) => a - b);
    const declared = sub.reduce((a, x) => a + x.numbersDeclared, 0);
    const consistent = sub.reduce((a, x) => a + x.numbersConsistent, 0);
    return {
      fixtureId: fx.fixture.id,
      label: fx.fixture.label,
      runs: sub.length,
      direct: sub.filter((x) => x.g2_outcome === 'direct').length,
      repaired: sub.filter((x) => x.g2_outcome === 'repaired').length,
      fail: sub.filter((x) => x.g2_outcome === 'fail').length,
      p50: nearestRank(subLat, 50),
      factRate: declared === 0 ? null : Math.round((consistent / declared) * 1000) / 1000,
    };
  });

  const declaredAll = runs.reduce((a, x) => a + x.numbersDeclared, 0);
  const consistentAll = runs.reduce((a, x) => a + x.numbersConsistent, 0);
  const summary = {
    modelLabel: cfg.modelLabel,
    model: cfg.model,
    runs: totalRuns,
    fixtures: fixtures.length,
    runsPerFixture: cfg.runsPerFixture,
    outcomes: {
      direct: runs.filter((x) => x.g2_outcome === 'direct').length,
      repaired: runs.filter((x) => x.g2_outcome === 'repaired').length,
      fail: runs.filter((x) => x.g2_outcome === 'fail').length,
      directRate: Math.round((runs.filter((x) => x.g2_outcome === 'direct').length / totalRuns) * 1000) / 1000,
    },
    sources: {
      llm: runs.filter((x) => x.g3_source === 'llm').length,
      rule: runs.filter((x) => x.g3_source === 'rule').length,
    },
    latency: {
      method: 'nearest-rank',
      p50: nearestRank(latencies, 50),
      p95: nearestRank(latencies, 95),
      min: latencies[0] ?? null,
      max: latencies[latencies.length - 1] ?? null,
      sortedAsc: latencies,
    },
    factConsistency: {
      declared: declaredAll,
      consistent: consistentAll,
      rate: declaredAll === 0 ? null : Math.round((consistentAll / declaredAll) * 1000) / 1000,
    },
    httpErrors: runs.filter((x) => x.httpStatus !== 200).length,
    byFixture,
  };

  const payload = {
    _meta: {
      ranAt: new Date().toISOString(),
      nodeVersion: process.version,
      model: cfg.model,
      baseUrl: cfg.baseUrl + CHAT_PATH,
      totalRuns,
      fixtures: fixtures.map((fx) => ({ id: fx.fixture.id, label: fx.fixture.label })),
      temperature: TEMPERATURE,
      maxTokens: MAX_TOKENS,
      declaration:
        '合成底稿、真实联网调用；提示词与请求参数逐字对齐应用内 MindMapPromptBuilder。'
        + 'latencyMs 为「发起请求到收完 SSE」的接口级耗时，含网络与模型生成，'
        + '不含设备端本地抽取/规整/渲染，不等同于设备 UI 端到端延迟。'
        + '本记录只描述这若干次实测，不外推总体成功率。',
      noKeyStored: true,
    },
    runs,
    summary,
  };
  fs.writeFileSync(path.join(outDir, cfg.outPrefix + '_results.json'), JSON.stringify(payload, null, 2), 'utf8');

  const rateTxt = summary.factConsistency.rate === null
    ? 'n/a' : (summary.factConsistency.rate * 100).toFixed(1) + '%';
  const lines = [
    `# ${cfg.modelLabel} 多底稿实测报告（${totalRuns} 次真实调用）`,
    '',
    `- 运行时间：${payload._meta.ranAt}`,
    `- 模型：\`${cfg.model}\`，端点 \`${cfg.baseUrl}${CHAT_PATH}\``,
    `- 底稿：${fixtures.length} 份合成底稿 × 每份 ${cfg.runsPerFixture} 次，stream=true，temperature=${TEMPERATURE}，max_tokens=${MAX_TOKENS}`,
    '',
    '## 口径诚实声明',
    '',
    'latencyMs 是「发起请求 → 收完 SSE」的**接口级耗时**（含网络往返、模型生成与传输），',
    '**不含**设备端本地 JSON 抽取、规整与渲染，因此不等同于 UI 端到端延迟。',
    '所有底稿都是人工合成数据（bench_fixtures.json 内已声明），只用于两模型同口径对比。',
    '',
    '## 每份底稿的表现',
    '',
    '| 底稿 | 次数 | direct | repaired | fail | p50(ms) | 数字一致率 |',
    '|---|---|---|---|---|---|---|',
    ...byFixture.map((f) =>
      `| ${f.fixtureId} ${f.label} | ${f.runs} | ${f.direct} | ${f.repaired} | ${f.fail} `
      + `| ${f.p50 === null ? 'n/a' : f.p50} `
      + `| ${f.factRate === null ? 'n/a' : (f.factRate * 100).toFixed(1) + '%'} |`),
    '',
    '## 总体结果',
    '',
    `- 分类：direct ${summary.outcomes.direct} / repaired ${summary.outcomes.repaired} / fail ${summary.outcomes.fail}`,
    `- 直接可解析率 = ${summary.outcomes.directRate * 100}%`,
    `- 来源：llm ${summary.sources.llm} 次 / rule ${summary.sources.rule} 次（fail 会走本地规则树兜底）`,
    `- 接口级耗时：p50 = ${summary.latency.p50} ms，p95 = ${summary.latency.p95} ms（nearest-rank）`,
    `- 数字事实一致性：${summary.factConsistency.consistent}/${summary.factConsistency.declared}（${rateTxt}）`,
    `- HTTP 非 200 次数：${summary.httpErrors}`,
    '',
    `排序后耗时数组（ms）：${JSON.stringify(summary.latency.sortedAsc)}`,
    '',
    '## 边界',
    '',
    `只描述这 ${totalRuns} 次实测，不外推总体成功率。两模型对比仅在`
      + '「同一批底稿、同一套提示词、同一批参数」下成立。',
    '本报告不含主观质量评价：「中文笔记理解」这类维度需要用户侧评分，不在本脚本范围内。',
    '空数据底稿的提示词内嵌了示例数字「25 分钟」，该数字按提示词约定计入该底稿白名单；',
    '模型在空数据上编造的任何其他数字都会被记为不一致。',
    '',
  ];
  fs.writeFileSync(path.join(outDir, cfg.outPrefix + '_report.md'), lines.join('\n'), 'utf8');

  console.log('');
  console.log(`完成：${path.join(outDir, cfg.outPrefix + '_results.json')}`);
  console.log(`报告：${path.join(outDir, cfg.outPrefix + '_report.md')}`);
  console.log(`direct=${summary.outcomes.direct}/${totalRuns} (${summary.outcomes.directRate * 100}%)  `
    + `p50=${summary.latency.p50}ms  p95=${summary.latency.p95}ms`);
  return summary;
}
