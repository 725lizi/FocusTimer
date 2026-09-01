import { describe, it, expect } from '@ohos/hypium';
import { EmbeddingParser } from '../main/ets/services/rag/EmbeddingParser';

export default function embeddingParserTest() {
  describe('EmbeddingParser', () => {

    it('parser_singleOk', 0, () => {
      const raw: string = '{"data":[{"index":0,"embedding":[0.1,0.2,0.3]}],"model":"x"}';
      const v: number[] = EmbeddingParser.parseSingle(raw);
      expect(v.length).assertEqual(3);
      expect(v[1]).assertEqual(0.2);
    });

    it('parser_batchReordersByIndex', 0, () => {
      // 服务端乱序返回：index 1 在前、0 在后，解析后必须按 index 归位
      const raw: string = '{"data":[' +
        '{"index":1,"embedding":[2,2]},' +
        '{"index":0,"embedding":[1,1]}]}';
      const r = EmbeddingParser.parseBatchResponse(raw);
      expect(r.ok).assertTrue();
      expect(r.vectors.length).assertEqual(2);
      expect(r.vectors[0][0]).assertEqual(1); // index 0 排到第一
      expect(r.vectors[1][0]).assertEqual(2);
    });

    it('parser_badJsonFails', 0, () => {
      const r = EmbeddingParser.parseBatchResponse('not-a-json{');
      expect(r.ok).assertFalse();
      expect(r.vectors.length).assertEqual(0);
    });

    it('parser_emptyStringFails', 0, () => {
      expect(EmbeddingParser.parseBatchResponse('').ok).assertFalse();
    });

    it('parser_missingDataFails', 0, () => {
      expect(EmbeddingParser.parseBatchResponse('{"model":"x"}').ok).assertFalse();
    });

    it('parser_emptyDataFails', 0, () => {
      expect(EmbeddingParser.parseBatchResponse('{"data":[]}').ok).assertFalse();
    });

    it('parser_filtersInvalidItemsKeepsValid', 0, () => {
      // 一条空向量、一条含非数字、一条合法；过滤后只剩合法那条
      const raw: string = '{"data":[' +
        '{"index":0,"embedding":[]},' +
        '{"index":1,"embedding":[1,"x"]},' +
        '{"index":2,"embedding":[0.5,0.5]}]}';
      const r = EmbeddingParser.parseBatchResponse(raw);
      expect(r.ok).assertTrue();
      expect(r.vectors.length).assertEqual(1);
      expect(r.vectors[0][0]).assertEqual(0.5);
    });

    it('parser_allInvalidFails', 0, () => {
      const raw: string = '{"data":[{"index":0,"embedding":[]}]}';
      expect(EmbeddingParser.parseBatchResponse(raw).ok).assertFalse();
    });

    it('parser_singleInvalidReturnsEmptyArray', 0, () => {
      expect(EmbeddingParser.parseSingle('{"data":[]}').length).assertEqual(0);
    });
  });
}
