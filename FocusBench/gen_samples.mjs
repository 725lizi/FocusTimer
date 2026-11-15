// FocusBench 确定性样例生成脚本
// 运行：node gen_samples.mjs
// 仅使用 Node 内置模块；不依赖 Math.random / 系统时钟 / 环境变量。
// 输出：data/samples.dev.jsonl（60 条）、data/samples.locked.jsonl（20 条）

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---------- 固定种子线性同余发生器 ----------
const LCG_A = 1103515245;
const LCG_C = 12345;
const LCG_M = 2147483648; // 2^31

function makeRng(seed) {
  let state = seed >>> 0;
  return function next() {
    state = (LCG_A * state + LCG_C) % LCG_M;
    return state;
  };
}

// 取 [0, n) 的整数
function randInt(rng, n) {
  return rng() % n;
}

// 取 [lo, hi] 的整数（含端点）
function randRange(rng, lo, hi) {
  return lo + randInt(rng, hi - lo + 1);
}

// ---------- 读取底稿 ----------
const FIXTURE_PATH = join(__dirname, '..', 'reliability_experiment', 'bench_fixtures.json');
const rawFixture = readFileSync(FIXTURE_PATH, 'utf8');
const fixtureDoc = JSON.parse(rawFixture);
const fixtures = fixtureDoc.fixtures;
if (!Array.isArray(fixtures) || fixtures.length === 0) {
  throw new Error('底稿 fixtures 为空或格式错误');
}

// 科目池（严格限定）
const SUBJECT_POOL = ['数学', '英语', '物理', '高数', '专业课', '阅读'];

// ---------- 派生变体 ----------
// 在底稿基础上按比例缩放 totalMinutes，并同步重算所有派生字段。
// 保证 subjects 的 minutes 之和等于 totalMinutes。
function deriveVariant(base, rng) {
  // 缩放比例：0.5 ~ 1.8 之间，步进 0.1
  const scaleTenths = randRange(rng, 5, 18); // 5..18 => 0.5..1.8
  const baseTotal = base.totalMinutes;

  let totalMinutes;
  if (baseTotal === 0) {
    // 零负荷底稿：保持 0，或生成一个小的正数（0 或 30~120）
    totalMinutes = randInt(rng, 2) === 0 ? 0 : randRange(rng, 30, 120);
  } else {
    totalMinutes = Math.round((baseTotal * scaleTenths) / 10);
    if (totalMinutes < 0) totalMinutes = 0;
  }

  // lastWeekMinutes：以底稿 lastWeek 为基准，按相近比例缩放，再叠加轻微扰动
  let lastWeekMinutes;
  if (base.lastWeekMinutes === 0) {
    lastWeekMinutes = totalMinutes === 0 ? 0 : randRange(rng, 0, Math.max(1, totalMinutes));
  } else {
    const lastScaleTenths = randRange(rng, 5, 18);
    lastWeekMinutes = Math.round((base.lastWeekMinutes * lastScaleTenths) / 10);
    if (lastWeekMinutes < 0) lastWeekMinutes = 0;
  }

  // weekOverWeekPercent = round((total - last) / last * 100)，last 为 0 记 0
  let weekOverWeekPercent;
  if (lastWeekMinutes === 0) {
    weekOverWeekPercent = 0;
  } else {
    weekOverWeekPercent = Math.round(((totalMinutes - lastWeekMinutes) / lastWeekMinutes) * 100);
  }

  // sessionCount：total 为 0 时为 0，否则 1~12
  let sessionCount;
  if (totalMinutes === 0) {
    sessionCount = 0;
  } else {
    sessionCount = randRange(rng, 1, 12);
  }

  // activeDays：0..min(7, sessionCount)，total 为 0 时为 0
  let activeDays;
  if (totalMinutes === 0 || sessionCount === 0) {
    activeDays = 0;
  } else {
    const maxDays = Math.min(7, sessionCount);
    activeDays = randRange(rng, 1, maxDays);
  }

  // avgMinutesPerSession = round(total / count)，count 为 0 记 0
  let avgMinutesPerSession;
  if (sessionCount === 0) {
    avgMinutesPerSession = 0;
  } else {
    avgMinutesPerSession = Math.round(totalMinutes / sessionCount);
  }

  // interruptCount：0..sessionCount
  let interruptCount;
  if (sessionCount === 0) {
    interruptCount = 0;
  } else {
    interruptCount = randRange(rng, 0, sessionCount);
  }

  // subjects：从科目池挑选 1..4 个，分配 minutes，总和必须等于 totalMinutes
  let subjects;
  if (totalMinutes === 0) {
    // 零负荷：保留 1 个科目，minutes 为 0
    const name = SUBJECT_POOL[randInt(rng, SUBJECT_POOL.length)];
    subjects = [{ name, minutes: 0 }];
  } else {
    const count = randRange(rng, 1, Math.min(4, SUBJECT_POOL.length));
    // 从池中不重复抽取 count 个科目
    const pool = SUBJECT_POOL.slice();
    const picked = [];
    for (let i = 0; i < count; i++) {
      const idx = randInt(rng, pool.length);
      picked.push(pool[idx]);
      pool.splice(idx, 1);
    }
    // 随机切分 totalMinutes 到 count 份，每份至少 1
    const parts = new Array(count).fill(1);
    let remaining = totalMinutes - count;
    if (remaining < 0) {
      // totalMinutes 小于科目数：退化为单科目
      subjects = [{ name: picked[0], minutes: totalMinutes }];
    } else {
      for (let i = 0; i < count; i++) {
        const take = randInt(rng, remaining + 1);
        parts[i] += take;
        remaining -= take;
      }
      // 剩余全给第一个
      parts[0] += remaining;
      subjects = picked.map((name, i) => ({ name, minutes: parts[i] }));
    }
  }

  // 校验：subjects 之和必须等于 totalMinutes
  const sum = subjects.reduce((acc, s) => acc + s.minutes, 0);
  if (sum !== totalMinutes) {
    // 差多少补到第一个科目
    const diff = totalMinutes - sum;
    subjects[0].minutes += diff;
  }
  const finalSum = subjects.reduce((acc, s) => acc + s.minutes, 0);
  if (finalSum !== totalMinutes) {
    throw new Error(`subjects 之和(${finalSum}) ≠ totalMinutes(${totalMinutes})`);
  }

  return {
    totalMinutes,
    lastWeekMinutes,
    weekOverWeekPercent,
    sessionCount,
    activeDays,
    avgMinutesPerSession,
    interruptCount,
    subjects
  };
}

// ---------- fact_checklist 生成 ----------
// 通用数字白名单基数（允许出现在文案里的合法数字）
const BASE_NUMBERS = [0, 1, 2, 3, 4, 8, 10, 16, 20, 24, 60];

function buildFactChecklist(input) {
  const nums = new Set();
  nums.add(input.totalMinutes);
  nums.add(input.lastWeekMinutes);
  nums.add(Math.abs(input.weekOverWeekPercent));
  nums.add(input.sessionCount);
  nums.add(input.activeDays);
  nums.add(input.avgMinutesPerSession);
  nums.add(input.interruptCount);
  for (const s of input.subjects) {
    nums.add(s.minutes);
  }
  for (const b of BASE_NUMBERS) {
    nums.add(b);
  }
  const numbers = Array.from(nums).sort((a, b) => a - b);

  const subjects = input.subjects.map((s) => s.name);

  let direction;
  if (input.totalMinutes === 0 && input.lastWeekMinutes === 0) {
    direction = 'none';
  } else if (input.weekOverWeekPercent > 0) {
    direction = 'up';
  } else if (input.weekOverWeekPercent < 0) {
    direction = 'down';
  } else {
    direction = 'flat';
  }

  return { numbers, subjects, direction };
}

// ---------- 常量 ----------
const EXPECTED_SCHEMA = {
  depthMin: 2,
  depthMax: 3,
  nodeMin: 8,
  nodeMax: 20,
  leafMax: 16,
  branches: 4
};

const BASE_FORBIDDEN = ['效率提升百分比', '健康诊断', '心理诊断', '疾病', '治疗建议', '模型排名'];

const FAULT_TYPES = [
  'network',
  'timeout',
  'unauthorized',
  'rate_limited',
  'server',
  'bad_request',
  'empty',
  'cancelled'
];

// task_type 配额（按顺序切片分配）
const DEV_QUOTA = [
  ['regular', 22],
  ['complex', 14],
  ['anomaly', 12],
  ['longtext', 4],
  ['fault', 8]
];
const LOCKED_QUOTA = [
  ['regular', 8],
  ['complex', 6],
  ['anomaly', 3],
  ['longtext', 1],
  ['fault', 2]
];

// 按配额展开成有序的 task_type 列表
function expandQuota(quota) {
  const list = [];
  for (const [type, count] of quota) {
    for (let i = 0; i < count; i++) list.push(type);
  }
  return list;
}

// ---------- 生成单条样例 ----------
function buildSample(sampleId, taskType, base, rng, faultIndex) {
  const input = deriveVariant(base, rng);
  const factChecklist = buildFactChecklist(input);

  // difficulty 规则
  let difficulty;
  if (taskType === 'regular') {
    // 按序号奇偶：奇数 easy，偶数 normal
    const seq = parseInt(sampleId.slice(-3), 10);
    difficulty = seq % 2 === 1 ? 'easy' : 'normal';
  } else if (taskType === 'complex' || taskType === 'anomaly' || taskType === 'longtext') {
    difficulty = 'hard';
  } else {
    // fault
    difficulty = 'normal';
  }

  // fault_type
  let faultType = null;
  if (taskType === 'fault') {
    faultType = FAULT_TYPES[faultIndex % FAULT_TYPES.length];
  }

  // forbidden_claims
  const forbidden = BASE_FORBIDDEN.slice();
  if (taskType === 'longtext') {
    forbidden.push('过度细节');
  }

  // 键顺序固定
  return {
    sample_id: sampleId,
    input,
    task_type: taskType,
    expected_schema: { ...EXPECTED_SCHEMA },
    fact_checklist: factChecklist,
    forbidden_claims: forbidden,
    difficulty,
    fault_type: faultType,
    source_type: 'synthetic'
  };
}

// ---------- 生成一个数据集 ----------
// seen：跨数据集共享的 input 签名集合，用于保证 dev 与 locked 不出现相同输入。
function generateDataset(prefix, quota, seed, seen) {
  const taskTypes = expandQuota(quota);
  const rng = makeRng(seed);
  const samples = [];
  let faultIndex = 0;

  for (let i = 0; i < taskTypes.length; i++) {
    const seq = i + 1;
    const sampleId = `${prefix}-${String(seq).padStart(3, '0')}`;
    const taskType = taskTypes[i];
    // 底稿轮转选取；若派生结果与已有输入重复，换下一份底稿并继续推进随机数，直到脱重
    let sample = buildSample(sampleId, taskType, fixtures[i % fixtures.length], rng, faultIndex);
    let tries = 0;
    while (seen.has(inputSignature(sample.input)) && tries < 500) {
      tries += 1;
      sample = buildSample(sampleId, taskType, fixtures[(i + tries) % fixtures.length], rng, faultIndex);
    }
    if (seen.has(inputSignature(sample.input))) {
      throw new Error(`${sampleId} 无法生成不重复的输入（已尝试 ${tries} 次），请扩大底稿或参数范围`);
    }
    seen.add(inputSignature(sample.input));
    if (taskType === 'fault') faultIndex++;
    samples.push(sample);
  }

  return samples;
}

// input 的稳定签名：键顺序固定，用于去重与跨集合比对
function inputSignature(input) {
  return JSON.stringify({
    totalMinutes: input.totalMinutes,
    lastWeekMinutes: input.lastWeekMinutes,
    weekOverWeekPercent: input.weekOverWeekPercent,
    sessionCount: input.sessionCount,
    activeDays: input.activeDays,
    avgMinutesPerSession: input.avgMinutesPerSession,
    interruptCount: input.interruptCount,
    subjects: input.subjects.map((s) => [s.name, s.minutes])
  });
}

// ---------- 序列化为 JSONL ----------
function toJsonl(samples) {
  const lines = samples.map((s) => JSON.stringify(s));
  return lines.join('\n') + '\n';
}

// ---------- 主流程 ----------
function main() {
  const seen = new Set(); // dev 与 locked 共用，保证两侧输入无重叠
  const devSamples = generateDataset('fb-dev', DEV_QUOTA, 20240607, seen);
  const lockedSamples = generateDataset('fb-locked', LOCKED_QUOTA, 20240608, seen);

  // 校验数量
  if (devSamples.length !== 60) {
    throw new Error(`dev 集数量错误：${devSamples.length} ≠ 60`);
  }
  if (lockedSamples.length !== 20) {
    throw new Error(`locked 集数量错误：${lockedSamples.length} ≠ 20`);
  }

  // 校验 id 唯一
  const devIds = new Set(devSamples.map((s) => s.sample_id));
  if (devIds.size !== devSamples.length) {
    throw new Error('dev 集存在重复 sample_id');
  }
  const lockedIds = new Set(lockedSamples.map((s) => s.sample_id));
  if (lockedIds.size !== lockedSamples.length) {
    throw new Error('locked 集存在重复 sample_id');
  }

  // 校验两侧 id 无交集
  for (const id of devIds) {
    if (lockedIds.has(id)) {
      throw new Error(`两侧 id 存在交集：${id}`);
    }
  }

  // 校验两侧 input 无交集（dev 与 locked 必须是不重复的输入，避免用同一底稿刷分）
  const devSigns = new Set(devSamples.map((s) => inputSignature(s.input)));
  const lockedSigns = new Set(lockedSamples.map((s) => inputSignature(s.input)));
  if (devSigns.size !== devSamples.length) {
    throw new Error('dev 集内部存在重复 input');
  }
  if (lockedSigns.size !== lockedSamples.length) {
    throw new Error('locked 集内部存在重复 input');
  }
  for (const sig of devSigns) {
    if (lockedSigns.has(sig)) {
      throw new Error('dev 与 locked 存在相同的 input');
    }
  }

  // 校验每条 subjects 之和
  for (const s of [...devSamples, ...lockedSamples]) {
    const sum = s.input.subjects.reduce((acc, x) => acc + x.minutes, 0);
    if (sum !== s.input.totalMinutes) {
      throw new Error(`${s.sample_id} subjects 之和(${sum}) ≠ totalMinutes(${s.input.totalMinutes})`);
    }
  }

  // 写出文件
  const dataDir = join(__dirname, 'data');
  mkdirSync(dataDir, { recursive: true });

  const devPath = join(dataDir, 'samples.dev.jsonl');
  const lockedPath = join(dataDir, 'samples.locked.jsonl');

  const devContent = toJsonl(devSamples);
  const lockedContent = toJsonl(lockedSamples);

  writeFileSync(devPath, devContent, { encoding: 'utf8' });
  writeFileSync(lockedPath, lockedContent, { encoding: 'utf8' });

  const devBytes = Buffer.byteLength(devContent, 'utf8');
  const lockedBytes = Buffer.byteLength(lockedContent, 'utf8');

  // 统计 task_type 计数
  function countByType(samples) {
    const map = {};
    for (const s of samples) {
      map[s.task_type] = (map[s.task_type] || 0) + 1;
    }
    return map;
  }

  const devCounts = countByType(devSamples);
  const lockedCounts = countByType(lockedSamples);

  console.log('=== FocusBench 样例生成完成 ===');
  console.log(`总数：dev=${devSamples.length}，locked=${lockedSamples.length}，合计=${devSamples.length + lockedSamples.length}`);  console.log('dev task_type 计数：', JSON.stringify(devCounts));
  console.log('locked task_type 计数：', JSON.stringify(lockedCounts));
  console.log(`文件字节数：samples.dev.jsonl=${devBytes}，samples.locked.jsonl=${lockedBytes}`);
}

main();
