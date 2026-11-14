import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { StudySession } from '../main/ets/services/LearningAnalysisService';
import { FocusProfileStats } from '../main/ets/services/profile/FocusProfileStats';
import { FocusInsightRules } from '../main/ets/services/profile/FocusInsightRules';
import { FocusInsightValidator } from '../main/ets/services/profile/FocusInsightValidator';
import {
  FocusFact, FocusInsight, FocusInsightBundle, FocusProfileStatsResult
} from '../main/ets/services/profile/FocusProfileTypes';

const NOW: number = new Date(2026, 10, 13, 12, 0, 0).getTime();
const DAY_MS: number = 24 * 60 * 60 * 1000;

function makeSession(id: string, dayOffset: number, hour: number, duration: number,
  tags: string[]): StudySession {
  const d: Date = new Date(2026, 10, 13, hour, 0, 0);
  const s: StudySession = {
    id: id,
    startTime: d.getTime() + dayOffset * DAY_MS,
    duration: duration,
    tags: tags,
    isInterrupted: false,
    interruptCount: 0
  };
  return s;
}

/** 构造一份数据充足的 7 天统计结果（跨多日、多时段、多类别） */
function richResult(): FocusProfileStatsResult {
  const sessions: StudySession[] = [
    makeSession('a', -1, 10, 40, ['高数']),
    makeSession('b', -1, 15, 30, ['高数', '英语']),
    makeSession('c', -2, 9, 50, ['高数']),
    makeSession('d', -3, 20, 25, ['英语']),
    makeSession('e', -4, 10, 35, ['物理'])
  ];
  return FocusProfileStats.build(sessions, 7, NOW);
}

function factIdSet(result: FocusProfileStatsResult): Set<string> {
  const set: Set<string> = new Set<string>();
  for (const f of result.facts) {
    set.add(f.id);
  }
  return set;
}

export default function focusInsightRulesTest() {
  describe('FocusInsightRules', () => {
    beforeEach(() => {
    });

    // 1) 空记录：来源 insufficient，给出提示性洞察，证据仍可追溯
    it('empty_shouldReturnInsufficientBundle', 0, () => {
      const result: FocusProfileStatsResult = FocusProfileStats.build([], 7, NOW);
      const bundle: FocusInsightBundle = FocusInsightRules.build(result, NOW);
      expect(bundle.source).assertEqual('insufficient');
      expect(bundle.insights.length >= 1).assertTrue();
      expect(bundle.insights[0].source).assertEqual('insufficient');
      expect(bundle.insights[0].evidenceIds.length >= 1).assertTrue();
    });

    // 2) 数据充足：来源 rule，生成多条洞察
    it('rich_shouldReturnRuleBundle', 0, () => {
      const bundle: FocusInsightBundle = FocusInsightRules.build(richResult(), NOW);
      expect(bundle.source).assertEqual('rule');
      expect(bundle.insights.length >= 3).assertTrue();
    });

    // 3) 每条规则洞察引用的证据 id 都真实存在（可追溯）
    it('rule_insights_shouldReferenceExistingFacts', 0, () => {
      const result: FocusProfileStatsResult = richResult();
      const bundle: FocusInsightBundle = FocusInsightRules.build(result, NOW);
      const real: Set<string> = factIdSet(result);
      for (const ins of bundle.insights) {
        expect(ins.evidenceIds.length >= 1).assertTrue();
        for (const id of ins.evidenceIds) {
          expect(real.has(id)).assertTrue();
        }
      }
    });

    // 4) 主导类别洞察包含占比最高的类别名（高数分钟最多）
    it('leading_category_insight_shouldMentionTopCategory', 0, () => {
      const bundle: FocusInsightBundle = FocusInsightRules.build(richResult(), NOW);
      let mentioned: boolean = false;
      for (const ins of bundle.insights) {
        if (ins.summary.includes('高数') && ins.summary.includes('最多')) {
          mentioned = true;
        }
      }
      expect(mentioned).assertTrue();
    });

    // 5) 规则洞察的结论与行动都非空
    it('insights_shouldHaveNonEmptySummaryAndAction', 0, () => {
      const bundle: FocusInsightBundle = FocusInsightRules.build(richResult(), NOW);
      for (const ins of bundle.insights) {
        expect(ins.summary.trim().length > 0).assertTrue();
        expect(ins.action.trim().length > 0).assertTrue();
      }
    });

    // 6) 30 天且周际可算时，包含周际变化洞察
    it('wow_insight_shouldAppearWhenComputable', 0, () => {
      const sessions: StudySession[] = [
        makeSession('prev', -10, 10, 30, ['高数']),
        makeSession('r1', -3, 10, 40, ['高数']),
        makeSession('r2', -2, 15, 30, ['英语']),
        makeSession('r3', -1, 9, 50, ['高数'])
      ];
      const result: FocusProfileStatsResult = FocusProfileStats.build(sessions, 30, NOW);
      const bundle: FocusInsightBundle = FocusInsightRules.build(result, NOW);
      let hasWow: boolean = false;
      for (const ins of bundle.insights) {
        if (ins.summary.includes('最近一周')) {
          hasWow = true;
        }
      }
      expect(hasWow).assertTrue();
    });

    // 7) 校验器：规则版洞察全部合法
    it('validator_shouldAcceptRuleInsights', 0, () => {
      const result: FocusProfileStatsResult = richResult();
      const bundle: FocusInsightBundle = FocusInsightRules.build(result, NOW);
      for (const ins of bundle.insights) {
        expect(FocusInsightValidator.isValid(ins, result.facts)).assertTrue();
      }
    });

    // 8) 校验器：引用不存在事实 id 的洞察被拒绝
    it('validator_shouldRejectFakeEvidence', 0, () => {
      const result: FocusProfileStatsResult = richResult();
      const fake: FocusInsight = {
        id: 'fake',
        windowDays: 7,
        summary: '一条没有依据的结论',
        evidenceIds: ['f7-cat-999'],
        action: '某行动',
        source: 'llm'
      };
      expect(FocusInsightValidator.isValid(fake, result.facts)).assertFalse();
    });

    // 9) 校验器：空证据的洞察被拒绝
    it('validator_shouldRejectEmptyEvidence', 0, () => {
      const result: FocusProfileStatsResult = richResult();
      const empty: FocusInsight = {
        id: 'empty',
        windowDays: 7,
        summary: '结论',
        evidenceIds: [],
        action: '行动',
        source: 'llm'
      };
      expect(FocusInsightValidator.isValid(empty, result.facts)).assertFalse();
    });

    // 10) filterValid 只保留合法洞察，剔除伪造证据
    it('filterValid_shouldDropInvalidInsights', 0, () => {
      const result: FocusProfileStatsResult = richResult();
      const bundle: FocusInsightBundle = FocusInsightRules.build(result, NOW);
      const fake: FocusInsight = {
        id: 'fake',
        windowDays: 7,
        summary: '无依据',
        evidenceIds: ['f7-total', 'f7-ghost'],
        action: '行动',
        source: 'llm'
      };
      const merged: FocusInsight[] = bundle.insights.concat([fake]);
      const kept: FocusInsight[] = FocusInsightValidator.filterValid(merged, result.facts);
      expect(kept.length).assertEqual(bundle.insights.length);
    });
  });
}
