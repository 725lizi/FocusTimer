import { describe, it, expect } from '@ohos/hypium';
import { MarkdownLite, TextSpan } from '../main/ets/common/MarkdownLite';

export default function markdownLiteTest() {
  describe('MarkdownLite', () => {

    it('markdownLite_emptyInputReturnsEmpty', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('');
      expect(spans.length).assertEqual(0);
    });

    it('markdownLite_plainTextIsOneNormalSpan', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('普通一句话');
      expect(spans.length).assertEqual(1);
      expect(spans[0].bold).assertFalse();
      expect(spans[0].text).assertEqual('普通一句话');
    });

    it('markdownLite_singleBoldPairBecomesBoldSpanWithoutStars', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('**总体情况**');
      expect(spans.length).assertEqual(1);
      expect(spans[0].bold).assertTrue();
      expect(spans[0].text).assertEqual('总体情况');
      expect(spans[0].text.includes('*')).assertFalse();
    });

    it('markdownLite_mixedNormalAndBoldKeepsOrder', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('前文**重点**后文');
      expect(spans.length).assertEqual(3);
      expect(spans[0].bold).assertFalse();
      expect(spans[0].text).assertEqual('前文');
      expect(spans[1].bold).assertTrue();
      expect(spans[1].text).assertEqual('重点');
      expect(spans[2].bold).assertFalse();
      expect(spans[2].text).assertEqual('后文');
    });

    it('markdownLite_multipleBoldPairs', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('**A**中间**B**');
      expect(spans.length).assertEqual(3);
      expect(spans[0].bold).assertTrue();
      expect(spans[0].text).assertEqual('A');
      expect(spans[1].bold).assertFalse();
      expect(spans[1].text).assertEqual('中间');
      expect(spans[2].bold).assertTrue();
      expect(spans[2].text).assertEqual('B');
    });

    it('markdownLite_unclosedOddStarsTreatTailAsNormal', 0, () => {
      // 只有一个 **（未闭合），不应把后半段错误加粗，也不应残留星号
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('a**b');
      expect(spans.length).assertEqual(2);
      expect(spans[0].bold).assertFalse();
      expect(spans[1].bold).assertFalse();
      const joined: string = spans.map((s: TextSpan) => s.text).join('');
      expect(joined).assertEqual('ab');
      expect(joined.includes('*')).assertFalse();
    });

    it('markdownLite_newlineInsideIsPreserved', 0, () => {
      const spans: TextSpan[] = MarkdownLite.parseBoldSpans('**标题**\n正文第二行');
      expect(spans.length).assertEqual(2);
      expect(spans[0].bold).assertTrue();
      expect(spans[0].text).assertEqual('标题');
      expect(spans[1].bold).assertFalse();
      expect(spans[1].text).assertEqual('\n正文第二行');
    });

    it('markdownLite_stripBoldMarkersRemovesAllStars', 0, () => {
      expect(MarkdownLite.stripBoldMarkers('a**b**c')).assertEqual('abc');
      expect(MarkdownLite.stripBoldMarkers('没有标记')).assertEqual('没有标记');
    });
  });
}
