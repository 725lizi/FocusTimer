// services/profile/FocusProfileStats.ets
// 模型分工：确定性统计引擎（纯函数、不联网、不依赖系统 API），由 DeepSeek 负责。
// 所有指标都由程序现算，结果可人工复算；只负责「算事实」，不在这里生成任何 AI 结论。

import { StudySession } from '../LearningAnalysisService';
import { CategoryShare, FocusFact, FocusProfileStatsResult, ProfileWindow, SegmentShare } from './FocusProfileTypes';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const UNCATEGORIZED: string = '未分类';
/** 单次时长超过该值（分钟）视为可疑极端值：保留并标注，不静默丢弃 */
const EXTREME_DURATION_MINUTES: number = 480;
/** 数据不足阈值：样本量或活跃天数低于对应值时标记 insufficientData */
const MIN_SAMPLE_SIZE: number = 3;
const MIN_ACTIVE_DAYS: number = 2;

interface SegmentDef {
  key: string;
  label: string;
}

interface SegmentBucket extends SegmentDef {
  minutes: number;
}

export class FocusProfileStats {
  /**
   * 构建一个窗口的确定性统计结果。
   * @param allSessions 全部专注记录（方法内部按窗口过滤）
   * @param windowDays 窗口天数 7 / 30
   * @param now 当前时间戳（毫秒）；测试时可注入固定时间，保证结果可复现
   */
  static build(allSessions: StudySession[], windowDays: ProfileWindow, now: number): FocusProfileStatsResult {
    const windowEnd: number = now;
    const windowStart: number = now - windowDays * DAY_MS;

    // 1) 窗口过滤：按开始时间落在 [windowStart, windowEnd] 内
    const inWindow: StudySession[] = allSessions.filter((s: StudySession) =>
      s.startTime >= windowStart && s.startTime <= windowEnd);

    // 2) 按 id 去重（保留首次出现），防止重复记录把数字算大
    const seenIds: Set<string> = new Set<string>();
    const deduped: StudySession[] = [];
    let duplicateCount: number = 0;
    for (const s of inWindow) {
      if (seenIds.has(s.id)) {
        duplicateCount++;
        continue;
      }
      seenIds.add(s.id);
      deduped.push(s);
    }

    // 3) 剔除时长非正的无效记录；标记可疑极端时长（保留，不丢数据）
    let invalidCount: number = 0;
    let extremeCount: number = 0;
    const valid: StudySession[] = [];
    for (const s of deduped) {
      if (!(s.duration > 0)) {
        invalidCount++;
        continue;
      }
      if (s.duration > EXTREME_DURATION_MINUTES) {
        extremeCount++;
      }
      valid.push(s);
    }

    const sampleSize: number = valid.length;
    const activeDays: number = FocusProfileStats.countActiveDays(valid);
    const totalMinutes: number = valid.reduce((sum: number, s: StudySession) => sum + s.duration, 0);
    const avgDailyMinutes: number = FocusProfileStats.round1(totalMinutes / windowDays);

    const categoryShares: CategoryShare[] = FocusProfileStats.buildCategoryShares(valid, totalMinutes);
    const segmentShares: SegmentShare[] = FocusProfileStats.buildSegmentShares(valid, totalMinutes);

    const durations: number[] = valid.map((s: StudySession) => s.duration);
    const avgSessionDuration: number = sampleSize > 0
      ? FocusProfileStats.round1(durations.reduce((a: number, b: number) => a + b, 0) / sampleSize)
      : 0;
    const medianSessionDuration: number = FocusProfileStats.median(durations);

    const sessionsPerActiveDay: number = activeDays > 0
      ? FocusProfileStats.round1(sampleSize / activeDays)
      : 0;

    // 周际变化只在 30 天窗口计算（7 天窗口凑不齐两个 7 天区间）
    const weekOverWeekChange: number = windowDays === 30
      ? FocusProfileStats.weekOverWeek(allSessions, now)
      : NaN;

    const insufficientData: boolean = sampleSize < MIN_SAMPLE_SIZE || activeDays < MIN_ACTIVE_DAYS;

    const cleaningNote: string =
      `按开始时间归属窗口与日期，一条记录不跨日拆分；空标签归「${UNCATEGORIZED}」。` +
      `本窗口去重 ${duplicateCount} 条、剔除时长非正的无效记录 ${invalidCount} 条、` +
      `可疑极端时长（>${EXTREME_DURATION_MINUTES} 分钟）${extremeCount} 条，极端值保留并在相关事实标注。`;

    const facts: FocusFact[] = FocusProfileStats.buildFacts(
      windowDays, valid, totalMinutes, avgDailyMinutes, categoryShares, segmentShares,
      avgSessionDuration, medianSessionDuration, sessionsPerActiveDay,
      weekOverWeekChange, cleaningNote, insufficientData);

    const result: FocusProfileStatsResult = {
      windowDays: windowDays,
      windowStart: windowStart,
      windowEnd: windowEnd,
      sampleSize: sampleSize,
      activeDays: activeDays,
      totalMinutes: totalMinutes,
      avgDailyMinutes: avgDailyMinutes,
      categoryShares: categoryShares,
      segmentShares: segmentShares,
      avgSessionDuration: avgSessionDuration,
      medianSessionDuration: medianSessionDuration,
      sessionsPerActiveDay: sessionsPerActiveDay,
      weekOverWeekChange: weekOverWeekChange,
      insufficientData: insufficientData,
      facts: facts
    };
    return result;
  }

  /** 取一条记录的有效类别：空/空白标签归未分类，去重，保证至少有一个类别 */
  private static categoriesOf(s: StudySession): string[] {
    const raw: string[] = s.tags;
    if (raw === null || raw === undefined || raw.length === 0) {
      return [UNCATEGORIZED];
    }
    const cleaned: string[] = [];
    for (const t of raw) {
      const name: string = (t !== null && t !== undefined && t.trim().length > 0)
        ? t.trim()
        : UNCATEGORIZED;
      if (cleaned.indexOf(name) === -1) {
        cleaned.push(name);
      }
    }
    return cleaned.length > 0 ? cleaned : [UNCATEGORIZED];
  }

  /** 类别分布：多标签记录的时长在各标签间均摊，保证各类别占比之和约等于 100% */
  private static buildCategoryShares(valid: StudySession[], totalMinutes: number): CategoryShare[] {
    const map: Map<string, number> = new Map<string, number>();
    for (const s of valid) {
      const cats: string[] = FocusProfileStats.categoriesOf(s);
      const per: number = s.duration / cats.length;
      for (const cat of cats) {
        const cur: number = map.get(cat) || 0;
        map.set(cat, cur + per);
      }
    }
    const shares: CategoryShare[] = [];
    map.forEach((minutes: number, category: string) => {
      const item: CategoryShare = {
        category: category,
        minutes: FocusProfileStats.round1(minutes),
        share: totalMinutes > 0 ? FocusProfileStats.round1(minutes / totalMinutes * 100) : 0
      };
      shares.push(item);
    });
    shares.sort((a: CategoryShare, b: CategoryShare) => b.minutes - a.minutes);
    return shares;
  }

  /** 固定 6 个时段定义，顺序固定，便于跨窗口对比 */
  private static segmentDefs(): SegmentDef[] {
    return [
      { key: 'dawn', label: '清晨（6-9点）' },
      { key: 'morning', label: '上午（9-12点）' },
      { key: 'noon', label: '午间（12-14点）' },
      { key: 'afternoon', label: '下午（14-18点）' },
      { key: 'evening', label: '晚间（18-21点）' },
      { key: 'night', label: '深夜（21-6点）' }
    ];
  }

  /** 按小时返回所属时段 */
  private static segmentOf(hour: number): SegmentDef {
    if (hour >= 6 && hour < 9) {
      return { key: 'dawn', label: '清晨（6-9点）' };
    }
    if (hour >= 9 && hour < 12) {
      return { key: 'morning', label: '上午（9-12点）' };
    }
    if (hour >= 12 && hour < 14) {
      return { key: 'noon', label: '午间（12-14点）' };
    }
    if (hour >= 14 && hour < 18) {
      return { key: 'afternoon', label: '下午（14-18点）' };
    }
    if (hour >= 18 && hour < 21) {
      return { key: 'evening', label: '晚间（18-21点）' };
    }
    return { key: 'night', label: '深夜（21-6点）' };
  }

  /** 时段分布：整条时长按开始小时归属一个时段，不跨时段拆分；无记录的时段分钟为 0 */
  private static buildSegmentShares(valid: StudySession[], totalMinutes: number): SegmentShare[] {
    const defs: SegmentDef[] = FocusProfileStats.segmentDefs();
    const buckets: Map<string, SegmentBucket> = new Map<string, SegmentBucket>();
    for (const d of defs) {
      const bucket: SegmentBucket = { key: d.key, label: d.label, minutes: 0 };
      buckets.set(d.key, bucket);
    }
    for (const s of valid) {
      const hour: number = new Date(s.startTime).getHours();
      const def: SegmentDef = FocusProfileStats.segmentOf(hour);
      const bucket: SegmentBucket = buckets.get(def.key) as SegmentBucket;
      bucket.minutes += s.duration;
    }
    const shares: SegmentShare[] = [];
    for (const d of defs) {
      const bucket: SegmentBucket = buckets.get(d.key) as SegmentBucket;
      const item: SegmentShare = {
        segmentKey: bucket.key,
        label: bucket.label,
        minutes: FocusProfileStats.round1(bucket.minutes),
        share: totalMinutes > 0 ? FocusProfileStats.round1(bucket.minutes / totalMinutes * 100) : 0
      };
      shares.push(item);
    }
    return shares;
  }

  /** 活跃天数：按本地年月日去重 */
  private static countActiveDays(valid: StudySession[]): number {
    const keys: Set<string> = new Set<string>();
    for (const s of valid) {
      keys.add(FocusProfileStats.dayKey(s.startTime));
    }
    return keys.size;
  }

  /** 本地年月日 key，格式 YYYY-MM-DD */
  private static dayKey(ts: number): string {
    const d: Date = new Date(ts);
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const ms: string = m < 10 ? '0' + m : m.toString();
    const ds: string = day < 10 ? '0' + day : day.toString();
    return `${d.getFullYear()}-${ms}-${ds}`;
  }

  /** 中位数：排序后取中间值，偶数个时取中间两个的平均，比均值更抗极端值 */
  private static median(values: number[]): number {
    if (values.length === 0) {
      return 0;
    }
    const sorted: number[] = [...values].sort((a: number, b: number) => a - b);
    const mid: number = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) {
      return FocusProfileStats.round1(sorted[mid]);
    }
    return FocusProfileStats.round1((sorted[mid - 1] + sorted[mid]) / 2);
  }

  /** 周际变化：最近 7 天 vs 再往前 7 天的总时长；上一周总时长为 0 时无法计算，返回 NaN */
  private static weekOverWeek(allSessions: StudySession[], now: number): number {
    const recentStart: number = now - 7 * DAY_MS;
    const previousStart: number = now - 14 * DAY_MS;
    let recentTotal: number = 0;
    let previousTotal: number = 0;
    for (const s of allSessions) {
      if (!(s.duration > 0)) {
        continue;
      }
      if (s.startTime > recentStart && s.startTime <= now) {
        recentTotal += s.duration;
      } else if (s.startTime > previousStart && s.startTime <= recentStart) {
        previousTotal += s.duration;
      }
    }
    if (previousTotal <= 0) {
      return NaN;
    }
    return FocusProfileStats.round1((recentTotal - previousTotal) / previousTotal * 100);
  }

  /** 构造全部带 id 的证据事实，AI 洞察只能引用这里的事实 */
  private static buildFacts(
    windowDays: ProfileWindow,
    valid: StudySession[],
    totalMinutes: number,
    avgDailyMinutes: number,
    categoryShares: CategoryShare[],
    segmentShares: SegmentShare[],
    avgSessionDuration: number,
    medianSessionDuration: number,
    sessionsPerActiveDay: number,
    weekOverWeekChange: number,
    cleaningNote: string,
    insufficientData: boolean
  ): FocusFact[] {
    const prefix: string = `f${windowDays}-`;
    const allIds: string[] = valid.map((s: StudySession) => s.id);
    const facts: FocusFact[] = [];

    const totalFact: FocusFact = {
      id: prefix + 'total',
      type: 'total_minutes',
      label: '总专注时长',
      value: totalMinutes,
      unit: '分钟',
      sourceSessionIds: [...allIds],
      calcNote: cleaningNote
    };
    facts.push(totalFact);

    const avgDailyFact: FocusFact = {
      id: prefix + 'avgdaily',
      type: 'avg_daily_minutes',
      label: '日均专注时长',
      value: avgDailyMinutes,
      unit: '分钟',
      sourceSessionIds: [...allIds],
      calcNote: `总时长 ÷ 窗口天数 ${windowDays}（含没有记录的日子）。` +
        (insufficientData ? '当前数据不足，该值仅供参考，不据此下结论。' : '')
    };
    facts.push(avgDailyFact);

    // 类别事实
    for (let i = 0; i < categoryShares.length; i++) {
      const c: CategoryShare = categoryShares[i];
      const ids: string[] = [];
      for (const s of valid) {
        if (FocusProfileStats.categoriesOf(s).indexOf(c.category) !== -1) {
          ids.push(s.id);
        }
      }
      const catFact: FocusFact = {
        id: prefix + 'cat-' + i,
        type: 'category_share',
        label: `「${c.category}」时长占比`,
        value: c.share,
        unit: '百分比',
        sourceSessionIds: ids,
        calcNote: c.category === UNCATEGORIZED
          ? '该类别为没有标签的记录，统一归为未分类；多标签记录时长在各标签间均摊。'
          : '多标签记录时长在各标签间均摊；占比 = 该类别分钟 ÷ 窗口总时长。'
      };
      facts.push(catFact);
    }

    // 时段事实
    for (const seg of segmentShares) {
      const ids: string[] = [];
      for (const s of valid) {
        const hour: number = new Date(s.startTime).getHours();
        if (FocusProfileStats.segmentOf(hour).key === seg.segmentKey) {
          ids.push(s.id);
        }
      }
      const segFact: FocusFact = {
        id: prefix + 'seg-' + seg.segmentKey,
        type: 'segment_share',
        label: `「${seg.label}」时长占比`,
        value: seg.share,
        unit: '百分比',
        sourceSessionIds: ids,
        calcNote: '按记录开始时间所在小时归属时段，整条时长计入，不跨时段拆分。'
      };
      facts.push(segFact);
    }

    const avgDurFact: FocusFact = {
      id: prefix + 'dur-avg',
      type: 'session_duration',
      label: '平均单次专注时长',
      value: avgSessionDuration,
      unit: '分钟',
      sourceSessionIds: [...allIds],
      calcNote: '窗口内全部有效记录时长的算术平均。'
    };
    facts.push(avgDurFact);

    const medianDurFact: FocusFact = {
      id: prefix + 'dur-median',
      type: 'session_duration',
      label: '单次专注时长中位数',
      value: medianSessionDuration,
      unit: '分钟',
      sourceSessionIds: [...allIds],
      calcNote: '把时长排序后取中间值，比平均值更不容易被极端时长带偏。'
    };
    facts.push(medianDurFact);

    const freqFact: FocusFact = {
      id: prefix + 'freq',
      type: 'frequency',
      label: '平均每活跃天记录条数',
      value: sessionsPerActiveDay,
      unit: '次',
      sourceSessionIds: [...allIds],
      calcNote: `样本量 ${allIds.length} ÷ 活跃天数；只统计有记录的日子。`
    };
    facts.push(freqFact);

    if (!isNaN(weekOverWeekChange)) {
      const wowFact: FocusFact = {
        id: prefix + 'wow',
        type: 'week_change',
        label: '最近一周相对上一周时长变化',
        value: weekOverWeekChange,
        unit: '百分比',
        sourceSessionIds: [...allIds],
        calcNote: '（最近 7 天总时长 − 再往前 7 天总时长）÷ 再往前 7 天总时长；正值表示最近一周时长增加。'
      };
      facts.push(wowFact);
    }

    return facts;
  }

  /** 保留一位小数 */
  private static round1(n: number): number {
    return Math.round(n * 10) / 10;
  }
}
