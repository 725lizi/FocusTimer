import { Constants } from '../model/Constants';

/** 首页顶部标题栏：标题 +「流转」按钮，点击跳转由父页面通过回调处理 */
@Component
export struct IndexHeader {
  // 点击「流转」按钮的事件回调，由父页面注入
  onTransfer: () => void = () => {};

  build() {
    Row() {
      Text('专注计时')
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
          this.onTransfer();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 15, bottom: 10 })
  }
}
