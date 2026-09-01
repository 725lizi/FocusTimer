// services/rag/RagQaService.ets
// 设备层：把一次「基于个人知识库的问答」完整跑通：
// 查询加 BGE 前缀 -> EmbeddingClient 向量化 -> 本地 VectorStore 做 Top-K 召回
// -> RagQaPlanner 纯逻辑规划（模式/上下文/提示词/引用）-> DeepSeekClient 流式生成。
// 纯逻辑环节都已单测，这里只做设备编排；查询向量化需要 embedding Key，生成需要 DeepSeek Key。

import { EmbeddingClient } from './EmbeddingClient';
import { VectorStore } from './VectorStore';
import { VectorRetriever } from './VectorRetriever';
import { RagQaPlanner } from './RagQaPlanner';
import { RagConfig } from './RagConfig';
import { QaPlan } from './RagTypes';
import { DeepSeekClient, StreamCallbacks } from '../ai/DeepSeekClient';
import { AiConfig } from '../ai/AiConfig';
import { ChatCompletionRequest, ChatMessage } from '../ai/AiChatTypes';
import { QaPromptBuilder } from './QaPromptBuilder';

/** 问答回调：在流式回调基础上，多一个「规划完成、即将请求大模型」时机，用于先渲染来源与模式 */
export interface QaCallbacks extends StreamCallbacks {
  onPlan: (plan: QaPlan) => void;
}

export class RagQaService {
  private store: VectorStore;
  private embedClient: EmbeddingClient = new EmbeddingClient();
  private llm: DeepSeekClient = new DeepSeekClient();

  constructor(store: VectorStore) {
    this.store = store;
  }

  /**
   * 发起一次知识库问答（流式）。
   * @param question 用户问题
   * @param embedKey 向量化服务 Key
   * @param llmKey DeepSeek 聊天 Key
   * @param callbacks 规划/增量/错误/完成回调
   * @param topK 召回条数
   */
  public async ask(question: string, embedKey: string, llmKey: string,
    callbacks: QaCallbacks, topK: number = 5): Promise<void> {
    const q: string = question.trim();
    if (q.length === 0) {
      callbacks.onError('bad_request', '问题为空');
      return;
    }

    // 1) 查询向量化（检索侧加 BGE 指令前缀，文档侧不加）
    const queryText: string = RagConfig.buildQueryText(q, true);
    const queryVectors: number[][] = await this.embedClient.embed([queryText], embedKey);
    if (queryVectors.length === 0 || queryVectors[0].length === 0) {
      callbacks.onError('server', '查询向量化为空');
      return;
    }

    // 2) 本地 Top-K 召回（完全离线）
    const scored = VectorRetriever.search(this.store, queryVectors[0], topK);

    // 3) 纯逻辑规划：模式、上下文、提示词、来源引用
    const plan: QaPlan = RagQaPlanner.plan(q, scored);
    callbacks.onPlan(plan);

    // 4) 组装 Chat 请求并流式生成（复用阶段2 DeepSeekClient）
    const systemContent: string = plan.mode === 'grounded'
      ? QaPromptBuilder.SYSTEM_GROUNDED
      : QaPromptBuilder.SYSTEM_NO_EVIDENCE;
    const messages: ChatMessage[] = [
      { role: 'system', content: systemContent },
      { role: 'user', content: plan.prompt }
    ];
    const body: ChatCompletionRequest = {
      model: AiConfig.DEFAULT_MODEL,
      messages: messages,
      stream: true,
      temperature: 0.3,   // RAG 要忠于材料，调低随机性
      max_tokens: 1024
    };
    this.llm.startStream(llmKey, body, callbacks);
  }

  /** 离开页面时取消正在进行的生成 */
  public cancel(): void {
    this.llm.cancel();
  }
}
