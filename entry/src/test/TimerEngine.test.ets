import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { TimerEngine } from '../main/ets/common/TimerEngine';

export default function timerEngineTest() {
  describe('TimerEngine', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('init_shouldDefaultTo25Minutes', 0, () => {
      const engine = new TimerEngine();
      expect(engine.totalSecond).assertEqual(1500);
      expect(engine.currentSecond).assertEqual(1500);
      expect(engine.isRunning).assertFalse();
      expect(engine.formatTime()).assertEqual('25:00');
      expect(engine.getProgress()).assertEqual(0);
    });

    it('customDuration_shouldFormatCorrectly', 0, () => {
      const engine = new TimerEngine(300);
      expect(engine.totalSecond).assertEqual(300);
      expect(engine.formatTime()).assertEqual('05:00');
    });

    it('start_shouldMarkRunning', 0, () => {
      const engine = new TimerEngine();
      engine.start();
      expect(engine.isRunning).assertTrue();
    });

    it('tick_shouldDecreaseOneSecondEachCall', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      for (let i = 0; i < 25; i++) {
        expect(engine.tick()).assertFalse();
      }
      expect(engine.currentSecond).assertEqual(1475);
      expect(engine.formatTime()).assertEqual('24:35');
    });

    it('pause_shouldStopDecreasing', 0, () => {
      const engine = new TimerEngine();
      engine.start();
      engine.tick();
      engine.tick();
      engine.pause();
      const frozen: number = engine.currentSecond;
      engine.tick();
      engine.tick();
      expect(engine.currentSecond).assertEqual(frozen);
      expect(engine.isRunning).assertFalse();
    });

    it('resume_shouldContinueFromPausedPoint', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      engine.tick();
      engine.tick();
      engine.pause();
      engine.start();
      engine.tick();
      expect(engine.currentSecond).assertEqual(1497);
    });

    it('complete_shouldReturnTrueAfterReachingZero', 0, () => {
      // 与 Index.ets 一致的已知行为：归零后的下一拍才触发完成
      const engine = new TimerEngine(1);
      engine.start();
      expect(engine.tick()).assertFalse(); // 1 -> 0，界面显示 00:00
      expect(engine.currentSecond).assertEqual(0);
      expect(engine.tick()).assertTrue(); // 归零后的下一拍，触发完成
    });

    it('startAfterComplete_shouldResetToTotal', 0, () => {
      const engine = new TimerEngine(1);
      engine.start();
      engine.tick();
      engine.tick(); // 完成
      engine.start();
      expect(engine.currentSecond).assertEqual(1);
      expect(engine.isRunning).assertTrue();
    });

    it('reset_shouldRestoreToTotalAndStop', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      engine.tick();
      engine.reset();
      expect(engine.currentSecond).assertEqual(1500);
      expect(engine.isRunning).assertFalse();
      expect(engine.formatTime()).assertEqual('25:00');
    });

    it('setDuration_shouldOnlyWorkWhenStopped', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      engine.setDuration(300);
      expect(engine.totalSecond).assertEqual(1500);
      engine.pause();
      engine.setDuration(300);
      expect(engine.totalSecond).assertEqual(300);
      expect(engine.currentSecond).assertEqual(300);
    });

    it('progress_shouldReflectElapsedRatio', 0, () => {
      const engine = new TimerEngine(600);
      engine.start();
      for (let i = 0; i < 300; i++) {
        engine.tick();
      }
      expect(engine.getProgress()).assertEqual(0.5);
    });

    it('progress_zeroTotal_shouldReturnZero', 0, () => {
      const engine = new TimerEngine(0);
      expect(engine.getProgress()).assertEqual(0);
    });

    it('restReminder_shouldTriggerOnceAt45Minutes', 0, () => {
      const engine = new TimerEngine(3600); // 60 分钟
      engine.start();
      // 前 2699 秒不触发
      for (let i = 0; i < 2699; i++) {
        engine.tick();
      }
      expect(engine.shouldTriggerRestReminder()).assertFalse();
      // 累计满 2700 秒（elapsed = total - current = 3600 - 900 = 2700）
      engine.tick();
      expect(engine.shouldTriggerRestReminder()).assertTrue();
      // 同一轮计时只触发一次
      engine.tick();
      expect(engine.shouldTriggerRestReminder()).assertFalse();
    });

    it('checkpoint_shouldHitEvery30Seconds', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      for (let i = 0; i < 29; i++) {
        engine.tick();
        expect(engine.shouldPersistCheckpoint()).assertFalse();
      }
      engine.tick(); // 剩余 1470，为 30 的倍数
      expect(engine.shouldPersistCheckpoint()).assertTrue();
    });

    it('pauseCount_shouldIncrementOnEachPause', 0, () => {
      const engine = new TimerEngine(1500);
      engine.start();
      engine.pause();
      engine.pause();
      expect(engine.pauseCount).assertEqual(2);
    });
  });
}
