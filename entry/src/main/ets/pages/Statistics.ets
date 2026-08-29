import { Constants } from '../model/Constants';
import { BottomNavBar } from '../components/BottomNavBar';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { CalendarSyncManager } from '../common/CalendarSyncManager';
import { ShareManager } from '../common/ShareManager';
import { SubjectTagManager } from '../common/SubjectTagManager';
import { SubjectTagModel } from '../model/SubjectTagModel';
import { AIAnalysisService, StudySession } from '../services/AIAnalysisService';
import { FocusSessionStore } from '../common/FocusSessionStore';
import { GlobalContext } from '../common/GlobalContext';

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

  @State subjectDistribution: SubjectDistributionItem[] = [];

  async aboutToAppear(): Promise<void> {
    await this.loadSubjectTags();

    const offlineFlag: Object | undefined = GlobalContext.getContext().getObject(Constants.OFFLINE_FLAG);
    this.isOffline = offlineFlag === true;

    await this.loadStatistics();
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

      const aiService = AIAnalysisService.getInstance();
      this.weeklyReport = (await aiService.generateWeeklyReport(sessions)).replace(/\\\\n/g, '\\n');
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

          if (this.weeklyReport) {
            Column() {
              Text('📊 学习分析周报')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_TEXT)
                .margin({ bottom: 8 })

              Text(this.weeklyReport)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .lineHeight(20)
                .textAlign(TextAlign.Start)
            }
            .width('90%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)
          }
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
  }

  @Builder
  shareSheetBuilder() {
    Column({ space: 16 }) {
      Text('📤 分享学习报告')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Text(this.weeklyReport || '暂无报告数据')
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
}