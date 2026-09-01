import { describe, it, expect } from '@ohos/hypium';
import { ChunkCodec, RagChunkRecord } from '../main/ets/services/rag/ChunkCodec';
import { BatchPlanner } from '../main/ets/services/rag/BatchPlanner';
import { IndexAssembler } from '../main/ets/services/rag/IndexAssembler';
import { EmbeddedChunk, TextChunk } from '../main/ets/services/rag/RagTypes';

function textChunk(idx: number, text: string): TextChunk {
  const c: TextChunk = {
    sourceId: 'n1', sourceType: 'note', sourceTitle: '标题', sourceTime: 1000,
    chunkIndex: idx, text: text
  };
  return c;
}

function embedded(idx: number, vector: number[]): EmbeddedChunk {
  const c: EmbeddedChunk = {
    sourceId: 'n1', sourceType: 'note', sourceTitle: '标题', sourceTime: 1000,
    chunkIndex: idx, text: '块' + idx, vector: vector
  };
  return c;
}

export default function indexPipelineTest() {
  describe('ChunkCodec', () => {

    it('codec_vectorRoundTripKeepsNegativeAndFloat', 0, () => {
      const vec: number[] = [-0.5, 0, 0.25, 3.14159];
      const back: number[] = ChunkCodec.decodeVector(ChunkCodec.encodeVector(vec));
      expect(back.length).assertEqual(4);
      expect(back[0]).assertEqual(-0.5);
      expect(Math.abs(back[3] - 3.14159) < 1e-9).assertTrue();
    });

    it('codec_decodeBadJsonReturnsEmpty', 0, () => {
      expect(ChunkCodec.decodeVector('{bad').length).assertEqual(0);
      expect(ChunkCodec.decodeVector('').length).assertEqual(0);
    });

    it('codec_decodeNonArrayReturnsEmpty', 0, () => {
      expect(ChunkCodec.decodeVector('{"a":1}').length).assertEqual(0);
    });

    it('codec_decodeWithNonNumberReturnsEmpty', 0, () => {
      expect(ChunkCodec.decodeVector('[1,"x",3]').length).assertEqual(0);
    });

    it('codec_chunkRecordRoundTrip', 0, () => {
      const origin: EmbeddedChunk = embedded(2, [0.1, 0.2]);
      const record: RagChunkRecord = ChunkCodec.encodeChunk(origin, 'm', 999);
      expect(record.vector.startsWith('[')).assertTrue();
      const back: EmbeddedChunk | null = ChunkCodec.decodeRecord(record);
      expect(back !== null).assertTrue();
      if (back !== null) {
        expect(back.chunkIndex).assertEqual(2);
        expect(back.text).assertEqual('块2');
        expect(back.sourceId).assertEqual('n1');
        expect(back.vector[1]).assertEqual(0.2);
      }
    });

    it('codec_decodeRecordBadVectorReturnsNull', 0, () => {
      const bad: RagChunkRecord = {
        sourceId: 'n1', sourceType: 'note', sourceTitle: '', sourceTime: 1,
        chunkIndex: 0, text: 'x', vector: 'not-json', model: 'm', createdAt: 1
      };
      expect(ChunkCodec.decodeRecord(bad) === null).assertTrue();
    });
  });

  describe('BatchPlanner', () => {

    it('batch_splitUnevenKeepsOrderAndRemainder', 0, () => {
      const items: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      const batches: number[][] = BatchPlanner.splitBatches(items, 3);
      expect(batches.length).assertEqual(4); // 3,3,3,1
      expect(batches[0].length).assertEqual(3);
      expect(batches[3].length).assertEqual(1);
      expect(batches[3][0]).assertEqual(10); // 顺序不丢
    });

    it('batch_splitEven', 0, () => {
      const batches: number[][] = BatchPlanner.splitBatches([1, 2, 3, 4, 5, 6], 3);
      expect(batches.length).assertEqual(2);
      expect(batches[1][2]).assertEqual(6);
    });

    it('batch_emptyReturnsEmpty', 0, () => {
      expect(BatchPlanner.splitBatches([], 4).length).assertEqual(0);
    });

    it('batch_invalidSizeFallsBackToOne', 0, () => {
      const batches: number[][] = BatchPlanner.splitBatches([1, 2, 3], 0);
      expect(batches.length).assertEqual(3); // 收敛为每批 1 条
    });
  });

  describe('IndexAssembler', () => {

    it('assemble_okPairsChunkWithVector', 0, () => {
      const chunks: TextChunk[] = [textChunk(0, 'a'), textChunk(1, 'b')];
      const vectors: number[][] = [[1, 0], [0, 1]];
      const r = IndexAssembler.assemble(chunks, vectors);
      expect(r.ok).assertTrue();
      expect(r.embedded.length).assertEqual(2);
      expect(r.embedded[1].text).assertEqual('b');
      expect(r.embedded[1].vector[0]).assertEqual(0);
    });

    it('assemble_countMismatchFails', 0, () => {
      const r = IndexAssembler.assemble([textChunk(0, 'a')], [[1], [2]]);
      expect(r.ok).assertFalse();
      expect(r.embedded.length).assertEqual(0);
    });

    it('assemble_emptyVectorFails', 0, () => {
      const r = IndexAssembler.assemble([textChunk(0, 'a')], [[]]);
      expect(r.ok).assertFalse();
    });
  });
}
