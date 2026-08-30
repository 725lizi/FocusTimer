// services/ai/SseChunkParser.ets
// 纯逻辑：解析大模型流式返回的 SSE（Server-Sent Events）文本分片。
//
// 为什么需要它：流式响应不是“一次给一整句”，而是网络到多少就回调多少，
// 一个回调里可能同时出现「多行 / 半行 / 甚至半段 JSON」，半行必须留到下次拼接，
// 否则直接 JSON.parse 就会崩。这些拼接/容错逻辑与网络无关，抽成纯类离线测最稳。

import { StreamChunk } from './AiChatTypes';

export class SseChunkParser {
  // 尚未凑成完整一行的半包内容，跨回调保留
  private buffer: string = '';
  // 是否收到结束标记 [DONE]
  private doneFlag: boolean = false;

  /**
   * 喂入一段原始文本，返回这段里能解析出的增量正文（按出现顺序）。
   * 调用方把返回的字符串依次追加到界面即可实现“逐字出现”。
   */
  feed(rawChunk: string): string[] {
    const deltas: string[] = [];
    this.buffer += rawChunk;

    // SSE 以换行分隔；最后一段若没有以换行结尾，说明是半包，留到下次
    const combined = this.buffer;
    const lines = combined.split('\n');
    if (combined.endsWith('\n')) {
      this.buffer = '';
    } else {
      this.buffer = (lines.pop() as string);
    }

    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (line.length === 0) {
        continue; // SSE 的空行只是事件分隔符
      }
      if (!line.startsWith('data:')) {
        continue; // 忽略 event:/id: 等非数据行
      }
      line = line.substring('data:'.length).trim();
      if (line.length === 0) {
        continue;
      }
      if (line === '[DONE]') {
        this.doneFlag = true;
        continue;
      }
      const text = SseChunkParser.extractDelta(line);
      if (text.length > 0) {
        deltas.push(text);
      }
    }
    return deltas;
  }

  /** 从一行 data: 的 JSON 中安全取出 choices[0].delta.content；任何异常都安全跳过 */
  private static extractDelta(jsonLine: string): string {
    try {
      const parsed = JSON.parse(jsonLine) as StreamChunk;
      if (parsed.choices && parsed.choices.length > 0) {
        const delta = parsed.choices[0].delta;
        if (delta && delta.content) {
          return delta.content;
        }
      }
      return '';
    } catch (err) {
      // 半段 JSON / 非 JSON 行：不当作错误抛出，留待后续拼接或直接忽略
      return '';
    }
  }

  isDone(): boolean {
    return this.doneFlag;
  }

  /** 当前残留半包（主要用于测试与排查） */
  pendingBuffer(): string {
    return this.buffer;
  }

  reset(): void {
    this.buffer = '';
    this.doneFlag = false;
  }
}
