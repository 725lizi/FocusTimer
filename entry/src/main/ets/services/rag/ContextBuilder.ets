// services/rag/ContextBuilder.ets
// 纯逻辑：把 Top-K 命中的材料整理成给大模型看的「上下文」，并聚合出可展示的来源引用。
// 同时做字符预算控制：模型上下文长度有限，材料要按相关度从高到低装、装不下就舍弃尾部。

import { Citation, ScoredChunk } from './RagTypes';

export class ContextBuilder {
  /** 单条材料的格式：【材料n】《来源标题》正文 */
  private static formatOne(ordinal: number, item: ScoredChunk): string {
    const title: string = item.chunk.sourceTitle.length > 0 ? item.chunk.sourceTitle : item.chunk.sourceId;
    return `【材料${ordinal}】《${title}》${item.chunk.text}`;
  }

  /**
   * 按字符预算截取：scored 已按分数降序，逐条累计，加入后超过预算就停止（至少保留1条）。
   */
  static fitBudget(scored: ScoredChunk[], maxChars: number): ScoredChunk[] {
    if (maxChars <= 0 || scored.length === 0) {
      return scored.slice();
    }
    const kept: ScoredChunk[] = [];
    let used: number = 0;
    for (let i = 0; i < scored.length; i++) {
      const len: number = scored[i].chunk.text.length;
      if (kept.length > 0 && used + len > maxChars) {
        break;
      }
      kept.push(scored[i]);
      used += len;
    }
    return kept;
  }

  /** 把命中材料拼成多行上下文文本 */
  static buildContextBlock(scored: ScoredChunk[]): string {
    const lines: string[] = [];
    for (let i = 0; i < scored.length; i++) {
      lines.push(ContextBuilder.formatOne(i + 1, scored[i]));
    }
    return lines.join('\n');
  }

  /**
   * 聚合来源引用：同一篇笔记的多个命中块合并为一条 Citation，
   * 块序号升序、topScore 取最高，来源按首次出现顺序排列。
   */
  static aggregateCitations(scored: ScoredChunk[]): Citation[] {
    const citations: Citation[] = [];
    const indexMap: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < scored.length; i++) {
      const id: string = scored[i].chunk.sourceId;
      const pos: number | undefined = indexMap.get(id);
      if (pos === undefined) {
        const citation: Citation = {
          sourceId: id,
          sourceType: scored[i].chunk.sourceType,
          title: scored[i].chunk.sourceTitle.length > 0 ? scored[i].chunk.sourceTitle : id,
          chunkIndexes: [scored[i].chunk.chunkIndex],
          topScore: scored[i].score
        };
        indexMap.set(id, citations.length);
        citations.push(citation);
      } else {
        const existed: Citation = citations[pos];
        existed.chunkIndexes.push(scored[i].chunk.chunkIndex);
        if (scored[i].score > existed.topScore) {
          existed.topScore = scored[i].score;
        }
      }
    }
    // 每篇内部块序号升序，阅读更自然
    for (let i = 0; i < citations.length; i++) {
      citations[i].chunkIndexes.sort((a: number, b: number): number => a - b);
    }
    return citations;
  }
}
