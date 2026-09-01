import { describe, it, expect } from '@ohos/hypium';
import { ContextBuilder } from '../main/ets/services/rag/ContextBuilder';
import { AnswerDecider } from '../main/ets/services/rag/AnswerDecider';
import { QaPromptBuilder } from '../main/ets/services/rag/QaPromptBuilder';
import { RagQaPlanner } from '../main/ets/services/rag/RagQaPlanner';
import { Citation, EmbeddedChunk, ScoredChunk } from '../main/ets/services/rag/RagTypes';

function scored(id: string, title: string, idx: number, text: string, score: number): ScoredChunk {
  const chunk: EmbeddedChunk = {
    sourceId: id, sourceType: 'note', sourceTitle: title, sourceTime: 1,
    chunkIndex: idx, text: text, vector: [score]
  };
  const item: ScoredChunk = { chunk: chunk, score: score };
  return item;
}

export default function qaPlannerTest() {
  describe('ContextBuilder', () => {

    it('ctx_fitBudgetKeepsFirstThenCutsByOrder', 0, () => {
      const list: ScoredChunk[] = [
        scored('n1', 't', 0, '12345', 0.9),   // 5
        scored('n1', 't', 1, '123', 0.6),     // +3 = 8
        scored('n2', 't', 0, '1234', 0.4)     // +4 = 12 > 10，舍弃
      ];
      const kept: ScoredChunk[] = ContextBuilder.fitBudget(list, 10);
      expect(kept.length).assertEqual(2);
      expect(kept[1].score).assertEqual(0.6);
    });

    it('ctx_buildContextBlockNumbersAndTitles', 0, () => {
      const block: string = ContextBuilder.buildContextBlock([scored('n1', '高数', 0, '导数定义', 0.9)]);
      expect(block.indexOf('【材料1】') >= 0).assertTrue();
      expect(block.indexOf('《高数》') >= 0).assertTrue();
      expect(block.indexOf('导数定义') >= 0).assertTrue();
    });

    it('ctx_aggregateMergesSameSourceSorted', 0, () => {
      const list: ScoredChunk[] = [
        scored('n1', '高数', 2, 'b', 0.6),
        scored('n1', '高数', 0, 'a', 0.9),
        scored('n2', '英语', 0, 'c', 0.4)
      ];
      const citations: Citation[] = ContextBuilder.aggregateCitations(list);
      expect(citations.length).assertEqual(2);
      expect(citations[0].sourceId).assertEqual('n1');
      expect(citations[0].chunkIndexes.length).assertEqual(2);
      expect(citations[0].chunkIndexes[0]).assertEqual(0); // 升序
      expect(citations[0].chunkIndexes[1]).assertEqual(2);
      expect(citations[0].topScore).assertEqual(0.9);
    });
  });

  describe('AnswerDecider', () => {

    it('decider_emptyIsNoEvidence', 0, () => {
      expect(AnswerDecider.decide([])).assertEqual('no_evidence');
    });

    it('decider_lowTopScoreIsNoEvidence', 0, () => {
      expect(AnswerDecider.decide([scored('n', 't', 0, 'x', 0.1)])).assertEqual('no_evidence');
    });

    it('decider_enoughScoreIsGrounded', 0, () => {
      expect(AnswerDecider.decide([scored('n', 't', 0, 'x', 0.5)])).assertEqual('grounded');
    });
  });

  describe('QaPromptBuilder', () => {

    it('prompt_groundedContainsQuestionAndMaterial', 0, () => {
      const p: string = QaPromptBuilder.buildGroundedUserPrompt('什么是导数', '【材料1】《高数》导数定义');
      expect(p.indexOf('什么是导数') >= 0).assertTrue();
      expect(p.indexOf('【材料1】') >= 0).assertTrue();
      expect(QaPromptBuilder.SYSTEM_GROUNDED.indexOf('不要编造') >= 0).assertTrue();
    });

    it('prompt_noEvidenceAdmitsMissing', 0, () => {
      expect(QaPromptBuilder.SYSTEM_NO_EVIDENCE.indexOf('没有') >= 0).assertTrue();
      expect(QaPromptBuilder.buildNoEvidenceUserPrompt('问题').indexOf('问题') >= 0).assertTrue();
    });
  });

  describe('RagQaPlanner', () => {

    it('planner_groundedFullPlan', 0, () => {
      const list: ScoredChunk[] = [
        scored('n1', '高数', 0, '导数是变化率', 0.8),
        scored('n1', '高数', 1, '导数几何意义', 0.5)
      ];
      const plan = RagQaPlanner.plan('  导数是什么  ', list);
      expect(plan.mode).assertEqual('grounded');
      expect(plan.usedCount).assertEqual(2);
      expect(plan.citations.length).assertEqual(1); // 同篇合并
      expect(plan.contextBlock.indexOf('导数是变化率') >= 0).assertTrue();
      expect(plan.prompt.indexOf('导数是什么') >= 0).assertTrue(); // 问题已 trim
      expect(plan.question).assertEqual('导数是什么');
    });

    it('planner_noEvidenceFullPlan', 0, () => {
      const plan = RagQaPlanner.plan('任意问题', [scored('n', 't', 0, 'x', 0.05)]);
      expect(plan.mode).assertEqual('no_evidence');
      expect(plan.usedCount).assertEqual(0);
      expect(plan.citations.length).assertEqual(0);
      expect(plan.contextBlock).assertEqual('');
    });
  });
}
