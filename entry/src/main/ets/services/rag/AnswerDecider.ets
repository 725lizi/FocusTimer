// services/rag/AnswerDecider.ets
// 纯逻辑：决定这次问答「有没有自己的材料可依据」。
// 没有召回、或最相关的一块相似度都太低时判为 no_evidence，
// 避免拿不相关的材料硬凑、逼着大模型编造（这是 RAG 防幻觉的关键闸门）。

import { QaMode, ScoredChunk } from './RagTypes';

export class AnswerDecider {
  /** 默认最低相关度：最高相似度低于它就视为「没有靠谱依据」 */
  static readonly DEFAULT_MIN_SCORE: number = 0.2;

  static decide(scored: ScoredChunk[], minScore: number = AnswerDecider.DEFAULT_MIN_SCORE): QaMode {
    if (scored.length === 0) {
      return 'no_evidence';
    }
    // scored 已按分数降序，第 0 个即最高分
    if (scored[0].score < minScore) {
      return 'no_evidence';
    }
    return 'grounded';
  }

  /** 最高相似度，便于界面展示「本次答案的把握程度」 */
  static topScore(scored: ScoredChunk[]): number {
    return scored.length > 0 ? scored[0].score : 0;
  }
}
