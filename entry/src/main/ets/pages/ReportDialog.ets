import { Constants } from '../model/Constants';

export interface ReportData {
  focusScore: number;
  totalMinutes: number;
  totalDays: number;
  avgDailyMinutes: number;
  bestTimeSegment: string;
  trend: string;
  tagDistribution: Map<string, number>;
  suggestion: string;
  interruptCount: number;
  sessionCount: number;
}

interface TagItem {
  tag: string;
  minutes: number;
}

@Component
export struct ReportDialog {
  report: ReportData = {
    focusScore: 0,
    totalMinutes: 0,
    totalDays: 0,
    avgDailyMinutes: 0,
    bestTimeSegment: '',
    trend: 'stable',
    tagDistribution: new Map(),
    suggestion: '',
    interruptCount: 0,
    sessionCount: 0
  };
  onClose?: () => void;

  private getScoreColor(): string {
    if (this.report.focusScore >= 80) return '#4CAF50';
    if (this.report.focusScore >= 60) return '#FF9800';
    return '#F44336';
  }

  private getScoreBg(): string {
    if (this.report.focusScore >= 80) return '#E8F5E9';
    if (this.report.focusScore >= 60) return '#FFF3E0';
    return '#FFEBEE';
  }

  private getTrendText(): string {
    if (this.report.trend === 'up') return '上升';
    if (this.report.trend === 'down') return '下降';
    return '稳定';
  }

  private getTagList(): TagItem[] {
    const list: TagItem[] = [];
    this.report.tagDistribution.forEach((minutes, tag) => {
      list.push({ tag: tag, minutes: minutes });
    });
    return list;
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('学习分析报告')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
        Blank()
        Text('关闭')
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            if (this.onClose) this.onClose();
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      Scroll() {
        Column({ space: 14 }) {
          // 评分
          Column() {
            Text('综合评分')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SUB)
            Text(this.report.focusScore.toString())
              .fontSize(48)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getScoreColor())
            Text('/100')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SUB)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.getScoreBg())
          .borderRadius(12)

          // 学习概况
          Column({ space: 10 }) {
            Text('学习概况')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT)

            Row() {
              Column() {
                Text(this.report.totalMinutes + '分钟')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT)
                Text('总时长')
                  .fontSize(11)
                  .fontColor(Constants.COLOR_TEXT_SUB)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)

              Column() {
                Text(this.report.totalDays + '天')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT)
                Text('学习天数')
                  .fontSize(11)
                  .fontColor(Constants.COLOR_TEXT_SUB)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)

              Column() {
                Text(this.report.avgDailyMinutes + '分钟')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT)
                Text('日均')
                  .fontSize(11)
                  .fontColor(Constants.COLOR_TEXT_SUB)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
            }
            .width('100%')

            Row() {
              Text('最佳时段：' + this.report.bestTimeSegment)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT)
            }
            .width('100%')

            Row() {
              Text('趋势：' + this.getTrendText())
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT)
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Constants.COLOR_BG)
          .borderRadius(12)

          // 标签分布
          if (this.getTagList().length > 0) {
            Column({ space: 8 }) {
              Text('各标签时长')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Constants.COLOR_TEXT)

              ForEach(this.getTagList(), (item: TagItem) => {
                Row() {
                  Text(item.tag)
                    .fontSize(13)
                    .fontColor(Constants.COLOR_TEXT)
                    .width(90)
                  Blank()
                  Text(item.minutes + '分钟')
                    .fontSize(13)
                    .fontColor(Constants.COLOR_PRIMARY)
                    .fontWeight(FontWeight.Medium)
                }
                .width('100%')
              }, (item: TagItem) => item.tag)
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Constants.COLOR_BG)
            .borderRadius(12)
          }

          // 学习建议
          Column() {
            Text('学习建议')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT)
              .margin({ bottom: 8 })

            Text(this.report.suggestion)
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT)
              .lineHeight(20)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Constants.COLOR_BG)
          .borderRadius(12)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 关闭按钮
      Button('知道了')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .borderRadius(22)
        .margin({ top: 16 })
        .onClick(() => {
          if (this.onClose) this.onClose();
        })
    }
    .width('85%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}