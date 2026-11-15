// FocusBench 唯一入口：跑数据集、评分、汇总、写报告
// 仅使用 Node 内置模块

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { scoreSample } from './scorer.mjs';
import * as mockAdapter from './adapters/mock_adapter.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const OUTCOMES = ['direct', 'repaired', 'rule_fallback', 'failed'];

// ---------- 命令行参数解析 ----------
function parseArgs(argv) {
  const opts = {
    adapter: 'mock',
    dataset: 'dev',
    repeat: 1,
    out: 'report/bench_report',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      const v = argv[i + 1];
      if (v === undefined) throw new Error(`参数 ${arg} 缺少取值`);
      i += 1;
      return v;
    };
    if (arg === '--adapter') opts.adapter = next();
    else if (arg === '--dataset') opts.dataset = next();
    else if (arg === '--repeat') opts.repeat = Number.parseInt(next(), 10);
    else if (arg === '--out') opts.out = next();
    else if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`未知参数：${arg}`);
    }
  }

  if (!['mock', 'openai'].includes(opts.adapter)) {
    throw new Error(`--adapter 只能是 mock 或 openai，收到：${opts.adapter}`);
  }
  if (!['dev', 'locked', 'both'].includes(opts.dataset)) {
    throw new Error(`--dataset 只能是 dev、locked 或 both，收到：${opts.dataset}`);
  }
  if (!Number.isInteger(opts.repeat) || opts.repeat < 1) {
    throw new Error(`--repeat 必须是 >=1 的整数，收到：${opts.repeat}`);
  }
  return opts;
}

function printUsage() {
  console.log('用法：node run_bench.mjs [--adapter mock|openai] [--dataset dev|locked|both] [--repeat N] [--out <path>]');
}

// 只保留主机名，避免把完整 URL（可能含查询参数）写进报告
function hostOnly(url) {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
}

// ---------- 数据集读取 ----------
async function loadJsonl(filePath) {
  const text = await readFile(filePath, 'utf8');
  const lines = text.split(/\r?\n/);
  const samples = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === '') continue;
    samples.push(JSON.parse(trimmed));
  }
  return samples;
}

async function loadDatasets(dataset) {
  const result = [];
  if (dataset === 'dev' || dataset === 'both') {
    const devPath = path.join(__dirname, 'data', 'samples.dev.jsonl');
    const dev = await loadJsonl(devPath);
    result.push({ name: 'dev', samples: dev });
  }
  if (dataset === 'locked' || dataset === 'both') {
    const lockedPath = path.join(__dirname, 'data', 'samples.locked.jsonl');
    const locked = await loadJsonl(lockedPath);
    result.push({ name: 'locked', samples: locked });
  }
  return result;
}

// ---------- 适配器选择 ----------
async function getAdapter(name) {
  if (name === 'mock') {
    return mockAdapter;
  }
  // 真实适配器按需动态导入，避免 mock 模式下触碰网络相关代码
  const mod = await import('./adapters/openai_compat_adapter.mjs');
  return mod;
}

// ---------- 统计工具 ----------
function ratio(count, total) {
  if (total === 0) return 0;
  return Number((count / total).toFixed(4));
}

// nearest-rank 分位数：k = ceil(p/100 * n)，取排序后第 k-1 个
function percentile(sortedAsc, p) {
  const n = sortedAsc.length;
  if (n === 0) return null;
  const k = Math.ceil((p / 100) * n);
  const idx = Math.min(Math.max(k - 1, 0), n - 1);
  return sortedAsc[idx];
}

function summarize(records) {
  const total = records.length;
  const outcomeCounts = { direct: 0, repaired: 0, rule_fallback: 0, failed: 0 };
  let softOkCount = 0;
  let factConsistentCount = 0;
  let forbiddenHitCount = 0;
  const errorKindCounts = {};
  const latencies = [];
  let promptTokensTotal = 0;
  let completionTokensTotal = 0;
  let usageSamples = 0;

  for (const r of records) {
    if (outcomeCounts[r.outcome] !== undefined) {
      outcomeCounts[r.outcome] += 1;
    }
    if (r.softOk === true) softOkCount += 1;
    if (r.factConsistent === true) factConsistentCount += 1;
    if (Array.isArray(r.forbiddenHits) && r.forbiddenHits.length > 0) {
      forbiddenHitCount += 1;
    }
    const ek = r.errorKind === null || r.errorKind === undefined ? 'none' : r.errorKind;
    errorKindCounts[ek] = (errorKindCounts[ek] || 0) + 1;
    if (typeof r.latencyMs === 'number' && Number.isFinite(r.latencyMs)) {
      latencies.push(r.latencyMs);
    }
    // token 用量只在拿到实际 usage 时累计，不用 0 冒充
    if (typeof r.promptTokens === 'number' && typeof r.completionTokens === 'number') {
      promptTokensTotal += r.promptTokens;
      completionTokensTotal += r.completionTokens;
      usageSamples += 1;
    }
  }

  const outcomeRatios = {};
  for (const key of OUTCOMES) {
    outcomeRatios[key] = ratio(outcomeCounts[key], total);
  }

  const tokenUsage =
    usageSamples === 0
      ? null
      : {
          promptTokensTotal,
          completionTokensTotal,
          tokensTotal: promptTokensTotal + completionTokensTotal,
          promptTokensAvg: Number((promptTokensTotal / usageSamples).toFixed(1)),
          completionTokensAvg: Number((completionTokensTotal / usageSamples).toFixed(1)),
          usageSamples,
        };

  return {
    total,
    outcomeCounts,
    outcomeRatios,
    softOkCount,
    softOkRatio: ratio(softOkCount, total),
    factConsistentCount,
    factConsistentRatio: ratio(factConsistentCount, total),
    forbiddenHitCount,
    errorKindCounts,
    latencies,
    tokenUsage,
  };
}

function printSummary(summary, adapterName, label) {
  const { total } = summary;
  console.log('');
  console.log(`===== 摘要${label ? `（${label}）` : ''} =====`);
  console.log(`样本总数：${total}`);
  console.log('四类结果计数与占比：');
  for (const key of OUTCOMES) {
    const c = summary.outcomeCounts[key];
    const pct = (summary.outcomeRatios[key] * 100).toFixed(2);
    console.log(`  ${key.padEnd(14)} ${String(c).padStart(4)} 条  ${pct}%`);
  }
  console.log(`软 Schema 通过：${summary.softOkCount} 条  ${(summary.softOkRatio * 100).toFixed(2)}%`);
  console.log(`事实一致：${summary.factConsistentCount} 条  ${(summary.factConsistentRatio * 100).toFixed(2)}%`);
  console.log(`触发禁止表述：${summary.forbiddenHitCount} 条`);

  const ekKeys = Object.keys(summary.errorKindCounts).sort();
  if (ekKeys.length === 0) {
    console.log('错误类型分布：无');
  } else {
    console.log('错误类型分布：');
    for (const k of ekKeys) {
      console.log(`  ${k.padEnd(14)} ${summary.errorKindCounts[k]} 条`);
    }
  }

  if (adapterName === 'openai') {
    const sorted = [...summary.latencies].sort((a, b) => a - b);
    if (sorted.length === 0) {
      console.log('延迟：无有效样本');
    } else {
      const p50 = percentile(sorted, 50);
      const p95 = percentile(sorted, 95);
      console.log(`延迟（ms）：p50=${p50}  p95=${p95}  n=${sorted.length}`);
    }
    // token 与成本
    const t = summary.tokenUsage;
    if (t === null) {
      console.log('token：未取得 usage 字段（接口未返回用量）');
    } else {
      console.log(
        `token：prompt=${t.promptTokensTotal}  completion=${t.completionTokensTotal}  合计=${t.tokensTotal}  有效样本=${t.usageSamples}`,
      );
      console.log(`token 均值：prompt=${t.promptTokensAvg}  completion=${t.completionTokensAvg}`);
      // 成本估算：单价按「元 / 百万 token」，未配置则不算
      const priceIn = parseFloat(process.env.FOCUSBENCH_PRICE_INPUT || '');
      const priceOut = parseFloat(process.env.FOCUSBENCH_PRICE_OUTPUT || '');
      if (Number.isFinite(priceIn) || Number.isFinite(priceOut)) {
        const pin = Number.isFinite(priceIn) ? priceIn : 0;
        const pout = Number.isFinite(priceOut) ? priceOut : 0;
        const cost = t.promptTokensTotal / 1e6 * pin + t.completionTokensTotal / 1e6 * pout;
        console.log(`估算成本：${cost.toFixed(4)} 元（单价：输入 ${pin} 元/百万 token，输出 ${pout} 元/百万 token）`);
      } else {
        console.log('未配置单价（FOCUSBENCH_PRICE_INPUT / FOCUSBENCH_PRICE_OUTPUT），未计算成本');
      }
    }
  } else {
    console.log('mock 模式不统计真实延迟');
    console.log('mock 模式不统计 token 用量与成本');
  }
}

// ---------- CSV 生成 ----------
function csvEscape(value) {
  if (value === null || value === undefined) return '';
  const s = String(value);
  if (/[",\r\n]/.test(s)) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

function buildCsv(records) {
  const header = [
    'sample_id',
    'task_type',
    'difficulty',
    'outcome',
    'source',
    'softOk',
    'factConsistent',
    'latencyMs',
    'promptTokens',
    'completionTokens',
    'httpStatus',
    'errorKind',
  ];
  const lines = [header.join(',')];
  for (const r of records) {
    lines.push(
      [
        csvEscape(r.sample_id),
        csvEscape(r.task_type),
        csvEscape(r.difficulty),
        csvEscape(r.outcome),
        csvEscape(r.source),
        csvEscape(r.softOk),
        csvEscape(r.factConsistent),
        csvEscape(r.latencyMs),
        csvEscape(r.promptTokens),
        csvEscape(r.completionTokens),
        csvEscape(r.httpStatus),
        csvEscape(r.errorKind),
      ].join(','),
    );
  }
  // CRLF 换行，便于 Excel 直接打开
  return lines.join('\r\n') + '\r\n';
}

// ---------- 主流程 ----------
async function runOnce(adapter, datasets) {
  const records = [];
  for (const ds of datasets) {
    for (const sample of ds.samples) {
      const adapterResult = await adapter.call(sample);
      const scored = scoreSample(sample, adapterResult);
      // 附加 token 用量（mock 或接口未返回 usage 时为 null）
      const usage = adapterResult && adapterResult.usage ? adapterResult.usage : null;
      records.push({
        ...scored,
        promptTokens: usage ? usage.promptTokens : null,
        completionTokens: usage ? usage.completionTokens : null,
        // 保留原始响应供事后核查；写报告时会转成文件路径，不直接塞进 JSON
        _raw: adapterResult && typeof adapterResult.raw === 'string' ? adapterResult.raw : null,
      });
    }
  }
  return records;
}

// 把未通过事实一致的样本原始响应落盘，便于事后核查
async function dumpFailedRaw(records, outDir, prefix) {
  const dir = path.join(outDir, 'failed_raw');
  for (const r of records) {
    const raw = r._raw;
    if (r.factConsistent === true) continue;
    if (typeof raw !== 'string' || raw === '') continue;
    if (!existsSync(dir)) {
      await mkdir(dir, { recursive: true });
    }
    const fname = `${prefix}${r.sample_id}.txt`;
    await writeFile(path.join(dir, fname), raw, 'utf8');
    r.rawFile = path.join('failed_raw', fname);
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const runStartedAt = new Date().toISOString();
  const adapter = await getAdapter(opts.adapter);
  const datasets = await loadDatasets(opts.dataset);

  const expectedTotal = datasets.reduce((acc, d) => acc + d.samples.length, 0);
  if (expectedTotal === 0) {
    throw new Error('数据集为空，无法运行基准');
  }

  const repeatRuns = [];
  let lastRecords = null;
  let lastSummary = null;

  for (let run = 1; run <= opts.repeat; run += 1) {
    const records = await runOnce(adapter, datasets);
    const summary = summarize(records);

    // 断言：四类之和必须等于样本总数
    const sum =
      summary.outcomeCounts.direct +
      summary.outcomeCounts.repaired +
      summary.outcomeCounts.rule_fallback +
      summary.outcomeCounts.failed;
    if (sum !== summary.total) {
      throw new Error(`断言失败：四类之和 ${sum} 不等于样本总数 ${summary.total}`);
    }
    if (summary.total !== expectedTotal) {
      throw new Error(`断言失败：评分条数 ${summary.total} 不等于样本总数 ${expectedTotal}`);
    }

    const label = opts.repeat > 1 ? `第 ${run}/${opts.repeat} 轮` : '';
    printSummary(summary, opts.adapter, label);

    // 每轮都落盘该轮未通过的原始响应（重复运行时前缀 runN_，避免互相覆盖）
    const outDirForDump = path.dirname(
      path.isAbsolute(opts.out) ? opts.out : path.join(__dirname, opts.out),
    );
    await dumpFailedRaw(records, outDirForDump, opts.repeat > 1 ? `run${run}_` : '');

    repeatRuns.push({
      run,
      outcomeCounts: { ...summary.outcomeCounts },
      total: summary.total,
    });

    lastRecords = records;
    lastSummary = summary;
  }

  // 可复现性提示：多轮时比较四类计数是否一致
  if (opts.repeat > 1) {
    const first = JSON.stringify(repeatRuns[0].outcomeCounts);
    const allSame = repeatRuns.every((r) => JSON.stringify(r.outcomeCounts) === first);
    console.log('');
    console.log(allSame ? '可复现性：各轮四类计数完全一致。' : '可复现性：各轮四类计数存在差异（真实 API 可能非确定性）。');
  }

  // ---------- 写报告 ----------
  const outBase = path.isAbsolute(opts.out)
    ? opts.out
    : path.join(__dirname, opts.out);
  const outDir = path.dirname(outBase);
  if (!existsSync(outDir)) {
    await mkdir(outDir, { recursive: true });
  }
  const jsonPath = outBase.endsWith('.json') ? outBase : outBase + '.json';
  const csvPath = outBase.endsWith('.csv') ? outBase.replace(/\.csv$/, '.json') : outBase + '.csv';

  const sortedLatencies = [...lastSummary.latencies].sort((a, b) => a - b);
  const latencyReport =
    opts.adapter === 'openai'
      ? {
          p50: percentile(sortedLatencies, 50),
          p95: percentile(sortedLatencies, 95),
          n: sortedLatencies.length,
        }
      : null;

  // 清掉内存里的原始响应，避免把长文本塞进 JSON 正文
  for (const r of lastRecords) {
    delete r._raw;
  }

  const report = {
    meta: {
      adapter: opts.adapter,
      dataset: opts.dataset,
      repeat: opts.repeat,
      generatedAt: new Date().toISOString(),
      runStartedAt,
      nodeVersion: process.version,
      model: opts.adapter === 'openai' ? (process.env.FOCUSBENCH_MODEL || 'deepseek-chat') : 'mock',
      baseUrlHost: opts.adapter === 'openai' ? hostOnly(process.env.FOCUSBENCH_BASE_URL || 'https://api.deepseek.com') : '',
      temperature: opts.adapter === 'openai' ? 0.4 : null,
      maxTokens: opts.adapter === 'openai' ? 900 : null,
      tokenUsage: lastSummary.tokenUsage,
      totalSamples: lastSummary.total,
      outcomeCounts: lastSummary.outcomeCounts,
      outcomeRatios: lastSummary.outcomeRatios,
      softOkCount: lastSummary.softOkCount,
      softOkRatio: lastSummary.softOkRatio,
      factConsistentCount: lastSummary.factConsistentCount,
      factConsistentRatio: lastSummary.factConsistentRatio,
      forbiddenHitCount: lastSummary.forbiddenHitCount,
      errorKindCounts: lastSummary.errorKindCounts,
      latency: latencyReport,
    },
    repeatRuns,
    records: lastRecords,
  };

  await writeFile(jsonPath, JSON.stringify(report, null, 2), 'utf8');
  await writeFile(csvPath, buildCsv(lastRecords), 'utf8');

  console.log('');
  console.log(`JSON 报告：${path.resolve(jsonPath)}`);
  console.log(`CSV 报告：${path.resolve(csvPath)}`);
}

main().catch((err) => {
  console.error('运行失败：' + (err && err.message ? err.message : String(err)));
  process.exit(1);
});
