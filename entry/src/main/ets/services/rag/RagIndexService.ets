// services/rag/RagIndexService.ets
// 设备层：索引构建流水线，把一篇原始材料（笔记/专注总结）变成「可检索的向量块」并持久化。
// 串联：TextChunker 切块 -> BatchPlanner 分批 -> EmbeddingClient 联网向量化
//       -> IndexAssembler 对齐组装 -> VectorRepository 持久化 + 内存 VectorStore 同步更新。
// 纯逻辑环节都已各自单测，这里只做编排与错误上抛；文档块入库不加 BGE 查询前缀（仅查询时加）。

import { ChunkMeta, EmbeddedChunk, TextChunk } from './RagTypes';
import { TextChunker } from './TextChunker';
import { BatchPlanner } from './BatchPlanner';
import { IndexAssembler, AssembleResult } from './IndexAssembler';
import { EmbeddingClient } from './EmbeddingClient';
import { VectorRepository } from './VectorRepository';
import { VectorStore } from './VectorStore';
import { RagConfig } from './RagConfig';

/** 一次索引构建的结果统计 */
export interface IndexResult {
  chunkCount: number;
  batchCount: number;
}

export class RagIndexService {
  private client: EmbeddingClient = new EmbeddingClient();
  private repository: VectorRepository = new VectorRepository();

  /**
   * 为单个来源构建/重建索引。
   * @param rawText 原始文本
   * @param meta 来源元信息（sourceId 决定覆盖哪篇材料）
   * @param apiKey 向量化服务 Key
   * @param model 向量模型，缺省用配置默认值
   * @param memoryStore 可选的内存向量库，传入则同步更新，使当次会话立即可检索
   */
  async indexDocument(rawText: string, meta: ChunkMeta, apiKey: string,
    model: string = RagConfig.DEFAULT_EMBED_MODEL,
    memoryStore: VectorStore | null = null): Promise<IndexResult> {
    const chunks: TextChunk[] = TextChunker.chunkText(rawText, meta);

    // 文本为空：等于删除该来源的旧索引
    if (chunks.length === 0) {
      await this.repository.deleteSource(meta.sourceId);
      if (memoryStore !== null) {
        memoryStore.removeBySource(meta.sourceId);
      }
      const empty: IndexResult = { chunkCount: 0, batchCount: 0 };
      return empty;
    }

    // 分批向量化，按批次顺序拼回向量，保证与 chunks 顺序一致
    const batches: TextChunk[][] = BatchPlanner.splitBatches(chunks, RagConfig.MAX_BATCH);
    const allVectors: number[][] = [];
    for (let b = 0; b < batches.length; b++) {
      const texts: string[] = batches[b].map((c: TextChunk): string => c.text);
      const vectors: number[][] = await this.client.embed(texts, apiKey, model);
      for (let v = 0; v < vectors.length; v++) {
        allVectors.push(vectors[v]);
      }
    }

    const assembled: AssembleResult = IndexAssembler.assemble(chunks, allVectors);
    if (!assembled.ok) {
      throw new Error('索引组装失败：' + assembled.error);
    }
    const embedded: EmbeddedChunk[] = assembled.embedded;

    // 持久化 + 内存库原子重建
    await this.repository.replaceSource(meta.sourceId, embedded, model);
    if (memoryStore !== null) {
      memoryStore.replaceSource(meta.sourceId, embedded);
    }

    const result: IndexResult = { chunkCount: embedded.length, batchCount: batches.length };
    return result;
  }

  /** 从数据库把已有索引全部加载进内存向量库（App 启动时调用，实现重启后可检索） */
  async hydrateInto(memoryStore: VectorStore): Promise<number> {
    const all: EmbeddedChunk[] = await this.repository.loadAll();
    memoryStore.clear();
    memoryStore.addChunks(all);
    return all.length;
  }
}
