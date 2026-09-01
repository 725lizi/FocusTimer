// services/rag/RagRuntime.ets
// 单例门面（Facade）：App 内只通过它访问 RAG 能力，保证索引写入和问答检索用的是【同一个】内存向量库。
// 职责：持有内存 VectorStore、索引流水线、问答服务；App 启动时从数据库 hydrate（重启后立即可检索）。
// UI 层只跟它打交道，不用关心内部切块/向量化/持久化/检索的分工。

import { ChunkMeta } from './RagTypes';
import { VectorStore } from './VectorStore';
import { RagIndexService, IndexResult } from './RagIndexService';
import { RagQaService, QaCallbacks } from './RagQaService';
import { RagConfig } from './RagConfig';

export class RagRuntime {
  private static instance: RagRuntime | null = null;
  private store: VectorStore = new VectorStore();
  private indexService: RagIndexService = new RagIndexService();
  private qaService: RagQaService = new RagQaService(this.store);

  private constructor() {
  }

  public static getInstance(): RagRuntime {
    if (RagRuntime.instance === null) {
      RagRuntime.instance = new RagRuntime();
    }
    return RagRuntime.instance;
  }

  /** 当前内存中已索引的块数（界面可显示「已收录 N 段」） */
  public indexedCount(): number {
    return this.store.size();
  }

  /** App 启动：把数据库里已持久化的向量块加载回内存，返回加载条数 */
  public async hydrate(): Promise<number> {
    return this.indexService.hydrateInto(this.store);
  }

  /** 为一篇材料构建/重建索引（内部会切块、分批向量化、落盘并同步内存库） */
  public async buildIndex(rawText: string, meta: ChunkMeta, embedKey: string,
    model: string = RagConfig.DEFAULT_EMBED_MODEL): Promise<IndexResult> {
    return this.indexService.indexDocument(rawText, meta, embedKey, model, this.store);
  }

  /** 删除某来源索引 */
  public async removeIndex(sourceId: string): Promise<void> {
    this.store.removeBySource(sourceId);
    await this.indexService.removeSource(sourceId);
  }

  /** 发起知识库问答（流式） */
  public ask(question: string, embedKey: string, llmKey: string,
    callbacks: QaCallbacks, topK: number = 5): Promise<void> {
    return this.qaService.ask(question, embedKey, llmKey, callbacks, topK);
  }

  /** 取消问答生成 */
  public cancelQa(): void {
    this.qaService.cancel();
  }
}
