// services/profile/FocusInsightRules.ets
// 模型分工：确定性规则洞察生成器（纯函数、不联网、不依赖系统 API），由 DeepSeek 负责。
// 它是画像永远可用的兜底：无 Key、无网或 AI 出错时，用已经算好的事实拼出带证据的洞察；
// 每条洞察只引用真实存在的事实 id，数据不足时只给提示、不硬下规律结论。

import {
  FocusInsight, FocusInsightBundle, FocusProfileStatsResult, ProfileWindow
} from './FocusProfileTypes';

export class FocusInsightRules {
  /**
   * 基于统计结果生成规则版洞察包。
   * @param result 已构建的确定性统计结果
   * @param now 当前时间戳（毫秒），写入 bundle
   */
  static build(result: FocusProfileStatsResult, now: number): FocusInsightBundle {
    const windowDays: ProfileWindow = result.windowDays;
    const prefix: string = `f${windowDays}-`;

    // 数据不足：只返回一条提示性洞察，不分析规律
    if (result.insufficientData) {
      const ids: string[] = FocusInsightRules.existingIds(result, [prefix + 'total']);
      const insight: FocusInsight = {
        id: prefix + 'ins-0',
        windowDays: windowDays,
        summary: `目前只记录了 ${result.sampleSize} 条、覆盖 ${result.activeDays} 天，数据还不够分析规律`,
        evidenceIds: ids,
        action: '再坚持记录几天（建议至少 3 条、覆盖 2 天以上），画像会自动生成规律分析',
        source: 'insufficient'
      };
      const bundle: FocusInsightBundle = {
        windowDays: windowDays,
        source: 'insufficient',
        insights: [insight],
        hint: '数据不足，以下为提示，不代表规律结论',
        generatedAt: now
      };
      return bundle;
    }

    const insights: FocusInsight[] = [];
    let seq: number = 0;

    // 1) 主导类别（类别已按分钟降序，取第一个）
    if (result.categoryShares.length > 0) {
      const catIndex: number = 0;
      const cat = result.categoryShares[catIndex];
      const ids: string[] = FocusInsightRules.existingIds(
        result, [prefix + 'cat-' + catIndex, prefix + 'total']);
      const action: string = cat.category === '未分类'
        ? '不少记录还没有标签，给它们补上科目标签，画像会更准确'
        : `可以把「${cat.category}」安排在状态最好的时段，先保证这块的专注质量`;
      const insight: FocusInsight = {
        id: prefix + 'ins-' + seq,
        windowDays: windowDays,
        summary: `你在「${cat.category}」上花的时间最多，共 ${cat.minutes} 分钟，占 ${cat.share}%`,
        evidenceIds: ids,
        action: action,
        source: 'rule'
      };
      insights.push(insight);
      seq++;
    }

    // 2) 高频时段（找分钟最大的时段）
    let topSegIndex: number = -1;
    let topSegMinutes: number = -1;
    for (let i = 0; i < result.segmentShares.length; i++) {
      if (result.segmentShares[i].minutes > topSegMinutes) {
        topSegMinutes = result.segmentShares[i].minutes;
        topSegIndex = i;
      }
    }
    if (topSegIndex >= 0) {
      const seg = result.segmentShares[topSegIndex];
      const ids: string[] = FocusInsightRules.existingIds(
        result, [prefix + 'seg-' + seg.segmentKey]);
      const insight: FocusInsight = {
        id: prefix + 'ins-' + seq,
        windowDays: windowDays,
        summary: `你最常在「${seg.label}」专注，占 ${seg.share}%`,
        evidenceIds: ids,
        action: `把最重要或最难的任务安排在「${seg.label}」，顺着你状态好的节奏走`,
        source: 'rule'
      };
      insights.push(insight);
      seq++;
    }

    // 3) 单次时长（均值 + 中位数）
    const durIds: string[] = FocusInsightRules.existingIds(
      result, [prefix + 'dur-avg', prefix + 'dur-median']);
    const durAction: string = result.medianSessionDuration < 25
      ? '单次时长偏短，可以试着从 25 分钟一个番茄起步，逐步拉长'
      : '单次专注比较稳定，保持这个节奏，注意每段之间安排短休息';
    const durInsight: FocusInsight = {
      id: prefix + 'ins-' + seq,
      windowDays: windowDays,
      summary: `你平均每次专注 ${result.avgSessionDuration} 分钟，中位数 ${result.medianSessionDuration} 分钟`,
      evidenceIds: durIds,
      action: durAction,
      source: 'rule'
    };
    insights.push(durInsight);
    seq++;

    // 4) 周际变化（仅 30 天且可计算）
    if (!isNaN(result.weekOverWeekChange)) {
      const wow: number = result.weekOverWeekChange;
      let summary: string = '';
      let action: string = '';
      if (wow > 0) {
        summary = `最近一周专注时长比上一周增加 ${wow}%`;
        action = '保持这个势头，把当前的安排固定下来';
      } else if (wow < 0) {
        summary = `最近一周专注时长比上一周减少 ${Math.abs(wow)}%`;
        action = '看看是哪几天断了，定一个低门槛的每日最小目标，先保证不断档';
      } else {
        summary = '最近一周专注时长与上一周基本持平';
        action = '时长稳定，可以试着提升单次专注的质量而不是只加时间';
      }
      const ids: string[] = FocusInsightRules.existingIds(result, [prefix + 'wow']);
      const insight: FocusInsight = {
        id: prefix + 'ins-' + seq,
        windowDays: windowDays,
        summary: summary,
        evidenceIds: ids,
        action: action,
        source: 'rule'
      };
      insights.push(insight);
    }

    const bundle: FocusInsightBundle = {
      windowDays: windowDays,
      source: 'rule',
      insights: insights,
      hint: '',
      generatedAt: now
    };
    return bundle;
  }

  /** 从期望 id 中筛出在 facts 里真实存在的那些，保证洞察引用的证据可追溯 */
  private static existingIds(result: FocusProfileStatsResult, wanted: string[]): string[] {
    const real: Set<string> = new Set<string>();
    for (const f of result.facts) {
      real.add(f.id);
    }
    const out: string[] = [];
    for (const id of wanted) {
      if (real.has(id)) {
        out.push(id);
      }
    }
    return out;
  }
}
