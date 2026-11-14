// services/profile/FocusInsightValidator.ets
// 模型分工：确定性证据校验（纯函数、不联网、不依赖系统 API），由 DeepSeek 负责。
// 作用：AI 返回的洞察必须通过证据校验才能展示——引用的事实 id 必须真实存在、证据非空，
// 防止模型编造没有依据的结论，或引用不存在的证据。

import { FocusFact, FocusInsight } from './FocusProfileTypes';

export class FocusInsightValidator {
  /** 构建合法事实 id 集合，便于快速校验 */
  private static factIdSet(facts: FocusFact[]): Set<string> {
    const set: Set<string> = new Set<string>();
    for (const f of facts) {
      set.add(f.id);
    }
    return set;
  }

  /** 单条洞察是否通过校验：结论/行动非空、证据非空且每个 id 都真实存在 */
  static isValid(insight: FocusInsight, facts: FocusFact[]): boolean {
    const ids: string[] = insight.evidenceIds;
    if (ids === null || ids === undefined || ids.length === 0) {
      return false;
    }
    if (insight.summary.trim().length === 0 || insight.action.trim().length === 0) {
      return false;
    }
    const idSet: Set<string> = FocusInsightValidator.factIdSet(facts);
    const seen: Set<string> = new Set<string>();
    for (const id of ids) {
      if (!idSet.has(id)) {
        return false; // 引用了不存在的事实，结论不可追溯
      }
      seen.add(id);
    }
    return seen.size > 0;
  }

  /** 批量过滤：只保留证据合法的洞察；AI 返回若全部非法则得到空数组，调用方据此降级规则版 */
  static filterValid(insights: FocusInsight[], facts: FocusFact[]): FocusInsight[] {
    const out: FocusInsight[] = [];
    for (const ins of insights) {
      if (FocusInsightValidator.isValid(ins, facts)) {
        out.push(ins);
      }
    }
    return out;
  }
}
