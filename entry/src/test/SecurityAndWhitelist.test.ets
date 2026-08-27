import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { SecurityManager } from '../main/ets/common/SecurityManager';
import { DeviceWhitelistManager } from '../main/ets/common/DeviceWhitelistManager';

export default function securityAndWhitelistTest() {
  describe('SecurityAndWhitelist', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('security_isValidFolderName_shouldRejectEmpty', 0, () => {
      expect(SecurityManager.isValidFolderName('')).assertFalse();
      expect(SecurityManager.isValidFolderName('   ')).assertFalse();
    });

    it('security_isValidFolderName_shouldAcceptNormal', 0, () => {
      expect(SecurityManager.isValidFolderName('私密笔记')).assertTrue();
      expect(SecurityManager.isValidFolderName(' 学习资料 ')).assertTrue();
    });

    it('whitelist_isValidDeviceId_shouldRejectEmpty', 0, () => {
      expect(DeviceWhitelistManager.isValidDeviceId('')).assertFalse();
    });

    it('whitelist_isValidDeviceId_shouldAcceptNormal', 0, () => {
      expect(DeviceWhitelistManager.isValidDeviceId('device_abc_123')).assertTrue();
    });
  });
}
