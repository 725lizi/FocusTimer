// 真实 API 适配器：OpenAI 兼容的 /chat/completions 端点
// 仅使用全局 fetch（Node v22 内置），不引入任何第三方依赖

const SYSTEM_PROMPT = [
  '你是一个把专注记录整理成结构化脑图的助手。',
  '请只输出一个脑图 JSON，不要输出任何解释、Markdown 代码围栏或多余文字。',
  'JSON 结构要求：根节点 text 为「本周专注复盘」，id 为 root；',
  '根节点下恰好四个一级分支，text 分别为：总体情况、科目分布、专注质量、下周行动。',
  '整棵脑图节点总数 8-20 个；每个叶子节点 text 不超过 16 个字。',
  '只能使用输入数据中出现过的数字，不得编造或推算任何新数字。',
  '不得做健康或心理诊断，不得给出医疗、心理方面的判断或建议。',
].join('\n');

function buildUserPrompt(sample) {
  const input = sample && sample.input ? sample.input : {};
  const payload = {
    totalMinutes: input.totalMinutes,
    lastWeekMinutes: input.lastWeekMinutes,
    weekOverWeekPercent: input.weekOverWeekPercent,
    sessionCount: input.sessionCount,
    activeDays: input.activeDays,
    avgMinutesPerSession: input.avgMinutesPerSession,
    interruptCount: input.interruptCount,
    subjects: input.subjects,
  };
  return [
    '以下是一份专注记录（数据为合成测试数据，不含任何真实个人信息）：',
    JSON.stringify(payload, null, 2),
    '请据此生成脑图 JSON。',
  ].join('\n');
}

// 把 HTTP 状态映射到 8 类 errorKind 之一
function mapHttpStatus(status) {
  if (status === 401 || status === 403) return 'unauthorized';
  if (status === 429) return 'rate_limited';
  if (status === 400 || status === 404 || status === 422) return 'bad_request';
  if (status === 408) return 'timeout';
  if (status >= 500) return 'server';
  return 'bad_request';
}

export async function call(sample) {
  const apiKey = process.env.FOCUSBENCH_API_KEY;
  if (!apiKey) {
    // 缺失密钥时立刻抛错，绝不返回假成功
    throw new Error('未配置 FOCUSBENCH_API_KEY，请改用 mock 模式');
  }

  const baseUrl = process.env.FOCUSBENCH_BASE_URL || 'https://api.deepseek.com';
  const model = process.env.FOCUSBENCH_MODEL || 'deepseek-chat';
  const endpoint = baseUrl.replace(/\/+$/, '') + '/chat/completions';

  const body = {
    model,
    stream: false,
    temperature: 0.4,
    max_tokens: 900,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: buildUserPrompt(sample) },
    ],
  };

  const startedAt = performance.now();
  let httpStatus = null;

  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    });
    httpStatus = res.status;
    const latencyMs = Math.round(performance.now() - startedAt);

    if (!res.ok) {
      // 尽量消费掉响应体，避免连接悬挂；失败内容不参与评分
      try {
        await res.text();
      } catch {
        // 忽略读取失败
      }
      return {
        raw: null,
        httpStatus,
        latencyMs,
        errorKind: mapHttpStatus(res.status),
      };
    }

    let data;
    try {
      data = await res.json();
    } catch {
      return { raw: null, httpStatus, latencyMs, errorKind: 'bad_request' };
    }

    const content =
      data &&
      data.choices &&
      data.choices[0] &&
      data.choices[0].message &&
      data.choices[0].message.content;

    if (typeof content !== 'string' || content.trim() === '') {
      return { raw: null, httpStatus, latencyMs, errorKind: 'empty' };
    }

    return { raw: content, httpStatus, latencyMs, errorKind: null };
  } catch (err) {
    const latencyMs = Math.round(performance.now() - startedAt);
    let errorKind = 'network';
    if (err && (err.name === 'AbortError' || err.code === 'ABORT_ERR')) {
      errorKind = 'timeout';
    }
    return { raw: null, httpStatus, latencyMs, errorKind };
  }
}
