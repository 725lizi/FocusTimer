// services/rag/VectorStore.ets
// 纯逻辑：内存版「向量库」，保存已向量化的文本块，支持按来源增删改与 Top-K 检索取数。
// 本步只做内存态（可完整离线单测）；落盘持久化（重启不丢）在后续任务做。
//
// 关键设计：同一篇笔记被编辑后要「先删旧块、再存新块」，否则同一内容会重复命中，
// 因此提供 replaceSource 原子重建。

import { EmbeddedChunk } from './RagTypes';

export class VectorStore {
  private items: EmbeddedChunk[] = [];

  /** 追加一批已向量化的块 */
  addChunks(chunks: EmbeddedChunk[]): void {
    for (let i = 0; i < chunks.length; i++) {
      this.items.push(chunks[i]);
    }
  }

  /** 删除某个来源（某篇笔记/某次专注）的全部块，返回被删掉的条数 */
  removeBySource(sourceId: string): number {
    const before: number = this.items.length;
    const kept: EmbeddedChunk[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].sourceId !== sourceId) {
        kept.push(this.items[i]);
      }
    }
    this.items = kept;
    return before - this.items.length;
  }

  /** 原子重建某来源：先删掉它的旧块，再写入新块，保证同一来源不残留、不重复 */
  replaceSource(sourceId: string, chunks: EmbeddedChunk[]): void {
    this.removeBySource(sourceId);
    this.addChunks(chunks);
  }

  /** 取某个来源的全部块（拷贝，避免外部直接改动内部数据） */
  findBySource(sourceId: string): EmbeddedChunk[] {
    const out: EmbeddedChunk[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].sourceId === sourceId) {
        out.push(this.items[i]);
      }
    }
    return out;
  }

  /** 全部块的拷贝 */
  all(): EmbeddedChunk[] {
    return this.items.slice();
  }

  size(): number {
    return this.items.length;
  }

  clear(): void {
    this.items = [];
  }
}
