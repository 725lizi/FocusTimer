import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { Constants } from '../model/Constants';

const DOMAIN = 0x0001;
const TAG = "SedentaryReminderManager";

/**
 * 久坐护眼联动管理器
 * 连续学习45分钟后触发震动提醒
 */
export class SedentaryReminderManager {
  private static instance: SedentaryReminderManager | null = null;
  private studyStartTime: number = 0;
  private reminderTimerId: number = -1;
  private callback: (() => void) | null = null;
  private hasReminded: boolean = false;

  private constructor() {
  }

  public static getInstance(): SedentaryReminderManager {
    if (SedentaryReminderManager.instance === null) {
      SedentaryReminderManager.instance = new SedentaryReminderManager();
    }
    return SedentaryReminderManager.instance;
  }

  /**
   * 开始监测
   */
  public startMonitoring(callback: () => void): void {
    this.callback = callback;
    this.studyStartTime = Date.now();
    this.hasReminded = false;

    this.reminderTimerId = setInterval(() => {
      const elapsedMinutes = Math.floor((Date.now() - this.studyStartTime) / (60 * 1000));
      if (elapsedMinutes >= Constants.SEDENTARY_THRESHOLD && !this.hasReminded) {
        this.hasReminded = true;
        this.triggerReminder();
      }
    }, 60 * 1000);

    hilog.info(DOMAIN, TAG, '久坐监测已启动');
  }

  /**
   * 停止监测
   */
  public stopMonitoring(): void {
    if (this.reminderTimerId !== -1) {
      clearInterval(this.reminderTimerId);
      this.reminderTimerId = -1;
    }
    this.callback = null;
    hilog.info(DOMAIN, TAG, '久坐监测已停止');
  }

  /**
   * 重置监测（重新开始计时）
   */
  public resetMonitoring(): void {
    this.studyStartTime = Date.now();
    this.hasReminded = false;
  }

  /**
   * 触发久坐提醒
   */
  private async triggerReminder(): Promise<void> {
    hilog.info(DOMAIN, TAG, '久坐提醒触发');

    // 震动提醒（双短震）
    try {
      await vibrator.startVibration({
        type: 'time',
        duration: 200
      }, {
        id: 0,
        usage: 'touch'
      });

      setTimeout(() => {
        vibrator.startVibration({
          type: 'time',
          duration: 200
        }, {
          id: 0,
          usage: 'touch'
        });
      }, 300);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '震动提醒失败');
    }

    // 回调通知
    if (this.callback) {
      this.callback();
    }
  }
}