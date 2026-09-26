// pages/NoteMindMap.ets
// 笔记脑图页：
//  - 路由参数 noteId 指定一篇笔记，交给 NoteMindMapOrchestrator 生成脑图；
//  - 在线且配置 Key：DeepSeek 流式生成脑图 JSON，再用自研 mindmap-harmony 的 MindMapView 渲染；
//  - 无网 / 未开 AI / 无 Key / 网络出错 / AI 返回坏 JSON：自动降级为本地规则解析，页面照常可用；
//  - 本页只做只读渲染（居中、双击复位、平移缩放由组件内置），不做节点编辑 / 导出 / 拖拽。
// 结构与 MindMapReview.ets 保持一致，本页只改标题、路由参数与取数方式。

import { router } from '@kit.ArkUI';
import { Constants } from '../model/Constants';
import { NoteMindMapOrchestrator } from '../services/ai/NoteMindMapOrchestrator';
import { MindTree, MindMapView } from 'mindmap-harmony';

/** 路由参数：笔记主键 */
interface NoteRouteParams {
  noteId: string;
}

@Entry
@Component
struct NoteMindMap {
  @State status: string = 'idle';        // idle/requesting/streaming/fallback/succeeded/failed
  @State source: string = '';           // llm / rule
  @State hint: string = '';             // 降级原因或来源说明（诚实展示给用户）
  @State tree: MindTree | null = null;  // 最终脑图树，非空时交给 MindMapView 渲染
  @State refreshTick: number = 0;       // 刷新计数：变化时驱动 MindMapView 重新布局
  @State noteId: string = '';           // 路由传入的笔记 id

  private orchestrator: NoteMindMapOrchestrator = new NoteMindMapOrchestrator();

  aboutToAppear(): void {
    // 取路由参数；缺失时直接给失败态，不发请求
    try {
      const params: NoteRouteParams = router.getParams() as NoteRouteParams;
      if (params === null || params === undefined
        || params.noteId === undefined || params.noteId.length === 0) {
        this.status = 'failed';
        this.source = 'rule';
        this.hint = '缺少笔记信息，请返回重试';
        return;
      }
      this.noteId = params.noteId;
      this.startGenerate();
    } catch (err) {
      this.status = 'failed';
      this.source = 'rule';
      this.hint = '缺少笔记信息，请返回重试';
      console.error('NoteMindMap getParams failed: ' + JSON.stringify(err));
    }
  }

  aboutToDisappear(): void {
    this.orchestrator.cancel();
  }

  /** 发起一次生成；首次进入、重试、重新生成都走这里 */
  private startGenerate(): void {
    this.status = 'requesting';
    this.source = '';
    this.hint = '';
    this.tree = null;

    this.orchestrator.generate(this.noteId, {
      onStatus: (status: string, src: string, statusHint: string) => {
        this.status = status;
        this.source = src;
        if (statusHint.length > 0) {
          this.hint = statusHint;
        }
      },
      onDone: (resultTree: MindTree, src: string, doneHint: string) => {
        this.tree = resultTree;
        this.source = src;
        if (doneHint.length > 0) {
          this.hint = doneHint;
        }
        this.refreshTick = this.refreshTick + 1;
      }
    });
  }

  private goBack(): void {
    try {
      router.back();
    } catch (err) {
      console.error('NoteMindMap router.back failed: ' + JSON.stringify(err));
    }
  }

  private isWorking(): boolean {
    return this.status === 'requesting' || this.status === 'streaming';
  }

  @Builder
  sourceBadge() {
    if (this.source === 'llm') {
      Text('✨ AI 生成')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor('#6C5CE7')
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    } else if (this.source === 'rule') {
      Text('本地规则')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor('#9AA5B1')
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    }
  }

  build() {
    Column() {
      // 顶部标题栏 + 返回
      Row() {
        Text('‹ 返回')
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.goBack();
          })
        Text('🧠 笔记脑图')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .margin({ left: 12 })
        Blank()
        this.sourceBadge()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      // 状态提示行：失败红色 / 规则或降级橙色 / AI 成功绿色
      if (this.status === 'failed') {
        Text(this.hint.length > 0 ? this.hint : '生成失败，请重试')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor(Constants.COLOR_ACCENT)
          .borderRadius(8)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .width('92%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })
      } else if (this.source === 'rule' && this.hint.length > 0
        && (this.status === 'succeeded' || this.status === 'fallback')) {
        Text(this.hint)
          .fontSize(11)
          .fontColor(Constants.COLOR_WARNING)
          .width('92%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 8 })
      } else if (this.status === 'succeeded' && this.source === 'llm') {
        Text('✨ 已由 AI 生成本篇笔记脑图')
          .fontSize(11)
          .fontColor(Constants.COLOR_SUCCESS)
          .width('92%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 8 })
      }

      // 主体：脑图画布 + 加载遮罩 + 失败遮罩
      Stack() {
        if (this.tree !== null) {
          MindMapView({ root: this.tree!.root, refreshTick: this.refreshTick })
            .width('100%')
            .height('100%')
        }

        if (this.isWorking()) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(34)
              .height(34)
              .color(Constants.COLOR_PRIMARY)
            Text('正在生成笔记脑图…')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_SUB)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Color.White)
        }

        if (this.status === 'failed') {
          Column({ space: 12 }) {
            Text('脑图暂时生成失败')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT)
            Text(this.hint.length > 0 ? this.hint : '请检查网络后重试')
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_SUB)
            Button('重试')
              .height(36)
              .fontSize(13)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .borderRadius(18)
              .padding({ left: 28, right: 28 })
              .onClick(() => {
                this.startGenerate();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Color.White)
        }
      }
      .layoutWeight(1)
      .width('92%')
      .backgroundColor(Color.White)
      .borderRadius(12)
      .clip(true)

      // 底部操作
      Row() {
        Button(this.isWorking() ? '生成中…' : '🔄 重新生成')
          .width('100%')
          .height(42)
          .fontSize(14)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(21)
          .enabled(!this.isWorking())
          .onClick(() => {
            this.startGenerate();
          })
      }
      .width('92%')
      .padding({ top: 10, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
  }
}
