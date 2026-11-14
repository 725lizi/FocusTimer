import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { StudySession } from '../main/ets/services/LearningAnalysisService';
import { FocusProfileStats } from '../main/ets/services/profile/FocusProfileStats';
import { FocusFact, FocusProfileStatsResult } from '../main/ets/services/profile/FocusProfileTypes';

// 固定基准时间：2026-11-13 12:00（本地），便于断言且结果可复现
const NOW: number = new Date(2026, 10, 13, 12, 0, 0, 0).getTime();
const DAY_MS: number = 24 * 60 * 60 * 1000;

function makeSession(id: string, startTime: number, duration: number, tags: string[],
  isInterrupted: boolean = false, interruptCount: number = 0): StudySession {
  const s: StudySession = {
    id: id,
    startTime: startTime,
    duration: duration,
    tags: tags,
    isInterrupted: isInterrupted,
    interruptCount: interruptCount
  };
  return s;
}

function factById(facts: FocusFact[], id: string): FocusFact {
  for (const f of facts) {
    if (f.id === id) {
      return f;
    }
  }
  throw new Error('fact not found: ' + id);
}

function hasFact(facts: FocusFact[], id: string): boolean {
  for (const f of facts) {
    if (f.id === id) {
      return true;
    }
  }
  return false;
}

export default function focusProfileStatsTest() {
  describe('FocusProfileStats', () => {
    beforeEach(() => {
    });

    // 1) 空记录：数值为 0、标记数据不足，仍生成基础事实，不报错
    it('empty_sessions_shouldReturnZeroAndInsufficient', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build([], 7, NOW);
      expect(r.sampleSize).assertEqual(0);
      expect(r.totalMinutes).assertEqual(0);
      expect(r.activeDays).assertEqual(0);
      expect(r.avgDailyMinutes).assertEqual(0);
      expect(r.insufficientData).assertTrue();
      expect(factById(r.facts, 'f7-total').value).assertEqual(0);
    });

    // 2) 总时长正确求和
    it('total_minutes_shouldSumDurations', 0, () => {
      const sessions: StudySession[] = [
        makeSession('a', NOW - DAY_MS, 25, ['高数']),
        makeSession('b', NOW - DAY_MS + 1000, 15, ['英语']),
        makeSession('c', NOW - DAY_MS + 2000, 5, ['高数'])
      ];
      const r: FocusProfileStatsResult = FocusProfileStats.build(sessions, 7, NOW);
      expect(r.totalMinutes).assertEqual(45);
    });

    // 3) 窗口过滤：窗口外（8 天前）的记录不纳入 7 天窗口
    it('window_filter_shouldExcludeOutOfRange', 0, () => {
      const sessions: StudySession[] = [
        makeSession('inside', NOW - 2 * DAY_MS, 30, ['高数']),
        makeSession('outside', NOW - 8 * DAY_MS, 60, ['高数'])
      ];
      const r: FocusProfileStatsResult = FocusProfileStats.build(sessions, 7, NOW);
      expect(r.sampleSize).assertEqual(1);
      expect(r.totalMinutes).assertEqual(30);
    });

    // 4) 相同 id 去重，只保留一条
    it('duplicate_ids_shouldDedup', 0, () => {
      const sessions: StudySession[] = [
        makeSession('same', NOW - DAY_MS, 30, ['高数']),
        makeSession('same', NOW - DAY_MS + 500, 30, ['高数'])
      ];
      const r: FocusProfileStatsResult = FocusProfileStats.build(sessions, 7, NOW);
      expect(r.sampleSize).assertEqual(1);
      expect(r.totalMinutes).assertEqual(30);
      expect(factById(r.facts, 'f7-total').calcNote).assertContain('去重 1 条');
    });

    // 5) 时长非正（0 或负数）的无效记录被剔除
    it('nonPositive_duration_shouldBeRemoved', 0, () => {
      const sessions: StudySession[] = [
        makeSession('ok', NOW - DAY_MS, 30, ['高数']),
        makeSession('zero', NOW - DAY_MS + 1000, 0, ['高数']),
        makeSession('neg', NOW - DAY_MS + 2000, -10, ['高数'])
      ];
      const r: FocusProfileStatsResult = FocusProfileStats.build(sessions, 7, NOW);
      expect(r.sampleSize).assertEqual(1);
      expect(r.totalMinutes).assertEqual(30);
      expect(factById(r.facts, 'f7-total').calcNote).assertContain('无效记录 2 条');
    });

    // 6) 空标签归未分类
    it('empty_tags_shouldMapToUncategorized', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('a', NOW - DAY_MS, 30, [])], 7, NOW);
      expect(r.categoryShares.length).assertEqual(1);
      expect(r.categoryShares[0].category).assertEqual('未分类');
      expect(r.categoryShares[0].minutes).assertEqual(30);
      expect(r.categoryShares[0].share).assertEqual(100);
    });

    // 7) 多标签记录时长均摊：30 分钟两个标签，各 15
    it('multiTag_duration_shouldSplitEvenly', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('a', NOW - DAY_MS, 30, ['高数', '英语'])], 7, NOW);
      let gao: number = -1;
      let ying: number = -1;
      for (const c of r.categoryShares) {
        if (c.category === '高数') {
          gao = c.minutes;
        }
        if (c.category === '英语') {
          ying = c.minutes;
        }
      }
      expect(gao).assertEqual(15);
      expect(ying).assertEqual(15);
    });

    // 8) 类别占比之和约等于 100%（允许小数舍入误差）
    it('category_shares_shouldSumAround100', 0, () => {
      const sessions: StudySession[] = [
        makeSession('a', NOW - 3 * DAY_MS, 30, ['高数', '英语']),
        makeSession('b', NOW - 2 * DAY_MS, 40, ['高数']),
        makeSession('c', NOW - DAY_MS, 30, [])
      ];
      const r: FocusProfileStatsResult = FocusProfileStats.build(sessions, 7, NOW);
      let sum: number = 0;
      for (const c of r.categoryShares) {
        sum += c.share;
      }
      expect(sum >= 99).assertTrue();
      expect(sum <= 101).assertTrue();
    });

    // 9) 时段归属：8 点属清晨、10 点属上午、12 点属午间、20 点属晚间、23 点属深夜
    it('hour_shouldMapToCorrectSegment', 0, () => {
      const cases: number[][] = [
        [8, 'dawn'], [10, 'morning'], [12, 'noon'], [20, 'evening'], [23, 'night']
      ];
      for (const c of cases) {
        const t: Date = new Date(2026, 10, 10);
        t.setHours(c[0], 0, 0, 0);
        const r: FocusProfileStatsResult = FocusProfileStats.build(
          [makeSession('h', t.getTime(), 20, ['高数'])], 7, NOW);
        expect(r.segmentShares.length).assertEqual(6);
        let hit: boolean = false;
        for (const seg of r.segmentShares) {
          if (seg.segmentKey === c[1] && seg.minutes === 20) {
            hit = true;
          }
        }
        expect(hit).assertTrue();
      }
    });

    // 10) 中位数：奇数取中间，偶数取中间两个平均
    it('median_shouldHandleOddAndEven', 0, () => {
      const odd: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('a', NOW - 3 * DAY_MS, 10, ['x']),
        makeSession('b', NOW - 2 * DAY_MS, 20, ['x']),
        makeSession('c', NOW - DAY_MS, 30, ['x'])
      ], 7, NOW);
      expect(odd.medianSessionDuration).assertEqual(20);

      const even: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('a', NOW - 4 * DAY_MS, 10, ['x']),
        makeSession('b', NOW - 3 * DAY_MS, 20, ['x']),
        makeSession('c', NOW - 2 * DAY_MS, 30, ['x']),
        makeSession('d', NOW - DAY_MS, 40, ['x'])
      ], 7, NOW);
      expect(even.medianSessionDuration).assertEqual(25);
    });

    // 11) 极端时长不剔除，保留并在清洗说明标注
    it('extreme_duration_shouldKeepAndNote', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('big', NOW - DAY_MS, 600, ['高数'])], 7, NOW);
      expect(r.sampleSize).assertEqual(1);
      expect(r.totalMinutes).assertEqual(600);
      expect(factById(r.facts, 'f7-total').calcNote).assertContain('极端时长');
    });

    // 12) 数据不足：样本量少于 3 标记
    it('few_samples_shouldFlagInsufficient', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('a', NOW - DAY_MS, 30, ['高数']),
        makeSession('b', NOW - 2 * DAY_MS, 30, ['高数'])], 7, NOW);
      expect(r.insufficientData).assertTrue();
    });

    // 13) 30 天窗口周际变化：最近 7 天 60 分钟、上一周 30 分钟 => +100%
    it('weekOverWeek_shouldComputeChange', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('recent', NOW - 3 * DAY_MS, 60, ['高数']),
        makeSession('previous', NOW - 10 * DAY_MS, 30, ['高数'])
      ], 30, NOW);
      expect(r.weekOverWeekChange).assertEqual(100);
      expect(hasFact(r.facts, 'f30-wow')).assertTrue();
    });

    // 14) 上一周总时长为 0 时周际变化为 NaN，且不生成 wow 事实
    it('weekOverWeek_zeroBase_shouldBeNaN', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('recent', NOW - 3 * DAY_MS, 60, ['高数'])], 30, NOW);
      expect(isNaN(r.weekOverWeekChange)).assertTrue();
      expect(hasFact(r.facts, 'f30-wow')).assertFalse();
    });

    // 15) 7 天窗口不计算周际变化（NaN）
    it('sevenDay_window_shouldNotComputeWoW', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('a', NOW - DAY_MS, 30, ['高数'])], 7, NOW);
      expect(isNaN(r.weekOverWeekChange)).assertTrue();
    });

    // 16) 事实 id 唯一
    it('fact_ids_shouldBeUnique', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('a', NOW - 3 * DAY_MS, 30, ['高数', '英语']),
        makeSession('b', NOW - 2 * DAY_MS, 40, []),
        makeSession('c', NOW - DAY_MS, 20, ['高数'])
      ], 30, NOW);
      const ids: Set<string> = new Set<string>();
      for (const f of r.facts) {
        expect(ids.has(f.id)).assertFalse();
        ids.add(f.id);
      }
    });

    // 17) 事实的来源记录 id 可追溯：未分类事实挂对应记录
    it('fact_sourceIds_shouldBeTraceable', 0, () => {
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('a', NOW - DAY_MS, 30, [])], 7, NOW);
      const f: FocusFact = factById(r.facts, 'f7-cat-0');
      expect(f.sourceSessionIds.length).assertEqual(1);
      expect(f.sourceSessionIds[0]).assertEqual('a');
    });

    // 18) 跨午夜记录按「开始日」归属、不跨日拆分：
    //     2026-11-12 23:50 开始、时长 20 分钟（实际时间跨到次日 00:10）。
    //     验证 sampleSize=1、totalMinutes=20、activeDays=1（只算开始那一天），
    //     开始小时 23 → 整条 20 分钟计入 night（深夜）时段，不拆到两个时段。
    it('crossMidnight_shouldBelongToStartDay', 0, () => {
      const crossStart: number = new Date(2026, 10, 12, 23, 50, 0, 0).getTime();
      const r: FocusProfileStatsResult = FocusProfileStats.build(
        [makeSession('cross', crossStart, 20, ['高数'])], 7, NOW);
      expect(r.sampleSize).assertEqual(1);
      expect(r.totalMinutes).assertEqual(20);
      // 开始日是 12 号、结束时刻已落到 13 号（确实跨了午夜）
      expect(new Date(crossStart).getDate()).assertEqual(12);
      expect(new Date(crossStart).getHours()).assertEqual(23);
      expect(new Date(crossStart + 20 * 60 * 1000).getDate()).assertEqual(13);
      // 但活跃天数只按开始日算 1 天，不因跨过午夜算成 2 天
      expect(r.activeDays).assertEqual(1);
      // 频率 = 样本量 1 ÷ 活跃天数 1 = 1；若跨午夜被算成 2 天，这里会是 0.5
      expect(factById(r.facts, 'f7-freq').value).assertEqual(1);
      // 整条 20 分钟只落入开始小时 23 所在的 night 时段，其余 5 个时段均为 0
      expect(r.segmentShares.length).assertEqual(6);
      expect(r.segmentShares[5].segmentKey).assertEqual('night');
      expect(r.segmentShares[5].minutes).assertEqual(20);
      expect(r.segmentShares[5].share).assertEqual(100);
      for (let i: number = 0; i < 5; i++) {
        expect(r.segmentShares[i].minutes).assertEqual(0);
      }
      const nightFact: FocusFact = factById(r.facts, 'f7-seg-night');
      expect(nightFact.sourceSessionIds.length).assertEqual(1);
      expect(nightFact.sourceSessionIds[0]).assertEqual('cross');

      // 日期归属反证：再补一条同一天（12 号 09:00）的记录，活跃天数仍为 1，
      // 说明跨午夜那条归属开始日 12 号，而不是次日 13 号
      const sameDayMorning: number = new Date(2026, 10, 12, 9, 0, 0, 0).getTime();
      const r2: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('cross', crossStart, 20, ['高数']),
        makeSession('same-day', sameDayMorning, 10, ['高数'])
      ], 7, NOW);
      expect(r2.sampleSize).assertEqual(2);
      expect(r2.totalMinutes).assertEqual(30);
      expect(r2.activeDays).assertEqual(1);
    });

    // 19) 午夜两侧边界各一条、分别归属正确：
    //     11 号 23:55（距午夜 5 分钟）与 12 号 00:05（过午夜 5 分钟），各 10 分钟。
    //     验证 activeDays=2（两条分属相邻两天，没有被合并成一天），
    //     两条都计入 night 时段且时段分钟为两者之和 20，证明边界记录既不合并也不丢弃。
    it('midnight_boundary_shouldCountTwoDays', 0, () => {
      const beforeMidnight: number = new Date(2026, 10, 11, 23, 55, 0, 0).getTime();
      const afterMidnight: number = new Date(2026, 10, 12, 0, 5, 0, 0).getTime();
      const r: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('before-midnight', beforeMidnight, 10, ['高数']),
        makeSession('after-midnight', afterMidnight, 10, ['英语'])
      ], 7, NOW);
      expect(r.sampleSize).assertEqual(2);
      expect(r.totalMinutes).assertEqual(20);
      // 11 号、12 号各算 1 天，共 2 个活跃天
      expect(r.activeDays).assertEqual(2);
      expect(new Date(beforeMidnight).getDate()).assertEqual(11);
      expect(new Date(beforeMidnight).getHours()).assertEqual(23);
      expect(new Date(afterMidnight).getDate()).assertEqual(12);
      expect(new Date(afterMidnight).getHours()).assertEqual(0);
      // 频率 = 样本量 2 ÷ 活跃天数 2 = 1
      expect(factById(r.facts, 'f7-freq').value).assertEqual(1);
      // 23 点与 0 点都属深夜（21-6 点）：10 + 10 = 20 分钟，占比 100%
      expect(r.segmentShares.length).assertEqual(6);
      expect(r.segmentShares[5].segmentKey).assertEqual('night');
      expect(r.segmentShares[5].minutes).assertEqual(20);
      expect(r.segmentShares[5].share).assertEqual(100);
      for (let i: number = 0; i < 5; i++) {
        expect(r.segmentShares[i].minutes).assertEqual(0);
      }
      const nightFact: FocusFact = factById(r.facts, 'f7-seg-night');
      expect(nightFact.sourceSessionIds.length).assertEqual(2);
      expect(nightFact.sourceSessionIds.indexOf('before-midnight') >= 0).assertTrue();
      expect(nightFact.sourceSessionIds.indexOf('after-midnight') >= 0).assertTrue();
    });

    // 20) 类别修改后统计「实时反映、无缓存污染」：
    //     同一条记录（同 id、同开始时间、同 30 分钟）先用 tags=[' 高数 '] build 得 r1，
    //     再用 tags=[' 英语 ']（新数组，模拟该记录类别被修改）build 得 r2。
    //     验证 r1 只有「高数」没有「英语」、r2 只有「英语」没有「高数」，
    //     且后一次 build 不污染前一次结果，两次计算相互独立。
    it('category_change_shouldReflectWithoutCache', 0, () => {
      const s1: StudySession = makeSession('mut', NOW - DAY_MS, 30, [' 高数 ']);
      const r1: FocusProfileStatsResult = FocusProfileStats.build([s1], 7, NOW);
      expect(r1.categoryShares.length).assertEqual(1);
      expect(r1.categoryShares[0].category).assertEqual('高数');
      expect(r1.categoryShares[0].minutes).assertEqual(30);
      expect(r1.categoryShares[0].share).assertEqual(100);
      expect(factById(r1.facts, 'f7-cat-0').label).assertContain('高数');

      const s2: StudySession = makeSession('mut', NOW - DAY_MS, 30, [' 英语 ']);
      const r2: FocusProfileStatsResult = FocusProfileStats.build([s2], 7, NOW);
      expect(r2.sampleSize).assertEqual(1);
      expect(r2.categoryShares.length).assertEqual(1);
      expect(r2.categoryShares[0].category).assertEqual('英语');
      expect(r2.categoryShares[0].minutes).assertEqual(30);
      expect(r2.categoryShares[0].share).assertEqual(100);
      expect(factById(r2.facts, 'f7-cat-0').label).assertContain('英语');

      // r2 里不应出现「高数」
      let gaoInR2: number = 0;
      for (let i: number = 0; i < r2.categoryShares.length; i++) {
        if (r2.categoryShares[i].category === '高数') {
          gaoInR2++;
        }
      }
      expect(gaoInR2).assertEqual(0);

      // r1 仍保持「高数」不变：后一次 build 没有改写它的类别分布与事实标签
      expect(r1.sampleSize).assertEqual(1);
      expect(r1.categoryShares.length).assertEqual(1);
      expect(r1.categoryShares[0].category).assertEqual('高数');
      expect(r1.categoryShares[0].minutes).assertEqual(30);
      expect(factById(r1.facts, 'f7-cat-0').label).assertContain('高数');
      let yingInR1: number = 0;
      for (let i: number = 0; i < r1.categoryShares.length; i++) {
        if (r1.categoryShares[i].category === '英语') {
          yingInR1++;
        }
      }
      expect(yingInR1).assertEqual(0);
    });

    // 21) 窗口边界按开始时间归属（与 build 的 [windowStart, windowEnd] 闭区间口径一致）：
    //     正好等于 windowStart 的记录纳入、比 windowStart 早 1 毫秒的不纳入；
    //     正好等于 windowEnd 的记录纳入、比 windowEnd 晚 1 毫秒的不纳入。
    it('window_boundary_shouldIncludeExactStartAndEnd', 0, () => {
      const windowStart: number = NOW - 7 * DAY_MS; // 2026-11-06 12:00
      const r: FocusProfileStatsResult = FocusProfileStats.build([
        makeSession('exact-start', windowStart, 30, ['高数']),
        makeSession('just-before', windowStart - 1, 30, ['高数']),
        makeSession('exact-end', NOW, 10, ['高数']),
        makeSession('just-after', NOW + 1, 10, ['高数'])
      ], 7, NOW);
      expect(r.windowDays).assertEqual(7);
      expect(r.windowStart).assertEqual(windowStart);
      expect(r.windowEnd).assertEqual(NOW);
      // 边界内 2 条（30 + 10 = 40 分钟），边界外 2 条被过滤
      expect(r.sampleSize).assertEqual(2);
      expect(r.totalMinutes).assertEqual(40);
      // 11-06 与 11-13 两个不同的本地日期
      expect(r.activeDays).assertEqual(2);
      const totalIds: string[] = factById(r.facts, 'f7-total').sourceSessionIds;
      expect(totalIds.length).assertEqual(2);
      expect(totalIds.indexOf('exact-start') >= 0).assertTrue();
      expect(totalIds.indexOf('exact-end') >= 0).assertTrue();
      expect(totalIds.indexOf('just-before') === -1).assertTrue();
      expect(totalIds.indexOf('just-after') === -1).assertTrue();
      // 两条纳入的记录都从本地 12:00 开始 → 都归午间时段，合计 40 分钟
      expect(r.segmentShares.length).assertEqual(6);
      expect(r.segmentShares[2].segmentKey).assertEqual('noon');
      expect(r.segmentShares[2].minutes).assertEqual(40);
      expect(r.segmentShares[2].share).assertEqual(100);
    });
  });
}
