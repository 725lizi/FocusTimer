// services/ai/ReportStrategy.ets
// 纯逻辑：决定一次周报“走大模型还是走本地规则”，以及大模型出错时是否降级回退。
// 把判断从网络代码里抽出来，离线即可覆盖各种组合，保证“无网必回退、有 key 才请求”。

import { ReportSource, ReportStrategyInput } from './AiChatTypes';

/** 大模型调用可能出现的错误类别 */
export type LlmErrorKind =
  'network'      // 断网 / 连不上
  | 'timeout'    // 超时
  | 'unauthorized' // key 错误 / 失效
  | 'rate_limited' // 触发限流
  | 'server'     // 服务端 5xx
  | 'bad_request'// 请求体有误
  | 'empty'      // 返回为空
  | 'cancelled'; // 用户主动取消

export class ReportStrategy {
  /**
   * 决策来源：只有「用户开启 AI + 有网 + 已配置 Key」三者同时满足才走大模型，
   * 其余情况一律走本地规则版（保证功能永远可用）。
   */
  static decideSource(input: ReportStrategyInput): ReportSource {
    if (input.llmEnabled && input.online && input.hasApiKey) {
      return 'llm';
    }
    return 'rule';
  }

  /** 当决策为规则版时，给出一句用户能看懂的原因（用于界面提示，诚实告知当前来源） */
  static ruleReason(input: ReportStrategyInput): string {
    if (!input.llmEnabled) {
      return 'AI 周报未开启，使用本地规则生成';
    }
    if (!input.hasApiKey) {
      return '未配置 API Key，使用本地规则生成';
    }
    if (!input.online) {
      return '当前无网络，已自动使用本地规则生成';
    }
    return '使用本地规则生成';
  }

  /**
   * 大模型出错后是否降级到规则版。
   * 只有「用户主动取消」不降级（用户都不要了，没必要再生成）；其余错误都兜底，保证有产出。
   */
  static shouldFallback(kind: LlmErrorKind): boolean {
    return kind !== 'cancelled';
  }

  /** 状态是否已进入终态（用于防止重复回调更新界面） */
  static isTerminal(status: string): boolean {
    return status === 'succeeded' || status === 'failed' || status === 'fallback';
  }
}
