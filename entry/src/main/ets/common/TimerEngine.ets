/**
 * 专注计时引擎（纯逻辑核心，不依赖 UI 与系统 API）
 *
 * 语义与 pages/Index.ets 的计时状态机一一对应：
 *  - start()          ↔ startTimer()  开始 / 继续计时
 *  - pause()          ↔ pauseTimer()  暂停（中断次数 +1）
 *  - reset()          ↔ resetTimer()  重置回总时长
 *  - tick()           ↔ setInterval 每秒回调：递减剩余秒数
 *  - getProgress()    ↔ progress getter
 *  - formatTime()     ↔ timeDisplay getter
 *  - shouldPersistCheckpoint()  ↔ currentSecond % 30 === 0 的接续保存点
 *  - shouldTriggerRestReminder()↔ elapsed >= 2700 的久坐休息提醒
 *
 * 说明：本类将 Index.ets 中混在 UI 里的计时状态机抽离为可单测的纯逻辑，
 * 当前 Index.ets 尚未切换调用本类，切换后可消除重复实现。
 */
export class TimerEngine {
  /** 预设时长（秒）：5 / 15 / 25 / 45 / 60 分钟 */
  static readonly PRESET_DURATIONS: number[] = [300, 900, 1500, 2700, 3600];
  /** 累计专注满 45 分钟触发休息提醒 */
  static readonly REST_REMINDER_ELAPSED_SECONDS: number = 2700;
  /** 默认时长 25 分钟 */
  static readonly DEFAULT_DURATION_SECONDS: number = 1500;

  private currentSecondValue: number;
  private totalSecondValue: number;
  private running: boolean;
  private pauseCountValue: number;
  private restReminderTriggeredFlag: boolean;

  constructor(durationSeconds: number = TimerEngine.DEFAULT_DURATION_SECONDS) {
    this.totalSecondValue = durationSeconds;
    this.currentSecondValue = durationSeconds;
    this.running = false;
    this.pauseCountValue = 0;
    this.restReminderTriggeredFlag = false;
  }

  /** 剩余秒数 */
  get currentSecond(): number {
    return this.currentSecondValue;
  }

  /** 总时长（秒） */
  get totalSecond(): number {
    return this.totalSecondValue;
  }

  /** 是否计时中 */
  get isRunning(): boolean {
    return this.running;
  }

  /** 暂停（中断）次数 */
  get pauseCount(): number {
    return this.pauseCountValue;
  }

  /**
   * 开始 / 继续计时。
   * 与 Index.startTimer 一致：剩余时间已耗尽时，先重置为总时长再开始。
   */
  start(): void {
    if (this.currentSecondValue <= 0) {
      this.currentSecondValue = this.totalSecondValue;
    }
    this.running = true;
    this.pauseCountValue = 0;
    this.restReminderTriggeredFlag = false;
  }

  /**
   * 暂停计时，中断次数 +1。
   * 与 Index.pauseTimer 一致（注意：原实现 onTimerComplete 也复用 pauseTimer，会使中断计数 +1）。
   */
  pause(): void {
    this.running = false;
    this.pauseCountValue++;
  }

  /**
   * 重置：暂停并把剩余时间恢复为总时长。
   * 与 Index.resetTimer 一致。
   */
  reset(): void {
    this.pause();
    this.currentSecondValue = this.totalSecondValue;
    this.restReminderTriggeredFlag = false;
  }

  /**
   * 设置计时时长（秒），仅在未运行时生效（与 Index 选择时长逻辑一致）。
   */
  setDuration(seconds: number): void {
    if (!this.running) {
      this.totalSecondValue = seconds;
      this.currentSecondValue = seconds;
    }
  }

  /**
   * 从异常接续点恢复：用保存的总时长与剩余时长重建引擎状态（默认不立即运行，
   * 由调用方决定是否再调用 start()）。对应 Index.acceptContinuation 的场景。
   */
  restoreFromCheckpoint(totalSeconds: number, remainSeconds: number): void {
    this.totalSecondValue = totalSeconds;
    this.currentSecondValue = remainSeconds;
    this.running = false;
    this.pauseCountValue = 0;
    this.restReminderTriggeredFlag = false;
  }

  /**
   * 推进一秒，由 UI 的 setInterval 每 1000ms 调用。
   *
   * 与 Index 的 setInterval 回调语义一致：
   *  - 剩余时间 > 0 时递减，返回 false（仍在计时）
   *  - 剩余时间已为 0 时返回 true（归零后的下一拍触发"计时完成"）
   *
   * @returns true 表示本拍应触发"计时完成"逻辑
   */
  tick(): boolean {
    // 未运行时忽略推进（对应 UI 侧 pause 后 clearInterval 的语义）
    if (!this.running) {
      return false;
    }
    if (this.currentSecondValue > 0) {
      this.currentSecondValue--;
      return false;
    }
    return true;
  }

  /**
   * 是否到达保存接续状态的检查点（每 30 秒一次，与 Index 的 currentSecond % 30 === 0 对应）。
   */
  shouldPersistCheckpoint(): boolean {
    return this.currentSecondValue > 0 && this.currentSecondValue % 30 === 0;
  }

  /**
   * 是否达到休息提醒阈值（累计专注满 45 分钟），同一轮计时只触发一次。
   */
  shouldTriggerRestReminder(): boolean {
    if (this.restReminderTriggeredFlag) {
      return false;
    }
    const elapsed: number = this.totalSecondValue - this.currentSecondValue;
    if (elapsed >= TimerEngine.REST_REMINDER_ELAPSED_SECONDS) {
      this.restReminderTriggeredFlag = true;
      return true;
    }
    return false;
  }

  /**
   * 计时进度 0 ~ 1（与 Index.progress 一致；总时长为 0 时返回 0，避免 NaN）。
   */
  getProgress(): number {
    if (this.totalSecondValue === 0) {
      return 0;
    }
    return 1 - this.currentSecondValue / this.totalSecondValue;
  }

  /**
   * mm:ss 补零格式化（与 Index.timeDisplay 一致）。
   */
  formatTime(): string {
    const min: number = Math.floor(this.currentSecondValue / 60);
    const sec: number = this.currentSecondValue % 60;
    return `${min < 10 ? '0' + min : min}:${sec < 10 ? '0' + sec : sec}`;
  }
}
