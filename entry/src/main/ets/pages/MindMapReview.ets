// pages/MindMapReview.ets
// 复盘脑图页：
//  - 进入即读取本地专注记录，交给 MindMapReviewOrchestrator 生成本周复盘脑图；
//  - 在线且配置 Key：DeepSeek 流式生成脑图 JSON，再用自研 mindmap-harmony 的 MindMapView 渲染；
//  - 无网 / 未开 AI / 无 Key / 网络出错 / AI 返回坏 JSON：自动降级为本地规则树，页面照常可用；
//  - 脑图默认整树只读展示（居中、双击复位、平移缩放由组件内置）；
//  - 点中任意节点即弹出编辑面板：可加子级 / 加同级 / 删除 / 改名，输入框打字回车可快速连录节点，
//    所有修改走组件 EditController 唯一入口，改完自增 refreshTick 触发重新布局。
// 纯逻辑都在 services/ai 且已单测，本页只负责取数、状态展示、编辑接线与渲染。

import { router } from '@kit.ArkUI';
import { Constants } from '../model/Constants';
import { FocusSessionStore } from '../common/FocusSessionStore';
import { StudySession } from '../services/LearningAnalysisService';
import { MindMapReviewOrchestrator } from '../services/ai/MindMapReviewOrchestrator';
import { MindTree, MindMapView, EditController, MindNode } from 'mindmap-harmony';

@Entry
@Component
struct MindMapReview {
  @State status: string = 'idle';        // idle/requesting/streaming/fallback/succeeded/failed
  @State source: string = '';           // llm / rule
  @State hint: string = '';             // 降级原因或来源说明（诚实展示给用户）
  @State tree: MindTree | null = null;  // 最终脑图树，非空时交给 MindMapView 渲染
  @State refreshTick: number = 0;       // 刷新计数：变化时驱动 MindMapView 重新布局
  @State selectedId: string = '';       // 当前选中节点 id（驱动 MindMapView 选中描边）；空串=未选中、面板隐藏
  @State selectedText: string = '';     // 当前选中节点文本（编辑面板顶部展示）
  @State inputText: string = '';        // 改名 / 快录输入框文本

  private static readonly INPUT_ID: string = 'mindmap_review_input';  // 输入框 id，回车连录后抢回焦点
  private orchestrator: MindMapReviewOrchestrator = new MindMapReviewOrchestrator();
  private editor: EditController | null = null;  // 编辑能力唯一入口（tree 生成后创建）
  private sessions: StudySession[] = [];

  aboutToAppear(): void {
    this.startGenerate();
  }

  aboutToDisappear(): void {
    this.orchestrator.cancel();
  }

  /** 取数并发起一次生成；首次进入、重试、重新生成都走这里 */
  private async startGenerate(): Promise<void> {
    this.status = 'requesting';
    this.source = '';
    this.hint = '';
    this.tree = null;
    this.editor = null;
    this.selectedId = '';
    this.selectedText = '';
    this.inputText = '';

    try {
      this.sessions = await FocusSessionStore.getInstance().getAllSessions();
    } catch (err) {
      // 读记录失败不致命：按空记录处理，规则脑图仍会给出完整结构与鼓励
      this.sessions = [];
      console.error('MindMapReview load sessions failed: ' + JSON.stringify(err));
    }

    this.orchestrator.generate(this.sessions, {
      onStatus: (status: string, src: string, statusHint: string) => {
        this.status = status;
        this.source = src;
        if (statusHint.length > 0) {
          this.hint = statusHint;
        }
      },
      onDone: (resultTree: MindTree, src: string, doneHint: string) => {
        this.tree = resultTree;
        // 生成完成后创建编辑入口；页面默认不选中（selectedId 留空），保持复盘视图干净
        this.editor = new EditController(resultTree);
        this.selectedId = '';
        this.selectedText = '';
        this.inputText = '';
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
      console.error('MindMapReview router.back failed: ' + JSON.stringify(err));
    }
  }

  /** 跳转到专注画像页（从单次脑图延伸到历史规律分析） */
  private goProfile(): void {
    router.pushUrl({ url: 'pages/FocusProfile' });
  }

  private isWorking(): boolean {
    return this.status === 'requesting' || this.status === 'streaming';
  }

  // ==================== 节点编辑接线 ====================

  /** 节点点击：交给 EditController 记录选中，并显示编辑面板 */
  private handleNodeSelect(id: string): void {
    if (this.editor === null) {
      return;
    }
    this.editor.select(id);
    this.selectedId = id;
    const node: MindNode | null = this.editor.getSelected();
    this.selectedText = node === null ? '' : node.text;
  }

  /** 编辑后刷新：自增 tick 触发重排，并同步选中节点 id / 文本 */
  private bumpAfterEdit(): void {
    this.refreshTick = this.refreshTick + 1;
    if (this.editor !== null) {
      this.selectedId = this.editor.selectedId;
      const node: MindNode | null = this.editor.getSelected();
      this.selectedText = node === null ? '' : node.text;
    }
  }

  /** 收起编辑面板（完成），回到干净的只读复盘视图 */
  private finishEditing(): void {
    this.selectedId = '';
    this.selectedText = '';
    this.inputText = '';
  }

  private doAddChild(): void {
    if (this.editor === null) {
      return;
    }
    this.editor.addChildToSelected(this.inputText === '' ? '新子节点' : this.inputText);
    this.inputText = '';
    this.bumpAfterEdit();
  }

  private doAddSibling(): void {
    if (this.editor === null) {
      return;
    }
    this.editor.addSiblingAfterSelected(this.inputText === '' ? '新同级' : this.inputText);
    this.inputText = '';
    this.bumpAfterEdit();
  }

  private doRemove(): void {
    if (this.editor === null) {
      return;
    }
    this.editor.removeSelected();
    this.inputText = '';
    this.bumpAfterEdit();
  }

  private doRename(): void {
    if (this.editor === null || this.inputText === '') {
      return;
    }
    this.editor.updateSelectedText(this.inputText);
    this.inputText = '';
    this.bumpAfterEdit();
  }

  /**
   * 回车快录：选中普通节点时加同级；根没有兄弟，降级为加子级。
   * 输入框为空时使用默认文案；完成后清空并把焦点还给输入框，支持连续录入。
   */
  private quickAddByEnter(): void {
    if (this.editor === null) {
      return;
    }
    const current: MindNode | null = this.editor.getSelected();
    if (current === null) {
      return;
    }
    if (current.isRoot()) {
      this.editor.addChildToSelected(this.inputText === '' ? '新子节点' : this.inputText);
    } else {
      this.editor.addSiblingAfterSelected(this.inputText === '' ? '新同级' : this.inputText);
    }
    this.inputText = '';
    this.bumpAfterEdit();
    focusControl.requestFocus(MindMapReview.INPUT_ID);
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
        Text('🧠 复盘脑图')
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
        Text('✨ 已由 AI 生成本周复盘脑图')
          .fontSize(11)
          .fontColor(Constants.COLOR_SUCCESS)
          .width('92%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 8 })
      }

      // 节点编辑面板：点中节点后出现，默认隐藏以保持复盘视图干净
      if (this.selectedId !== '' && this.tree !== null) {
        Column() {
          Row() {
            Text('已选：')
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_SUB)
            Text(this.selectedText)
              .fontSize(12)
              .fontColor(Constants.COLOR_PRIMARY)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('完成')
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .onClick(() => {
                this.finishEditing();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row({ space: 6 }) {
            Button('加子级')
              .fontSize(12)
              .height(30)
              .layoutWeight(1)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .onClick(() => {
                this.doAddChild();
              })
            Button('加同级')
              .fontSize(12)
              .height(30)
              .layoutWeight(1)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .onClick(() => {
                this.doAddSibling();
              })
            Button('删除')
              .fontSize(12)
              .height(30)
              .layoutWeight(1)
              .backgroundColor(Constants.COLOR_ACCENT)
              .fontColor(Color.White)
              .onClick(() => {
                this.doRemove();
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row({ space: 6 }) {
            TextInput({ text: this.inputText, placeholder: '输入文本，回车快加节点' })
              .id(MindMapReview.INPUT_ID)
              .layoutWeight(1)
              .height(34)
              .onChange((value: string) => {
                this.inputText = value;
              })
              .onSubmit(() => {
                this.quickAddByEnter();
              })
            Button('改名')
              .fontSize(12)
              .height(34)
              .backgroundColor(Constants.COLOR_TEXT_SUB)
              .fontColor(Color.White)
              .onClick(() => {
                this.doRename();
              })
          }
          .width('100%')
        }
        .width('92%')
        .padding(10)
        .backgroundColor(Color.White)
        .borderRadius(10)
        .margin({ bottom: 8 })
      }

      // 主体：脑图画布 + 加载遮罩 + 失败遮罩
      Stack() {
        if (this.tree !== null) {
          MindMapView({
            root: this.tree!.root,
            refreshTick: this.refreshTick,
            selectedId: this.selectedId,
            onNodeSelect: (id: string): void => {
              this.handleNodeSelect(id);
            }
          })
            .width('100%')
            .height('100%')
        }

        if (this.isWorking()) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(34)
              .height(34)
              .color(Constants.COLOR_PRIMARY)
            Text('正在生成复盘脑图…')
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
      Row({ space: 8 }) {
        Button('🎯 专注画像')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Color.White)
          .fontColor(Constants.COLOR_PRIMARY)
          .borderRadius(21)
          .onClick(() => {
            this.goProfile();
          })
        Button(this.isWorking() ? '生成中…' : '🔄 重新生成')
          .layoutWeight(1)
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
