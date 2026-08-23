import { hilog } from '@kit.PerformanceAnalysisKit';
import { GlobalContext } from './GlobalContext';

const DOMAIN = 0x0001;
const TAG = "FocusModeManager";

/**
 * 专注模式系统级管控
 * 开启后屏蔽娱乐应用通知，计时结束自动恢复
 */
export class FocusModeManager {
  private static instance: FocusModeManager | null = null;
  private isFocusModeActive: boolean = false;
  private focusTimerId: number = -1;

  // 娱乐类应用包名列表
  private static readonly ENTERTAINMENT_APPS: string[] = [
    'com.kuaishou.nebula',
    'com.ss.android.ugc.aweme',
    'com.tencent.tmgp.sgame',
    'com.tencent.tmgp.pubgmhd',
    'com.bilibili.app.in',
    'com.tencent.qqlive',
    'com.youku.phone',
    'com.iqiyi.phone'
  ];

  private constructor() {
  }

  public static getInstance(): FocusModeManager {
    if (FocusModeManager.instance === null) {
      FocusModeManager.instance = new FocusModeManager();
    }
    return FocusModeManager.instance;
  }

  /**
   * 开启专注模式
   */
  public startFocusMode(durationMinutes: number): boolean {
    if (this.isFocusModeActive) {
      return true;
    }

    this.isFocusModeActive = true;
    GlobalContext.getContext().setObject('focus_mode_active', true);

    // 设置自动解除计时器
    this.focusTimerId = setTimeout(() => {
      this.stopFocusMode();
    }, durationMinutes * 60 * 1000);

    hilog.info(DOMAIN, TAG, '专注模式已开启，持续 %{public}d 分钟', durationMinutes);
    return true;
  }

  /**
   * 停止专注模式
   */
  public stopFocusMode(): void {
    if (!this.isFocusModeActive) {
      return;
    }

    if (this.focusTimerId !== -1) {
      clearTimeout(this.focusTimerId);
      this.focusTimerId = -1;
    }

    this.isFocusModeActive = false;
    GlobalContext.getContext().setObject('focus_mode_active', false);
    hilog.info(DOMAIN, TAG, '专注模式已停止');
  }

  /**
   * 检查是否在专注模式中
   */
  public isInFocusMode(): boolean {
    return this.isFocusModeActive;
  }

  /**
   * 检查应用是否为娱乐类
   */
  public isEntertainmentApp(packageName: string): boolean {
    return FocusModeManager.ENTERTAINMENT_APPS.includes(packageName);
  }

  /**
   * 获取娱乐应用列表
   */
  public getEntertainmentApps(): string[] {
    return FocusModeManager.ENTERTAINMENT_APPS;
  }
}