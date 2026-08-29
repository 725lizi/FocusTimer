import { Constants } from '../model/Constants';

/** 专注免打扰模式开关行；开关状态由父页面持有，切换经回调上抛 */
@Component
export struct FocusModeToggle {
  isOn: boolean = false;
  onChange: (isOn: boolean) => void = () => {};

  build() {
    Row() {
      Text('专注免打扰模式')
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(Constants.COLOR_PRIMARY)
        .onChange((isOn: boolean) => {
          this.onChange(isOn);
        })
    }
    .width('90%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .margin({ top: 12 })
  }
}
