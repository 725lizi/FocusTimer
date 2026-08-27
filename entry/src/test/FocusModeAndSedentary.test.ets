import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { FocusModeManager } from '../main/ets/common/FocusModeManager';
import { SedentaryReminderManager } from '../main/ets/common/SedentaryReminderManager';
import { Constants } from '../main/ets/model/Constants';

export default function focusAndSedentaryTest() {
  describe('FocusModeAndSedentary', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('focus_isEntertainmentApp_shouldReturnTrueForKnownApps', 0, () => {
      const manager = FocusModeManager.getInstance();
      expect(manager.isEntertainmentApp('com.ss.android.ugc.aweme')).assertTrue();
      expect(manager.isEntertainmentApp('com.bilibili.app.in')).assertTrue();
      expect(manager.isEntertainmentApp('com.kuaishou.nebula')).assertTrue();
      expect(manager.isEntertainmentApp('com.tencent.tmgp.sgame')).assertTrue();
    });

    it('focus_isEntertainmentApp_shouldReturnFalseForOthers', 0, () => {
      const manager = FocusModeManager.getInstance();
      expect(manager.isEntertainmentApp('com.tencent.mm')).assertFalse();
      expect(manager.isEntertainmentApp('')).assertFalse();
    });

    it('focus_entertainmentList_shouldHave8Entries', 0, () => {
      const apps = FocusModeManager.getInstance().getEntertainmentApps();
      expect(apps.length).assertEqual(8);
    });

    it('sedentary_belowThreshold_shouldNotRemind', 0, () => {
      expect(SedentaryReminderManager.shouldTriggerReminder(Constants.SEDENTARY_THRESHOLD - 1, false)).assertFalse();
    });

    it('sedentary_atThreshold_shouldRemind', 0, () => {
      expect(SedentaryReminderManager.shouldTriggerReminder(Constants.SEDENTARY_THRESHOLD, false)).assertTrue();
      expect(SedentaryReminderManager.shouldTriggerReminder(Constants.SEDENTARY_THRESHOLD + 10, false)).assertTrue();
    });

    it('sedentary_hasReminded_shouldNotRemindAgain', 0, () => {
      expect(SedentaryReminderManager.shouldTriggerReminder(Constants.SEDENTARY_THRESHOLD + 10, true)).assertFalse();
    });
  });
}
