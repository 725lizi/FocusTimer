// services/rag/VectorRetriever.ets
// 纯逻辑：Top-K 语义检索。给定查询向量，在向量库里用余弦相似度逐个打分，
// 返回最相关的前 K 块（分数从高到低）。不联网、不碰系统 API，可完整离线单测。

import { VectorStore } from './VectorStore';
import { VectorMath } from './VectorMath';
import { EmbeddingVector, ScoredChunk } from './RagTypes';

export class VectorRetriever {
  /**
   * @param store 向量库
   * @param queryVector 查询文本的向量（调用方先用 EmbeddingClient 向量化）
   * @param topK 返回条数上限
   * @param minScore 最低相似度阈值，默认 0：余弦为负代表方向相反、语义不相关，直接丢弃
   */
  static search(store: VectorStore, queryVector: EmbeddingVector,
    topK: number, minScore: number = 0): ScoredChunk[] {
    if (topK <= 0 || queryVector.length === 0) {
      return [];
    }
    const all = store.all();
    const scored: ScoredChunk[] = [];
    for (let i = 0; i < all.length; i++) {
      const chunk = all[i];
      // 维度对不上无法比较，直接跳过而不是报错（防止脏数据中断整次检索）
      if (!VectorMath.sameDimension(queryVector, chunk.vector)) {
        continue;
      }
      const score: number = VectorMath.cosineSimilarity(queryVector, chunk.vector);
      if (score < minScore) {
        continue;
      }
      const item: ScoredChunk = { chunk: chunk, score: score };
      scored.push(item);
    }
    // 分数从高到低；分数相同则保持稳定（不额外打乱），用稳定排序思路：比较时相等返回 0
    scored.sort((a: ScoredChunk, b: ScoredChunk): number => {
      if (a.score > b.score) {
        return -1;
      }
      if (a.score < b.score) {
        return 1;
      }
      return 0;
    });
    if (scored.length <= topK) {
      return scored;
    }
    return scored.slice(0, topK);
  }
}
