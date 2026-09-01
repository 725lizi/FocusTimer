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
