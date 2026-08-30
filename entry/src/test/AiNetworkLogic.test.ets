import { describe, it, expect } from '@ohos/hypium';
import { HttpErrorMapper } from '../main/ets/services/ai/HttpErrorMapper';
import { LlmErrorKind } from '../main/ets/services/ai/ReportStrategy';

export default function aiNetworkLogicTest() {
  describe('AiNetworkLogic', () => {

    // ===== HttpErrorMapper.classifyStatus：HTTP 状态码 → 统一错误类别 =====

    it('httpMapper_401_shouldBeUnauthorized', 0, () => {
      expect(HttpErrorMapper.classifyStatus(401)).assertEqual('unauthorized' as LlmErrorKind);
    });

    it('httpMapper_403_shouldBeUnauthorized', 0, () => {
      expect(HttpErrorMapper.classifyStatus(403)).assertEqual('unauthorized' as LlmErrorKind);
    });

    it('httpMapper_429_shouldBeRateLimited', 0, () => {
      expect(HttpErrorMapper.classifyStatus(429)).assertEqual('rate_limited' as LlmErrorKind);
    });

    it('httpMapper_400_404_422_shouldBeBadRequest', 0, () => {
      expect(HttpErrorMapper.classifyStatus(400)).assertEqual('bad_request' as LlmErrorKind);
      expect(HttpErrorMapper.classifyStatus(404)).assertEqual('bad_request' as LlmErrorKind);
      expect(HttpErrorMapper.classifyStatus(422)).assertEqual('bad_request' as LlmErrorKind);
    });

    it('httpMapper_5xx_shouldBeServer', 0, () => {
      expect(HttpErrorMapper.classifyStatus(500)).assertEqual('server' as LlmErrorKind);
      expect(HttpErrorMapper.classifyStatus(502)).assertEqual('server' as LlmErrorKind);
      expect(HttpErrorMapper.classifyStatus(503)).assertEqual('server' as LlmErrorKind);
    });

    it('httpMapper_408_shouldBeTimeout', 0, () => {
      expect(HttpErrorMapper.classifyStatus(408)).assertEqual('timeout' as LlmErrorKind);
    });

    it('httpMapper_unknown_shouldBeNetwork', 0, () => {
      expect(HttpErrorMapper.classifyStatus(0)).assertEqual('network' as LlmErrorKind);
      expect(HttpErrorMapper.classifyStatus(-1)).assertEqual('network' as LlmErrorKind);
    });

    // ===== HttpErrorMapper.classifyFrameworkError：框架错误码 → 类别 =====

    it('httpMapper_cancelCode_shouldBeCancelled', 0, () => {
      expect(HttpErrorMapper.classifyFrameworkError(2300089)).assertEqual('cancelled' as LlmErrorKind);
    });

    it('httpMapper_timeoutCodes_shouldBeTimeout', 0, () => {
      expect(HttpErrorMapper.classifyFrameworkError(2300004)).assertEqual('timeout' as LlmErrorKind);
      expect(HttpErrorMapper.classifyFrameworkError(2300047)).assertEqual('timeout' as LlmErrorKind);
      expect(HttpErrorMapper.classifyFrameworkError(2300999)).assertEqual('timeout' as LlmErrorKind);
    });

    it('httpMapper_unknownFrameworkCode_shouldBeNetwork', 0, () => {
      expect(HttpErrorMapper.classifyFrameworkError(12345)).assertEqual('network' as LlmErrorKind);
    });

    // ===== userMessage：每个类别都要有非空中文提示 =====

    it('httpMapper_everyKindHasUserMessage', 0, () => {
      const kinds: LlmErrorKind[] =
        ['network', 'timeout', 'unauthorized', 'rate_limited', 'server', 'bad_request', 'empty', 'cancelled'];
      for (let i = 0; i < kinds.length; i++) {
        const msg: string = HttpErrorMapper.userMessage(kinds[i]);
        expect(msg.length > 0).assertTrue();
      }
      // 取消不应误导成“切换规则版”
      expect(HttpErrorMapper.userMessage('cancelled')).assertEqual('已取消生成');
    });
  });
}
