import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { LearningAnalysisService, StudySession } from '../main/ets/services/LearningAnalysisService';

function makeSession(id: string, startTime: number, duration: number, tags: string[],
  isInterrupted: boolean = false, interruptCount: number = 0): StudySession {
  const session: StudySession = {
    id: id,
    startTime: startTime,
    duration: duration,
    tags: tags,
    isInterrupted: isInterrupted,
    interruptCount: interruptCount
  };
  return session;
}

export default function learningAnalysisTest() {
  const service: LearningAnalysisService = LearningAnalysisService.getInstance();
  describe('LearningAnalysisService', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('generateReport_emptySessions_shouldReturnEmptyReport', 0, async () => {
      const report = await service.generateReport([]);
      expect(report.totalMinutes).assertEqual(0);
      expect(report.focusScore).assertEqual(0);
      expect(report.totalDays).assertEqual(0);
      expect(report.avgDailyMinutes).assertEqual(0);
      expect(report.bestTimeSegment).assertEqual('暂无数据');
      expect(report.trend).assertEqual('stable');
      expect(report.suggestion).assertContain('开始你的第一次');
    });

    it('generateReport_shouldSumTotalMinutes', 0, async () => {
      const sessions: StudySession[] = [
        makeSession('1', Date.now(), 25, ['高数']),
        makeSession('2', Date.now() + 1000, 15, ['英语']),
        makeSession('3', Date.now() + 2000, 5, ['高数'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.totalMinutes).assertEqual(45);
    });

    it('generateReport_shouldAggregateTagDistribution', 0, async () => {
      const sessions: StudySession[] = [
        makeSession('1', Date.now(), 25, ['高数']),
        makeSession('2', Date.now() + 1000, 15, ['英语']),
        makeSession('3', Date.now() + 2000, 5, ['高数'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.tagDistribution.get('高数')).assertEqual(30);
      expect(report.tagDistribution.get('英语')).assertEqual(15);
    });

    it('generateReport_focusScoreWithinBounds', 0, async () => {
      const sessions: StudySession[] = [
        makeSession('1', Date.now(), 45, ['高数'], true, 2),
        makeSession('2', Date.now() + 1000, 45, ['高数']),
        makeSession('3', Date.now() + 2000, 45, ['英语'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.focusScore >= 0).assertTrue();
      expect(report.focusScore <= 100).assertTrue();
    });

    it('generateReport_shouldPickBestTimeSegment', 0, async () => {
      const morning = new Date();
      morning.setHours(8, 0, 0, 0);
      const sessions: StudySession[] = [
        makeSession('1', morning.getTime(), 25, ['高数'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.bestTimeSegment).assertEqual('🌅 清晨（6-9点）');
    });

    it('recommendPomodoro_lessThan3Sessions_shouldDefault25', 0, () => {
      const sessions: StudySession[] = [makeSession('1', Date.now(), 25, ['高数'])];
      expect(service.recommendPomodoroDuration(sessions)).assertEqual(25);
    });

    it('recommendPomodoro_shouldClampBetween15And90', 0, () => {
      const sessions: StudySession[] = [
        makeSession('1', Date.now(), 20, ['高数']),
        makeSession('2', Date.now(), 30, ['英语']),
        makeSession('3', Date.now(), 40, ['高数']),
        makeSession('4', Date.now(), 50, ['英语'])
      ];
      const recommended = service.recommendPomodoroDuration(sessions);
      expect(recommended >= 15).assertTrue();
      expect(recommended <= 90).assertTrue();
      expect(recommended % 5).assertEqual(0);
    });

    it('extractNoteKeywords_empty_shouldReturnEmpty', 0, async () => {
      const keywords = await service.extractNoteKeywords('');
      expect(keywords.length).assertEqual(0);
      const blank = await service.extractNoteKeywords('   ');
      expect(blank.length).assertEqual(0);
    });

    it('extractNoteKeywords_chinese_shouldExtract', 0, async () => {
      const keywords = await service.extractNoteKeywords('微分方程 微分方程 求导 积分 函数');
      expect(keywords.length > 0).assertTrue();
    });

    it('extractNoteKeywords_formula_shouldExtract', 0, async () => {
      const keywords = await service.extractNoteKeywords('公式 $y = kx + b$ 很重要');
      expect(keywords.length > 0).assertTrue();
    });

    it('parseDocument_empty_shouldReturnEmpty', 0, async () => {
      const result = await service.parseDocument('  ');
      expect(result.keywords.length).assertEqual(0);
      expect(result.summary).assertEqual('');
    });

    it('parseDocument_content_shouldBuildSummary', 0, async () => {
      const result = await service.parseDocument('高斯公式 高斯公式 散度 旋度');
      expect(result.summary.length > 0).assertTrue();
    });

    it('generateWeeklyReport_empty_shouldReturnHint', 0, async () => {
      const report = await service.generateWeeklyReport([]);
      expect(report).assertContain('暂无学习记录');
    });

    it('generateWeeklyReport_withData_shouldContainHeader', 0, async () => {
      const sessions: StudySession[] = [makeSession('1', Date.now(), 30, ['高数'])];
      const report = await service.generateWeeklyReport(sessions);
      expect(report).assertContain('本周学习报告');
    });

    // ===== 2.7 补充：边界与分支覆盖 =====

    it('getInstance_shouldReturnSameSingleton', 0, () => {
      // 单例：多次取到的是同一个实例
      const a: LearningAnalysisService = LearningAnalysisService.getInstance();
      const b: LearningAnalysisService = LearningAnalysisService.getInstance();
      expect(a === b).assertTrue();
    });

    it('generateReport_singleSession_shouldCountOneDay', 0, async () => {
      // 单条：只算 1 天，日均=该条时长，趋势必为 stable（样本不足不下结论）
      const t: number = new Date(2026, 7, 20, 10, 0).getTime();
      const report = await service.generateReport([makeSession('s1', t, 40, ['高数'])]);
      expect(report.totalDays).assertEqual(1);
      expect(report.totalMinutes).assertEqual(40);
      expect(report.avgDailyMinutes).assertEqual(40);
      expect(report.trend).assertEqual('stable');
    });

    it('generateReport_multiSessionsSameDay_shouldDedupDays', 0, async () => {
      // 跨天去重：同一天 3 条 + 次日 1 条 => 仅 2 天；日均=总时长/天数 四舍五入
      const d1: number = new Date(2026, 7, 20, 9, 0).getTime();
      const d2: number = new Date(2026, 7, 20, 15, 0).getTime();
      const d3: number = new Date(2026, 7, 20, 20, 0).getTime();
      const d4: number = new Date(2026, 7, 21, 9, 0).getTime();
      const sessions: StudySession[] = [
        makeSession('a', d1, 30, ['高数']),
        makeSession('b', d2, 30, ['高数']),
        makeSession('c', d3, 30, ['英语']),
        makeSession('d', d4, 60, ['高数'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.totalDays).assertEqual(2);
      expect(report.totalMinutes).assertEqual(150);
      expect(report.avgDailyMinutes).assertEqual(75);
    });

    it('generateReport_interruption_shouldLowerFocusScore', 0, async () => {
      // 等间隔 24h、单次均 45 分钟时：时长分=100、规律分=100；
      // 全中断 => 中断分=0，总分 round(100*.4+0*.35+100*.25)=65；全不中断 => 100
      const base: number = new Date(2026, 7, 1, 9, 0).getTime();
      const dayMs: number = 24 * 60 * 60 * 1000;
      const allInterrupted: StudySession[] = [
        makeSession('a', base, 45, ['x'], true),
        makeSession('b', base + dayMs, 45, ['x'], true),
        makeSession('c', base + 2 * dayMs, 45, ['x'], true)
      ];
      const noneInterrupted: StudySession[] = [
        makeSession('a', base, 45, ['x']),
        makeSession('b', base + dayMs, 45, ['x']),
        makeSession('c', base + 2 * dayMs, 45, ['x'])
      ];
      const r1 = await service.generateReport(allInterrupted);
      const r2 = await service.generateReport(noneInterrupted);
      expect(r1.focusScore).assertEqual(65);
      expect(r2.focusScore).assertEqual(100);
      expect(r1.focusScore < r2.focusScore).assertTrue();
    });

    it('generateReport_veryLongDuration_shouldCapScoreWithin100', 0, async () => {
      // 单次时长远超 45 分钟，时长分被 Math.min 封顶 100；单条规律分取默认 80，
      // 总分 round(100*.4+100*.35+80*.25)=95，且永远不超过 100
      const t: number = new Date(2026, 7, 20, 10, 0).getTime();
      const report = await service.generateReport([makeSession('big', t, 120, ['高数'])]);
      expect(report.focusScore).assertEqual(95);
      expect(report.focusScore <= 100).assertTrue();
    });

    it('generateReport_emptyTags_shouldYieldEmptyTagMap', 0, async () => {
      // 没有任何标签时标签分布应为空表，不报错
      const t: number = new Date(2026, 7, 20, 10, 0).getTime();
      const report = await service.generateReport([makeSession('e', t, 30, [])]);
      expect(report.tagDistribution.size).assertEqual(0);
    });

    it('generateReport_trendUp_shouldReflectInSuggestion', 0, async () => {
      // 4 条（中点=2），后半均值比前半高 >10% => up，建议含提升话术
      const t0: number = new Date(2026, 7, 1, 9, 0).getTime();
      const dayMs: number = 24 * 60 * 60 * 1000;
      const sessions: StudySession[] = [
        makeSession('1', t0, 20, ['a']),
        makeSession('2', t0 + dayMs, 20, ['a']),
        makeSession('3', t0 + 2 * dayMs, 60, ['a']),
        makeSession('4', t0 + 3 * dayMs, 60, ['a'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.trend).assertEqual('up');
      expect(report.suggestion).assertContain('持续提升');
    });

    it('generateReport_trendDown_shouldReflectInSuggestion', 0, async () => {
      // 后半均值比前半低 >10% => down，建议含下降提醒
      const t0: number = new Date(2026, 7, 1, 9, 0).getTime();
      const dayMs: number = 24 * 60 * 60 * 1000;
      const sessions: StudySession[] = [
        makeSession('1', t0, 60, ['a']),
        makeSession('2', t0 + dayMs, 60, ['a']),
        makeSession('3', t0 + 2 * dayMs, 20, ['a']),
        makeSession('4', t0 + 3 * dayMs, 20, ['a'])
      ];
      const report = await service.generateReport(sessions);
      expect(report.trend).assertEqual('down');
      expect(report.suggestion).assertContain('下降趋势');
    });

    it('generateReport_timeSegmentBoundaries_shouldMapCorrectly', 0, async () => {
      // 覆盖各时段及临界小时：6 点属清晨、9/13/16/19 分别属上午/午间/下午/晚间、21 与 23 属深夜
      const hours: number[] = [6, 9, 13, 16, 19, 21, 23];
      const expected: string[] = [
        '🌅 清晨（6-9点）', '☀️ 上午（9-12点）', '🌤️ 午间（12-14点）',
        '🌇 下午（14-18点）', '🌆 晚间（18-21点）', '🌙 深夜（21-6点）', '🌙 深夜（21-6点）'
      ];
      for (let i = 0; i < hours.length; i++) {
        const d: Date = new Date();
        d.setHours(hours[i], 30, 0, 0);
        const report = await service.generateReport([makeSession('h', d.getTime(), 10, ['a'])]);
        expect(report.bestTimeSegment).assertEqual(expected[i]);
      }
    });

    it('recommendPomodoro_empty_shouldDefault25', 0, () => {
      expect(service.recommendPomodoroDuration([])).assertEqual(25);
    });

    it('recommendPomodoro_veryShort_shouldClampToMin15', 0, () => {
      // 中位数/均值都极小 => 向上取整后仍被下限钳到 15
      const t: number = Date.now();
      const sessions: StudySession[] = [
        makeSession('1', t, 5, []), makeSession('2', t + 1000, 5, []), makeSession('3', t + 2000, 5, [])
      ];
      expect(service.recommendPomodoroDuration(sessions)).assertEqual(15);
    });

    it('recommendPomodoro_veryLong_shouldClampToMax90', 0, () => {
      // 中位数/均值都极大 => 被上限钳到 90
      const t: number = Date.now();
      const sessions: StudySession[] = [
        makeSession('1', t, 200, []), makeSession('2', t + 1000, 200, []), makeSession('3', t + 2000, 200, [])
      ];
      expect(service.recommendPomodoroDuration(sessions)).assertEqual(90);
    });

    it('recommendPomodoro_normal_shouldRoundUpToMultipleOf5', 0, () => {
      // 22 分钟 => ceil(22/5)*5 = 25，验证向上取整到 5 的倍数
      const t: number = Date.now();
      const sessions: StudySession[] = [
        makeSession('1', t, 22, []), makeSession('2', t + 1000, 22, []), makeSession('3', t + 2000, 22, [])
      ];
      expect(service.recommendPomodoroDuration(sessions)).assertEqual(25);
    });

    it('extractNoteKeywords_englishTerms_shouldExtract', 0, async () => {
      const keywords: string[] = await service.extractNoteKeywords('Bayesian Network is very important');
      const hit: boolean = keywords.some(k => k.includes('Bayesian Network'));
      expect(hit).assertTrue();
    });

    it('extractNoteKeywords_stopWords_shouldBeFiltered', 0, async () => {
      // 常见虚词进停用词表被剔除，真实专业词保留
      const joined: string = (await service.extractNoteKeywords('我们 因为 所以 微分方程')).join('|');
      expect(joined.includes('我们')).assertFalse();
      expect(joined.includes('因为')).assertFalse();
      expect(joined.includes('所以')).assertFalse();
      expect(joined.includes('微分方程')).assertTrue();
    });

    it('generateWeeklyReport_weekOverWeekUp_shouldMentionRise', 0, async () => {
      // 上周共 60 分钟、本周共 120 分钟 => 环比提升 >10%，并输出科目明细
      const now: number = Date.now();
      const last: number = now - 7 * 24 * 60 * 60 * 1000;
      const sessions: StudySession[] = [
        makeSession('l1', last, 30, ['高数']),
        makeSession('l2', last + 1000, 30, ['高数']),
        makeSession('t1', now, 60, ['高数']),
        makeSession('t2', now + 1000, 60, ['高数'])
      ];
      const report = await service.generateWeeklyReport(sessions);
      expect(report).assertContain('提升');
      expect(report).assertContain('高数');
    });

    it('generateWeeklyReport_weekOverWeekDown_shouldMentionDrop', 0, async () => {
      // 上周 120、本周 30 => 环比下降 >10%
      const now: number = Date.now();
      const last: number = now - 7 * 24 * 60 * 60 * 1000;
      const sessions: StudySession[] = [
        makeSession('l1', last, 60, ['高数']),
        makeSession('l2', last + 1000, 60, ['高数']),
        makeSession('t1', now, 30, ['高数'])
      ];
      const report = await service.generateWeeklyReport(sessions);
      expect(report).assertContain('下降');
    });

    it('generateWeeklyReport_lowDailyAverage_shouldWarn', 0, async () => {
      // 本周仅 20 分钟，日均 20/7 < 30 => 提示日均偏少
      const sessions: StudySession[] = [makeSession('t1', Date.now(), 20, ['高数'])];
      const report = await service.generateWeeklyReport(sessions);
      expect(report).assertContain('日均学习时间偏少');
    });
  });
}
