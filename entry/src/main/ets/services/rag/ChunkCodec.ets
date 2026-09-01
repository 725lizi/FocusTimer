// services/rag/ChunkCodec.ets
// 纯逻辑：内存里的「已向量化块 EmbeddedChunk」与数据库可存储的「行记录 RagChunkRecord」互转。
// 数据库的一列只能存字符串/数字，因此向量 number[] 要序列化成字符串、读出来再还原。
// 转换不依赖数据库 API，可完整离线单测；读到脏数据时安全跳过而不是崩溃。

import { ChunkSourceType, EmbeddedChunk } from './RagTypes';

/** 对应 rag_vector_chunk 表一行（向量已被序列化成字符串） */
export interface RagChunkRecord {
  sourceId: string;
  sourceType: string;
  sourceTitle: string;
  sourceTime: number;
  chunkIndex: number;
  text: string;
  vector: string;
  model: string;
  createdAt: number;
}

export class ChunkCodec {
  /** 向量数组 -> 可入库字符串（JSON，能稳妥保留负数/小数） */
  static encodeVector(vector: number[]): string {
    return JSON.stringify(vector);
  }

  /** 入库字符串 -> 向量数组；坏 JSON / 含非数字 / 空向量一律返回空数组 */
  static decodeVector(raw: string): number[] {
    if (raw === null || raw === undefined || raw.length === 0) {
      return [];
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      return [];
    }
    if (!Array.isArray(parsed)) {
      return [];
    }
    const arr = parsed as number[];
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] !== 'number' || !Number.isFinite(arr[i])) {
        return [];
      }
    }
    return arr.slice();
  }

  /** 内存块 -> 可存储行 */
  static encodeChunk(chunk: EmbeddedChunk, model: string, now: number): RagChunkRecord {
    const record: RagChunkRecord = {
      sourceId: chunk.sourceId,
      sourceType: chunk.sourceType,
      sourceTitle: chunk.sourceTitle,
      sourceTime: chunk.sourceTime,
      chunkIndex: chunk.chunkIndex,
      text: chunk.text,
      vector: ChunkCodec.encodeVector(chunk.vector),
      model: model,
      createdAt: now
    };
    return record;
  }

  /** 数据库行 -> 内存块；向量无法还原时返回 null（调用方跳过该行） */
  static decodeRecord(record: RagChunkRecord): EmbeddedChunk | null {
    const vector: number[] = ChunkCodec.decodeVector(record.vector);
    if (vector.length === 0) {
      return null;
    }
    const chunk: EmbeddedChunk = {
      sourceId: record.sourceId,
      sourceType: record.sourceType as ChunkSourceType,
      sourceTitle: record.sourceTitle,
      sourceTime: record.sourceTime,
      chunkIndex: record.chunkIndex,
      text: record.text,
      vector: vector
    };
    return chunk;
  }
}
