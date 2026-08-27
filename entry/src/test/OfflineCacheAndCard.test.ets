import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { OfflineCacheManager } from '../main/ets/common/OfflineCacheManager';
import { CardDataBuilder } from '../main/ets/common/CardDataBuilder';

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

    it('card_build_shouldFormatMinutes', 0, () => {
      const data = CardDataBuilder.build(120);
      expect(data.title).assertEqual('专注计时');
      expect(data.focusTime).assertEqual('25:00');
      expect(data.taskInfo).assertEqual('今日待学：高等数学');
      expect(data.todayMinutes).assertEqual('120分钟');
    });

    it('card_build_zeroMinutes_shouldFormatZero', 0, () => {
      const data = CardDataBuilder.build(0);
      expect(data.todayMinutes).assertEqual('0分钟');
    });
  });
}
