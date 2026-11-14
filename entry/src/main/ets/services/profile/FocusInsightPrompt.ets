// services/profile/FocusInsightPrompt.ets
// 模型分工：确定性提示词构建（纯函数、不联网、不依赖系统 API），由 DeepSeek 负责。
// 思路：把已经算好的事实喂给 Queen，明确要求只能引用这些事实 id，输出固定 JSON，
// 从源头减少模型编造证据，真正的证据校验再由 FocusInsightValidator 兜底。

import { ChatMessage } from '../ai/AiChatTypes';
import { FocusProfileStatsResult } from './FocusProfileTypes';

export class FocusInsightPrompt {
  /** 构建发给大模型的 system + user 两条消息 */
  static buildMessages(result: FocusProfileStatsResult): ChatMessage[] {
    const system: ChatMessage = {
      role: 'system',
      content:
        '你是一个专注记录分析助手。你只能依据用户提供的「统计事实」生成洞察，' +
        '不得编造事实、不得引用列表之外的证据 id、不得做健康或心理诊断、不得给出没有依据的因果结论。' +
        '每条洞察必须包含 summary（一句话人话结论）、evidenceIds（引用给定事实 id，至少一个）、' +
        'action（可执行的一句话建议）。只输出 JSON，不要输出解释或 Markdown 代码块，' +
        '格式为 {"insights":[{"summary":"...","evidenceIds":["..."],"action":"..."}]}。'
    };
    const user: ChatMessage = {
      role: 'user',
      content: FocusInsightPrompt.buildUserContent(result)
    };
    return [system, user];
  }

  private static buildUserContent(result: FocusProfileStatsResult): string {
    let factLines: string = '';
    for (const f of result.facts) {
      factLines += `- id=${f.id}｜${f.label}=${f.value}${f.unit}｜口径：${f.calcNote}\n`;
    }
    return `窗口：近 ${result.windowDays} 天；样本量 ${result.sampleSize}；活跃天数 ${result.activeDays}。\n` +
      '可用统计事实如下（evidenceIds 只能从这些 id 中选择）：\n' + factLines +
      '请生成 3 到 4 条最有价值的洞察，优先讲占比最高的类别、最常专注的时段、单次时长规律和周际变化。';
  }
}
