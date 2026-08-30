import { describe, it, expect } from '@ohos/hypium';
import { StudySession } from '../main/ets/services/LearningAnalysisService';
import { ReportPromptBuilder, WeeklyDataSummary } from '../main/ets/services/ai/ReportPromptBuilder';
import { SseChunkParser } from '../main/ets/services/ai/SseChunkParser';
import { ReportStrategy, LlmErrorKind } from '../main/ets/services/ai/ReportStrategy';
import { ReportStrategyInput, ChatMessage } from '../main/ets/services/ai/AiChatTypes';

function makeSession(id: string, startTime: number, duration: number, tags: string[],
  isInterrupted: boolean = false): StudySession {
  const session: StudySession = {
    id: id,
    startTime: startTime,
    duration: duration,
    tags: tags,
    isInterrupted: isInterrupted,
    interruptCount: isInterrupted ? 1 : 0
  };
  return session;
}

export default function aiReportLogicTest() {
  describe('AiReportLogic', () => {

    // ===== ReportPromptBuilder =====

    it('promptBuilder_shouldSplitThisWeekAndLastWeekAndAggregate', 0, () => {
      // now 取 2026-08-30（周日），本周一为 08-24；上周为 08-17~08-23
      const now: Date = new Date(2026, 7, 30, 12, 0, 0);
      const sessions: StudySession[] = [
        makeSession('l1', new Date(2026, 7, 18, 10).getTime(), 30, ['数学']),
        makeSession('l2', new Date(2026, 7, 19, 11).getTime(), 30, ['英语']),
        makeSession('t1', new Date(2026, 7, 25, 9).getTime(), 40, ['数学']),
        makeSession('t2', new Date(2026, 7, 26, 10).getTime(), 50, ['英语']),
        makeSession('t3', new Date(2026, 7, 26, 15).getTime(), 10, ['数学'], true)
      ];
      const s: WeeklyDataSummary = ReportPromptBuilder.buildSummary(sessions, now);
      expect(s.thisWeekMinutes).assertEqual(100);
      expect(s.lastWeekMinutes).assertEqual(60);
      expect(s.changePercent).assertEqual(66.7);
      expect(s.sessionCount).assertEqual(3);
      expect(s.activeDays).assertEqual(2);
      expect(s.interruptedCount).assertEqual(1);
      expect(s.avgSessionMinutes).assertEqual(33.3);
      expect(s.tagMinutes.get('数学')).assertEqual(50);
      expect(s.tagMinutes.get('英语')).assertEqual(50);
    });

    it('promptBuilder_empty_shouldAllZero', 0, () => {
      const s: WeeklyDataSummary = ReportPromptBuilder.buildSummary([], new Date(2026, 7, 30));
      expect(s.thisWeekMinutes).assertEqual(0);
      expect(s.lastWeekMinutes).assertEqual(0);
      expect(s.changePercent).assertEqual(0);
      expect(s.sessionCount).assertEqual(0);
      expect(s.activeDays).assertEqual(0);
      expect(s.tagMinutes.size).assertEqual(0);
    });

    it('promptBuilder_messages_shouldBeSystemPlusUserAndContainFacts', 0, () => {
      const now: Date = new Date(2026, 7, 30);
      const s: WeeklyDataSummary = ReportPromptBuilder.buildSummary(
        [makeSession('a', new Date(2026, 7, 25).getTime(), 45, ['高数'])], now);
      const messages: ChatMessage[] = ReportPromptBuilder.buildMessages(s);
      expect(messages.length).assertEqual(2);
      expect(messages[0].role).assertEqual('system');
      expect(messages[1].role).assertEqual('user');
      // 事实数字必须进 prompt，约束模型不得编造
      expect(messages[1].content).assertContain('45 分钟');
      expect(messages[0].content).assertContain('禁止编造');
    });

    it('promptBuilder_streamRequest_shouldBeStreamed', 0, () => {
      const req = ReportPromptBuilder.buildStreamRequest(
        ReportPromptBuilder.buildSummary([], new Date(2026, 7, 30)), 'deepseek-chat');
      expect(req.stream).assertTrue();
      expect(req.model).assertEqual('deepseek-chat');
      expect(req.messages.length).assertEqual(2);
      expect(req.max_tokens > 0).assertTrue();
    });

    it('promptBuilder_weekStart_shouldSnapToMondayMidnight', 0, () => {
      // 一周从周一 00:00 起：周日 08-30（上一周最后一天）回退到本周一 08-24；
      // 周一 08-31 00:30 已进入新一周，其本周一就是当天 08-31 00:00
      const sunday: Date = new Date(2026, 7, 30, 12, 0);
      const mondayEarly: Date = new Date(2026, 7, 31, 0, 30);
      const mondayOfSundayWeek: number = new Date(2026, 7, 24, 0, 0, 0, 0).getTime();
      const mondayOfNewWeek: number = new Date(2026, 7, 31, 0, 0, 0, 0).getTime();
      expect(ReportPromptBuilder.getWeekStartTime(sunday)).assertEqual(mondayOfSundayWeek);
      expect(ReportPromptBuilder.getWeekStartTime(mondayEarly)).assertEqual(mondayOfNewWeek);
    });

    // ===== SseChunkParser =====

    it('sse_singleChunk_shouldExtractDelta', 0, () => {
      const parser = new SseChunkParser();
      const d1: string[] = parser.feed('data: {"choices":[{"delta":{"content":"你好"}}]}\n\n');
      expect(d1.length).assertEqual(1);
      expect(d1[0]).assertEqual('你好');
      const d2: string[] = parser.feed('data: {"choices":[{"delta":{"content":"，世界"}}]}\n\n');
      expect(d2[0]).assertEqual('，世界');
    });

    it('sse_halfChunk_shouldBufferAndStitch', 0, () => {
      const parser = new SseChunkParser();
      // 第一片是半行，不应产出，且要留在 buffer
      expect(parser.feed('data: {"choices":[{"delta":{"content":"AB').length).assertEqual(0);
      expect(parser.pendingBuffer().length > 0).assertTrue();
      // 第二片补齐，拼回完整 JSON
      const stitched: string[] = parser.feed('"}}]}\n\n');
      expect(stitched.length).assertEqual(1);
      expect(stitched[0]).assertEqual('AB');
      expect(parser.pendingBuffer()).assertEqual('');
    });

    it('sse_doneMarker_shouldSetDoneWithoutText', 0, () => {
      const parser = new SseChunkParser();
      expect(parser.feed('data: [DONE]\n\n').length).assertEqual(0);
      expect(parser.isDone()).assertTrue();
    });

    it('sse_badJsonAndEmptyDelta_shouldBeSafe', 0, () => {
      const parser = new SseChunkParser();
      expect(parser.feed('data: not-json\n\n').length).assertEqual(0);
      expect(parser.feed('data: {"choices":[{"delta":{}}]}\n\n').length).assertEqual(0);
      expect(parser.isDone()).assertFalse();
    });

    it('sse_shouldIgnoreNonDataLines', 0, () => {
      const parser = new SseChunkParser();
      const out: string[] = parser.feed('event: message\ndata: {"choices":[{"delta":{"content":"X"}}]}\n\n');
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('X');
    });

    it('sse_reset_shouldClearState', 0, () => {
      const parser = new SseChunkParser();
      parser.feed('data: [DONE]\n\n');
      parser.reset();
      expect(parser.isDone()).assertFalse();
      expect(parser.pendingBuffer()).assertEqual('');
    });

    // ===== ReportStrategy =====

    it('strategy_decideSource_shouldRequireAllThreeConditions', 0, () => {
      const ok: ReportStrategyInput = { llmEnabled: true, online: true, hasApiKey: true };
      expect(ReportStrategy.decideSource(ok)).assertEqual('llm');
      const cases: ReportStrategyInput[] = [
        { llmEnabled: false, online: true, hasApiKey: true },
        { llmEnabled: true, online: false, hasApiKey: true },
        { llmEnabled: true, online: true, hasApiKey: false },
        { llmEnabled: false, online: false, hasApiKey: false }
      ];
      cases.forEach(c => {
        expect(ReportStrategy.decideSource(c)).assertEqual('rule');
      });
    });

    it('strategy_ruleReason_shouldExplainWhy', 0, () => {
      expect(ReportStrategy.ruleReason({ llmEnabled: false, online: true, hasApiKey: true }))
        .assertContain('未开启');
      expect(ReportStrategy.ruleReason({ llmEnabled: true, online: false, hasApiKey: true }))
        .assertContain('无网络');
      expect(ReportStrategy.ruleReason({ llmEnabled: true, online: true, hasApiKey: false }))
        .assertContain('API Key');
    });

    it('strategy_shouldFallbackExceptUserCancel', 0, () => {
      const fallbackKinds: LlmErrorKind[] = ['network', 'timeout', 'unauthorized', 'rate_limited', 'server', 'empty'];
      fallbackKinds.forEach(k => expect(ReportStrategy.shouldFallback(k)).assertTrue());
      expect(ReportStrategy.shouldFallback('cancelled')).assertFalse();
    });

    it('strategy_isTerminal_shouldRecognizeEndStates', 0, () => {
      expect(ReportStrategy.isTerminal('succeeded')).assertTrue();
      expect(ReportStrategy.isTerminal('fallback')).assertTrue();
      expect(ReportStrategy.isTerminal('failed')).assertTrue();
      expect(ReportStrategy.isTerminal('streaming')).assertFalse();
      expect(ReportStrategy.isTerminal('requesting')).assertFalse();
    });
  });
}
