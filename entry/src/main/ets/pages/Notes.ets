import { relationalStore } from '@kit.ArkData';
import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { SubjectTagManager } from '../common/SubjectTagManager';
import { SubjectTagModel } from '../model/SubjectTagModel';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { GlobalContext } from '../common/GlobalContext';
import { ContinuationManager } from '../common/ContinuationManager';
import { AIAnalysisService } from '../services/AIAnalysisService';

/** 笔记条目 */
interface NoteItem {
  id: string;
  title: string;
  content: string;
  lastEditTime: string;
}

/** 笔记数据库值 */
interface NoteValues {
  id: string;
  title: string;
  content: string;
  subject_tag_id: string;
  is_encrypted: number;
  is_offline: number;
  is_synced: number;
  created_at: number;
  updated_at: number;
}

@Entry
@Component
struct Notes {
  // 笔记列表
  @State noteList: NoteItem[] = [];

  // 编辑相关
  @State isEditing: boolean = false;
  @State editTitle: string = '';
  @State editContent: string = '';
  @State editIndex: number = -1;

  // 流转相关
  @State isSearching: boolean = false;
  @State showDeviceList: boolean = false;
  @State availableDevices: string[] = [];
  @State showTransferConfirm: boolean = false;
  @State selectedDevice: string = '';
  @State hasDraft: boolean = false;

  // 科目标签相关
  @State subjectTags: SubjectTagModel[] = [];
  @State selectedSubjectTagId: string = '';

  // 离线状态
  @State isOffline: boolean = false;

  // 加密选项
  @State isEncrypted: boolean = false;

  // 要点解析结果
  @State aiParseResult: string = '';

  // ====== 生命周期 ======
  async aboutToAppear(): Promise<void> {
    await this.loadSubjectTags();

    const offlineFlag: Object | undefined = GlobalContext.getContext().getObject(Constants.OFFLINE_FLAG);
    this.isOffline = offlineFlag === true;

    await this.loadNotesFromDb();

    // 检查跨设备草稿
    this.checkNoteDraft();
  }

  // ====== 加载科目标签 ======
  private async loadSubjectTags(): Promise<void> {
    try {
      const tagManager = SubjectTagManager.getInstance();
      this.subjectTags = await tagManager.getAllTags();
    } catch (err) {
      console.error('loadSubjectTags failed: ' + JSON.stringify(err));
    }
  }

  // ====== 从数据库加载笔记 ======
  private async loadNotesFromDb(): Promise<void> {
    try {
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_NOTE, '', [], 'updated_at');
      if (resultSet) {
        const dbNotes: NoteItem[] = [];
        while (resultSet.goToNextRow()) {
          const noteItem: NoteItem = {
            id: resultSet.getString(resultSet.getColumnIndex('id')),
            title: resultSet.getString(resultSet.getColumnIndex('title')),
            content: resultSet.getString(resultSet.getColumnIndex('content')),
            lastEditTime: this.formatTime(resultSet.getLong(resultSet.getColumnIndex('updated_at')))
          };
          dbNotes.push(noteItem);
        }
        resultSet.close();
        if (dbNotes.length > 0) {
          this.noteList = dbNotes;
        }
      }
    } catch (err) {
      console.error('loadNotesFromDb failed: ' + JSON.stringify(err));
    }
  }

  // ====== 格式化时间 ======
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  // ====== 检查跨设备草稿 ======
  private checkNoteDraft(): void {
    const continuationManager = ContinuationManager.getInstance();
    const draft = continuationManager.getNoteDraft();
    if (draft.title || draft.content) {
      this.hasDraft = true;
      this.editTitle = draft.title;
      this.editContent = draft.content;
      this.selectedSubjectTagId = draft.subjectTagId;
      this.isEncrypted = draft.isEncrypted;
      this.isEditing = true;
    }
  }

  // ====== 保存草稿 ======
  private saveDraft(): void {
    const continuationManager = ContinuationManager.getInstance();
    continuationManager.saveNoteDraft(
      this.editTitle,
      this.editContent,
      this.selectedSubjectTagId,
      this.isEncrypted
    );
  }

  // ====== 笔记要点解析（端侧关键词/公式/术语提取） ======
  private async performAIParse(): Promise<void> {
    try {
      if (!this.editContent || this.editContent.trim().length === 0) {
        this.showToast('请先输入笔记内容');
        return;
      }

      const aiService = AIAnalysisService.getInstance();
      const result = await aiService.parseDocument(this.editContent);

      if (result.keywords.length === 0) {
        this.aiParseResult = '未能提取有效知识点，请添加更多内容。';
        return;
      }

      const keywordsText = result.keywords.join('\n');
      this.aiParseResult = `知识点提取：\n${keywordsText}\n\n摘要：\n${result.summary}`;
    } catch (err) {
      console.error('performAIParse failed: ' + JSON.stringify(err));
      this.aiParseResult = '要点解析失败，请稍后重试。';
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('笔记流转')
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
            this.startTransfer();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 15, bottom: 10 })

      // 离线提示
      if (this.isOffline) {
        Row() {
          Text('◉ 离线模式 · 笔记已本地保存，联网后自动同步')
            .fontSize(12)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(6)
        .backgroundColor(Constants.COLOR_WARNING)
      }

      // 编辑区域 / 列表
      if (this.isEditing) {
        Column({ space: 12 }) {
          TextInput({ text: this.editTitle, placeholder: '笔记标题' })
            .fontSize(16)
            .height(44)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .onChange((value: string) => {
              this.editTitle = value;
              this.saveDraft();
            })

          TextArea({ text: this.editContent, placeholder: '在这里记录你的笔记...' })
            .fontSize(15)
            .height(200)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .padding(12)
            .onChange((value: string) => {
              this.editContent = value;
              this.saveDraft();
            })

          // 科目标签选择
          if (this.subjectTags.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.subjectTags, (tag: SubjectTagModel) => {
                  Text(tag.name)
                    .fontSize(11)
                    .fontColor(this.selectedSubjectTagId === tag.id ? Color.White : tag.color)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.selectedSubjectTagId === tag.id ? tag.color : Color.White)
                    .borderRadius(12)
                    .border({ width: 1, color: tag.color })
                    .onClick(() => {
                      this.selectedSubjectTagId = tag.id;
                      this.saveDraft();
                    })
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('100%')
          }

          // 加密选项
          Row() {
            Text('加密此笔记')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isEncrypted })
              .selectedColor(Constants.COLOR_PRIMARY)
              .onChange((isOn: boolean) => {
                this.isEncrypted = isOn;
                if (isOn) {
                  this.showToast('笔记将使用生物识别加密');
                }
                this.saveDraft();
              })
          }
          .width('100%')

          // 要点解析按钮
          Button('解析笔记要点')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor(Constants.COLOR_ACCENT)
            .fontColor(Color.White)
            .borderRadius(20)
            .onClick(() => {
              this.performAIParse();
            })

          // 要点解析结果展示
          if (this.aiParseResult) {
            Text(this.aiParseResult)
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT)
              .width('100%')
              .padding(12)
              .backgroundColor('#F0F5FF')
              .borderRadius(8)
          }

          // 取消 / 保存按钮
          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(44)
              .backgroundColor(Color.White)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .borderRadius(22)
              .border({ width: 1, color: '#E0E0E0' })
              .onClick(() => {
                this.isEditing = false;
                this.isEncrypted = false;
                this.aiParseResult = '';
                ContinuationManager.getInstance().clearNoteDraft();
                this.hasDraft = false;
              })

            Button('保存')
              .layoutWeight(1)
              .height(44)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .borderRadius(22)
              .onClick(() => {
                this.saveNote();
              })
          }
          .width('100%')
        }
        .width('90%')
        .padding(16)
      } else {
        // 笔记列表模式
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.noteList, (item: NoteItem, index: number) => {
              Row() {
                Column() {
                  Text(item.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Constants.COLOR_TEXT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.content)
                    .fontSize(13)
                    .fontColor(Constants.COLOR_TEXT_SUB)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                  Text(item.lastEditTime)
                    .fontSize(11)
                    .fontColor('#CCCCCC')
                    .margin({ top: 6 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(16)
              .backgroundColor(Color.White)
              .borderRadius(12)
              .onClick(() => {
                this.editIndex = index;
                this.editTitle = item.title;
                this.editContent = item.content;
                this.aiParseResult = '';
                this.isEditing = true;
                this.saveDraft();
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 20 })
        }
        .layoutWeight(1)

        Button('+ 新建笔记')
          .width(160)
          .height(44)
          .fontSize(15)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(22)
          .margin({ bottom: 10 })
          .onClick(() => {
            this.editIndex = -1;
            this.editTitle = '';
            this.editContent = '';
            this.selectedSubjectTagId = '';
            this.isEncrypted = false;
            this.aiParseResult = '';
            this.isEditing = true;
            ContinuationManager.getInstance().clearNoteDraft();
            this.hasDraft = false;
          })
      }

      // 底部导航
      // 底部导航
      Row() {
        Column() {
          Circle({ width: 6, height: 6 }).fill(Constants.COLOR_PRIMARY)
          Text('计时').fontSize(12).fontColor(Constants.COLOR_PRIMARY).margin({ top: 4 })
        }.layoutWeight(1)
        .onClick(() => this.navigateToPage(Constants.PAGE_INDEX))

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('笔记').fontSize(12).fontColor(Constants.COLOR_PRIMARY).fontWeight(FontWeight.Bold).margin({ top: 4 })
        }.layoutWeight(1)

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('统计').fontSize(12).fontColor(Constants.COLOR_TEXT_SUB).margin({ top: 4 })
        }.layoutWeight(1)
        .onClick(() => this.navigateToPage(Constants.PAGE_STATS))
      }
      .width('100%')
      .height(60)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 16, topRight: 16 })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
    .bindSheet($$this.showDeviceList, this.deviceSheetBuilder(), { height: 300, dragBar: true })
    .bindContentCover($$this.showTransferConfirm, this.transferConfirmBuilder())
  }

  // ====== 导航辅助 ======
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

  // ====== 设备选择弹窗 ======
  @Builder
  deviceSheetBuilder() {
    Column({ space: 16 }) {
      Text('选择目标设备').fontSize(18).fontWeight(FontWeight.Bold)
      if (this.isSearching) {
        LoadingProgress().width(48).height(48).color(Constants.COLOR_PRIMARY)
        Text('正在搜索同账号设备...').fontSize(14).fontColor(Constants.COLOR_TEXT_SUB)
      } else if (this.availableDevices.length === 0) {
        Text('未发现可用设备').fontSize(14).fontColor(Constants.COLOR_TEXT_SUB)
        Text('请确保目标设备已登录同一华为账号\n且处于同一网络环境').fontSize(12).fontColor('#CCCCCC').textAlign(TextAlign.Center)
      } else {
        ForEach(this.availableDevices, (device: string) => {
          Row() {
            Text('▣').fontSize(24)
            Text(device).fontSize(15).fontColor(Constants.COLOR_TEXT).margin({ left: 12 })
          }
          .width('100%').padding(14).backgroundColor('#F8F8F8').borderRadius(10)
          .onClick(() => {
            this.selectedDevice = device;
            this.showDeviceList = false;
            this.showTransferConfirm = true;
          })
        })
      }
    }
    .width('100%').padding(24)
  }

  // ====== 流转确认弹窗 ======
  @Builder
  transferConfirmBuilder() {
    Column({ space: 16 }) {
      Text('确认流转').fontSize(18).fontWeight(FontWeight.Bold)
      Text(`将笔记流转到：${this.selectedDevice}`).fontSize(14).fontColor(Constants.COLOR_TEXT)
      Text('流转需要二次确认以保障数据安全').fontSize(12).fontColor(Constants.COLOR_TEXT_SUB)
      Row({ space: 16 }) {
        Button('取消').layoutWeight(1).height(44).backgroundColor(Color.White).fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(22).border({ width: 1, color: '#E0E0E0' })
          .onClick(() => { this.showTransferConfirm = false; })
        Button('确认流转').layoutWeight(1).height(44).backgroundColor(Constants.COLOR_PRIMARY).fontColor(Color.White)
          .borderRadius(22).onClick(() => { this.confirmTransfer(); })
      }.width('100%')
    }
    .width('100%').padding(24).backgroundColor(Color.White).borderRadius({ topLeft: 20, topRight: 20 })
  }

  // ====== 保存笔记 ======
  private async saveNote(): Promise<void> {
    try {
      if (!this.editTitle && !this.editContent) {
        this.showToast('请输入笔记内容');
        return;
      }
      const now = new Date();
      const timeStr = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')} ${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;

      const db = DatabaseHelper.getInstance();
      const newId = Date.now().toString();
      const noteValues: relationalStore.ValuesBucket = {
        id: newId,
        title: this.editTitle || '无标题',
        content: this.editContent,
        subject_tag_id: this.selectedSubjectTagId,
        is_encrypted: this.isEncrypted ? 1 : 0,
        is_offline: 0,
        is_synced: 0,
        created_at: Date.now(),
        updated_at: Date.now()
      };

      if (this.editIndex >= 0 && this.editIndex < this.noteList.length) {
        const existingNote = this.noteList[this.editIndex];
        noteValues.id = existingNote.id;
        await db.update(Constants.TABLE_NOTE, noteValues, 'id = ?', [existingNote.id]);
        const updated: NoteItem[] = [...this.noteList];
        updated[this.editIndex] = {
          id: existingNote.id,
          title: this.editTitle,
          content: this.editContent,
          lastEditTime: timeStr
        };
        this.noteList = updated;
      } else {
        await db.insert(Constants.TABLE_NOTE, noteValues);
        const newNote: NoteItem = {
          id: newId,
          title: this.editTitle || '无标题',
          content: this.editContent,
          lastEditTime: timeStr
        };
        this.noteList = [newNote, ...this.noteList];
      }

      await ContinuationManager.getInstance().clearNoteDraft();
      this.hasDraft = false;
      this.isEditing = false;
      this.isEncrypted = false;
      this.aiParseResult = '';
      this.showToast('保存成功');
    } catch (err) {
      console.error('saveNote failed: ' + JSON.stringify(err));
      this.showToast('保存失败，请重试');
    }
  }

  private startTransfer(): void {
    this.isSearching = true;
    this.showDeviceList = true;
    setTimeout(() => {
      this.isSearching = false;
      this.availableDevices = ['黎姿的平板', '黎姿的MatePad'];
    }, 2000);
  }

  private confirmTransfer(): void {
    this.showTransferConfirm = false;
    this.showToast(`正在流转到 ${this.selectedDevice}...`);
    setTimeout(() => {
      this.showToast(`笔记已成功流转到 ${this.selectedDevice}`);
    }, 2000);
  }
}