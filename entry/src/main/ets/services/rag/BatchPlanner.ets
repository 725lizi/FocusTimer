// services/rag/BatchPlanner.ets
// 纯逻辑：把一个长列表按固定大小切成多批。
// 用途：一次向量化的文本条数有上限（RagConfig.MAX_BATCH），块很多时要分批请求，
// 既避免单次请求体过大，也便于失败时只重发某一批。

export class BatchPlanner {
  /**
   * 把 items 按每批至多 batchSize 条切分，保持原有顺序。
   * 空列表返回 []；batchSize 非法（<=0）时保守收敛为 1，避免死循环或一次性全塞。
   */
  static splitBatches<T>(items: T[], batchSize: number): T[][] {
    const size: number = batchSize <= 0 ? 1 : batchSize;
    const batches: T[][] = [];
    for (let start = 0; start < items.length; start += size) {
      const end: number = Math.min(start + size, items.length);
      batches.push(items.slice(start, end));
    }
    return batches;
  }
}
