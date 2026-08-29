import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { AIAnalysisService, StudySession, AIReport } from '../services/AIAnalysisService';
import { preferences } from '@kit.ArkData';
import { vibrator } from '@kit.SensorServiceKit';
import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ContinuationManager, SessionState } from '../common/ContinuationManager';
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

  @State todayFocusCount: number = 0;
  @State todayFocusMinutes: number = 0;
  @State dailyGoalMinutes: number = 120; // 今日目标分钟数
  @State dailyProgressValue: number = 0; // 保存计算后的进度百分比

  private sessionStartTime: number = 0;
  private interruptCount: number = 0;
  private hasRemindedToRest: boolean = false;

  @State lightValue: number = 0;
  @State isEyeCareAlertShown: boolean = false;
  private static readonly DARK_LIGHT_THRESHOLD = 50;

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
      this.currentSecond = sessionState.remainSeconds || this.currentSecond;
      this.totalSecond = sessionState.totalSeconds || this.totalSecond;
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
  private get progress(): number {
    if (this.totalSecond === 0) return 0;
    return 1 - this.currentSecond / this.totalSecond;
  }

  private get timeDisplay(): string {
    const min = Math.floor(this.currentSecond / 60);
    const sec = this.currentSecond % 60;
    return `${min < 10 ? '0' + min : min}:${sec < 10 ? '0' + sec : sec}`;
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
        Row() {
          Text('📡 离线模式 · 数据已本地保存，联网后自动同步')
            .fontSize(12)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(8)
        .backgroundColor(Constants.COLOR_WARNING)
      }

      Row() {
        Text('专注计时')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
        Blank()
        Button('流转')
          .height(32)
          .fontSize(14)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(16)
          .onClick(() => {
            this.navigateToPage(Constants.PAGE_NOTES);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 15, bottom: 10 })

      // ====== 可滚动内容区域 ======
      Scroll() {
        Column() {
          Column() {
            Stack() {
              Circle()
                .width(240)
                .height(240)
                .fill(Color.White)
                .shadow({ radius: 20, color: 'rgba(74,144,217,0.15)', offsetX: 0, offsetY: 4 })
              Circle()
                .width(220)
                .height(220)
                .fill(Color.White)
                .stroke(this.isRunning ? Constants.COLOR_PRIMARY : Constants.COLOR_ACCENT)
                .strokeWidth(8)
                .strokeDashArray([this.progress * 690, 690])
              Column() {
                Text(this.timeDisplay)
                  .fontSize(52)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Constants.COLOR_TEXT)
                  .fontFamily('monospace')
                Text(this.isRunning ? '专注中...' : '准备就绪')
                  .fontSize(14)
                  .fontColor(Constants.COLOR_TEXT_SUB)
                  .margin({ top: 8 })
              }
            }
            .margin({ top: 30 })

            Button(this.isRunning ? '暂停' : '开始专注')
              .width(180)
              .height(50)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.isRunning ? Constants.COLOR_ACCENT : Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .borderRadius(25)
              .margin({ top: 40 })
              .onClick(() => {
                this.toggleTimer();
              })

            if (!this.isRunning && this.currentSecond !== this.totalSecond) {
              Button('重置')
                .width(120)
                .height(40)
                .fontSize(14)
                .backgroundColor(Color.Transparent)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .borderRadius(20)
                .border({ width: 1, color: Constants.COLOR_TEXT_SUB })
                .margin({ top: 16 })
                .onClick(() => {
                  this.resetTimer();
                })
            }
          }
          .width('100%')
          .padding(20)

          // 今日学习目标进度
          Column() {
            Row() {
              Text('🎯 今日学习目标')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Constants.COLOR_TEXT)
              Blank()
              Text(`${this.todayFocusMinutes}/${this.dailyGoalMinutes}分钟`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SUB)
            }
            .width('100%')

            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width('100%')
                .height(10)
                .backgroundColor('#EEEEEE')
                .borderRadius(5)
              Row()
                .width(`${this.dailyProgressValue}%`)
                .height(10)
                .backgroundColor(Constants.COLOR_PRIMARY)
                .borderRadius(5)
            }
            .width('100%')
            .margin({ top: 10 })

            Text(this.dailyProgressValue >= 100 ? '🎉 今日目标已达成！太棒了！' : `已完成 ${this.dailyProgressValue}%，继续加油！`)
              .fontSize(13)
              .fontColor(this.dailyProgressValue >= 100 ? Constants.COLOR_SUCCESS : Constants.COLOR_PRIMARY)
              .margin({ top: 8 })
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .margin({ top: 20 })

          if (this.subjectTags.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.subjectTags, (tag: SubjectTagModel) => {
                  Column() {
                    Text(tag.icon).fontSize(18)
                    Text(tag.name)
                      .fontSize(10)
                      .fontColor(this.selectedSubjectTagId === tag.id ? Color.White : Constants.COLOR_TEXT_SUB)
                  }
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.selectedSubjectTagId === tag.id ? tag.color : Color.White)
                  .borderRadius(16)
                  .border({ width: 1, color: tag.color })
                  .onClick(() => {
                    this.selectedSubjectTagId = tag.id;
                  })
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('90%')
            .margin({ top: 12 })
          }

          Column() {
            Text('选择时长')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT)
              .margin({ bottom: 12 })
            Row({ space: 10 }) {
              ForEach(Constants.PRESET_LABELS, (label: string, index: number) => {
                Text(label)
                  .fontSize(13)
                  .fontColor(this.selectedDuration === index ? Color.White : Constants.COLOR_PRIMARY)
                  .backgroundColor(this.selectedDuration === index ? Constants.COLOR_PRIMARY : Color.White)
                  .borderRadius(16)
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .border({ width: 1, color: Constants.COLOR_PRIMARY })
                  .onClick(() => {
                    if (!this.isRunning) {
                      this.selectedDuration = index;
                      this.totalSecond = Constants.PRESET_DURATIONS[index];
                      this.currentSecond = Constants.PRESET_DURATIONS[index];
                    }
                  })
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .margin({ top: 20 })

          Row() {
            Text('专注免打扰模式')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.focusMode })
              .selectedColor(Constants.COLOR_PRIMARY)
              .onChange((isOn: boolean) => {
                this.focusMode = isOn;
                this.showToast(isOn ? '已开启免打扰' : '已关闭免打扰');
              })
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .margin({ top: 12 })

          Row() {
            Text(this.lightValue < Index.DARK_LIGHT_THRESHOLD ? '🌙' : '☀️')
              .fontSize(22)
            Column() {
              Text('环境光线')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT)
              Text(`${Math.round(this.lightValue)} lux${this.lightValue < Index.DARK_LIGHT_THRESHOLD ? ' (偏暗，注意护眼)' : ''}`)
                .fontSize(12)
                .fontColor(this.lightValue < Index.DARK_LIGHT_THRESHOLD ? '#FF6B35' : Constants.COLOR_TEXT_SUB)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 10 })
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .margin({ top: 12 })

          Row() {
            Column() {
              Text(`${this.todayFocusCount}`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_PRIMARY)
              Text('今日次数')
                .fontSize(12)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .margin({ top: 4 })
            }
            .layoutWeight(1)

            Divider().vertical(true).height(30)

            Column() {
              Text(`${this.todayFocusMinutes}`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_ACCENT)
              Text('今日分钟')
                .fontSize(12)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .margin({ bottom: 10 })
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // ====== 底部导航（固定） ======
      // ====== 底部导航（固定） ======
      Row() {
        Column() {
          Circle({ width: 6, height: 6 }).fill(Constants.COLOR_PRIMARY)
          Text('计时').fontSize(12).fontColor(Constants.COLOR_PRIMARY).fontWeight(FontWeight.Bold).margin({ top: 4 })
        }.layoutWeight(1)

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('笔记').fontSize(12).fontColor(Constants.COLOR_TEXT_SUB).margin({ top: 4 })
        }.layoutWeight(1)
        .onClick(() => this.navigateToPage(Constants.PAGE_NOTES))

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('统计').fontSize(12).fontColor(Constants.COLOR_TEXT_SUB).margin({ top: 4 })
        }.layoutWeight(1)
        .onClick(() => this.navigateToPage(Constants.PAGE_STATS))

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('分析报告').fontSize(12).fontColor(Constants.COLOR_TEXT_SUB).margin({ top: 4 })
        }.layoutWeight(1)
        .onClick(() => this.navigateToPage(Constants.PAGE_REPORT))
      }
      .width('100%')
      .height(60)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 16, topRight: 16 })

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

  private startTimer(): void {
    if (this.currentSecond <= 0) {
      this.currentSecond = this.totalSecond;
    }
    this.isRunning = true;
    this.sessionStartTime = Date.now();
    this.interruptCount = 0;
    this.hasRemindedToRest = false;
    this.saveContinuationState();
    if (this.focusMode) {
      FocusModeManager.getInstance().startFocusMode(Math.floor(this.totalSecond / 60));
    }
    SedentaryReminderManager.getInstance().startMonitoring(() => {
      console.info('🪑 久坐提醒触发');
    });
    this.timerId = setInterval(() => {
      if (this.currentSecond > 0) {
        this.currentSecond--;
        if (this.currentSecond % 30 === 0) {
          this.saveContinuationState();
        }
        const elapsed = this.totalSecond - this.currentSecond;
        if (elapsed >= 2700 && !this.hasRemindedToRest) {
          this.hasRemindedToRest = true;
          this.triggerRestReminder();
        }
      } else {
        this.onTimerComplete();
      }
    }, 1000);
  }

  private pauseTimer(): void {
    this.isRunning = false;
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.interruptCount++;
    FocusModeManager.getInstance().stopFocusMode();
    SedentaryReminderManager.getInstance().stopMonitoring();
    this.saveContinuationState();
  }

  private resetTimer(): void {
    this.pauseTimer();
    this.currentSecond = this.totalSecond;
    this.hasRemindedToRest = false;
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
          this.currentSecond = this.totalSecond;
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
      isInterrupted: this.interruptCount > 0,
      interruptCount: this.interruptCount
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