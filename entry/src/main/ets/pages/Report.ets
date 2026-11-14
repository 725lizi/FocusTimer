// pages/Report.ets
// 模型分工：复杂 ArkTS 自定义 UI 与页面接线，由智谱 GLM 负责。
// 分析报告页（分析能力入口聚合）：
//  - 旧版本页面被误写成了“笔记流转”，与“笔记”页重复，现修正为真正的分析报告入口；
//  - 复盘脑图：把本周专注记录生成可视化脑图，AI 不可用时自动降级本地规则；
//  - 专注画像：近 7/30 天的专注统计与带证据的规律洞察，每条结论都可追溯；
//  - 本页只负责入口跳转，不做数据计算，纯逻辑都在各自 services 内且已单测。

import { router } from '@kit.ArkUI';
import { Constants } from '../model/Constants';
import { BottomNavBar } from '../components/BottomNavBar';

@Entry
@Component
struct Report {
  // 打开复盘脑图页
  private openMindMapReview(): void {
    try {
      router.pushUrl({ url: 'pages/MindMapReview' });
    } catch (err) {
      console.error('open mindmap review failed: ' + JSON.stringify(err));
    }
  }

  // 直接打开专注画像页（无需先进复盘脑图）
  private openFocusProfile(): void {
    try {
      router.pushUrl({ url: 'pages/FocusProfile' });
    } catch (err) {
      console.error('open focus profile failed: ' + JSON.stringify(err));
    }
  }

  // 单个入口卡片：kind 决定点击后跳哪个页面（只传字符串，符合 ArkTS 严格规则）
  @Builder
  entryCard(icon: string, title: string, desc: string, kind: string) {
    Row() {
      Text(icon)
        .fontSize(30)
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
        Text(desc)
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14 })
      Text('›')
        .fontSize(22)
        .fontColor(Constants.COLOR_TEXT_SUB)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Constants.COLOR_CARD)
    .borderRadius(14)
    .onClick(() => {
      if (kind === 'mindmap') {
        this.openMindMapReview();
      } else if (kind === 'profile') {
        this.openFocusProfile();
      }
    })
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('分析报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 15, bottom: 12 })

      // 两个分析能力入口
      Column({ space: 14 }) {
        this.entryCard(
          '🧠',
          '复盘脑图',
          '把本周专注记录生成可视化脑图，AI 不可用时自动用本地规则',
          'mindmap'
        )
        this.entryCard(
          '🎯',
          '专注画像',
          '近 7/30 天专注统计与带证据的规律洞察，每条结论都可追溯',
          'profile'
        )
      }
      .width('92%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 底部导航（当前高亮“分析报告”）
      BottomNavBar({ active: 'report' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
  }
}
