import { Constants } from '../model/Constants';
import { BottomNavBar } from '../components/BottomNavBar';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { CalendarSyncManager } from '../common/CalendarSyncManager';
import { ShareManager } from '../common/ShareManager';
import { SubjectTagManager } from '../common/SubjectTagManager';
import { SubjectTagModel } from '../model/SubjectTagModel';
import { LearningAnalysisService, StudySession } from '../services/LearningAnalysisService';
import { FocusSessionStore } from '../common/FocusSessionStore';
import { GlobalContext } from '../common/GlobalContext';
import { AiReportOrchestrator } from '../services/ai/AiReportOrchestrator';
import { ApiKeyStore } from '../services/ai/ApiKeyStore';
import { ReportSource, ReportStatus } from '../services/ai/AiChatTypes';
import { MarkdownLite, TextSpan } from '../common/MarkdownLite';

/** 统计项接口 */
interface StatItem {
  label: string;
  value: number;
  unit: string;
  icon: string;
}

/** 科目学习时长分布项 */
interface SubjectDistributionItem {
  tagName: string;
  minutes: number;
  percent: number;
  color: string;
}

@Entry
@Component
struct Statistics {
  @State statItems: StatItem[] = [
    { label: '今日专注', value: 0, unit: '次', icon: '⏱' },
    { label: '今日时长', value: 0, unit: '分钟', icon: '📊' },
    { label: '本周专注', value: 0, unit: '次', icon: '📅' },
    { label: '本周时长', value: 0, unit: '分钟', icon: '📈' },
    { label: '总专注', value: 0, unit: '次', icon: '🏆' },
    { label: '总时长', value: 0, unit: '分钟', icon: '💪' },
  ];

  @State selectedTab: number = 0; // 0=日, 1=周, 2=月
  private tabLabels: string[] = ['日', '周', '月'];

  @State dailyData: number[] = [0, 0, 0, 0, 0, 0, 0];
  @State weeklyData: number[] = [0, 0, 0, 0, 0, 0, 0];
  @State monthlyData: number[] = [0, 0, 0, 0];

  @State subjectTags: SubjectTagModel[] = [];
  @State selectedSubjectFilter: string = '';

  @State weeklyReport: string = '';
  @State showShareDialog: boolean = false;

  @State isOffline: boolean = false;

  // ===== AI 周报相关状态 =====
  @State reportStatus: string = 'idle';        // idle/requesting/streaming/succeeded/fallback/failed
  @State reportSource: string = 'rule';       // llm=AI生成 / rule=本地规则
  @State reportHint: string = '';             // 降级原因或来源说明（诚实展示给用户）
  @State showAiSettings: boolean = false;     // AI 设置弹层
  @State apiKeyInput: string = '';            // 弹层里待保存的 Key
  @State aiSwitchInSheet: boolean = false;    // 弹层里的 AI 开关
  @State hasKey: boolean = false;             // 当前是否已保存 Key
  private orchestrator: AiReportOrchestrator = new AiReportOrchestrator();
  private allSessions: StudySession[] = [];   // 缓存最近一次记录，供 AI 生成复用

  @State subjectDistribution: SubjectDistributionItem[] = [];

  async aboutToAppear(): Promise<void> {
    this.refreshKeyState();
    await this.loadSubjectTags();

    const offlineFlag: Object | undefined = GlobalContext.getContext().getObject(Constants.OFFLINE_FLAG);
    this.isOffline = offlineFlag === true;

    await this.loadStatistics();
  }

  aboutToDisappear(): void {
    // 离开页面取消未完成的流式请求，避免监听/请求泄漏
    this.orchestrator.cancel();
  }

  private async loadSubjectTags(): Promise<void> {
    try {
      const tagManager = SubjectTagManager.getInstance();
      this.subjectTags = await tagManager.getAllTags();
    } catch (err) {
      console.error('loadSubjectTags failed: ' + JSON.stringify(err));
    }
  }

  private async loadStatistics(): Promise<void> {
    try {
      const calendarManager = CalendarSyncManager.getInstance();
      let sessions: StudySession[] = await FocusSessionStore.getInstance().getAllSessions();

      // 兼容旧数据：把"X分钟"这种错误标签（旧版把时长预设名当科目名存了）清洗为"未分类"
      sessions = sessions.map((s: StudySession) => {
        s.tags = s.tags.map((tag: string) => {
          if (/^\d+分钟$/.test(tag)) {
            return '未分类';
          }
          return tag;
        });
        return s;
      });
      // 缓存清洗后的记录，供「AI 生成周报」直接复用
      this.allSessions = sessions;

      const today = new Date().toDateString();
      const weekStart = this.getWeekStartTime();

      const todaySessions = sessions.filter(s => new Date(s.startTime).toDateString() === today);
      const todayCount = todaySessions.length;
      const todayMinutes = todaySessions.reduce((sum, s) => sum + s.duration, 0);

      const weekSessions = sessions.filter(s => s.startTime >= weekStart);
      const weekCount = weekSessions.length;
      const weekMinutes = weekSessions.reduce((sum, s) => sum + s.duration, 0);

      const totalCount = sessions.length;
      const totalMinutes = sessions.reduce((sum, s) => sum + s.duration, 0);

      const newStatItems: StatItem[] = [
        { label: '今日专注', value: todayCount, unit: '次', icon: '⏱' },
        { label: '今日时长', value: todayMinutes, unit: '分钟', icon: '📊' },
        { label: '本周专注', value: weekCount, unit: '次', icon: '📅' },
        { label: '本周时长', value: weekMinutes, unit: '分钟', icon: '📈' },
        { label: '总专注', value: totalCount, unit: '次', icon: '🏆' },
        { label: '总时长', value: totalMinutes, unit: '分钟', icon: '💪' },
      ];
      this.statItems = newStatItems;

      this.weeklyData = await calendarManager.getWeeklyTrend();
      this.dailyData = this.weeklyData.length > 0 ? this.weeklyData : [0, 0, 0, 0, 0, 0, 0];

      // 统计各科学习时长分布
      const tagMinutesMap = new Map<string, number>();
      for (const s of sessions) {
        for (const tag of s.tags) {
          const current = tagMinutesMap.get(tag) || 0;
          tagMinutesMap.set(tag, current + s.duration);
        }
      }

      const totalTagMinutes = Array.from(tagMinutesMap.values()).reduce((a, b) => a + b, 0);
      const distribution: SubjectDistributionItem[] = [];
      const colors = ['#4A90D9', '#00B894', '#6C5CE7', '#F39C12', '#E74C3C', '#1ABC9C'];

      let colorIndex = 0;
      tagMinutesMap.forEach((minutes, tagName) => {
        const percent = totalTagMinutes > 0 ? Math.round((minutes / totalTagMinutes) * 100) : 0;
        distribution.push({
          tagName: tagName,
          minutes: minutes,
          percent: percent,
          color: colors[colorIndex % colors.length]
        });
        colorIndex++;
      });

      this.subjectDistribution = distribution;

      // 进页面默认先给本地规则版周报（保证一进来就有内容，AI 由用户手动触发）
      const analysisService = LearningAnalysisService.getInstance();
      this.weeklyReport = (await analysisService.generateWeeklyReport(sessions)).replace(/\\n/g, '\n');
      this.reportSource = 'rule';
      this.reportStatus = 'succeeded';
      this.reportHint = '';
    } catch (err) {
      console.error('loadStatistics failed: ' + JSON.stringify(err));
    }
  }

  private async filterBySubject(subjectTagId: string): Promise<void> {
    try {
      this.selectedSubjectFilter = subjectTagId;

      const sessions: StudySession[] = await FocusSessionStore.getInstance().getAllSessions();

      let filteredSessions = sessions;
      if (subjectTagId) {
        const tagManager = SubjectTagManager.getInstance();
        const tagName = await tagManager.getTagName(subjectTagId);
        filteredSessions = sessions.filter(s => s.tags.includes(tagName));
      }

      const totalMinutes = filteredSessions.reduce((sum, s) => sum + s.duration, 0);
      const totalCount = filteredSessions.length;

      const newStatItems: StatItem[] = [
        { label: '今日专注', value: 0, unit: '次', icon: '⏱' },
        { label: '今日时长', value: 0, unit: '分钟', icon: '📊' },
        { label: '本周专注', value: 0, unit: '次', icon: '📅' },
        { label: '本周时长', value: 0, unit: '分钟', icon: '📈' },
        { label: '筛选专注', value: totalCount, unit: '次', icon: '🏆' },
        { label: '筛选时长', value: totalMinutes, unit: '分钟', icon: '💪' },
      ];
      this.statItems = newStatItems;

      this.showToast(`已筛选${subjectTagId ? '' : '全部'}科目`);
    } catch (err) {
      console.error('filterBySubject failed: ' + JSON.stringify(err));
    }
  }

  private getWeekStartTime(): number {
    const now = new Date();
    const dayOfWeek = now.getDay() || 7;
    const mondayOffset = (dayOfWeek - 1) * 24 * 60 * 60 * 1000;
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    weekStart.setTime(weekStart.getTime() - mondayOffset);
    weekStart.setHours(0, 0, 0, 0);
    return weekStart.getTime();
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (err) {
      console.error('showToast failed: ' + JSON.stringify(err));
    }
  }

  // ============ AI 周报：编排接入 ============

  private refreshKeyState(): void {
    this.hasKey = ApiKeyStore.getInstance().hasApiKeySync();
  }

  /** 点击「✨ AI生成」：走编排服务，自动决策 AI / 规则 / 降级 */
  private async generateAiReport(): Promise<void> {
    try {
      if (this.reportStatus === 'requesting' || this.reportStatus === 'streaming') {
        return; // 生成中防重复点击
      }
      let sessions: StudySession[] = this.allSessions;
      if (sessions.length === 0) {
        sessions = await FocusSessionStore.getInstance().getAllSessions();
        this.allSessions = sessions;
      }

      this.reportHint = '';
      this.weeklyReport = '';
      this.reportStatus = 'requesting';

      await this.orchestrator.generate(sessions, {
        onStatus: (status: ReportStatus, source: ReportSource, hint: string) => {
          this.reportStatus = status;
          this.reportSource = source;
          if (hint.length > 0) {
            this.reportHint = hint;
          }
        },
        onDelta: (fullText: string) => {
          // 流式：每来一段就用累计全文刷新界面，实现逐字出现
          this.weeklyReport = fullText;
        },
        onDone: (text: string, source: ReportSource, hint: string) => {
          this.weeklyReport = text;
          this.reportSource = source;
          this.reportStatus = 'succeeded';
          if (hint.length > 0) {
            this.reportHint = hint;
          }
        }
      });
    } catch (err) {
      this.reportStatus = 'failed';
      this.showToast('AI 周报生成异常，请查看本地规则版');
      console.error('generateAiReport failed: ' + JSON.stringify(err));
    }
  }

  private openAiSettings(): void {
    const store = ApiKeyStore.getInstance();
    this.apiKeyInput = '';
    this.aiSwitchInSheet = store.isEnabledSync();
    this.refreshKeyState();
    this.showAiSettings = true;
  }

  private async saveAiSettings(): Promise<void> {
    try {
      const store = ApiKeyStore.getInstance();
      if (this.apiKeyInput.trim().length > 0) {
        await store.saveApiKey(this.apiKeyInput.trim());
      }
      await store.setLlmEnabled(this.aiSwitchInSheet);
      this.refreshKeyState();
      this.showAiSettings = false;
      this.showToast('AI 设置已保存');
    } catch (err) {
      this.showToast('保存失败，请重试');
      console.error('saveAiSettings failed: ' + JSON.stringify(err));
    }
  }

  private async clearAiKey(): Promise<void> {
    try {
      await ApiKeyStore.getInstance().clearApiKey();
      this.apiKeyInput = '';
      this.refreshKeyState();
      this.showToast('已清空 Key');
    } catch (err) {
      console.error('clearAiKey failed: ' + JSON.stringify(err));
    }
  }

  build() {
    Column() {
      Row() {
        Text('数据统计')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
        Blank()
        Button('📤 分享')
          .height(32)
          .fontSize(13)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(16)
          .onClick(() => {
            this.showShareDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 15, bottom: 10 })

      if (this.isOffline) {
        Row() {
          Text('📡 离线模式 · 数据已本地保存')
            .fontSize(12)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(6)
        .backgroundColor(Constants.COLOR_WARNING)
      }

      Scroll() {
        Column({ space: 16 }) {
          if (this.subjectTags.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                Text('📚 全部')
                  .fontSize(11)
                  .fontColor(this.selectedSubjectFilter === '' ? Color.White : Constants.COLOR_PRIMARY)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.selectedSubjectFilter === '' ? Constants.COLOR_PRIMARY : Color.White)
                  .borderRadius(12)
                  .border({ width: 1, color: Constants.COLOR_PRIMARY })
                  .onClick(() => {
                    this.filterBySubject('');
                  })

                ForEach(this.subjectTags, (tag: SubjectTagModel) => {
                  Text(`${tag.icon} ${tag.name}`)
                    .fontSize(11)
                    .fontColor(this.selectedSubjectFilter === tag.id ? Color.White : tag.color)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.selectedSubjectFilter === tag.id ? tag.color : Color.White)
                    .borderRadius(12)
                    .border({ width: 1, color: tag.color })
                    .onClick(() => {
                      this.filterBySubject(tag.id);
                    })
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('90%')
          }

          Grid() {
            ForEach(this.statItems, (item: StatItem, index: number) => {
              GridItem() {
                Column() {
                  Text(item.icon)
                    .fontSize(28)
                  Text(`${item.value}`)
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Constants.COLOR_TEXT)
                    .margin({ top: 8 })
                  Text(`${item.label}(${item.unit})`)
                    .fontSize(11)
                    .fontColor(Constants.COLOR_TEXT_SUB)
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Color.White)
                .borderRadius(12)
              }
            })
          }
          .columnsTemplate('1fr 1fr')
          .rowsGap(12)
          .columnsGap(12)
          .width('90%')

          Row() {
            ForEach(this.tabLabels, (label: string, index: number) => {
              Text(label)
                .fontSize(14)
                .fontColor(this.selectedTab === index ? Color.White : Constants.COLOR_PRIMARY)
                .backgroundColor(this.selectedTab === index ? Constants.COLOR_PRIMARY : Color.White)
                .borderRadius(16)
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .border({ width: 1, color: Constants.COLOR_PRIMARY })
                .margin({ right: 10 })
                .onClick(() => {
                  this.selectedTab = index;
                })
            })
          }
          .width('90%')
          .justifyContent(FlexAlign.Start)

          Column() {
            Text('专注时长趋势（分钟）')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT)
              .margin({ bottom: 16 })

            Row({ space: 8 }) {
              ForEach(
                this.selectedTab === 0 ? this.dailyData :
                  this.selectedTab === 1 ? this.weeklyData : this.monthlyData,
                (value: number, index: number) => {
                  Column() {
                    Text(`${value}`)
                      .fontSize(11)
                      .fontColor(Constants.COLOR_TEXT_SUB)
                    Column()
                      .width(30)
                      .height(Math.max(4, Math.min(120, value / 3)))
                      .backgroundColor(this.selectedSubjectFilter ? Constants.COLOR_ACCENT : Constants.COLOR_PRIMARY)
                      .borderRadius({ topLeft: 4, topRight: 4 })
                    Text(`${index + 1}`)
                      .fontSize(10)
                      .fontColor(Constants.COLOR_TEXT_SUB)
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Center)
                }
              )
            }
            .alignItems(VerticalAlign.Bottom)
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)

          if (this.subjectDistribution.length > 0) {
            Column() {
              Text('📚 科目学习时长分布')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_TEXT)
                .margin({ bottom: 12 })

              ForEach(this.subjectDistribution, (item: SubjectDistributionItem) => {
                Column() {
                  Row() {
                    Text(item.tagName)
                      .fontSize(14)
                      .fontColor(Constants.COLOR_TEXT)
                      .layoutWeight(1)
                    Text(`${item.minutes}分钟 · ${item.percent}%`)
                      .fontSize(12)
                      .fontColor(Constants.COLOR_TEXT_SUB)
                  }
                  .width('100%')

                  Stack({ alignContent: Alignment.Start }) {
                    Row()
                      .width('100%')
                      .height(8)
                      .backgroundColor('#EEEEEE')
                      .borderRadius(4)
                    Row()
                      .width(`${item.percent}%`)
                      .height(8)
                      .backgroundColor(item.color)
                      .borderRadius(4)
                  }
                  .width('100%')
                  .margin({ top: 6 })
                }
                .width('100%')
                .padding({ bottom: 12 })
              })
            }
            .width('90%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)
          }

          // ===== 学习分析周报（规则版 + AI 流式版共用卡片）=====
          Column() {
            Row() {
              Text('📊 学习分析周报')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_TEXT)
              Blank()
              Text(this.reportSource === 'llm' ? '✨ AI 周报' : '本地规则')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor(this.reportSource === 'llm' ? '#6C5CE7' : '#9AA5B1')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ right: 8 })
              Button('✨ AI生成')
                .height(28)
                .fontSize(12)
                .backgroundColor(Constants.COLOR_PRIMARY)
                .fontColor(Color.White)
                .borderRadius(14)
                .enabled(this.reportStatus !== 'requesting' && this.reportStatus !== 'streaming')
                .onClick(() => {
                  this.generateAiReport();
                })
              Button('设置')
                .height(28)
                .fontSize(12)
                .margin({ left: 6 })
                .backgroundColor(Color.White)
                .fontColor(Constants.COLOR_PRIMARY)
                .borderRadius(14)
                .border({ width: 1, color: Constants.COLOR_PRIMARY })
                .onClick(() => {
                  this.openAiSettings();
                })
            }
            .width('100%')
            .margin({ bottom: 8 })

            if (this.reportHint.length > 0) {
              Text(this.reportHint)
                .fontSize(11)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .margin({ bottom: 6 })
                .textAlign(TextAlign.Start)
            }

            if (this.reportStatus === 'requesting') {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(Constants.COLOR_PRIMARY)
                Text('AI 正在连接并生成…')
                  .fontSize(12)
                  .fontColor(Constants.COLOR_TEXT_SUB)
              }
              .margin({ bottom: 6 })
            } else if (this.reportStatus === 'streaming') {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color('#6C5CE7')
                Text('正在逐字生成…')
                  .fontSize(12)
                  .fontColor('#6C5CE7')
              }
              .margin({ bottom: 6 })
            }

            if (this.weeklyReport.length > 0) {
              // 规则版/AI 版正文都可能含 Markdown 的 **加粗** 标记：
              // 解析成片段后用 Span 渲染，加粗段用粗体深色，普通段用常规色，且不再显示星号
              Text() {
                ForEach(MarkdownLite.parseBoldSpans(this.weeklyReport),
                  (span: TextSpan) => {
                    Span(span.text)
                      .fontSize(13)
                      .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(span.bold ? '#2D3436' : Constants.COLOR_TEXT_SUB)
                  },
                  (span: TextSpan, index: number) => `${index}-${span.bold}-${span.text.length}`)
              }
                .width('100%')
                .lineHeight(20)
                .textAlign(TextAlign.Start)
            } else {
              Text('暂无周报数据')
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .lineHeight(20)
                .textAlign(TextAlign.Start)
            }
          }
          .width('90%')
          .padding(16)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 16, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部导航（全局公共组件）
      BottomNavBar({ active: 'stats' })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
    .bindSheet($$this.showShareDialog, this.shareSheetBuilder(), {
      height: 250,
      dragBar: true
    })
    .bindSheet($$this.showAiSettings, this.aiSettingsBuilder(), {
      height: 480,
      dragBar: true
    })
  }

  @Builder
  shareSheetBuilder() {
    Column({ space: 16 }) {
      Text('📤 分享学习报告')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Text(this.weeklyReport.length > 0 ? MarkdownLite.stripBoldMarkers(this.weeklyReport) : '暂无报告数据')
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .backgroundColor(Color.White)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(20)
          .border({ width: 1, color: '#E0E0E0' })
          .onClick(() => {
            this.showShareDialog = false;
          })

        Button('分享到设备')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(20)
          .onClick(() => {
            const shareManager = ShareManager.getInstance();
            const shareData = shareManager.generateReportShareData(this.weeklyReport);
            console.info('分享数据: ' + JSON.stringify(shareData));
            this.showShareDialog = false;
            this.showToast('报告已生成，可流转到其他设备');
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
  }

  // ===== AI 设置底部弹层：填 Key、开关、保存、清空 =====
  @Builder
  aiSettingsBuilder() {
    Column({ space: 14 }) {
      Text('AI 周报设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Column({ space: 6 }) {
        Text('DeepSeek API Key（只保存在本机沙箱，不会上传、不进代码仓库）')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
        TextInput({
          text: this.apiKeyInput,
          placeholder: this.hasKey ? '已保存，输入新值可覆盖' : '粘贴 sk- 开头的 Key'
        })
          .type(InputType.Password)
          .height(44)
          .borderRadius(8)
          .backgroundColor('#F5F6F8')
          .onChange((value: string) => {
            this.apiKeyInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('启用 AI 周报')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.aiSwitchInSheet })
          .selectedColor(Constants.COLOR_PRIMARY)
          .onChange((isOn: boolean) => {
            this.aiSwitchInSheet = isOn;
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('清空 Key')
          .layoutWeight(1)
          .height(42)
          .fontSize(13)
          .backgroundColor(Color.White)
          .fontColor('#E74C3C')
          .borderRadius(21)
          .border({ width: 1, color: '#E74C3C' })
          .onClick(() => {
            this.clearAiKey();
          })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(21)
          .onClick(() => {
            this.saveAiSettings();
          })
      }
      .width('100%')

      Text('未开启 AI、未填 Key 或无网络时，会自动使用本地规则周报，功能不会中断；AI 出错也会自动回退。')
        .fontSize(11)
        .fontColor('#BBBBBB')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 20, topRight: 20 })
    .alignItems(HorizontalAlign.Start)
  }
}
