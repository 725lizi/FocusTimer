// FocusBench 评分器：对单个样本 + 适配器结果做多维度判定。
// 严格按顺序判定 outcome/source，不合并成单一成功率。
import {
  analyze,
  buildRuleTree,
  extract,
  normalize,
  structuralOk,
  softSchemaOk,
} from '../reliability_experiment/reliability_engine.mjs';

// 从原始响应得到最终树：先抽 JSON 文本（剥代码围栏/前后说明），再规整。
// 与引擎 analyze 的内部顺序一致，避免对带围栏或带解说的响应取不到树。
function treeFromRaw(raw) {
  const ex = extract(raw);
  if (!ex || typeof ex.text !== 'string') return null;
  const nz = normalize(ex.text);
  return nz && nz.tree ? nz.tree : null;
}

// 科目池：用于"清单外出现"判定。若树文本出现池内但不在样本 subjects 清单里的科目，视为不一致。
const SUBJECT_POOL = ['数学', '英语', '物理', '高数', '专业课', '阅读'];

// 方向词表
const UP_WORDS = ['增加', '提升', '上升', '增长'];
const DOWN_WORDS = ['减少', '下降', '降低', '回落'];
const FLAT_WORDS = ['持平', '不变'];

// 从任意对象里递归收集所有 text 字段，拼成一段文本用于事实核查。
function collectText(node, acc) {
  if (node == null) return acc;
  if (typeof node === 'string') {
    acc.push(node);
    return acc;
  }
  if (Array.isArray(node)) {
    for (const item of node) collectText(item, acc);
    return acc;
  }
  if (typeof node === 'object') {
    if (typeof node.text === 'string') acc.push(node.text);
    if (Array.isArray(node.children)) {
      for (const child of node.children) collectText(child, acc);
    }
  }
  return acc;
}

// 提取文本中出现的数字集合（去掉小数尾点，如 "12." -> "12"）。
function extractNumbers(text) {
  const set = new Set();
  const re = /[\d.]+/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    let token = m[0];
    // 去掉尾部多余的点
    token = token.replace(/\.+$/, '');
    if (token === '' || token === '.') continue;
    set.add(token);
  }
  return set;
}

// 数字归一化比较：把 "12" 与 "12.0" 视为同一数字。
function normalizeNumber(token) {
  const n = Number(token);
  if (Number.isNaN(n)) return token;
  return String(n);
}

// 事实核查：对最终树做数字/科目/方向/禁止表述检查。
function checkFacts(sample, tree) {
  const textParts = [];
  collectText(tree, textParts);
  const text = textParts.join('\n');

  const checklist = sample.fact_checklist || {};
  const expectedNumbers = Array.isArray(checklist.numbers) ? checklist.numbers : [];
  const expectedSubjects = Array.isArray(checklist.subjects) ? checklist.subjects : [];
  const direction = checklist.direction || 'none';

  // ---- 数字 ----
  const appeared = extractNumbers(text);
  const appearedNorm = new Set([...appeared].map(normalizeNumber));
  const expectedNorm = new Set(expectedNumbers.map((n) => normalizeNumber(String(n))));

  const factNumbersTotal = appearedNorm.size;
  let factNumbersHit = 0;
  for (const n of appearedNorm) {
    if (expectedNorm.has(n)) factNumbersHit += 1;
  }

  // ---- 科目 ----
  // 清单内命中数
  let factSubjectsTotal = 0;
  for (const s of expectedSubjects) {
    if (text.includes(s)) factSubjectsTotal += 1;
  }
  let factSubjectsHit = factSubjectsTotal;

  // 清单外出现判定：树文本包含任何池内但不在清单里的科目 -> 不一致
  const expectedSubjectSet = new Set(expectedSubjects);
  let outOfList = false;
  for (const s of SUBJECT_POOL) {
    if (!expectedSubjectSet.has(s) && text.includes(s)) {
      outOfList = true;
      break;
    }
  }
  if (outOfList) {
    factSubjectsHit = 0;
  }

  // ---- 方向 ----
  const hasUp = UP_WORDS.some((w) => text.includes(w));
  const hasDown = DOWN_WORDS.some((w) => text.includes(w));
  const hasFlat = FLAT_WORDS.some((w) => text.includes(w));

  let factDirectionOk = false;
  if (direction === 'up') {
    factDirectionOk = hasUp && !hasDown;
  } else if (direction === 'down') {
    factDirectionOk = hasDown && !hasUp;
  } else if (direction === 'flat') {
    factDirectionOk = hasFlat && !hasUp && !hasDown;
  } else if (direction === 'none') {
    factDirectionOk = !hasUp && !hasDown;
  }

  // ---- 禁止表述 ----
  const forbiddenHits = [];
  const forbidden = Array.isArray(sample.forbidden_claims) ? sample.forbidden_claims : [];
  for (const claim of forbidden) {
    if (!claim) continue;
    if (text.includes(claim)) {
      forbiddenHits.push(claim);
      continue;
    }
    // 宽松匹配：针对"效率提升百分比"这类，出现"效率提升"或"提升 XX%"即算命中
    if (claim.includes('效率提升')) {
      if (text.includes('效率提升') || /提升\s*[\d.]+\s*%/.test(text)) {
        forbiddenHits.push(claim);
      }
    }
  }

  // ---- 汇总 ----
  // 科目项判定的是"没有编造清单外科目"，不是"必须提及每个科目"：
  // 全 0 周或文案未展开科目时，没有编造即通过，命中数只作统计。
  const subjectOk = !outOfList;
  // 引用性：有专注记录（totalMinutes>0）时，复盘里至少应出现一个数字，否则视为没有真正引用输入。
  const totalMinutes = sample.input && typeof sample.input.totalMinutes === 'number' ? sample.input.totalMinutes : 0;
  const referenceOk = totalMinutes > 0 ? factNumbersTotal > 0 : true;
  const factConsistent =
    factNumbersHit === factNumbersTotal && subjectOk && factDirectionOk && referenceOk;

  return {
    factNumbersTotal,
    factNumbersHit,
    factSubjectsTotal,
    factSubjectsHit,
    factDirectionOk,
    factConsistent,
    forbiddenHits,
  };
}

export function scoreSample(sample, adapterResult) {
  const result = adapterResult || {};
  const errorKind = result.errorKind ?? null;
  const latencyMs = typeof result.latencyMs === 'number' ? result.latencyMs : 0;
  const httpStatus = result.httpStatus ?? null;

  let outcome;
  let source;
  let tree = null;

  // 规则 4 优先：用户取消单独处理（保留 errorKind 供报告区分）
  if (errorKind === 'cancelled') {
    outcome = 'failed';
    source = 'none';
  } else if (errorKind != null && errorKind !== '') {
    // 规则 1：适配器报错（非取消）-> 规则兜底
    outcome = 'rule_fallback';
    source = 'rule';
    tree = buildRuleTree({ primary: sample.input });
  } else if (result.raw == null || result.raw === '') {
    // 规则 2：无原始响应 -> 失败
    outcome = 'failed';
    source = 'none';
  } else {
    // 规则 3：交给引擎分析
    const analysis = analyze(result.raw);
    if (analysis.g2_outcome === 'direct') {
      outcome = 'direct';
      source = 'llm';
      tree = treeFromRaw(result.raw);
    } else if (analysis.g2_outcome === 'repaired') {
      outcome = 'repaired';
      source = 'llm';
      tree = treeFromRaw(result.raw);
    } else {
      // fail -> 规则兜底
      outcome = 'rule_fallback';
      source = 'rule';
      tree = buildRuleTree({ primary: sample.input });
    }
  }

  // 事实核查：对最终树进行。若树缺失（failed 分支），用空树占位。
  const factTree = tree ?? { text: '', children: [] };
  const facts = checkFacts(sample, factTree);
  // 完全没有产出（failed）谈不上事实一致，明确置为 false，避免空树被误判为一致。
  if (outcome === 'failed') facts.factConsistent = false;

  return {
    sample_id: sample.sample_id,
    task_type: sample.task_type,
    difficulty: sample.difficulty,
    outcome,
    source,
    hardOk: tree ? structuralOk(tree) : false,
    softOk: tree ? softSchemaOk(tree) : false,
    factNumbersTotal: facts.factNumbersTotal,
    factNumbersHit: facts.factNumbersHit,
    factSubjectsTotal: facts.factSubjectsTotal,
    factSubjectsHit: facts.factSubjectsHit,
    factDirectionOk: facts.factDirectionOk,
    factConsistent: facts.factConsistent,
    forbiddenHits: facts.forbiddenHits,
    latencyMs,
    httpStatus,
    errorKind,
  };
}

export default { scoreSample };
