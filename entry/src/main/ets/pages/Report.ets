import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

/** 笔记条目 */
interface NoteItem {
  id: string;
  title: string;
  content: string;
  lastEditTime: string;
}

@Entry
@Component
struct Notes {
  // 笔记列表
  @State noteList: NoteItem[] = [
    { id: '1', title: '高等数学笔记', content: '微积分基本定理...', lastEditTime: '2026-07-28 08:00' },
    { id: '2', title: '英语单词本', content: 'abandon 放弃...', lastEditTime: '2026-07-27 20:30' },
  ];

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

  build() {
    Column() {
      // ====== 顶部标题栏 ======
      Row() {
        Text('笔记流转')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
        Blank()
        // 流转按钮
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

      // ====== 编辑区域 / 笔记列表 ======
      if (this.isEditing) {
        // 编辑模式
        Column({ space: 12 }) {
          TextInput({ text: this.editTitle, placeholder: '笔记标题' })
            .fontSize(16)
            .height(44)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .onChange((value: string) => {
              this.editTitle = value;
            })

          TextArea({ text: this.editContent, placeholder: '在这里记录你的笔记...' })
            .fontSize(15)
            .height(300)
            .borderRadius(8)
            .backgroundColor(Color.White)
            .padding(12)
            .onChange((value: string) => {
              this.editContent = value;
            })

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
                // 点击编辑笔记
                this.editIndex = index;
                this.editTitle = item.title;
                this.editContent = item.content;
                this.isEditing = true;
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 20 })
        }
        .layoutWeight(1)

        // 新建笔记按钮
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
            this.isEditing = true;
          })
      }

      // ====== 底部导航 ======
      // ====== 底部导航 ======
      Row() {
        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('计时')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => {
          try {
            router.pushUrl({ url: Constants.PAGE_INDEX });
          } catch (err) {
            console.error('pushUrl failed: ' + JSON.stringify(err));
          }
        })

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('笔记')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => {
          try {
            router.pushUrl({ url: Constants.PAGE_NOTES });
          } catch (err) {
            console.error('pushUrl failed: ' + JSON.stringify(err));
          }
        })

        Column() {
          Circle({ width: 6, height: 6 }).fill(Color.Transparent)
          Text('统计')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => {
          try {
            router.pushUrl({ url: Constants.PAGE_STATS });
          } catch (err) {
            console.error('pushUrl failed: ' + JSON.stringify(err));
          }
        })

        Column() {
          Circle({ width: 6, height: 6 }).fill(Constants.COLOR_PRIMARY)
          Text('AI报告')
            .fontSize(12)
            .fontColor(Constants.COLOR_PRIMARY)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height(60)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 16, topRight: 16 })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
    // ====== 设备列表弹窗 =====
    .bindSheet($$this.showDeviceList, this.deviceSheetBuilder(), {
      height: 300,
      dragBar: true
    })
    // ====== 流转确认弹窗 =====
    .bindContentCover($$this.showTransferConfirm, this.transferConfirmBuilder())
  }

  // ====== 设备选择弹窗内容 ======
  @Builder
  deviceSheetBuilder() {
    Column({ space: 16 }) {
      Text('选择目标设备')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      if (this.isSearching) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Constants.COLOR_PRIMARY)
        Text('正在搜索同账号设备...')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_SUB)
      } else if (this.availableDevices.length === 0) {
        Text('未发现可用设备')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_SUB)
        Text('请确保目标设备已登录同一华为账号\\\\\\\\n且处于同一网络环境')
          .fontSize(12)
          .fontColor('#CCCCCC')
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.availableDevices, (device: string) => {
          Row() {
            Text('??')
              .fontSize(24)
            Text(device)
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT)
              .margin({ left: 12 })
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#F8F8F8')
          .borderRadius(10)
          .onClick(() => {
            this.selectedDevice = device;
            this.showDeviceList = false;
            this.showTransferConfirm = true;
          })
        })
      }
    }
    .width('100%')
    .padding(24)
  }

  // ====== 流转确认弹窗 ======
  @Builder
  transferConfirmBuilder() {
    Column({ space: 16 }) {
      Text('确认流转')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Text(`将笔记流转到：${this.selectedDevice}`)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT)

      Text('流转需要二次确认以保障数据安全')
        .fontSize(12)
        .fontColor(Constants.COLOR_TEXT_SUB)

      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Color.White)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(22)
          .border({ width: 1, color: '#E0E0E0' })
          .onClick(() => {
            this.showTransferConfirm = false;
          })

        Button('确认流转')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(22)
          .onClick(() => {
            this.confirmTransfer();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  // ====== 业务方法 ======

  /**  保存笔记 */
  private saveNote(): void {
    try {
      if (!this.editTitle && !this.editContent) {
        promptAction.showToast({ message: '请输入笔记内容' });
        return;
      }
      const now = new Date();
      const timeStr = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')} ${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;

      if (this.editIndex >= 0) {
        // 更新已有笔记
        let updated: NoteItem[] = [...this.noteList];
        updated[this.editIndex] = {
          id: updated[this.editIndex].id,
          title: this.editTitle,
          content: this.editContent,
          lastEditTime: timeStr
        };
        this.noteList = updated;
      } else {
        // 新建笔记
        const newNote: NoteItem = {
          id: Date.now().toString(),
          title: this.editTitle || '无标题',
          content: this.editContent,
          lastEditTime: timeStr
        };
        this.noteList = [newNote, ...this.noteList];
      }
      this.isEditing = false;
      promptAction.showToast({ message: '保存成功' });
    } catch (err) {
      console.error('saveNote failed: ' + JSON.stringify(err));
    }
  }

  /** 开始流转 - 搜索可用设备 */
  private startTransfer(): void {
    this.isSearching = true;
    this.showDeviceList = true;

    // 模拟搜索设备
    setTimeout(() => {
      this.isSearching = false;
      this.availableDevices = ['黎姿的平板', '黎姿的MatePad'];
    }, 2000);
  }

  /**  确认流转 */
  private confirmTransfer(): void {
    this.showTransferConfirm = false;
    try {
      promptAction.showToast({
        message: `正在流转到 ${this.selectedDevice}...`
      });

      // 模拟流转过程
      setTimeout(() => {
        try {
          promptAction.showToast({
            message: `笔记已成功流转到 ${this.selectedDevice}`
          });
        } catch (err) {
          console.error('showToast failed: ' + JSON.stringify(err));
        }
      }, 2000);
    } catch (err) {
      console.error('confirmTransfer failed: ' + JSON.stringify(err));
    }
  }
}