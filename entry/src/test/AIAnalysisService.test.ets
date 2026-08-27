import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { AIAnalysisService, StudySession } from '../main/ets/services/AIAnalysisService';

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

export default function aiAnalysisTest() {
  const service: AIAnalysisService = AIAnalysisService.getInstance();
  describe('AIAnalysisService', () => {
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
  });
}
