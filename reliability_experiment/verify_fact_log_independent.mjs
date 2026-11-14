// 独立验证脚本（助手编写，不 import DeepSeek 的 fact_check.mjs / run_logging.mjs）
// 只 import 已在 #87 独立复核过的 reliability_engine（真实源码复刻）。
// 目标：用自己的逻辑独立复算事实核查与日志/案例库，并与 DeepSeek 落盘文件交叉对照。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyze, extract, normalize, buildRuleTree } from './reliability_engine.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const read = (f) => fs.readFileSync(path.join(HERE, f), 'utf8');
const corpus = read('fault_corpus.jsonl').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
const fixture = JSON.parse(read('summary_fixture.json'));
const primary = fixture.primary;
const content = corpus.filter((s) => s.kind === 'content').sort((a, b) => (a.id < b.id ? -1 : 1));
const network = corpus.filter((s) => s.kind !== 'content');

let failures = 0;
const assert = (cond, msg) => { console.log((cond ? 'PASS ' : 'FAIL ') + msg); if (!cond) failures++; };

// ---- 独立白名单：自己从 primary 递归取数，不看 fact_check 的实现 ----
const myWhitelist = new Set();
(function collect(v) {
  if (typeof v === 'number' && Number.isFinite(v)) myWhitelist.add(v);
  else if (Array.isArray(v)) v.forEach(collect);
  else if (v && typeof v === 'object') Object.keys(v).forEach((k) => collect(v[k]));
})(primary);
myWhitelist.add(0);
const subjectMinutes = new Map(primary.subjects.map((s) => [s.name, s.minutes]));

// 独立得到最终树（与真实链路一致：fail 走规则树，否则 extract→normalize）
function finalTree(sample) {
  const j = analyze(sample.raw);
  if (j.g2_outcome === 'fail') return { tree: buildRuleTree(fixture), from: 'rule' };
  const ex = extract(sample.raw);
  const nz = normalize(ex.text);
  return { tree: nz.tree, from: 'llm' };
}
function* walk(n) {
  yield n;
  if (Array.isArray(n.children)) for (const c of n.children) yield* walk(c);
}

// ---- Part 1：独立复算事实核查 ----
let myClaims = 0, myBad = 0, myFullTrees = 0, myFromLlm = 0, myFromRule = 0;
const typeCount = { number: 0, subject: 0, direction: 0 };
for (const s of content) {
  const { tree, from } = finalTree(s);
  if (from === 'llm') myFromLlm++; else myFromRule++;
  let treeBad = 0;
  for (const node of walk(tree)) {
    const text = node.text || '';
    // A 数字：独立正则
    const nums = (text.match(/\d+/g) || []).map(Number);
    for (const n of nums) {
      myClaims++; typeCount.number++;
      if (!myWhitelist.has(n)) { myBad++; treeBad++; }
    }
    // B 科目：同句带数字则核对该科目分钟
    for (const [name, mins] of subjectMinutes) {
      if (text.includes(name) && nums.length > 0) {
        myClaims++; typeCount.subject++;
        if (nums[0] !== mins) { myBad++; treeBad++; }
      }
    }
    // C 方向：周对比语境 + 方向词
    if (/环比|比上周|较上周|上周|本周/.test(text)) {
      let dir = null;
      if (/减少|下降|降低|下滑|回落/.test(text)) dir = 'down';
      else if (/持平|不变/.test(text)) dir = 'flat';
      else if (/增加|上升|增长|提升|上涨/.test(text)) dir = 'up';
      if (dir) { myClaims++; typeCount.direction++; if (dir !== 'up') { myBad++; treeBad++; } }
    }
  }
  if (treeBad === 0) myFullTrees++;
}

console.log('--- Part 1 独立复算事实核查 ---');
console.log('我的白名单:', Array.from(myWhitelist).sort((a, b) => a - b).join(','));
console.log('我的计数: 声明', myClaims, '不一致', myBad, '完全一致树', myFullTrees,
  '| 类型', JSON.stringify(typeCount), '| 云端', myFromLlm, '规则', myFromRule);
assert(myClaims === 344 && myBad === 0, '独立复算：344 条声明、0 不一致');
assert(myFullTrees === 60 && myFromLlm === 51 && myFromRule === 9, '独立复算：60 棵完全一致树（云端51/规则9）');
assert(typeCount.number === 256 && typeCount.subject === 56 && typeCount.direction === 32,
  '独立复算分类：number256/subject56/direction32');

// 与 DeepSeek 落盘 JSON 交叉对照
const fc = JSON.parse(read('fact_check_results.json'));
assert(fc.metrics.claims.total === myClaims && fc.metrics.claims.rate === 100,
  'fact_check_results.json 总声明数与一致率与独立复算一致');
assert(fc.metrics.trees.fullyConsistent === myFullTrees,
  'fact_check_results.json 完全一致树数与独立复算一致');
assert(JSON.stringify(fc.whitelist.numbers) === JSON.stringify(Array.from(myWhitelist).sort((a, b) => a - b)),
  '白名单内容与独立生成完全相同');

// 反向破坏：我的独立逻辑必须能抓到坏树（证明不是永远 100%）
const good = buildRuleTree(fixture);
const badNum = JSON.parse(JSON.stringify(good)); badNum.children[0].children[0].text = '本周 999 分钟';
let caught999 = false;
for (const node of walk(badNum)) for (const n of ((node.text || '').match(/\d+/g) || []).map(Number))
  if (!myWhitelist.has(n)) caught999 = true;
assert(caught999, '反向测试：独立逻辑能抓到白名单外数字 999');

// ---- Part 2：独立核对日志与案例库 ----
console.log('--- Part 2 独立核对日志/案例库 ---');
const logsDoc = JSON.parse(read('run_logs.json'));
const logs = logsDoc.logs;
assert(logs.length === 80, 'run_logs 恰好 80 条');
const ids = new Set(logs.map((l) => l.sampleId));
assert(ids.size === 80 && corpus.every((s) => ids.has(s.id)), '80 条日志 id 与 corpus 完全对应、无重复无遗漏');
const cLogs = logs.filter((l) => l.kind === 'content');
const nLogs = logs.filter((l) => l.kind === 'network');
const cnt = (list, k) => list.reduce((a, l) => ((a[l[k]] = (a[l[k]] || 0) + 1), a), {});
const co = cnt(cLogs, 'outcome'), no = cnt(nLogs, 'outcome');
assert(co.direct === 27 && co.repaired === 24 && co.rule === 9, '内容日志 direct27/repaired24/rule9');
assert(no.rule === 18 && no.cancelled === 2, '网络日志 降级18/cancelled2');

// 独立抽查 6 条日志，回到原始样本核对 outcome
let spotOk = true;
for (const sid of ['S01', 'S21', 'S28', 'S40', 'B14', 'B40']) {
  const sample = corpus.find((s) => s.id === sid);
  const log = logs.find((l) => l.sampleId === sid);
  if (sample.kind === 'content') {
    const j = analyze(sample.raw);
    const expect = j.g2_outcome === 'fail' ? 'rule' : j.g2_outcome;
    if (log.outcome !== expect) spotOk = false;
  } else {
    const expect = sample.error_kind === 'cancelled' ? 'cancelled' : 'rule';
    if (log.outcome !== expect) spotOk = false;
  }
}
assert(spotOk, '抽查 6 条日志 outcome 与原始样本独立判定一致');

// 案例库独立核对
const casesDoc = JSON.parse(read('failure_cases.json'));
const cases = casesDoc.cases;
assert(cases.length === 53, '失败案例库恰好 53 条');
assert(cases.every((c) => c.outcome !== 'direct'), '案例库不含任何 direct 案例');
const caseIds = new Set(cases.map((c) => c.sampleId));
const expectedCaseIds = logs.filter((l) => l.outcome !== 'direct').map((l) => l.sampleId);
assert(expectedCaseIds.every((id) => caseIds.has(id)) && caseIds.size === expectedCaseIds.length,
  '案例库 id 集合 = 日志中所有非 direct 样本');
// 内容类案例必须附 raw、网络类无 raw
const rawRuleOk = cases.every((c) => (c.kind === 'content' ? typeof c.raw === 'string' : !('raw' in c)));
assert(rawRuleOk, '内容案例附 raw、网络案例无 raw');

console.log('-------------------------------------------');
console.log(failures === 0 ? 'ALL INDEPENDENT CHECKS PASSED' : `${failures} CHECK(S) FAILED`);
process.exitCode = failures === 0 ? 0 : 1;
