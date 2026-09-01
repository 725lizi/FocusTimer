import { describe, it, expect } from '@ohos/hypium';
import { TextChunker } from '../main/ets/services/rag/TextChunker';
import { ChunkMeta, TextChunk } from '../main/ets/services/rag/RagTypes';

function meta(): ChunkMeta {
  const m: ChunkMeta = {
    sourceId: 'note-1',
    sourceType: 'note',
    sourceTitle: '高数笔记',
    sourceTime: 1788000000000
  };
  return m;
}

export default function textChunkerTest() {
  describe('TextChunker', () => {

    it('chunker_emptyOrBlankReturnsNoChunk', 0, () => {
      expect(TextChunker.chunkText('', meta()).length).assertEqual(0);
      expect(TextChunker.chunkText('    \n  ', meta()).length).assertEqual(0);
    });

    it('chunker_shortTextIsOneChunkWithMetaAndIndex0', 0, () => {
      const chunks: TextChunk[] = TextChunker.chunkText('今天学了高数。', meta());
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].text).assertEqual('今天学了高数。');
      expect(chunks[0].chunkIndex).assertEqual(0);
      expect(chunks[0].sourceId).assertEqual('note-1');
      expect(chunks[0].sourceTitle).assertEqual('高数笔记');
      expect(chunks[0].sourceType).assertEqual('note');
    });

    it('chunker_longTextSplitsWithContinuousIndexAndMeta', 0, () => {
      const text: string = '第一句话在这里。第二句话也在这里哦。第三句话收尾。';
      const chunks: TextChunk[] = TextChunker.chunkText(text, meta(), 12, 3);
      expect(chunks.length > 1).assertTrue();
      for (let i = 0; i < chunks.length; i++) {
        expect(chunks[i].chunkIndex).assertEqual(i); // 序号连续
        expect(chunks[i].text.length <= 12).assertTrue(); // 不超长
        expect(chunks[i].sourceId).assertEqual('note-1'); // 每块带来源
      }
    });

    it('chunker_adjacentChunksKeepOverlap', 0, () => {
      // 句子都较短，tail + 句长不会超上限，因此相邻块必然保留 overlap 重叠
      const text: string = '甲甲乙乙。丙丙丁丁。戊戊己己。庚庚辛辛。';
      const overlap: number = 3;
      const chunks: TextChunk[] = TextChunker.chunkText(text, meta(), 10, overlap);
      expect(chunks.length >= 2).assertTrue();
      for (let i = 1; i < chunks.length; i++) {
        const prev: string = chunks[i - 1].text;
        const head: string = chunks[i].text.substring(0, overlap);
        expect(prev.endsWith(head)).assertTrue(); // 后块开头 = 前块结尾 overlap
      }
    });

    it('chunker_noPunctuationLongStringHardCutsWithoutDroppingChars', 0, () => {
      // 21 个无标点字符，上限 10、重叠 2
      const text: string = '一二三四五六七八九十一二三四五六七八九十二十一';
      const chunks: TextChunk[] = TextChunker.chunkText(text, meta(), 10, 2);
      expect(chunks.length >= 3).assertTrue();
      for (const c of chunks) {
        expect(c.text.length <= 10).assertTrue();
      }
      // 硬切窗口步长为 8（10-2），覆盖原文：逐字符确认原文每个字符都出现在块拼接中
      const joined: string = chunks.map((c: TextChunk) => c.text).join('');
      for (const ch of text) {
        expect(joined.indexOf(ch) >= 0).assertTrue();
      }
    });

    it('chunker_overlapLargerThanMaxIsClampedAndTerminates', 0, () => {
      // overlap 异常大于 max 时必须被收敛，算法必须正常结束、不卡死，且块不超长
      const text: string = 'aaaaaaaaaabbbbbbbbbbcccccccccc';
      const chunks: TextChunk[] = TextChunker.chunkText(text, meta(), 5, 999);
      expect(chunks.length > 1).assertTrue();
      for (const c of chunks) {
        expect(c.text.length <= 5).assertTrue();
      }
    });

    it('chunker_splitIntoUnitsCutsAtBoundaryAndKeepsPunctuation', 0, () => {
      const units: string[] = TextChunker.splitIntoUnits('第一句。第二句！第三段\n尾句');
      expect(units.length).assertEqual(4);
      expect(units[0]).assertEqual('第一句。'); // 标点保留在句尾
      expect(units[2]).assertEqual('第三段');
      expect(units[3]).assertEqual('尾句');
    });

    it('chunker_focusSourceTypeIsCarried', 0, () => {
      const focusMeta: ChunkMeta = {
        sourceId: 'focus-9',
        sourceType: 'focus',
        sourceTitle: '数学专注 45 分钟',
        sourceTime: 1788100000000
      };
      const chunks: TextChunk[] = TextChunker.chunkText('一段来自专注记录的总结。', focusMeta);
      expect(chunks[0].sourceType).assertEqual('focus');
      expect(chunks[0].sourceId).assertEqual('focus-9');
    });
  });
}
