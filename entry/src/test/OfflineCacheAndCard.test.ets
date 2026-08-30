import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { OfflineCacheManager } from '../main/ets/common/OfflineCacheManager';
import { CardDataBuilder, CardData } from '../main/ets/common/CardDataBuilder';

export default function offlineAndCardTest() {
  describe('OfflineCacheAndCard', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('offline_hasStatusChanged_sameStatus_shouldBeFalse', 0, () => {
      expect(OfflineCacheManager.hasStatusChanged(false, false)).assertFalse();
      expect(OfflineCacheManager.hasStatusChanged(true, true)).assertFalse();
    });

    it('offline_hasStatusChanged_diffStatus_shouldBeTrue', 0, () => {
      expect(OfflineCacheManager.hasStatusChanged(true, false)).assertTrue();
      expect(OfflineCacheManager.hasStatusChanged(false, true)).assertTrue();
    });

    it('card_build_shouldFormatAllFields', 0, () => {
      // 今日 120 分钟、上次 25 分钟、科目高数：组装出完整卡片文本
      const data: CardData = CardDataBuilder.build(120, 25, '高等数学');
      expect(data.title).assertEqual('专注计时');
      expect(data.focusTime).assertEqual('25:00');
      expect(data.taskInfo).assertEqual('今日待学：高等数学');
      expect(data.todayMinutes).assertEqual('120分钟');
    });

    it('card_build_zeroAndEmpty_shouldUseDefaults', 0, () => {
      // 全零/空科目时回退到默认展示
      const data: CardData = CardDataBuilder.build(0, 0, '');
      expect(data.focusTime).assertEqual('00:00');
      expect(data.taskInfo).assertEqual('今日待学：未选择');
      expect(data.todayMinutes).assertEqual('0分钟');
    });

    it('card_formatFocusTime_shouldPadAndFloor', 0, () => {
      // 个位数补前导 0；非整数向下取整
      expect(CardDataBuilder.formatFocusTime(9)).assertEqual('09:00');
      expect(CardDataBuilder.formatFocusTime(25.9)).assertEqual('25:00');
    });
  });
}
