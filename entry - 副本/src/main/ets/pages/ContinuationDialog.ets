import { Constants } from '../model/Constants';

/**
 * 跨设备任务接续弹窗组件
 */
@CustomDialog
export struct ContinuationDialog {
  controller: CustomDialogController;
  taskName: string = '';
  remainSeconds: number = 0;
  subjectTagName: string = '';
  @State syncTimer: boolean = true;
  @State syncNotes: boolean = true;
  onConfirm: (() => void) | null = null;

  build() {
    Column({ space: 16 }) {
      Text('🔄 跨设备任务接续')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT)
        .margin({ top: 20 })

      Text(`检测到其他设备上有进行中的学习任务`)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .textAlign(TextAlign.Center)

      // 任务信息
      Column({ space: 8 }) {
        Text(`任务：${this.taskName || '专注学习'}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT)

        Text(`剩余时间：${this.formatTime(this.remainSeconds)}`)
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)

        if (this.subjectTagName) {
          Text(`科目：${this.subjectTagName}`)
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SUB)
        }
      }
      .width('90%')
      .padding(12)
      .backgroundColor(Constants.COLOR_BG)
      .borderRadius(10)
      .margin({ top: 4 })

      // 同步选项
      Column({ space: 12 }) {
        Row() {
          Text('同步当前计时任务')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT)
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.syncTimer })
            .selectedColor(Constants.COLOR_PRIMARY)
            .onChange((isOn: boolean) => {
              this.syncTimer = isOn;
            })
        }
        .width('100%')

        Row() {
          Text('同步笔记数据')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT)
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.syncNotes })
            .selectedColor(Constants.COLOR_PRIMARY)
            .onChange((isOn: boolean) => {
              this.syncNotes = isOn;
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(12)
      .margin({ top: 4 })

      // 按钮
      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Color.White)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(21)
          .border({ width: 1, color: '#E0E0E0' })
          .onClick(() => {
            this.controller.close();
          })

        Button('接续任务')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Color.White)
          .borderRadius(21)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm();
            }
            this.controller.close();
          })
      }
      .width('90%')
      .margin({ bottom: 20 })
    }
    .width('85%')
    .backgroundColor(Color.White)
    .borderRadius(20)
    .padding(16)
  }

  private formatTime(seconds: number): string {
    const min = Math.floor(seconds / 60);
    const sec = seconds % 60;
    return `${min < 10 ? '0' + min : min}:${sec < 10 ? '0' + sec : sec}`;
  }
}