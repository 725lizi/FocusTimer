import { Constants } from '../model/Constants';

/** 离线模式顶部提示条：检测到离线时由父页面决定是否展示 */
@Component
export struct OfflineBanner {
  build() {
    Row() {
      Text('📡 离线模式 · 数据已本地保存，联网后自动同步')
        .fontSize(12)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Constants.COLOR_WARNING)
  }
}
