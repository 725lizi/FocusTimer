import { Constants } from '../model/Constants';

/** 今日数据卡片：今日专注次数与累计分钟数 */
@Component
export struct TodayStatsCard {
  count: number = 0;
  minutes: number = 0;

  build() {
    Row() {
      Column() {
        Text(`${this.count}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_PRIMARY)
        Text('今日次数')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .margin({ top: 4 })
      }
      .layoutWeight(1)

      Divider().vertical(true).height(30)

      Column() {
        Text(`${this.minutes}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_ACCENT)
        Text('今日分钟')
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
    }
    .width('90%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .margin({ bottom: 10 })
  }
}
