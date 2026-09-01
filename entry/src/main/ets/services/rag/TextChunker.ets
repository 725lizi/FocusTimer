// services/rag/TextChunker.ets
// RAG 第一步：把长文本切成带「来源」的小块（纯逻辑，不依赖网络/系统，可离线单测）。
//
// 为什么需要切块：笔记/记录整篇太长，不能直接送去向量化和塞进提示词，要切成大小合适的块；
// 切块时优先在中文句子/段落边界断开（不把一句话硬切成两半），相邻块之间留一点「重叠」，
// 避免恰好落在边界上的完整意思被切断；遇到「一整句都没有标点且超长」的极端情况再按长度硬切兜底。
//
// 设计契约（可被单测验证）：
//  1) 输入空白文本 => 返回空数组；
//  2) 每个块都携带相同的来源元信息，chunkIndex 从 0 连续递增；
//  3) 普通块长度不超过 maxChars；
//  4) 相邻普通块尽量保留 overlapChars 的重叠（尾巴接到下一块开头）；
//  5) 无标点的超长串按窗口硬切，步长 = maxChars - overlap，保证不丢字、不死循环。

import { ChunkMeta, TextChunk } from './RagTypes';

/** 中文/常见语句与段落结束边界（命中即在其后断开，标点保留在前一句末尾） */
const BOUNDARY_CHARS: string = '。！？!?；;\n';

export class TextChunker {
  /** 默认每块目标最大字符数 */
  static readonly DEFAULT_MAX_CHARS: number = 220;
  /** 默认相邻块重叠字符数 */
  static readonly DEFAULT_OVERLAP_CHARS: number = 30;

  /**
   * 把一段文本切成块。
   * @param raw 原始文本
   * @param meta 来源元信息（笔记/专注记录）
   * @param maxChars 每块目标最大字符数，需为正整数
   * @param overlapChars 相邻块重叠字符数，会被收敛到 [0, maxChars-1]，防止步长为 0 死循环
   */
  static chunkText(raw: string, meta: ChunkMeta,
    maxChars: number = 220,
    overlapChars: number = 30): TextChunk[] {
    const chunks: TextChunk[] = [];
    if (raw === null || raw === undefined) {
      return chunks;
    }
    const text: string = raw.trim();
    if (text.length === 0) {
      return chunks;
    }

    // 参数兜底，保证算法一定能向前推进
    const limit: number = (Number.isInteger(maxChars) && maxChars > 0) ? maxChars : TextChunker.DEFAULT_MAX_CHARS;
    let overlap: number = (Number.isInteger(overlapChars) && overlapChars >= 0) ? overlapChars : 0;
    if (overlap >= limit) {
      overlap = limit - 1;
    }

    const units: string[] = TextChunker.splitIntoUnits(text);
    let current: string = '';
    let index: number = 0;

    const pushChunk = (body: string, metaInfo: ChunkMeta, atIndex: number): void => {
      const cleaned: string = body.trim();
      if (cleaned.length > 0) {
        chunks.push(TextChunker.makeChunk(cleaned, metaInfo, atIndex));
      }
    };

    for (let i = 0; i < units.length; i++) {
      const unit: string = units[i];

      // 情况 A：单个语义单元本身就超长 —— 先封存当前块，再对它按窗口硬切
      if (unit.length > limit) {
        if (current.length > 0) {
          pushChunk(current, meta, index);
          index++;
          current = '';
        }
        let start: number = 0;
        while (start < unit.length) {
          const end: number = Math.min(start + limit, unit.length);
          pushChunk(unit.substring(start, end), meta, index);
          index++;
          if (end >= unit.length) {
            break;
          }
          start = end - overlap; // 下一片回退 overlap，形成重叠
        }
        continue;
      }

      // 情况 B：普通语义单元，贪心往当前块里装
      if (current.length === 0) {
        current = unit;
      } else if (current.length + unit.length <= limit) {
        current += unit;
      } else {
        // 加上这句会超限：封存当前块，新块以「上一块尾巴 overlap」起头
        pushChunk(current, meta, index);
        index++;
        const tail: string = overlap > 0 ? current.substring(current.length - overlap) : '';
        const merged: string = tail + unit;
        // 若带上重叠后仍超限（重叠 + 这句 > 上限），就放弃这次重叠，保证块不超长、不产生碎片
        current = (merged.length <= limit) ? merged : unit;
      }
    }

    if (current.trim().length > 0) {
      pushChunk(current, meta, index);
    }
    return chunks;
  }

  /**
   * 按语句/段落边界把文本切成最小语义单元，标点保留在单元末尾。
   * 手动扫描而非正则后行断言，兼容性更稳，且 for...of 按字符（code point）遍历，中文/emoji 安全。
   */
  static splitIntoUnits(text: string): string[] {
    const units: string[] = [];
    let buffer: string = '';
    for (const ch of text) {
      buffer += ch;
      if (BOUNDARY_CHARS.indexOf(ch) >= 0) {
        if (buffer.trim().length > 0) {
          units.push(buffer.trim());
        }
        buffer = '';
      }
    }
    if (buffer.trim().length > 0) {
      units.push(buffer.trim());
    }
    return units;
  }

  private static makeChunk(text: string, meta: ChunkMeta, chunkIndex: number): TextChunk {
    const chunk: TextChunk = {
      sourceId: meta.sourceId,
      sourceType: meta.sourceType,
      sourceTitle: meta.sourceTitle,
      sourceTime: meta.sourceTime,
      chunkIndex: chunkIndex,
      text: text
    };
    return chunk;
  }
}
