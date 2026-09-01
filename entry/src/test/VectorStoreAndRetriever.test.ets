import { describe, it, expect } from '@ohos/hypium';
import { VectorStore } from '../main/ets/services/rag/VectorStore';
import { VectorRetriever } from '../main/ets/services/rag/VectorRetriever';
import { EmbeddedChunk, ScoredChunk } from '../main/ets/services/rag/RagTypes';

function chunk(sourceId: string, idx: number, vector: number[], text: string): EmbeddedChunk {
  const c: EmbeddedChunk = {
    sourceId: sourceId,
    sourceType: 'note',
    sourceTitle: sourceId + '-title',
    sourceTime: 1788000000000 + idx,
    chunkIndex: idx,
    text: text,
    vector: vector
  };
  return c;
}

export default function vectorStoreAndRetrieverTest() {
  describe('VectorStore', () => {

    it('store_addAndSize', 0, () => {
      const store: VectorStore = new VectorStore();
      expect(store.size()).assertEqual(0);
      store.addChunks([chunk('n1', 0, [1, 0], 'a'), chunk('n1', 1, [0, 1], 'b')]);
      expect(store.size()).assertEqual(2);
      expect(store.all().length).assertEqual(2);
    });

    it('store_removeBySourceOnlyRemovesThatSource', 0, () => {
      const store: VectorStore = new VectorStore();
      store.addChunks([chunk('n1', 0, [1], 'a'), chunk('n1', 1, [1], 'b'), chunk('n2', 0, [1], 'c')]);
      const removed: number = store.removeBySource('n1');
      expect(removed).assertEqual(2);
      expect(store.size()).assertEqual(1);
      expect(store.all()[0].sourceId).assertEqual('n2');
    });

    it('store_replaceSourceNoDuplicate', 0, () => {
      const store: VectorStore = new VectorStore();
      store.addChunks([chunk('n1', 0, [1], 'old')]);
      // 模拟笔记被编辑后重建：旧块应被清掉，只留新块
      store.replaceSource('n1', [chunk('n1', 0, [1], 'new1'), chunk('n1', 1, [1], 'new2')]);
      expect(store.size()).assertEqual(2);
      expect(store.findBySource('n1')[0].text).assertEqual('new1');
    });

    it('store_clear', 0, () => {
      const store: VectorStore = new VectorStore();
      store.addChunks([chunk('n1', 0, [1], 'a')]);
      store.clear();
      expect(store.size()).assertEqual(0);
    });
  });

  describe('VectorRetriever', () => {

    function buildStore(): VectorStore {
      const store: VectorStore = new VectorStore();
      store.addChunks([
        chunk('s', 0, [1, 0], 'A'),        // 与 [1,0] 同向，余弦 1
        chunk('s', 1, [1, 1], 'B'),        // 余弦 1/sqrt2 ≈ 0.707
        chunk('s', 2, [0, 1], 'C'),        // 正交，余弦 0
        chunk('s', 3, [-1, 0], 'D'),       // 反向，余弦 -1（默认阈值 0 会被过滤）
        chunk('s', 4, [1, 0, 0], 'E')      // 维度不一致，应跳过不崩
      ]);
      return store;
    }

    it('retriever_emptyStoreReturnsEmpty', 0, () => {
      expect(VectorRetriever.search(new VectorStore(), [1, 0], 3).length).assertEqual(0);
    });

    it('retriever_topKReturnsHighestInDescOrder', 0, () => {
      const result: ScoredChunk[] = VectorRetriever.search(buildStore(), [1, 0], 2);
      expect(result.length).assertEqual(2);
      expect(result[0].chunk.text).assertEqual('A'); // 最相关
      expect(result[1].chunk.text).assertEqual('B');
      expect(result[0].score >= result[1].score).assertTrue(); // 降序
      expect(Math.abs(result[0].score - 1) < 1e-9).assertTrue();
    });

    it('retriever_filtersByMinScoreAndSkipsMismatchedDim', 0, () => {
      // 阈值 0.5：只留 A、B；D 负相关被过滤，E 维度不一致被跳过
      const result: ScoredChunk[] = VectorRetriever.search(buildStore(), [1, 0], 10, 0.5);
      expect(result.length).assertEqual(2);
      expect(result[0].chunk.text).assertEqual('A');
      expect(result[1].chunk.text).assertEqual('B');
    });

    it('retriever_zeroOrNegativeTopKReturnsEmpty', 0, () => {
      expect(VectorRetriever.search(buildStore(), [1, 0], 0).length).assertEqual(0);
    });

    it('retriever_emptyQueryReturnsEmpty', 0, () => {
      expect(VectorRetriever.search(buildStore(), [], 3).length).assertEqual(0);
    });

    it('retriever_eachResultCarriesSourceMeta', 0, () => {
      const result: ScoredChunk[] = VectorRetriever.search(buildStore(), [1, 0], 1);
      expect(result[0].chunk.sourceId).assertEqual('s');
      expect(result[0].chunk.chunkIndex === 0).assertTrue();
    });
  });
}
