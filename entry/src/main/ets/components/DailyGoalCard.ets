import { Constants } from '../model/Constants';

/** 今日学习目标卡片：已专注分钟数 / 目标分钟数 + 进度条 + 鼓励文案 */
@Component
export struct DailyGoalCard {
  todayFocusMinutes: number = 0;
  dailyGoalMinutes: number = 120;
  // 已计算好的进度百分比（0~100），由父页面统一计算后传入
  dailyProgressValue: number = 0;

  build() {
    Column() {
      Row() {
        Text('🎯 今日学习目标')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT)
        Blank()
        Text(`${this.todayFocusMinutes}/${this.dailyGoalMinutes}分钟`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_SUB)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(10)
          .backgroundColor('#EEEEEE')
          .borderRadius(5)
        Row()
          .width(`${this.dailyProgressValue}%`)
          .height(10)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .borderRadius(5)
      }
      .width('100%')
      .margin({ top: 10 })

      Text(this.dailyProgressValue >= 100 ? '🎉 今日目标已达成！太棒了！' : `已完成 ${this.dailyProgressValue}%，继续加油！`)
        .fontSize(13)
        .fontColor(this.dailyProgressValue >= 100 ? Constants.COLOR_SUCCESS : Constants.COLOR_PRIMARY)
        .margin({ top: 8 })
    }
    .width('90%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .margin({ top: 20 })
  }
}
