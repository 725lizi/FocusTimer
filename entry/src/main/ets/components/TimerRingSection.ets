import { Constants } from '../model/Constants';

/**
 * 计时环区域：进度圆环 + 剩余时间 + 开始/暂停按钮 + 重置按钮。
 * 只负责展示与把用户操作通过回调上抛，本身不持有计时状态。
 */
@Component
export struct TimerRingSection {
  // 当前剩余秒数 / 总秒数 / 是否运行中，均由父页面传入
  currentSecond: number = 0;
  totalSecond: number = 0;
  isRunning: boolean = false;
  // 开始或暂停、重置两个动作的回调
  onToggle: () => void = () => {};
  onReset: () => void = () => {};

  // 圆环进度（0~1）：已过时长占总时长的比例
  private get progress(): number {
    if (this.totalSecond === 0) {
      return 0;
    }
    return 1 - this.currentSecond / this.totalSecond;
  }

  // 剩余时间的 mm:ss 展示文本
  private get timeDisplay(): string {
    const min = Math.floor(this.currentSecond / 60);
    const sec = this.currentSecond % 60;
    return `${min < 10 ? '0' + min : min}:${sec < 10 ? '0' + sec : sec}`;
  }

  build() {
    Column() {
      Stack() {
        Circle()
          .width(240)
          .height(240)
          .fill(Color.White)
          .shadow({ radius: 20, color: 'rgba(74,144,217,0.15)', offsetX: 0, offsetY: 4 })
        Circle()
          .width(220)
          .height(220)
          .fill(Color.White)
          .stroke(this.isRunning ? Constants.COLOR_PRIMARY : Constants.COLOR_ACCENT)
          .strokeWidth(8)
          .strokeDashArray([this.progress * 690, 690])
        Column() {
          Text(this.timeDisplay)
            .fontSize(52)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT)
            .fontFamily('monospace')
          Text(this.isRunning ? '专注中...' : '准备就绪')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 8 })
        }
      }
      .margin({ top: 30 })

      Button(this.isRunning ? '暂停' : '开始专注')
        .width(180)
        .height(50)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.isRunning ? Constants.COLOR_ACCENT : Constants.COLOR_PRIMARY)
        .fontColor(Color.White)
        .borderRadius(25)
        .margin({ top: 40 })
        .onClick(() => {
          this.onToggle();
        })

      if (!this.isRunning && this.currentSecond !== this.totalSecond) {
        Button('重置')
          .width(120)
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .borderRadius(20)
          .border({ width: 1, color: Constants.COLOR_TEXT_SUB })
          .margin({ top: 16 })
          .onClick(() => {
            this.onReset();
          })
      }
    }
    .width('100%')
    .padding(20)
  }
}
