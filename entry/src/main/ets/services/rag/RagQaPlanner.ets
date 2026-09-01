// services/rag/RagQaPlanner.ets
// 纯逻辑总装：输入「问题 + Top-K 召回结果」，输出一份可直接执行的问答规划 QaPlan
// （是否有依据模式、材料上下文、最终提示词、来源引用清单、实际用到几条）。
// 设备层拿到 plan 后，只需按 plan.mode 选系统提示、把 plan.prompt 发给大模型即可，不含任何联网/系统 API。

import { AnswerDecider } from './AnswerDecider';
import { ContextBuilder } from './ContextBuilder';
import { QaPromptBuilder } from './QaPromptBuilder';
import { QaMode, QaPlan, ScoredChunk } from './RagTypes';

export class RagQaPlanner {
  /** 默认进入上下文的材料字符预算，避免超出模型上下文窗口 */
  static readonly DEFAULT_MAX_CONTEXT_CHARS: number = 1200;

  static plan(question: string, scored: ScoredChunk[],
    minScore: number = AnswerDecider.DEFAULT_MIN_SCORE,
    maxContextChars: number = RagQaPlanner.DEFAULT_MAX_CONTEXT_CHARS): QaPlan {
    const q: string = question.trim();
    const budgeted: ScoredChunk[] = ContextBuilder.fitBudget(scored, maxContextChars);
    const mode: QaMode = AnswerDecider.decide(budgeted, minScore);

    if (mode === 'no_evidence') {
      const noPlan: QaPlan = {
        mode: 'no_evidence',
        question: q,
        contextBlock: '',
        prompt: QaPromptBuilder.buildNoEvidenceUserPrompt(q),
        citations: [],
        usedCount: 0
      };
      return noPlan;
    }

    const contextBlock: string = ContextBuilder.buildContextBlock(budgeted);
    const groundedPlan: QaPlan = {
      mode: 'grounded',
      question: q,
      contextBlock: contextBlock,
      prompt: QaPromptBuilder.buildGroundedUserPrompt(q, contextBlock),
      citations: ContextBuilder.aggregateCitations(budgeted),
      usedCount: budgeted.length
    };
    return groundedPlan;
  }
}
