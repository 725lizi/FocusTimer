// 负责模型：DeepSeek
// =============================================================================
// reliability_engine.mjs —— 「三级容错」链路的共享纯逻辑模块
//
// 为什么要有这个文件：validate_corpus.mjs（校验样本库）和 ablation_g0g3.mjs（消融实验）
// 必须用**同一套**判定逻辑，否则两份脚本各写一遍迟早漂移。所以把 extract / normalize /
// 硬逻辑 / 软 Schema / 本地规则树 都收在这里，两边一起 import。
//
// 逐函数对应真实工程源码（改这里之前请先改源码）：
//   extract     ← services/ai/MindMapJsonExtractor.ets   :: MindMapJsonExtractor.extract
//   normalize   ← services/ai/MindMapJsonExtractor.ets   :: MindMapJsonExtractor.normalize
//   structuralOk← 组件库 JsonSerializer.deserialize/buildNode 的硬校验（id/text/children 三件套）
//   softSchema  ← MindMapPromptBuilder 的理想 Prompt 契约（只是理想，真实代码不强制）
//   buildRuleTree ← services/ai/RuleMindMapBuilder.ets    :: RuleMindMapBuilder.build
//
// 边界：纯函数、不联网、不读时钟、无随机；同一入参必得同一出参。
// 声明：本模块只做离线判定，不产出任何真实模型成功率或延迟数据。
// =============================================================================

/** 根节点固定文案（提示词契约 & 规则树都用它） */
export const ROOT_TEXT = '本周专注复盘';
/** 四个一级分支，顺序即输出顺序 */
export const BRANCH_TITLES = ['总体情况', '科目分布', '专注质量', '下周行动'];
/** 规整器对节点 text 的硬截断上限（硬逻辑；源码里是 24） */
export const HARD_TEXT_LIMIT = 24;
/** 理想契约要求叶子 text 不超过 16 个汉字（软 Schema） */
export const SOFT_LEAF_LIMIT = 16;
/** 理想契约的节点总数区间 */
export const SOFT_MIN_NODES = 8;
export const SOFT_MAX_NODES = 20;
/** 规整时 text 为空的兜底文案（与源码一致） */
export const DEFAULT_TEXT = '专注记录';
/** 自动补号前缀（与源码一致） */
export const AUTO_ID_PREFIX = 'm';
/** 根节点固定 id */
export const ROOT_ID = 'root';

// ---------------------------------------------------------------------------
// 1) extract —— 从模型原文里挖出 JSON 对象文本
// ---------------------------------------------------------------------------

/** 去掉 markdown 代码围栏：开头的 ```json / ``` 与结尾的 ``` 各去掉一次（同源码） */
function stripFences(text) {
  let out = text;
  if (out.startsWith('```')) {
    const firstLineEnd = out.indexOf('\n');
    if (firstLineEnd >= 0) {
      out = out.substring(firstLineEnd + 1);
    } else {
      out = out.substring(3);
    }
  }
  out = out.trim();
  if (out.endsWith('```')) {
    out = out.substring(0, out.length - 3);
  }
  return out;
}

/**
 * 文本抽取：去围栏 → 截取首个 `{` 到末个 `}`（不判断语法）。
 * @returns {{text: string} | {error: 'EMPTY'|'NO_JSON'}}
 */
export function extract(raw) {
  if (typeof raw !== 'string') return { error: 'EMPTY' };
  let text = raw.trim();
  if (text.length === 0) return { error: 'EMPTY' };
  text = stripFences(text).trim();
  if (text.length === 0) return { error: 'EMPTY' };
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end < 0 || end < start) return { error: 'NO_JSON' };
  return { text: text.substring(start, end + 1) };
}

// ---------------------------------------------------------------------------
// 2) 信封拆解与结构校验
// ---------------------------------------------------------------------------

/** 取根节点：优先 `{root:{...}}` 信封，其次裸节点；都不是对象则返回 null（同源码 pickRawRoot） */
export function pickRawRoot(parsed) {
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
  const wrapped = parsed.root;
  if (wrapped !== null && wrapped !== undefined && typeof wrapped === 'object' && !Array.isArray(wrapped)) {
    return wrapped;
  }
  if (typeof parsed.text === 'string') return parsed;
  return null;
}

/** 宽松取树：信封优先，否则原样返回（用于「裸 parse 后看一眼形状」，不追求严格） */
export function toTree(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  if (!('children' in value) && value.root !== null && typeof value.root === 'object' && !Array.isArray(value.root)) {
    return value.root;
  }
  return value;
}

/**
 * 【硬逻辑】真实系统实际强制的东西（组件库 deserialize 的校验）：
 * id 非空且全局唯一、text 非空字符串且 ≤ 24、children 是数组、根节点存在。
 * 不限制深度、不限制节点数、不要求四个分支、不要求叶子 16 字 —— 这些都不影响能不能用。
 */
export function structuralOk(tree) {
  if (tree === null || typeof tree !== 'object' || Array.isArray(tree)) return false;
  const ids = new Set();
  let ok = true;
  const walk = (node) => {
    if (!ok) return;
    if (node === null || typeof node !== 'object' || Array.isArray(node)) { ok = false; return; }
    if (typeof node.id !== 'string' || node.id === '') { ok = false; return; }
    if (ids.has(node.id)) { ok = false; return; }
    ids.add(node.id);
    if (typeof node.text !== 'string' || node.text.trim() === '') { ok = false; return; }
    if (node.text.length > HARD_TEXT_LIMIT) { ok = false; return; }
    if (!Array.isArray(node.children)) { ok = false; return; }
    for (const child of node.children) walk(child);
  };
  walk(tree);
  return ok;
}

/**
 * 【软 Schema】理想 Prompt 契约：只统计「输出有多接近理想」，不参与降级。
 * 根 id/text、四分支顺序、节点 8–20、深度 2–3、每节点只有三个字段、叶子 ≤ 16 字。
 */
export function softSchemaOk(tree) {
  if (!structuralOk(tree)) return false;
  if (tree.id !== ROOT_ID || tree.text !== ROOT_TEXT) return false;
  if (!Array.isArray(tree.children) || tree.children.length !== BRANCH_TITLES.length) return false;
  for (let i = 0; i < BRANCH_TITLES.length; i++) {
    if (tree.children[i].text !== BRANCH_TITLES[i]) return false;
  }
  let count = 0;
  let maxDepth = 0;
  let ok = true;
  const walk = (node, depth) => {
    if (!ok) return;
    count += 1;
    if (depth > maxDepth) maxDepth = depth;
    if (Object.keys(node).sort().join(',') !== 'children,id,text') { ok = false; return; }
    if (!Array.isArray(node.children)) { ok = false; return; }
    if (node.children.length === 0 && node.text.length > SOFT_LEAF_LIMIT) { ok = false; return; }
    for (const child of node.children) walk(child, depth + 1);
  };
  walk(tree, 1);
  if (!ok) return false;
  return count >= SOFT_MIN_NODES && count <= SOFT_MAX_NODES && maxDepth >= 2 && maxDepth <= 3;
}

/** 统计树的节点数与最大深度（消融实验用来描述「修出来的是什么形状」） */
export function treeShape(tree) {
  let count = 0;
  let depth = 0;
  const walk = (node, d) => {
    count += 1;
    if (d > depth) depth = d;
    if (Array.isArray(node.children)) for (const child of node.children) walk(child, d + 1);
  };
  if (tree !== null && typeof tree === 'object') walk(tree, 1);
  return { nodes: count, depth };
}

// ---------------------------------------------------------------------------
// 3) normalize —— 确定性修复（同源码；**不拍平深度**）
// ---------------------------------------------------------------------------

function collectReservedIds(node, reserved) {
  if (node === null || typeof node !== 'object') return;
  if (typeof node.id === 'string' && node.id.trim().length > 0) reserved.add(node.id.trim());
  if (Array.isArray(node.children)) for (const child of node.children) collectReservedIds(child, reserved);
}

function normalizeId(value, used) {
  if (typeof value !== 'string') return '';
  const id = value.trim();
  if (id.length === 0) return '';
  if (id === ROOT_ID) return '';       // root 专属根节点
  if (used.has(id)) return '';         // 重复的重新补号
  return id;
}

function nextAutoId(state) {
  while (true) {
    const candidate = AUTO_ID_PREFIX + state.autoSeq;
    state.autoSeq += 1;
    if (!state.used.has(candidate) && !state.reserved.has(candidate) && candidate !== ROOT_ID) {
      return candidate;
    }
  }
}

function normalizeNode(raw, isRoot, state) {
  // text：trim；空则兜底；超 24 截断
  const rawText = typeof raw.text === 'string' ? raw.text : '';
  let text = rawText.trim();
  if (text.length === 0) {
    text = DEFAULT_TEXT;
    state.changed = true;
  } else if (text.length > HARD_TEXT_LIMIT) {
    text = text.substring(0, HARD_TEXT_LIMIT);
    state.changed = true;
  } else if (text !== rawText) {
    state.changed = true;              // 仅去了首尾空白，也算改过
  }

  let id;
  if (isRoot) {
    id = ROOT_ID;
  } else {
    id = normalizeId(raw.id, state.used);
    if (id.length === 0) {
      id = nextAutoId(state);
      state.changed = true;
    }
  }
  state.used.add(id);

  const children = [];
  if (Array.isArray(raw.children)) {
    for (const child of raw.children) {
      if (child === null || typeof child !== 'object' || Array.isArray(child)) {
        state.changed = true;          // 数组里混进脏元素：跳过（同源码）
        continue;
      }
      children.push(normalizeNode(child, false, state));
    }
  } else {
    state.changed = true;              // children 缺失 / 为 null / 非数组 → []
  }

  return { id, text, children };
}

/**
 * 规整：JSON.parse 失败 → INVALID；成功后按源码规则修复。
 * 注意：**不拍平深度**——输入第 4 层，输出还是第 4 层。
 * @returns {{tree: object, changed: boolean} | {error: 'EMPTY'|'INVALID'}}
 *          changed 表示是否发生过「语义修改」（补 id / 补 children / 补或截断 text）
 */
export function normalize(text) {
  if (typeof text !== 'string') return { error: 'EMPTY' };
  const trimmed = text.trim();
  if (trimmed.length === 0) return { error: 'EMPTY' };
  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (err) {
    return { error: 'INVALID' };
  }
  const rawRoot = pickRawRoot(parsed);
  if (rawRoot === null) return { error: 'INVALID' };

  const reserved = new Set();
  collectReservedIds(rawRoot, reserved);
  reserved.delete(ROOT_ID);

  const state = { used: new Set(), reserved, autoSeq: 0, changed: false };
  const tree = normalizeNode(rawRoot, true, state);
  return { tree, changed: state.changed };
}

// ---------------------------------------------------------------------------
// 4) 一次判定：把一条 raw 的四级标签与两个指标一起算出来
// ---------------------------------------------------------------------------

/**
 * @returns {{
 *   g0_parse: boolean, g1_contract: boolean, g2_outcome: 'direct'|'repaired'|'fail',
 *   g3_source: 'llm'|'rule', hardOk: boolean, softOk: boolean,
 *   extractError: string|null, normalizeError: string|null, repaired: boolean
 * }}
 */
export function analyze(raw) {
  let parseOk = true;
  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    parseOk = false;
  }
  const g0 = parseOk;
  const g1 = parseOk ? softSchemaOk(toTree(parsed)) : false;

  let hardOk = false;
  let softOk = false;
  let g2 = 'fail';
  let extractError = null;
  let normalizeError = null;
  let changed = false;

  const ex = extract(raw);
  if (ex.error) {
    extractError = ex.error;
  } else {
    const nz = normalize(ex.text);
    if (nz.error) {
      normalizeError = nz.error;
    } else if (structuralOk(nz.tree)) {
      hardOk = true;
      softOk = softSchemaOk(nz.tree);
      changed = nz.changed === true;
      // 零语义修改 = 抽取没改文本、规整没改树 → direct；否则 repaired
      g2 = ex.text === raw && !changed ? 'direct' : 'repaired';
    }
  }

  return {
    g0_parse: g0,
    g1_contract: g1,
    g2_outcome: g2,
    g3_source: g2 === 'fail' ? 'rule' : 'llm',
    hardOk,
    softOk,
    extractError,
    normalizeError,
    repaired: g2 === 'repaired',
  };
}

// ---------------------------------------------------------------------------
// 5) 本地规则树（三级容错的最后一级兜底）
//    逐条移植自 services/ai/RuleMindMapBuilder.ets，数字全部来自 summary_fixture.json。
// ---------------------------------------------------------------------------

function clip(text, budget = SOFT_LEAF_LIMIT) {
  const trimmed = String(text).trim();
  return trimmed.length > budget ? trimmed.substring(0, budget) : trimmed;
}

function sortedTags(tagMinutes) {
  const items = [];
  tagMinutes.forEach((minutes, tag) => items.push({ tag, minutes }));
  items.sort((a, b) => {
    if (b.minutes !== a.minutes) return b.minutes - a.minutes;
    if (a.tag === b.tag) return 0;
    return a.tag < b.tag ? -1 : 1;
  });
  return items;
}

function topTags(tagMinutes) {
  return sortedTags(tagMinutes).slice(0, 3);
}

function isGrowing(summary) {
  if (summary.lastWeekMinutes <= 0) return summary.thisWeekMinutes > 0;
  return summary.thisWeekMinutes > summary.lastWeekMinutes;
}

function overallChildren(summary) {
  const items = [];
  items.push({ text: '本周 ' + summary.thisWeekMinutes + ' 分钟', children: [] });
  if (summary.lastWeekMinutes <= 0) {
    items.push({ text: '上周为 0 分钟', children: [] });
    items.push({ text: '上周暂无记录', children: [] });
  } else if (summary.changePercent === 0) {
    items.push({ text: '环比持平 0%', children: [] });
    items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
  } else if (summary.changePercent > 0) {
    items.push({ text: '环比增加 ' + summary.changePercent + '%', children: [] });
    items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
  } else {
    items.push({ text: '环比减少 ' + Math.abs(summary.changePercent) + '%', children: [] });
    items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
  }
  return items;
}

function tagChildren(summary) {
  if (summary.tagMinutes.size === 0) {
    return [
      { text: '本周暂无科目记录', children: [] },
      { text: '下次专注带上标签', children: [] },
    ];
  }
  const items = [];
  for (const item of topTags(summary.tagMinutes)) {
    items.push({ text: clip(item.tag), children: [] });
    items.push({ text: item.minutes + ' 分钟', children: [] });
  }
  return items;
}

function qualityChildren(summary) {
  const items = [];
  items.push({ text: '平均每次 ' + summary.avgSessionMinutes + ' 分钟', children: [] });
  items.push({ text: '中断 ' + summary.interruptedCount + ' 次', children: [] });
  if (summary.interruptedCount === 0) {
    items.push({ text: '全程未被打断', children: [] });
  } else {
    items.push({ text: '被打断后尽快回到桌前', children: [] });
  }
  return items;
}

function emptyDataChildren() {
  return [
    { text: BRANCH_TITLES[0], children: [{ text: '本周还没有专注记录', children: [] }] },
    { text: BRANCH_TITLES[1], children: [{ text: '还没有科目用时', children: [] }] },
    { text: BRANCH_TITLES[2], children: [{ text: '本周暂无中断记录', children: [] }] },
    { text: BRANCH_TITLES[3], children: [{ text: '先从一次专注开始', children: [] }, { text: '完成一次就给自己点赞', children: [] }] },
  ];
}

function actionChildren(summary) {
  const items = [];
  if (summary.thisWeekMinutes <= 0) {
    items.push({ text: '先完成本周第一次专注', children: [] });
    items.push({ text: '给这次专注打上标签', children: [] });
    return items;
  }
  if (summary.tagMinutes.size > 0) {
    const top = topTags(summary.tagMinutes)[0];
    const prefix = '继续保持「';
    const suffix = '」';
    const tagBudget = SOFT_LEAF_LIMIT - prefix.length - suffix.length;
    items.push({ text: prefix + clip(top.tag, tagBudget) + suffix, children: [] });
  } else {
    items.push({ text: '给每次专注补上科目标签', children: [] });
  }
  const hasEnoughSamples = summary.sessionCount >= 2;
  if (isGrowing(summary)) {
    if (hasEnoughSamples) {
      items.push({ text: '趁势把周时长再提一点', children: [] });
    } else {
      items.push({ text: '保持势头，试着做 2 次', children: [{ text: '把专注排进固定时段', children: [] }] });
    }
  } else if (summary.lastWeekMinutes > 0) {
    items.push({ text: '先追平上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
  } else if (hasEnoughSamples) {
    items.push({ text: '保持节奏，别断更', children: [] });
  } else {
    items.push({ text: '先稳住每天一次', children: [{ text: '小步快跑胜过猛冲一回', children: [] }] });
  }
  return items;
}

function branchChildren(summary) {
  return [
    { text: BRANCH_TITLES[0], children: overallChildren(summary) },
    { text: BRANCH_TITLES[1], children: tagChildren(summary) },
    { text: BRANCH_TITLES[2], children: qualityChildren(summary) },
    { text: BRANCH_TITLES[3], children: actionChildren(summary) },
  ];
}

/** 层序编号：根固定 root，其余 m0、m1…（同源码 finalize） */
function finalize(draft, isRoot, seq) {
  let id;
  if (isRoot) {
    id = ROOT_ID;
  } else {
    id = AUTO_ID_PREFIX + seq[0];
    seq[0] += 1;
  }
  const children = [];
  for (const child of draft.children) children.push(finalize(child, false, seq));
  return { id, text: clip(draft.text), children };
}

/**
 * 用固定周摘要底稿生成合规脑图（三级容错的最后一级）。
 * @param {object} fixture summary_fixture.json 解析后的对象（读取 primary 底稿）
 * @returns {object} 裸根节点 {id,text,children}
 */
export function buildRuleTree(fixture) {
  const primary = fixture !== null && typeof fixture === 'object' ? fixture.primary : null;
  if (primary === null || typeof primary !== 'object') {
    throw new Error('summary_fixture.json 缺少 primary 底稿，规则树无法生成');
  }
  const subjects = Array.isArray(primary.subjects) ? primary.subjects : [];
  const tagMinutes = new Map();
  for (const item of subjects) tagMinutes.set(item.name, item.minutes);

  const summary = {
    thisWeekMinutes: primary.totalMinutes,
    lastWeekMinutes: primary.lastWeekMinutes,
    changePercent: primary.weekOverWeekPercent,
    avgSessionMinutes: primary.avgMinutesPerSession,
    interruptedCount: primary.interruptCount,
    sessionCount: primary.sessionCount,
    tagMinutes,
  };

  const hasData = summary.thisWeekMinutes > 0;
  const children = hasData ? branchChildren(summary) : emptyDataChildren();
  return finalize({ text: ROOT_TEXT, children }, true, [0]);
}
