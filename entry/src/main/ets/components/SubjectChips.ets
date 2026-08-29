import { Constants } from '../model/Constants';
import { SubjectTagModel } from '../model/SubjectTagModel';

/** 科目标签横向滑动选择器；选中项由父页面通过 selectedId 控制，点击经回调上抛 */
@Component
export struct SubjectChips {
  tags: SubjectTagModel[] = [];
  selectedId: string = '';
  onSelect: (id: string) => void = () => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.tags, (tag: SubjectTagModel) => {
          Column() {
            Text(tag.icon).fontSize(18)
            Text(tag.name)
              .fontSize(10)
              .fontColor(this.selectedId === tag.id ? Color.White : Constants.COLOR_TEXT_SUB)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.selectedId === tag.id ? tag.color : Color.White)
          .borderRadius(16)
          .border({ width: 1, color: tag.color })
          .onClick(() => {
            this.onSelect(tag.id);
          })
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('90%')
    .margin({ top: 12 })
  }
}
