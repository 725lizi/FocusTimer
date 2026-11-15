// 评分器确定性回归测试：不调用任何外部 API，纯粹用构造响应验证判定逻辑
// 运行：node tests/verify_scorer.mjs

import { scoreSample } from '../scorer.mjs';

let pass = 0;
let fail = 0;

function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    pass += 1;
    console.log(`PASS  ${name}`);
  } else {
    fail += 1;
    console.log(`FAIL  ${name}  期望=${JSON.stringify(expected)} 实际=${JSON.stringify(actual)}`);
  }
}

// 构造一棵符合软 Schema 的树：4 分支、8-20 节点、叶子 ≤16 字
function makeRaw(overallLines, subjectLines, qualityLines, actionLines) {
  const branch = (text, lines) => ({ text, children: lines.map((t) => ({ text: t })) });
  return JSON.stringify({
    text: '本周专注复盘',
    id: 'root',
    children: [
      branch('总体情况', overallLines),
      branch('科目分布', subjectLines),
      branch('专注质量', qualityLines),
      branch('下周行动', actionLines),
    ],
  });
}

function makeSample({ totalMinutes, lastWeekMinutes, wow, subjects, direction, numbers, directions }) {
  return {
    sample_id: 'unit',
    input: {
      totalMinutes,
      lastWeekMinutes,
      weekOverWeekPercent: wow,
      sessionCount: 5,
      activeDays: 3,
      avgMinutesPerSession: 51,
      interruptCount: 0,
      subjects: subjects.map((s) => ({ name: s.name, minutes: s.minutes })),
    },
    task_type: 'regular',
    expected_schema: { depthMin: 2, depthMax: 3, nodeMin: 8, nodeMax: 20, leafMax: 16, branches: 4 },
    fact_checklist: {
      numbers,
      subjects: subjects.map((s) => s.name),
      direction,
    },
    forbidden_claims: ['效率提升百分比', '健康诊断', '心理诊断', '疾病', '治疗建议', '模型排名'],
  };
}

const baseSubjects = [{ name: '数学', minutes: 255 }];

// ---- 1. 环比写作「环比264%」，无增减汉字，应为一致 ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const raw = makeRaw(
    ['总专注255分钟', '上周70分钟', '环比264%', '5次专注', '活跃3天'],
    ['数学255分钟'],
    ['平均每次51分钟', '中断0次'],
    ['保持专注节奏'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('环比264% 判 up 一致', r.factConsistent, true);
}

// ---- 2. 环比写反（应为 up 却写 -13%），必须判不一致 ----
{
  const sample = makeSample({
    totalMinutes: 267,
    lastWeekMinutes: 306,
    wow: -13,
    subjects: baseSubjects,
    direction: 'down',
    numbers: [267, 306, 13, 9, 3, 30, 1],
  });
  const raw = makeRaw(
    ['总专注267分钟', '上周306分钟', '环比+13%'],
    ['数学267分钟'],
    ['平均每次30分钟', '中断1次'],
    ['减少无效学习'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('方向写反判不一致', r.factConsistent, false);
}

// ---- 3. 环比-13% 与输入一致 ----
{
  const sample = makeSample({
    totalMinutes: 267,
    lastWeekMinutes: 306,
    wow: -13,
    subjects: baseSubjects,
    direction: 'down',
    numbers: [267, 306, 13, 9, 3, 30, 1],
  });
  const raw = makeRaw(
    ['总专注267分钟', '上周306分钟', '环比-13%', '共9次专注', '活跃3天'],
    ['数学267分钟'],
    ['平均每次30分钟', '中断1次'],
    ['减少无效学习'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('环比-13% 判 down 一致', r.factConsistent, true);
}

// ---- 4. 「下周行动：减少中断」不得干扰总体情况的方向判断 ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const raw = makeRaw(
    ['总专注255分钟', '上周70分钟', '环比增长264%', '5次专注', '活跃3天'],
    ['数学255分钟'],
    ['平均每次51分钟', '中断0次'],
    ['减少中断次数'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('行动分支含「减少」不影响总体判断', r.factConsistent, true);
}

// ---- 5. 编造数字（999）应被判不一致 ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const raw = makeRaw(
    ['总专注255分钟', '上周70分钟', '环比264%', '999次专注'],
    ['数学255分钟'],
    ['平均每次51分钟', '中断0次'],
    ['保持节奏'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('编造数字被判不一致', r.factConsistent, false);
}

// ---- 6. 出现禁止表述（效率提升百分比）应被记录 ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const raw = makeRaw(
    ['总专注255分钟', '上周70分钟', '环比264%', '5次专注'],
    ['数学255分钟'],
    ['效率提升30%', '中断0次'],
    ['保持节奏'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('禁止表述被捕获', r.forbiddenHits.length > 0, true);
}

// ---- 7. 编造清单外科目应被判不一致 ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const raw = makeRaw(
    ['总专注255分钟', '上周70分钟', '环比264%', '5次专注'],
    ['数学255分钟', '化学200分钟'],
    ['平均每次51分钟', '中断0次'],
    ['保持节奏'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('编造清单外科目被判不一致', r.factConsistent, false);
}

// ---- 8. 空响应判 failed，且事实一致强制 false ----
{
  const sample = makeSample({
    totalMinutes: 255,
    lastWeekMinutes: 70,
    wow: 264,
    subjects: baseSubjects,
    direction: 'up',
    numbers: [255, 70, 264, 5, 3, 51, 0],
  });
  const r = scoreSample(sample, { raw: '', httpStatus: 200, latencyMs: 5, errorKind: null });
  check('空响应= failed', [r.outcome, r.factConsistent], ['failed', false]);
}

// ---- 9. 「环比减少 65%」汉字方向词在间隙里、数字无符号，必须判 down 且一致 ----
{
  const sample = makeSample({
    totalMinutes: 78,
    lastWeekMinutes: 225,
    wow: -65,
    subjects: [{ name: '专业课', minutes: 78 }],
    direction: 'down',
    numbers: [78, 225, 65, 9, 0],
  });
  const raw = makeRaw(
    ['本周78分钟', '上周225分钟', '环比减少 65%'],
    ['专业课', '78分钟'],
    ['平均每次9分钟', '中断0次'],
    ['先追平上周225分钟'],
  );
  const r = scoreSample(sample, { raw, httpStatus: 200, latencyMs: 1200, errorKind: null });
  check('环比减少65% 判 down 一致', [r.factDirectionOk, r.factConsistent], [true, true]);
}

console.log('');
console.log(`用例合计 ${pass + fail}，PASS ${pass}，FAIL ${fail}`);
if (fail > 0) process.exit(1);
