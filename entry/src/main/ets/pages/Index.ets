import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { AIAnalysisService, StudySession, AIReport } from '../services/AIAnalysisService';
import { preferences } from '@kit.ArkData';
import { vibrator } from '@kit.SensorServiceKit';
import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ContinuationManager, SessionState } from '../common/ContinuationManager';
import { TimerEngine } from '../common/TimerEngine';
import { SubjectTagManager } from '../common/SubjectTagManager';
import { SubjectTagModel } from '../model/SubjectTagModel';
import { OfflineCacheManager } from '../common/OfflineCacheManager';
import { FocusModeManager } from '../common/FocusModeManager';
import { SedentaryReminderManager } from '../common/SedentaryReminderManager';
import { GlobalContext } from '../common/GlobalContext';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { formProvider, formBindingData } from '@kit.FormKit';
import { CardDataBuilder, WidgetCardData } from '../common/CardDataBuilder';


import EntryFormAbility from '../entryformability/EntryFormAbility';
import { BottomNavBar } from '../components/BottomNavBar';
import { OfflineBanner } from '../components/OfflineBanner';
import { IndexHeader } from '../components/IndexHeader';
import { TimerRingSection } from '../components/TimerRingSection';
import { DailyGoalCard } from '../components/DailyGoalCard';
import { SubjectChips } from '../components/SubjectChips';
import { DurationSelector } from '../components/DurationSelector';
import { FocusModeToggle } from '../components/FocusModeToggle';
import { AmbientLightCard } from '../components/AmbientLightCard';
import { TodayStatsCard } from '../components/TodayStatsCard';

@Entry
@Component
struct Index {
  // ====== 计时状态 ======
  @State currentSecond: number = Constants.PRESET_DURATIONS[Constants.DEFAULT_INDEX];
  @State totalSecond: number = Constants.PRESET_DURATIONS[Constants.DEFAULT_INDEX];
  @State isRunning: boolean = false;
  @State focusMode: boolean = false;
  @State selectedDuration: number = Constants.DEFAULT_INDEX;

  // ====== 跨设备接续相关 ======
  @State showContinuationDialog: boolean = false;
  @State continuationTaskName: string = '';
  @State continuationRemainSeconds: number = 0;
  @State continuationSubjectTagName: string = '';

  // ====== 科目标签相关 ======
  @State subjectTags: SubjectTagModel[] = [];
  @State selectedSubjectTagId: string = '';

  // ====== 离线状态 ======
  @State isOffline: boolean = false;

  private timerId: number = -1;
  // 纯逻辑计时状态机；下面的 @State 仅作为它的镜像，用于驱动界面刷新
  private timerEngine: TimerEngine = new TimerEngine(Constants.PRESET_DURATIONS[Constants.DEFAULT_INDEX]);

  @State todayFocusCount: number = 0;
  @State todayFocusMinutes: number = 0;
  @State dailyGoalMinutes: number = 120; // 今日目标分钟数
  @State dailyProgressValue: number = 0; // 保存计算后的进度百分比

  private sessionStartTime: number = 0;

  @State lightValue: number = 0;
  @State isEyeCareAlertShown: boolean = false;

  // 自动专注时间段（晚自习）
  private static readonly AUTO_FOCUS_START_HOUR = 19;
  private static readonly AUTO_FOCUS_END_HOUR = 22;

  async aboutToAppear() {
    try {
      await DatabaseHelper.getInstance().init(getContext(this));

      this.loadTodayStats();
      this.startLightMonitoring();
      await this.loadSubjectTags();
      this.checkContinuation();

      const offlineFlag: Object | undefined = GlobalContext.getContext().getObject(Constants.OFFLINE_FLAG);
      this.isOffline = offlineFlag === true;

      // 启动学习自动化定时器
      this.startAutoFocusScheduler();
    } catch (err) {
      console.error('aboutToAppear failed: ' + JSON.stringify(err));
    }
  }

  aboutToDisappear(): void {
    this.stopLightMonitoring();
  }

  private async loadSubjectTags(): Promise<void> {
    try {
      const tagManager = SubjectTagManager.getInstance();
      this.subjectTags = await tagManager.getAllTags();
      if (this.subjectTags.length === 0) {
        await tagManager.createTag('高数', '#4A90D9', '📐');
        await tagManager.createTag('英语', '#00B894', '📝');
        await tagManager.createTag('专业课', '#6C5CE7', '📚');
        this.subjectTags = await tagManager.getAllTags();
      }
    } catch (err) {
      console.error('loadSubjectTags failed: ' + JSON.stringify(err));
    }
  }

  private async checkContinuation(): Promise<void> {
    try {
      // 直接从 Preferences 读取接续状态，不依赖内存初始化时序
      const prefs = await preferences.getPreferences(getContext(this), 'continuation_session');
      const saved = await prefs.get('session_state', '') as string;
      if (!saved) {
        return;
      }
      const sessionState: SessionState = JSON.parse(saved) as SessionState;
      if (sessionState && sessionState.active === true) {
        this.continuationTaskName = sessionState.taskName || '专注学习';
        this.continuationRemainSeconds = sessionState.remainSeconds || 0;
        const tagId = sessionState.subjectTagId || '';
        if (tagId) {
          const tagManager = SubjectTagManager.getInstance();
          this.continuationSubjectTagName = await tagManager.getTagName(tagId);
        }
        this.showContinuationDialog = true;
      }
    } catch (err) {
      console.error('checkContinuation failed: ' + JSON.stringify(err));
    }
  }

  private async acceptContinuation(): Promise<void> {
    try {
      const continuationManager = ContinuationManager.getInstance();
      const sessionState: SessionState = continuationManager.getSessionState();
      const totalSeconds: number = sessionState.totalSeconds || this.timerEngine.totalSecond;
      const remainSeconds: number = sessionState.remainSeconds || this.timerEngine.currentSecond;
      this.timerEngine.restoreFromCheckpoint(totalSeconds, remainSeconds);
      this.syncFromEngine();
      this.selectedSubjectTagId = sessionState.subjectTagId || '';
      if (sessionState.isPaused !== true) {
        this.startTimer();
      }
      await continuationManager.clearSessionState();
      this.showContinuationDialog = false;
    } catch (err) {
      console.error('acceptContinuation failed: ' + JSON.stringify(err));
    }
  }

  private async saveContinuationState(): Promise<void> {
    try {
      const continuationManager = ContinuationManager.getInstance();
      await continuationManager.saveSessionState(
        this.isRunning,
        '专注学习',
        this.selectedSubjectTagId,
        this.currentSecond,
        this.totalSecond,
        this.todayFocusMinutes,
        false
      );
    } catch (err) {
      console.error('saveContinuationState failed: ' + JSON.stringify(err));
    }
  }

  private async saveSessionToDb(): Promise<void> {
    try {
      const continuationManager = ContinuationManager.getInstance();
      const tagManager = SubjectTagManager.getInstance();
      const tagName = await tagManager.getTagName(this.selectedSubjectTagId);
      const taskName = tagName ? `${tagName}学习` : '专注学习';

      await continuationManager.saveStudySessionToDb(
        taskName,
        this.sessionStartTime,
        Date.now(),
        Math.floor(this.totalSecond / 60),
        this.selectedSubjectTagId
      );

      const dbMinutes = await continuationManager.loadTodayTotalMinutes();
      this.todayFocusMinutes = dbMinutes;
      this.updateDailyProgress();

      // 写入 preferences，供桌面卡片读取
      const prefs = await preferences.getPreferences(getContext(this), 'focusUserPrefs');
      await prefs.put('todayTotal', dbMinutes);                                    // 今日累计分钟数
      await prefs.put('lastDuration', Math.floor(this.totalSecond / 60));          // 本次计时时长（分钟）
      await prefs.put('lastSubject', tagName || '未分类');                         // 本次科目名
      await prefs.flush();

      // 计时完成后主动刷新桌面卡片
      try {
        await EntryFormAbility.requestUpdate(getContext(this));
        this.showToast('桌面卡片已更新');
      } catch (cardErr) {
        console.error('卡片更新异常: ' + JSON.stringify(cardErr));
        this.showToast('卡片更新失败，请重新添加桌面卡片');
      }

    } catch (err) {
      console.error('saveSessionToDb failed: ' + JSON.stringify(err));
    }
  }
  // 更新每日进度，确保不会出现 NaN 或 undefined
  private updateDailyProgress(): void {
    if (this.dailyGoalMinutes <= 0) {
      this.dailyProgressValue = 0;
      return;
    }
    const progress = Math.round((this.todayFocusMinutes / this.dailyGoalMinutes) * 100);
    if (isNaN(progress) || !isFinite(progress)) {
      this.dailyProgressValue = 0;
    } else {
      this.dailyProgressValue = Math.min(progress, 100);
    }
  }

  // 主动更新桌面卡片今日专注分钟数
  private async updateWidgetTodayMinutes(minutes: number): Promise<void> {
    try {
      const formsInfo = await formProvider.getFormsInfo();
      if (!formsInfo || formsInfo.length === 0) {
        return;
      }

      const cardData: WidgetCardData = CardDataBuilder.build(minutes);

      const formData = formBindingData.createFormBindingData(cardData);

      for (const formInfoItem of formsInfo) {
        const formId = (formInfoItem as Object as Record<string, Object>)['formId'] as string;
        await formProvider.updateForm(formId, formData);
      }
    } catch (err) {
      console.error('更新桌面卡片失败: ' + JSON.stringify(err));
    }
  }

  private startAutoFocusScheduler(): void {
    setInterval(() => {
      const now = new Date();
      const hour = now.getHours();
      const isAutoFocusTime = hour >= Index.AUTO_FOCUS_START_HOUR && hour < Index.AUTO_FOCUS_END_HOUR;

      if (isAutoFocusTime && !this.focusMode) {
        this.focusMode = true;
        this.showToast('已自动开启晚自习免打扰模式');
      } else if (!isAutoFocusTime && this.focusMode) {
        this.focusMode = false;
        this.showToast('已自动关闭免打扰模式');
      }
    }, 60000);
  }

  build() {
    Column() {
      if (this.isOffline) {
        OfflineBanner()
      }

      IndexHeader({ onTransfer: () => this.navigateToPage(Constants.PAGE_NOTES) })

      // ====== 可滚动内容区域 ======
      Scroll() {
        Column() {
          TimerRingSection({
            currentSecond: this.currentSecond,
            totalSecond: this.totalSecond,
            isRunning: this.isRunning,
            onToggle: () => this.toggleTimer(),
            onReset: () => this.resetTimer()
          })

          DailyGoalCard({
            todayFocusMinutes: this.todayFocusMinutes,
            dailyGoalMinutes: this.dailyGoalMinutes,
            dailyProgressValue: this.dailyProgressValue
          })

          if (this.subjectTags.length > 0) {
            SubjectChips({
              tags: this.subjectTags,
              selectedId: this.selectedSubjectTagId,
              onSelect: (id: string) => {
                this.selectedSubjectTagId = id;
              }
            })
          }

          DurationSelector({
            selectedIndex: this.selectedDuration,
            disabled: this.isRunning,
            onSelect: (index: number) => {
              this.selectedDuration = index;
              this.timerEngine.setDuration(Constants.PRESET_DURATIONS[index]);
              this.syncFromEngine();
            }
          })

          FocusModeToggle({
            isOn: this.focusMode,
            onChange: (isOn: boolean) => {
              this.focusMode = isOn;
              this.showToast(isOn ? '已开启免打扰' : '已关闭免打扰');
            }
          })

          AmbientLightCard({ lightValue: this.lightValue })

          TodayStatsCard({ count: this.todayFocusCount, minutes: this.todayFocusMinutes })
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // ====== 底部导航（全局公共组件） ======
      BottomNavBar({ active: 'timer' })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
    .bindContentCover($$this.showContinuationDialog, this.continuationDialogBuilder())
  }

  private navigateToPage(url: string): void {
    try {
      router.pushUrl({ url: url });
    } catch (err) {
      console.error('pushUrl failed: ' + JSON.stringify(err));
    }
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (err) {
      console.error('showToast failed: ' + JSON.stringify(err));
    }
  }

  private toggleTimer(): void {
    if (this.isRunning) {
      this.pauseTimer();
    } else {
      this.startTimer();
    }
  }

  // 把纯逻辑引擎的当前状态同步为驱动界面的 @State 镜像
  private syncFromEngine(): void {
    this.currentSecond = this.timerEngine.currentSecond;
    this.totalSecond = this.timerEngine.totalSecond;
    this.isRunning = this.timerEngine.isRunning;
  }

  // 停止计时时的系统侧副作用：清定时器、退出免打扰与久坐监测、保存接续点
  private stopRunningSideEffects(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    FocusModeManager.getInstance().stopFocusMode();
    SedentaryReminderManager.getInstance().stopMonitoring();
    this.saveContinuationState();
  }

  private startTimer(): void {
    this.timerEngine.start();
    this.syncFromEngine();
    this.sessionStartTime = Date.now();
    this.saveContinuationState();
    if (this.focusMode) {
      FocusModeManager.getInstance().startFocusMode(Math.floor(this.totalSecond / 60));
    }
    SedentaryReminderManager.getInstance().startMonitoring(() => {
      console.info('🪑 久坐提醒触发');
    });
    this.timerId = setInterval(() => {
      const completed: boolean = this.timerEngine.tick();
      this.syncFromEngine();
      if (completed) {
        this.onTimerComplete();
        return;
      }
      if (this.timerEngine.shouldPersistCheckpoint()) {
        this.saveContinuationState();
      }
      if (this.timerEngine.shouldTriggerRestReminder()) {
        this.triggerRestReminder();
      }
    }, 1000);
  }

  private pauseTimer(): void {
    this.timerEngine.pause();
    this.syncFromEngine();
    this.stopRunningSideEffects();
  }

  private resetTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    FocusModeManager.getInstance().stopFocusMode();
    SedentaryReminderManager.getInstance().stopMonitoring();
    // 引擎 reset 内部暂停一次（中断计数 +1，与历史行为一致）、剩余回满并清除休息提醒标记
    this.timerEngine.reset();
    this.syncFromEngine();
    this.saveContinuationState();
  }

  private onTimerComplete(): void {
    console.info('⭐ 计时完成！');
    this.pauseTimer();
    this.todayFocusCount++;
    this.todayFocusMinutes += Math.floor(this.totalSecond / 60);
    this.saveSessionToDb();
    ContinuationManager.getInstance().clearSessionState();
    this.saveCurrentSession();
    try {
      promptAction.showDialog({
        title: '🎉 专注完成！',
        message: `你已完成 ${Math.floor(this.totalSecond / 60)} 分钟的专注，太棒了！`,
        buttons: [
          { text: '继续专注', color: Constants.COLOR_PRIMARY },
          { text: '休息一下', color: Constants.COLOR_TEXT_SUB }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 0) {
          this.startTimer();
        }
      }).catch((err: BusinessError) => {
        console.error('showDialog error: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('showDialog failed: ' + JSON.stringify(err));
    }
  }

  private async saveCurrentSession() {
    const durationMinutes = Math.max(1, Math.floor(this.totalSecond / 60));

    // 取用户选择的真实科目名，未选则归为"未分类"
    let subjectName: string = '未分类';
    if (this.selectedSubjectTagId) {
      try {
        const tagManager = SubjectTagManager.getInstance();
        const name = await tagManager.getTagName(this.selectedSubjectTagId);
        if (name) {
          subjectName = name;
        }
      } catch (err) {
        console.error('getTagName failed: ' + JSON.stringify(err));
      }
    }

    const session: StudySession = {
      id: Date.now().toString(),
      startTime: this.sessionStartTime || Date.now(),
      duration: durationMinutes,
      tags: [subjectName],
      isInterrupted: this.timerEngine.pauseCount > 0,
      interruptCount: this.timerEngine.pauseCount
    };
    await this.handleSessionEnd(session);
  }

  private async handleSessionEnd(session: StudySession) {
    try {
      await this.saveSession(session);
      await this.loadTodayStats();
      const allSessions = await this.loadAllSessions();
      const report = await AIAnalysisService.getInstance().generateReport(allSessions);
      this.showAIReport(report);
    } catch (err) {
      console.error('handleSessionEnd failed: ' + JSON.stringify(err));
    }
  }

  private async saveSession(session: StudySession) {
    try {
      const prefs = await preferences.getPreferences(getContext(this), 'study_data');
      const existing = await prefs.get('sessions', '[]') as string;
      const sessions: StudySession[] = JSON.parse(existing);
      sessions.push(session);
      await prefs.put('sessions', JSON.stringify(sessions));
      await prefs.flush();
    } catch (err) {
      console.error('saveSession failed: ' + JSON.stringify(err));
    }
  }

  private async loadAllSessions(): Promise<StudySession[]> {
    try {
      const prefs = await preferences.getPreferences(getContext(this), 'study_data');
      const existing = await prefs.get('sessions', '[]') as string;
      return JSON.parse(existing) as StudySession[];
    } catch (err) {
      console.error('loadAllSessions failed: ' + JSON.stringify(err));
      return [];
    }
  }

  private async loadTodayStats(): Promise<void> {
    try {
      const continuationManager = ContinuationManager.getInstance();
      const todayMinutes = await continuationManager.loadTodayTotalMinutes();
      this.todayFocusMinutes = todayMinutes;
      const allSessions = await this.loadAllSessions();
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const todaySessions = allSessions.filter(s => s.startTime >= todayStart.getTime());
      this.todayFocusCount = todaySessions.length;

      // 更新进度条
      this.updateDailyProgress();
    } catch (err) {
      console.error('loadTodayStats failed: ' + JSON.stringify(err));
    }
  }

  private showAIReport(report: AIReport): void {
    console.info(`📊 分析报告 - 专注评分: ${report.focusScore}, 总时长: ${report.totalMinutes}分钟`);
  }

  private startLightMonitoring(): void {}
  private stopLightMonitoring(): void {}
  private triggerRestReminder(): void {}

  @Builder
  continuationDialogBuilder() {
    Column() {
      Text('发现未完成的学习任务')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT)
      Text(`任务：${this.continuationTaskName}`)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .margin({ top: 12 })
      Text(`剩余时间：${Math.floor(this.continuationRemainSeconds / 60)}分${this.continuationRemainSeconds % 60}秒`)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .margin({ top: 4 })
      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.White)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(20)
          .border({ width: 1, color: '#E0E0E0' })
          .onClick(() => {
            this.showContinuationDialog = false;
          })
        Button('继续学习')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(20)
          .onClick(() => {
            this.acceptContinuation();
          })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}