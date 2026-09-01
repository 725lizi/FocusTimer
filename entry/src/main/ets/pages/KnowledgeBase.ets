// pages/KnowledgeBase.ets
// RAG 个人学习知识库问答页：
//  - 「重建知识库」：把本地未加密笔记逐篇切块+向量化+入库（需向量化 Key）
//  - 提问：查询向量化 -> 本地 Top-K 召回 -> 规划 -> DeepSeek 流式回答，并展示来源引用
//  - 设置弹层：填向量化 Key（DeepSeek 聊天 Key 复用统计页设置）
// 纯逻辑都在 services/rag 且已单测，本页只做交互与渲染。

import { router, promptAction } from '@kit.ArkUI';
import { Constants } from '../model/Constants';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { MarkdownLite, TextSpan } from '../common/MarkdownLite';
import { ApiKeyStore } from '../services/ai/ApiKeyStore';
import { EmbeddingKeyStore } from '../services/rag/EmbeddingKeyStore';
import { RagRuntime } from '../services/rag/RagRuntime';
import { ChunkMeta, Citation, QaPlan } from '../services/rag/RagTypes';
import { relationalStore } from '@kit.ArkData';
import { LlmErrorKind } from '../services/ai/ReportStrategy';
import { HttpErrorMapper } from '../services/ai/HttpErrorMapper';

@Entry
@Component
struct KnowledgeBase {
  @State answer: string = '';
  @State status: string = 'idle';          // idle / working / streaming / succeeded / failed
  @State isAsking: boolean = false;       // 是否正在问答（显式状态，驱动输入框/按钮，避免在 UI 里绑定方法调用）
  @State hint: string = '';
  @State citations: Citation[] = [];
  @State qaMode: string = '';              // grounded / no_evidence
  @State questionInput: string = '';
  @State indexedCount: number = 0;
  @State rebuilding: boolean = false;
  @State rebuildHint: string = '';

  @State showSettings: boolean = false;
  @State embedKeyInput: string = '';
  @State hasEmbedKey: boolean = false;
  @State hasLlmKey: boolean = false;

  aboutToAppear(): void {
    this.refreshState();
  }

  aboutToDisappear(): void {
    RagRuntime.getInstance().cancelQa();
  }

  private refreshState(): void {
    this.hasEmbedKey = EmbeddingKeyStore.getInstance().hasApiKeySync();
    this.hasLlmKey = ApiKeyStore.getInstance().hasApiKeySync();
    this.indexedCount = RagRuntime.getInstance().indexedCount();
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (err) {
      console.error('showToast failed: ' + JSON.stringify(err));
    }
  }

  // ============ 提问 ============
  private async sendQuestion(): Promise<void> {
    const question: string = this.questionInput.trim();
    if (this.isAsking) {
      return;
    }
    if (question.length === 0) {
      this.showToast('请先输入问题');
      return;
    }
    const embedKey: string = EmbeddingKeyStore.getInstance().getApiKeySync();
    const llmKey: string = ApiKeyStore.getInstance().getApiKeySync();
    if (embedKey.length === 0) {
      this.showToast('请先在右上角设置里填写向量化 Key');
      this.showSettings = true;
      return;
    }
    if (llmKey.length === 0) {
      this.showToast('还未配置 DeepSeek Key，请先到统计页设置');
      return;
    }

    this.answer = '';
    this.citations = [];
    this.qaMode = '';
    this.hint = '';
    this.status = 'working';
    this.isAsking = true;

    try {
      await RagRuntime.getInstance().ask(question, embedKey, llmKey, {
        onPlan: (plan: QaPlan) => {
          this.qaMode = plan.mode;
          this.citations = plan.citations;
          this.status = 'streaming';
          if (plan.mode === 'no_evidence') {
            this.hint = '你的笔记里没有找到足够相关的内容，以下为通用建议';
          } else {
            this.hint = `已从你的 ${plan.usedCount} 段笔记中检索作答`;
          }
        },
        onDelta: (delta: string) => {
          this.answer += delta;
        },
        onError: (kind: LlmErrorKind, message: string) => {
          this.status = 'failed';
          this.isAsking = false;
          this.hint = HttpErrorMapper.userMessage(kind);
          console.error('RAG QA error: ' + kind + ' ' + message);
        },
        onComplete: (fullText: string) => {
          this.answer = fullText;
          this.status = 'succeeded';
          this.isAsking = false;
        }
      }, 5);
    } catch (err) {
      this.status = 'failed';
      this.isAsking = false;
      this.hint = '问答失败，请检查网络或 Key 后重试';
      console.error('sendQuestion failed: ' + JSON.stringify(err));
    }
  }

  private cancelQuestion(): void {
    RagRuntime.getInstance().cancelQa();
    this.isAsking = false;
    this.status = this.answer.length > 0 ? 'succeeded' : 'idle';
  }

  // ============ 重建知识库 ============
  private async rebuildIndex(): Promise<void> {
    if (this.rebuilding) {
      return;
    }
    const embedKey: string = EmbeddingKeyStore.getInstance().getApiKeySync();
    if (embedKey.length === 0) {
      this.showToast('请先填写向量化 Key');
      this.showSettings = true;
      return;
    }
    this.rebuilding = true;
    this.rebuildHint = '正在读取笔记并向量化…';
    let noteCount: number = 0;
    let rs: relationalStore.ResultSet | null = null;
    try {
      const db = DatabaseHelper.getInstance();
      rs = await db.query(Constants.TABLE_NOTE, 'is_encrypted = 0', [], 'updated_at');
      if (rs !== null) {
        while (rs.goToNextRow()) {
          const id: string = String(rs.getLong(rs.getColumnIndex('id')));
          const title: string = rs.getString(rs.getColumnIndex('title'));
          const content: string = rs.getString(rs.getColumnIndex('content'));
          if (!content || content.trim().length === 0) {
            continue;
          }
          const meta: ChunkMeta = {
            sourceId: id,
            sourceType: 'note',
            sourceTitle: title && title.length > 0 ? title : '未命名笔记',
            sourceTime: rs.getLong(rs.getColumnIndex('updated_at'))
          };
          const raw: string = `${title}\n${content}`;
          await RagRuntime.getInstance().buildIndex(raw, meta, embedKey);
          noteCount++;
          this.rebuildHint = `已处理 ${noteCount} 篇笔记，累计 ${RagRuntime.getInstance().indexedCount()} 段`;
        }
      }
      this.indexedCount = RagRuntime.getInstance().indexedCount();
      this.rebuildHint = '';
      this.showToast(noteCount > 0 ? `知识库已更新，共 ${noteCount} 篇笔记` : '没有可索引的笔记');
    } catch (err) {
      this.rebuildHint = '';
      this.showToast('重建失败，请检查网络或 Key');
      console.error('rebuildIndex failed: ' + JSON.stringify(err));
    } finally {
      if (rs !== null) {
        rs.close();
      }
      this.rebuilding = false;
    }
  }

  // ============ 设置 ============
  private openSettings(): void {
    this.embedKeyInput = '';
    this.refreshState();
    this.showSettings = true;
  }

  private async saveEmbedKey(): Promise<void> {
    if (this.embedKeyInput.trim().length === 0) {
      this.showToast('请粘贴 Key 后再保存');
      return;
    }
    await EmbeddingKeyStore.getInstance().saveApiKey(this.embedKeyInput.trim());
    this.refreshState();
    this.showSettings = false;
    this.showToast('向量化 Key 已保存');
  }

  @Builder
  citationChips() {
    if (this.citations.length > 0) {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.citations, (c: Citation) => {
          Text(`📎 ${c.title}`)
            .fontSize(11)
            .fontColor(Constants.COLOR_PRIMARY)
            .backgroundColor('#EAF2FD')
            .borderRadius(10)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ right: 6, bottom: 6 })
        }, (c: Citation) => c.sourceId)
      }
      .width('100%')
      .margin({ bottom: 8 })
    }
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('‹ 返回')
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            router.back();
          })
        Text('🧠 知识库问答')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .margin({ left: 12 })
        Blank()
        Text('⚙ 设置')
          .fontSize(13)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.openSettings();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      // 知识库状态条
      Row() {
        Column() {
          Text(`已收录 ${this.indexedCount} 段笔记`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT)
          if (this.rebuildHint.length > 0) {
            Text(this.rebuildHint)
              .fontSize(10)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.rebuilding ? '重建中…' : '🔄 重建知识库')
          .height(32)
          .fontSize(12)
          .enabled(!this.rebuilding)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(16)
          .onClick(() => {
            this.rebuildIndex();
          })
      }
      .width('92%')
      .padding(12)
      .backgroundColor(Color.White)
      .borderRadius(12)

      // 答案区
      Scroll() {
        Column() {
          if (this.isAsking) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color('#6C5CE7')
              Text(this.status === 'working' ? '正在检索你的笔记…' : '正在生成回答…')
                .fontSize(12)
                .fontColor(Constants.COLOR_TEXT_SUB)
            }
            .width('100%')
            .margin({ bottom: 8 })
          }

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(11)
              .fontColor(this.qaMode === 'no_evidence' ? Constants.COLOR_WARNING : Constants.COLOR_PRIMARY)
              .width('100%')
              .margin({ bottom: 6 })
          }

          this.citationChips()

          if (this.answer.length > 0) {
            Text() {
              ForEach(MarkdownLite.parseBoldSpans(this.answer), (span: TextSpan) => {
                Span(span.text)
                  .fontSize(14)
                  .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(span.bold ? '#2D3436' : Constants.COLOR_TEXT)
              }, (span: TextSpan, index: number) => `${index}-${span.bold}-${span.text.length}`)
            }
            .width('100%')
            .lineHeight(22)
            .textAlign(TextAlign.Start)
          } else if (!this.isAsking) {
            Text('向我提问吧，我会优先根据你自己的笔记回答。\n例如：我这周学的导数有哪些要点？\n\n第一次使用请先点「重建知识库」收录笔记。')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .lineHeight(22)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
      }
      .layoutWeight(1)
      .width('92%')
      .backgroundColor(Color.White)
      .borderRadius(12)
      .margin({ top: 12 })
      .scrollBar(BarState.Off)

      // 底部输入栏
      Row({ space: 8 }) {
        TextInput({ text: this.questionInput, placeholder: '基于你的笔记提问…' })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#F5F6F8')
          .enabled(!this.isAsking)
          .onChange((value: string) => {
            this.questionInput = value;
          })
        if (this.isAsking) {
          Button('停止')
            .height(40)
            .fontSize(13)
            .backgroundColor(Color.White)
            .fontColor('#E74C3C')
            .borderRadius(20)
            .border({ width: 1, color: '#E74C3C' })
            .onClick(() => {
              this.cancelQuestion();
            })
        } else {
          Button('发送')
            .height(40)
            .fontSize(13)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Color.White)
            .borderRadius(20)
            .onClick(() => {
              this.sendQuestion();
            })
        }
      }
      .width('92%')
      .padding({ top: 10, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
    .bindSheet($$this.showSettings, this.settingsBuilder(), {
      height: 460,
      dragBar: true
    })
  }

  @Builder
  settingsBuilder() {
    Column({ space: 14 }) {
      Text('知识库设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Column({ space: 6 }) {
        Text('向量化 API Key（硅基流动，只保存在本机沙箱，不上传、不进仓库）')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
        TextInput({
          text: this.embedKeyInput,
          placeholder: this.hasEmbedKey ? '已保存，输入新值可覆盖' : '粘贴向量化服务 Key'
        })
          .type(InputType.Password)
          .height(44)
          .borderRadius(8)
          .backgroundColor('#F5F6F8')
          .onChange((value: string) => {
            this.embedKeyInput = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('DeepSeek 聊天 Key')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT)
          .layoutWeight(1)
        Text(this.hasLlmKey ? '已配置' : '未配置（去统计页设置）')
          .fontSize(12)
          .fontColor(this.hasLlmKey ? Constants.COLOR_SUCCESS : Constants.COLOR_WARNING)
      }
      .width('100%')

      Button('保存向量化 Key')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .fontColor(Color.White)
        .borderRadius(22)
        .onClick(() => {
          this.saveEmbedKey();
        })

      Text('向量化用于把你的笔记和问题变成可比对的语义向量；生成回答仍走 DeepSeek。两把 Key 分开保存。')
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
