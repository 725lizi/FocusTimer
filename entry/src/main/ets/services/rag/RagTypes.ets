// services/rag/RagTypes.ets
// RAG（检索增强生成）模块共用的纯数据类型，不依赖任何系统 API。

/** 被切块内容的来源类型：学习笔记 / 一次专注记录 */
export type ChunkSourceType = 'note' | 'focus';

/** 一个文本块的来源元信息：保证 AI 回答时能标注「这句话出自我的哪条材料」 */
export interface ChunkMeta {
  /** 来源记录的唯一 id */
  sourceId: string;
  /** 来源种类：笔记还是专注记录 */
  sourceType: ChunkSourceType;
  /** 来源的可读标题（如笔记标题），用于界面展示与引用出处 */
  sourceTitle: string;
  /** 来源记录的时间戳（毫秒），用于按时间排序/过滤 */
  sourceTime: number;
}

/** 切分后的一个文本块：正文 + 它在原文档中的序号 + 来源元信息 */
export interface TextChunk extends ChunkMeta {
  /** 该块在同一来源内的序号，从 0 开始连续递增 */
  chunkIndex: number;
  /** 块正文（已去除首尾空白） */
  text: string;
}

/** 一个文本块被向量化后得到的「嵌入向量」，即用一串数字表示这段文字的语义 */
export type EmbeddingVector = number[];

/** 已向量化的文本块：文本块 + 它的向量，后续存入本地向量库用于相似度检索 */
export interface EmbeddedChunk extends TextChunk {
  vector: EmbeddingVector;
}

/** 一次向量化请求的单条输入（文本 + 可选的客户端侧序号，用于和返回结果对齐） */
export interface EmbeddingInputItem {
  text: string;
  index: number;
}

/** 检索命中结果：被命中的已向量化块 + 它与查询的相似度分数（余弦，-1~1，越大越相关） */
export interface ScoredChunk {
  chunk: EmbeddedChunk;
  score: number;
}
