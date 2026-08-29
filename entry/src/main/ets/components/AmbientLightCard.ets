import { Constants } from '../model/Constants';

/** 环境光线展示卡片：低于暗光阈值时提示护眼；光线数值由父页面传感器采集后传入 */
@Component
export struct AmbientLightCard {
  lightValue: number = 0;

  build() {
    Row() {
      Text(this.lightValue < Constants.DARK_LIGHT_THRESHOLD ? '🌙' : '☀️')
        .fontSize(22)
      Column() {
        Text('环境光线')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT)
        Text(`${Math.round(this.lightValue)} lux${this.lightValue < Constants.DARK_LIGHT_THRESHOLD ? ' (偏暗，注意护眼)' : ''}`)
          .fontSize(12)
          .fontColor(this.lightValue < Constants.DARK_LIGHT_THRESHOLD ? '#FF6B35' : Constants.COLOR_TEXT_SUB)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('90%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .margin({ top: 12 })
  }
}
