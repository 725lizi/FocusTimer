// ============================================================================
// verify_live_independent.mjs —— DeepSeek 20 次实测的独立复核
//
// 不相信 bench_core 自己写出的 summary，从原始 runs + 底稿重新独立计算：
//   1) 每条 rawText 重新走 reliability_engine 的 analyze，核对 g2_outcome/g3_source；
//   2) 独立 extract→normalize→structuralOk 得到树，重新提取树节点数字，
//      对照独立重建的白名单核对事实一致性；
//   3) 独立 nearest-rank 重算 p50/p95，与产物 summary 比对；
//   4) 核对总数、HTTP 状态、三类计数。
// 只依赖 Node 内置能力 + reliability_engine.mjs。
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  analyze,
  extract,
  normalize,
  structuralOk,
} from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const results = JSON.parse(fs.readFileSync(path.join(HERE, 'deepseek_bench_results.json'), 'utf8'));
const fixturesDoc = JSON.parse(fs.readFileSync(path.join(HERE, 'bench_fixtures.json'), 'utf8'));

// —— 独立重建每个底稿的白名单（与 bench_core 相同规则，但这里独立实现）——
function collectNumbers(value, out) {
  if (typeof value === 'number' && Number.isFinite(value)) out.add(value);
  else if (Array.isArray(value)) for (const v of value) collectNumbers(v, out);
  else if (value !== null && typeof value === 'object') for (const k of Object.keys(value)) collectNumbers(value[k], out);
  return out;
}
const whitelistById = new Map();
for (const f of fixturesDoc.fixtures) {
  const wl = collectNumbers(f, new Set());
  wl.add(0);
  if (f.totalMinutes === 0) wl.add(25); // 空数据底稿提示词内嵌示例 25
  whitelistById.set(f.id, wl);
}

function walkText(node, out) {
  if (node && typeof node === 'object') {
    if (typeof node.text === 'string') out.push(node.text);
    for (const c of node.children || []) walkText(c, out);
  }
  return out;
}

function nearestRank(sortedAsc, p) {
  const k = Math.ceil((p / 100) * sortedAsc.length);
  return sortedAsc[Math.max(0, Math.min(sortedAsc.length - 1, k - 1))];
}

let pass = 0;
let fail = 0;
function check(name, cond, detail = '') {
  if (cond) { pass += 1; console.log(`PASS  ${name}`); }
  else { fail += 1; console.log(`FAIL  ${name}  ${detail}`); }
}

const runs = results.runs;
check('run 总数 = 20', runs.length === 20, `实际 ${runs.length}`);

const independentOutcomes = { direct: 0, repaired: 0, fail: 0 };
const independentSources = { llm: 0, rule: 0 };
const latencies = [];
let allHttp200 = true;
let verdictMismatch = 0;
let factMismatch = 0;
let totalDeclared = 0;
let totalConsistent = 0;

for (const r of runs) {
  if (r.httpStatus !== 200) allHttp200 = false;
  if (typeof r.latencyMs === 'number') latencies.push(r.latencyMs);

  // 1) 独立重新判定
  const verdict = analyze(r.rawText || '');
  independentOutcomes[verdict.g2_outcome] += 1;
  independentSources[verdict.g3_source] += 1;
  if (verdict.g2_outcome !== r.g2_outcome || verdict.g3_source !== r.g3_source) {
    verdictMismatch += 1;
    console.log(`  判定不一致 #${r.index}: 独立=${verdict.g2_outcome}/${verdict.g3_source} 产物=${r.g2_outcome}/${r.g3_source}`);
  }

  // 2) 独立解析树并核对数字
  const wl = whitelistById.get(r.fixtureId);
  const ex = extract(r.rawText || '');
  let declared = 0;
  let consistent = 0;
  if (!ex.error) {
    const nz = normalize(ex.text);
    if (!nz.error && structuralOk(nz.tree)) {
      const texts = walkText(nz.tree, []);
      for (const t of texts) {
        for (const m of t.match(/\d+/g) || []) {
          const n = Number(m);
          declared += 1;
          if (wl.has(n)) consistent += 1;
          else console.log(`  白名单外数字 #${r.index}: ${n}`);
        }
      }
    }
  }
  totalDeclared += declared;
  totalConsistent += consistent;
  if (declared !== r.numbersDeclared || consistent !== r.numbersConsistent) {
    factMismatch += 1;
    console.log(`  事实计数不一致 #${r.index}: 独立=${consistent}/${declared} 产物=${r.numbersConsistent}/${r.numbersDeclared}`);
  }
}

check('全部 HTTP 200', allHttp200);
check('独立判定与产物完全一致（20 条）', verdictMismatch === 0, `${verdictMismatch} 条不一致`);
check('独立事实核对与产物完全一致', factMismatch === 0, `${factMismatch} 条不一致`);
check('独立三类：direct=20 / repaired=0 / fail=0',
  independentOutcomes.direct === 20 && independentOutcomes.repaired === 0 && independentOutcomes.fail === 0,
  JSON.stringify(independentOutcomes));
check('独立来源：llm=20 / rule=0',
  independentSources.llm === 20 && independentSources.rule === 0, JSON.stringify(independentSources));
check(`独立事实一致：${totalConsistent}/${totalDeclared} = 100%`,
  totalDeclared === totalConsistent && totalDeclared > 0, `${totalConsistent}/${totalDeclared}`);

// 3) 独立重算 p50/p95
latencies.sort((a, b) => a - b);
const p50 = nearestRank(latencies, 50);
const p95 = nearestRank(latencies, 95);
const s = results.summary;
check(`独立 p50 = ${p50} 与产物 ${s.latency.p50} 一致`, p50 === s.latency.p50);
check(`独立 p95 = ${p95} 与产物 ${s.latency.p95} 一致`, p95 === s.latency.p95);
check('产物 noKeyStored = true', results._meta.noKeyStored === true);

console.log('');
console.log(`独立复核完成：PASS ${pass} 项，FAIL ${fail} 项`);
console.log(`独立 p50=${p50}ms  p95=${p95}ms  事实=${totalConsistent}/${totalDeclared}`);
process.exit(fail === 0 ? 0 : 1);
