// services/rag/IndexAssembler.ets
// 纯逻辑：把「文本块」和它们对应的「向量」按顺序一一配对，组装成可入库/检索的 EmbeddedChunk。
// 网络分批返回后向量可能拼接出错，因此这里严格校验数量一致、每条向量非空，不一致就报错、绝不静默错配。

import { EmbeddedChunk, TextChunk } from './RagTypes';

export interface AssembleResult {
  ok: boolean;
  embedded: EmbeddedChunk[];
  error: string;
}

export class IndexAssembler {
  static assemble(chunks: TextChunk[], vectors: number[][]): AssembleResult {
    if (chunks.length !== vectors.length) {
      const failResult: AssembleResult = {
        ok: false,
        embedded: [],
        error: `文本块 ${chunks.length} 个，但向量 ${vectors.length} 个，数量不一致`
      };
      return failResult;
    }
    const embedded: EmbeddedChunk[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const vec: number[] = vectors[i];
      if (!Array.isArray(vec) || vec.length === 0) {
        const badResult: AssembleResult = {
          ok: false,
          embedded: [],
          error: `第 ${i} 块向量为空，无法组装`
        };
        return badResult;
      }
      const item: EmbeddedChunk = {
        sourceId: chunks[i].sourceId,
        sourceType: chunks[i].sourceType,
        sourceTitle: chunks[i].sourceTitle,
        sourceTime: chunks[i].sourceTime,
        chunkIndex: chunks[i].chunkIndex,
        text: chunks[i].text,
        vector: vec
      };
      embedded.push(item);
    }
    const okResult: AssembleResult = { ok: true, embedded: embedded, error: '' };
    return okResult;
  }
}
