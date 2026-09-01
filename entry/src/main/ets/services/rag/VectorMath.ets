// services/rag/VectorMath.ets
// 纯逻辑：向量运算，RAG 相似度检索的数学基础（不依赖系统 API，可完整离线单测）。
//
// 核心是「余弦相似度」：衡量两个向量方向有多接近，取值 -1~1，越接近 1 表示两段文字语义越像。
// 相比直接比向量各维差值，余弦只看方向、不被向量整体长短影响，是文本语义检索最常用的度量。

import { EmbeddingVector } from './RagTypes';

export class VectorMath {
  /** 点积（内积）：对应维相乘再求和；维度不一致视为非法，返回 NaN */
  static dot(a: EmbeddingVector, b: EmbeddingVector): number {
    if (a.length !== b.length || a.length === 0) {
      return NaN;
    }
    let sum: number = 0;
    for (let i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /** 向量的模长（L2 范数） */
  static norm(a: EmbeddingVector): number {
    if (a.length === 0) {
      return 0;
    }
    let sum: number = 0;
    for (let i = 0; i < a.length; i++) {
      sum += a[i] * a[i];
    }
    return Math.sqrt(sum);
  }

  /**
   * 余弦相似度 = 点积 / (模长a * 模长b)。
   * 维度不一致或任一为零向量时，无法定义相似度，保守返回 0（视为不相关），不抛异常。
   */
  static cosineSimilarity(a: EmbeddingVector, b: EmbeddingVector): number {
    if (a.length !== b.length || a.length === 0) {
      return 0;
    }
    const normA: number = VectorMath.norm(a);
    const normB: number = VectorMath.norm(b);
    if (normA === 0 || normB === 0) {
      return 0;
    }
    const value: number = VectorMath.dot(a, b) / (normA * normB);
    // 浮点误差可能略微超出 [-1,1]，夹回区间，结果更可预测
    if (value > 1) {
      return 1;
    }
    if (value < -1) {
      return -1;
    }
    return value;
  }

  /** 归一化为单位向量（模长=1）；零向量原样返回 */
  static normalize(a: EmbeddingVector): EmbeddingVector {
    const n: number = VectorMath.norm(a);
    if (n === 0) {
      return a.slice();
    }
    const out: EmbeddingVector = [];
    for (let i = 0; i < a.length; i++) {
      out.push(a[i] / n);
    }
    return out;
  }

  /** 两个向量维度是否一致且非空（入库/检索前的合法性检查） */
  static sameDimension(a: EmbeddingVector, b: EmbeddingVector): boolean {
    return a.length > 0 && a.length === b.length;
  }
}
