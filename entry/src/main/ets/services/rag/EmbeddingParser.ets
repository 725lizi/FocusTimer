// services/rag/EmbeddingParser.ets
// 纯逻辑：把 OpenAI 兼容 /embeddings 接口返回的 JSON 安全解析成「向量数组」。
// 网络不可信，解析必须容错：坏 JSON、缺 data、乱序、某条向量为空/非数组，都不能让流程崩。

import { EmbeddingVector } from './RagTypes';

/** 解析结果：成功带向量列表，失败带一句原因（供上层决定是否降级/提示） */
export interface EmbeddingParseResult {
  ok: boolean;
  vectors: EmbeddingVector[];
  error: string;
}

/** OpenAI 兼容响应里的单条结构（仅声明用到的字段） */
interface OpenAiEmbedItem {
  embedding: number[];
  index: number;
}
interface OpenAiEmbedResponse {
  data: OpenAiEmbedItem[];
}

export class EmbeddingParser {
  private static fail(message: string): EmbeddingParseResult {
    const result: EmbeddingParseResult = { ok: false, vectors: [], error: message };
    return result;
  }

  /**
   * 解析批量向量化响应。
   * 服务端不保证 data 顺序与请求 input 顺序一致，因此按每条的 index 升序归位，
   * 保证「第 i 个向量」确实对应「第 i 段输入文本」。
   */
  static parseBatchResponse(raw: string): EmbeddingParseResult {
    if (raw === null || raw === undefined || raw.length === 0) {
      return EmbeddingParser.fail('响应为空');
    }
    let parsed: OpenAiEmbedResponse;
    try {
      parsed = JSON.parse(raw) as OpenAiEmbedResponse;
    } catch (err) {
      return EmbeddingParser.fail('响应不是合法 JSON');
    }
    if (parsed === null || parsed === undefined || parsed.data === undefined) {
      return EmbeddingParser.fail('响应缺少 data 字段');
    }
    const items: OpenAiEmbedItem[] = parsed.data;
    if (!Array.isArray(items) || items.length === 0) {
      return EmbeddingParser.fail('data 为空');
    }

    // 过滤掉非法条目，再按 index 排序
    const valid: OpenAiEmbedItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: OpenAiEmbedItem = items[i];
      const vec: number[] = item ? item.embedding : [];
      if (Array.isArray(vec) && vec.length > 0 && EmbeddingParser.allNumbers(vec)) {
        valid.push(item);
      }
    }
    if (valid.length === 0) {
      return EmbeddingParser.fail('没有合法向量');
    }
    valid.sort((a: OpenAiEmbedItem, b: OpenAiEmbedItem): number => a.index - b.index);

    const vectors: EmbeddingVector[] = [];
    for (let i = 0; i < valid.length; i++) {
      vectors.push(valid[i].embedding);
    }
    const okResult: EmbeddingParseResult = { ok: true, vectors: vectors, error: '' };
    return okResult;
  }

  /** 便捷方法：确认只发了一条文本时取唯一向量；非法返回空数组 */
  static parseSingle(raw: string): EmbeddingVector {
    const result: EmbeddingParseResult = EmbeddingParser.parseBatchResponse(raw);
    if (result.ok && result.vectors.length > 0) {
      return result.vectors[0];
    }
    return [];
  }

  private static allNumbers(vec: number[]): boolean {
    for (let i = 0; i < vec.length; i++) {
      if (typeof vec[i] !== 'number' || !Number.isFinite(vec[i])) {
        return false;
      }
    }
    return true;
  }
}
