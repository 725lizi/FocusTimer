import { Constants } from '../model/Constants';

/** 专注时长档位选择器；计时运行中禁用切换，点击档位经回调把下标上抛父页面 */
@Component
export struct DurationSelector {
  selectedIndex: number = Constants.DEFAULT_INDEX;
  // 是否禁用（计时运行中不允许切换档位）
  disabled: boolean = false;
  onSelect: (index: number) => void = () => {};

  build() {
    Column() {
      Text('选择时长')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT)
        .margin({ bottom: 12 })
      Row({ space: 10 }) {
        ForEach(Constants.PRESET_LABELS, (label: string, index: number) => {
          Text(label)
            .fontSize(13)
            .fontColor(this.selectedIndex === index ? Color.White : Constants.COLOR_PRIMARY)
            .backgroundColor(this.selectedIndex === index ? Constants.COLOR_PRIMARY : Color.White)
            .borderRadius(16)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .border({ width: 1, color: Constants.COLOR_PRIMARY })
            .onClick(() => {
              if (!this.disabled) {
                this.onSelect(index);
              }
            })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('90%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .margin({ top: 20 })
  }
}
