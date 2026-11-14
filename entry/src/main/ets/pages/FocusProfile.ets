// pages/FocusProfile.ets
// 模型分工：复杂 ArkTS 自定义 UI 与页面接线，由智谱 GLM 负责。
// 专注画像页：
//  - 顶部可切换近 7 天 / 30 天窗口，切换后重新生成统计与洞察；
//  - 上半部分展示确定性统计事实（总时长、日均、类别占比、时段分布、单次时长、周际变化）；
//  - 下半部分是洞察卡片，每条洞察显示结论、可点开的证据（evidence_ids 对应真实事实）和行动建议；
//  - 来源用徽标诚实区分：云端 AI / 本地规则 / 数据不足；无网无 Key 也能看规则版。
// 本页只负责取数、状态展示与渲染，纯逻辑在 services/profile 且已单测。

import { router } from '@kit.ArkUI';
import { Constants } from '../model/Constants';
import { FocusSessionStore } from '../common/FocusSessionStore';
import { StudySession } from '../services/LearningAnalysisService';
import { FocusProfileStats } from '../services/profile/FocusProfileStats';
import { FocusInsightOrchestrator } from '../services/profile/FocusInsightOrchestrator';
import { ReportSource, ReportStatus } from '../services/ai/AiChatTypes';
import {
  CategoryShare, FocusFact, FocusInsight, FocusInsightBundle, FocusProfileStatsResult,
  ProfileWindow, SegmentShare
} from '../services/profile/FocusProfileTypes';

@Entry
@Component
struct FocusProfile {
  @State status: string = 'idle';
  @State windowDays: ProfileWindow = 7;
  @State bundle: FocusInsightBundle | null = null;
  @State statsResult: FocusProfileStatsResult | null = null;
  // 当前展开证据的事实 id；空串表示没有展开
  @State expandedFactId: string = '';

  private orchestrator: FocusInsightOrchestrator = new FocusInsightOrchestrator();
  private sessions: StudySession[] = [];

  aboutToAppear(): void {
    this.initAndLoad();
  }

  aboutToDisappear(): void {
    this.orchestrator.cancel();
  }

  /** 首次进入：取记录后加载默认 7 天窗口 */
  private async initAndLoad(): Promise<void> {
    try {
      this.sessions = await FocusSessionStore.getInstance().getAllSessions();
    } catch (err) {
      this.sessions = [];
      console.error('FocusProfile load sessions failed: ' + JSON.stringify(err));
    }
    this.loadWindow(this.windowDays);
  }

  /** 加载指定窗口：先本地算统计事实，再让编排器生成洞察 */
  private loadWindow(days: ProfileWindow): void {
    this.status = 'requesting';
    this.bundle = null;
    this.expandedFactId = '';
    const now: number = Date.now();
    this.statsResult = FocusProfileStats.build(this.sessions, days, now);

    this.orchestrator.generate(this.sessions, days, {
      onStatus: (nextStatus: ReportStatus, _source: ReportSource, _hint: string) => {
        this.status = nextStatus;
      },
      onDone: (resultBundle: FocusInsightBundle) => {
        this.bundle = resultBundle;
      }
    });
  }

  private switchWindow(days: ProfileWindow): void {
    if (this.windowDays === days) {
      return;
    }
    this.windowDays = days;
    this.loadWindow(days);
  }

  private goBack(): void {
    try {
      router.back();
    } catch (err) {
      console.error('FocusProfile router.back failed: ' + JSON.stringify(err));
    }
  }

  /** 按 id 找到统计事实，用于展开证据 */
  private factById(id: string): FocusFact | null {
    if (this.statsResult === null) {
      return null;
    }
    for (const f of this.statsResult.facts) {
      if (f.id === id) {
        return f;
      }
    }
    return null;
  }

  private toggleFact(id: string): void {
    this.expandedFactId = this.expandedFactId === id ? '' : id;
  }

  /** 来源徽标：AI 紫色、规则灰色、数据不足橙色 */
  @Builder
  sourceTag(source: string) {
    if (source === 'llm') {
      Text('云端 AI')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor('#6C5CE7')
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    } else if (source === 'insufficient') {
      Text('数据不足')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor(Constants.COLOR_WARNING)
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    } else {
      Text('本地规则')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor('#9AA5B1')
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    }
  }

  @Builder
  overviewBlock(r: FocusProfileStatsResult) {
    Column() {
      Text('📊 统计概览')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .width('100%')
          .margin({ bottom: 8 })

        Row() {
          this.overviewCell('总时长', `${r.totalMinutes}`, '分钟')
          this.overviewCell('日均', `${r.avgDailyMinutes}`, '分钟')
        }
        .width('100%')

        Row() {
          this.overviewCell('样本量', `${r.sampleSize}`, '条')
          this.overviewCell('活跃天数', `${r.activeDays}`, '天')
        }
        .width('100%')

        // 类别占比
        Text('类别占比')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .width('100%')
          .margin({ top: 10, bottom: 4 })
        ForEach(r.categoryShares, (c: CategoryShare) => {
          Row() {
            Text(c.category)
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${c.minutes} 分钟`)
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .margin({ right: 8 })
            Text(`${c.share}%`)
              .fontSize(12)
              .fontColor(Constants.COLOR_PRIMARY)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ top: 3, bottom: 3 })
        }, (c: CategoryShare) => c.category)

        // 时段分布
        Text('时段分布')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .width('100%')
          .margin({ top: 10, bottom: 4 })
        ForEach(r.segmentShares, (s: SegmentShare) => {
          if (s.minutes > 0) {
            Row() {
              Text(s.label)
                .fontSize(12)
                .fontColor(Constants.COLOR_TEXT)
                .layoutWeight(1)
              Text(`${s.share}%`)
                .fontSize(12)
                .fontColor(Constants.COLOR_PRIMARY)
            }
            .width('100%')
            .padding({ top: 3, bottom: 3 })
          }
        }, (s: SegmentShare) => s.segmentKey)

        // 单次时长
        Text('单次时长')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .width('100%')
          .margin({ top: 10, bottom: 4 })
        Row() {
          Text(`平均 ${r.avgSessionDuration} 分钟`)
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT)
            .layoutWeight(1)
          Text(`中位数 ${r.medianSessionDuration} 分钟`)
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT)
        }
        .width('100%')

        // 周际变化（仅 30 天且可计算）
        if (!isNaN(r.weekOverWeekChange)) {
          Text(`周际变化 ${r.weekOverWeekChange}%`)
            .fontSize(12)
            .fontColor(r.weekOverWeekChange >= 0 ? Constants.COLOR_SUCCESS : Constants.COLOR_ACCENT)
            .width('100%')
            .margin({ top: 8 })
        }
      }
      .width('92%')
      .padding(12)
      .backgroundColor(Color.White)
      .borderRadius(12)
      .margin({ bottom: 10 })
  }

  @Builder
  overviewCell(label: string, value: string, unit: string) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(Constants.COLOR_TEXT_SUB)
      Row() {
        Text(value)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_PRIMARY)
        Text(unit)
          .fontSize(10)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .margin({ left: 2, bottom: 1 })
      }
      .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(Constants.COLOR_BG)
    .borderRadius(10)
    .margin(4)
  }

  @Builder
  factDetail(fact: FocusFact) {
    Column() {
      Text(`${fact.label}：${fact.value}${fact.unit}`)
        .fontSize(11)
        .fontColor(Constants.COLOR_TEXT)
        .width('100%')
      Text(`口径：${fact.calcNote}`)
        .fontSize(10)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Constants.COLOR_BG)
    .borderRadius(8)
  }

  @Builder
  insightCard(ins: FocusInsight) {
    Column() {
      Row() {
        this.sourceTag(ins.source)
        Blank()
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(ins.summary)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT)
        .width('100%')
        .margin({ bottom: 6 })

      // 证据：点击编号展开对应事实
      Text('证据 evidence_ids')
        .fontSize(11)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .width('100%')
        .margin({ bottom: 4 })
      ForEach(ins.evidenceIds, (id: string) => {
        Column() {
          Text(id)
            .fontSize(11)
            .fontColor(Constants.COLOR_PRIMARY)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.toggleFact(id);
            })
          if (this.expandedFactId === id) {
            if (this.factById(id) !== null) {
              this.factDetail(this.factById(id)!)
            }
          }
        }
        .width('100%')
      }, (id: string) => id)

      Row() {
        Text('行动建议：')
          .fontSize(11)
          .fontColor(Constants.COLOR_TEXT_SUB)
        Text(ins.action)
          .fontSize(12)
          .fontColor(Constants.COLOR_SUCCESS)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('92%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('‹ 返回')
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.goBack();
          })
        Text('🎯 专注画像')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .margin({ left: 12 })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 8 })

      // 窗口切换
      Row({ space: 8 }) {
        Button('近 7 天')
          .fontSize(13)
          .height(34)
          .layoutWeight(1)
          .backgroundColor(this.windowDays === 7 ? Constants.COLOR_PRIMARY : Color.White)
          .fontColor(this.windowDays === 7 ? Color.White : Constants.COLOR_TEXT_SUB)
          .onClick(() => {
            this.switchWindow(7);
          })
        Button('近 30 天')
          .fontSize(13)
          .height(34)
          .layoutWeight(1)
          .backgroundColor(this.windowDays === 30 ? Constants.COLOR_PRIMARY : Color.White)
          .fontColor(this.windowDays === 30 ? Color.White : Constants.COLOR_TEXT_SUB)
          .onClick(() => {
            this.switchWindow(30);
          })
      }
      .width('92%')
      .margin({ bottom: 10 })

      // 来源提示（降级/数据不足原因）
      if (this.bundle !== null && this.bundle.hint.length > 0) {
        Text(this.bundle.hint)
          .fontSize(11)
          .fontColor(Constants.COLOR_WARNING)
          .width('92%')
          .margin({ bottom: 8 })
      }

      // 内容区
      Scroll() {
        Column() {
          if (this.status === 'requesting') {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(34)
                .height(34)
                .color(Constants.COLOR_PRIMARY)
              Text('正在生成专注画像…')
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SUB)
            }
            .width('100%')
            .padding({ top: 40, bottom: 40 })
          } else {
            if (this.statsResult !== null) {
              this.overviewBlock(this.statsResult!)
            }
            if (this.bundle !== null) {
              ForEach(this.bundle.insights, (ins: FocusInsight) => {
                this.insightCard(ins);
              }, (ins: FocusInsight) => ins.id)
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
  }
}
