// FocusBench mock 适配器：离线、确定性、不联网、不读环境变量、不用随机数、不读系统时钟。
// 用 buildRuleTree 生成合法树，再按 task_type 变换成不同"模型响应"。
import { buildRuleTree } from '../../reliability_experiment/reliability_engine.mjs';

// 从 sample_id 尾部取序号，用于确定性变换（如 anomaly 的三种破坏、latency 算式）。
function sampleIndex(sample) {
  const m = /(\d+)\s*$/.exec(String(sample.sample_id || ''));
  return m ? Number(m[1]) : 0;
}

// 故障类型 -> 固定延迟表（毫秒），不随机。
const FAULT_LATENCY = {
  network: 0,
  timeout: 15000,
  unauthorized: 210,
  rate_limited: 240,
  server: 860,
  bad_request: 190,
  empty: 1300,
  cancelled: 50,
};

// 故障类型 -> HTTP 状态码（按真实语义）。
const FAULT_HTTP = {
  network: 0,
  timeout: 408,
  unauthorized: 401,
  rate_limited: 429,
  server: 500,
  bad_request: 400,
  empty: 200,
  cancelled: 0,
};

// 深拷贝树，避免变换时污染原始对象。
function cloneTree(tree) {
  return JSON.parse(JSON.stringify(tree));
}

// 找到第一个叶子节点（无 children 或 children 为空）。
function findFirstLeaf(node) {
  if (!node || typeof node !== 'object') return null;
  if (!Array.isArray(node.children) || node.children.length === 0) return node;
  for (const child of node.children) {
    const leaf = findFirstLeaf(child);
    if (leaf) return leaf;
  }
  return null;
}

// 收集所有节点（用于重复 id 等破坏）。
function collectNodes(node, acc) {
  if (!node || typeof node !== 'object') return acc;
  acc.push(node);
  if (Array.isArray(node.children)) {
    for (const child of node.children) collectNodes(child, acc);
  }
  return acc;
}

// 生成合法树（注意：buildRuleTree 需要 {primary: 扁平底稿}）。
function makeTree(sample) {
  return buildRuleTree({ primary: sample.input });
}

// 对 anomaly 做三种破坏之一（按序号尾数 % 3）。
function breakTree(tree, idx) {
  const mode = idx % 3;
  const broken = cloneTree(tree);

  if (mode === 0) {
    // 破坏①：删掉根节点 text 字段 —— 模拟模型漏写根节点文案，规整能补默认文案。
    delete broken.text;
    return broken;
  }

  if (mode === 1) {
    // 破坏②：把 children 拆平 / 重复 id —— 模拟模型输出结构错乱，规整能补号。
    const nodes = collectNodes(broken, []);
    // 重复 id：把第二个及以后的节点 id 改成与第一个相同
    if (nodes.length > 1) {
      const firstId = nodes[0].id;
      for (let i = 1; i < nodes.length; i += 1) {
        if (nodes[i].id != null) nodes[i].id = firstId;
      }
    }
    // 拆平：把某个中间节点的 children 直接挂到根上（制造层级混乱）
    const root = broken;
    if (Array.isArray(root.children) && root.children.length > 0) {
      const firstChild = root.children[0];
      if (Array.isArray(firstChild.children) && firstChild.children.length > 0) {
        root.children = root.children.concat(firstChild.children);
      }
    }
    return broken;
  }

  // 破坏③：把某个叶子 text 塞成 40 个汉字 —— 模拟模型啰嗦超长，规整会截断到 24。
  const leaf = findFirstLeaf(broken);
  if (leaf) {
    leaf.text = '这是一段被故意写得很长很长的叶子节点文案用于测试截断行为是否生效';
  }
  return broken;
}

export async function call(sample) {
  const idx = sampleIndex(sample);
  const taskType = sample.task_type;

  // 故障类：按 fault_type 返回错误，raw=null（empty 例外为 ''）。
  if (taskType === 'fault') {
    const fault = sample.fault_type;
    const latencyMs = FAULT_LATENCY[fault] ?? 0;
    const httpStatus = FAULT_HTTP[fault] ?? 0;

    if (fault === 'empty') {
      // 模拟服务端 200 但返回空体：raw 为空字符串，交由评分器判 failed。
      return { raw: '', httpStatus, latencyMs, errorKind: fault };
    }

    // 其余故障：raw=null，errorKind 保留故障类型，评分器据此走规则兜底或失败。
    return { raw: null, httpStatus, latencyMs, errorKind: fault };
  }

  // 非故障类：先造一棵合法树，再按 task_type 变换成不同"模型响应"。
  const tree = makeTree(sample);
  // 固定延迟算式：800 + 序号×7，不随机。
  const latencyMs = 800 + idx * 7;

  if (taskType === 'regular') {
    // 模拟模型正常返回纯 JSON：期望 direct。
    return {
      raw: JSON.stringify(tree),
      httpStatus: 200,
      latencyMs,
      errorKind: null,
    };
  }

  if (taskType === 'complex') {
    // 模拟模型习惯性加 ```json 代码围栏：抽取器能剥围栏，期望 direct。
    const fenced = '```json\n' + JSON.stringify(tree) + '\n```';
    return {
      raw: fenced,
      httpStatus: 200,
      latencyMs,
      errorKind: null,
    };
  }

  if (taskType === 'anomaly') {
    // 模拟模型输出结构瑕疵（漏字段/错乱/超长）：规整能修复，期望 repaired。
    const broken = breakTree(tree, idx);
    return {
      raw: JSON.stringify(broken),
      httpStatus: 200,
      latencyMs,
      errorKind: null,
    };
  }

  if (taskType === 'longtext') {
    // 模拟模型在 JSON 前后夹带说明文字：抽取器能定位 JSON，期望 repaired。
    const wrapped =
      '好的，以下是本周复盘：\n' + JSON.stringify(tree) + '\n以上供参考';
    return {
      raw: wrapped,
      httpStatus: 200,
      latencyMs,
      errorKind: null,
    };
  }

  // 兜底：未知类型按 regular 处理，保证确定性。
  return {
    raw: JSON.stringify(tree),
    httpStatus: 200,
    latencyMs,
    errorKind: null,
  };
}

export default { call };
