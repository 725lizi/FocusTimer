import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';

/**
 * 全局底部导航栏（4 个主页面共用）。
 * 用法：BottomNavBar({ active: 'timer' | 'notes' | 'stats' | 'report' })
 * 统一四个主页面的导航外观与跳转行为，避免同一段 UI 在各页面复制粘贴。
 */
@Component
export struct BottomNavBar {
  // 当前页面所属的导航项，由父页面传入；决定哪一项高亮
  @Prop active: string = 'timer';

  // 四个导航项的标识、文案与目标路由，下标一一对应
  private readonly tabKeys: string[] = ['timer', 'notes', 'stats', 'report'];
  private readonly tabLabels: string[] = ['计时', '笔记', '统计', '分析报告'];
  private readonly tabRoutes: string[] =
    [Constants.PAGE_INDEX, Constants.PAGE_NOTES, Constants.PAGE_STATS, Constants.PAGE_REPORT];

  private navigate(url: string): void {
    try {
      router.pushUrl({ url: url });
    } catch (err) {
      console.error('BottomNavBar pushUrl failed: ' + JSON.stringify(err));
    }
  }

  @Builder
  tabItem(key: string, label: string, route: string) {
    Column() {
      Circle({ width: 6, height: 6 })
        .fill(this.active === key ? Constants.COLOR_PRIMARY : Color.Transparent)
      Text(label)
        .fontSize(12)
        .fontColor(this.active === key ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SUB)
        .fontWeight(this.active === key ? FontWeight.Bold : FontWeight.Normal)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .onClick(() => {
      // 已在当前页时不重复跳转，避免页面栈无限增长
      if (this.active !== key) {
        this.navigate(route);
      }
    })
  }

  build() {
    Row() {
      ForEach(this.tabKeys, (key: string, index: number) => {
        this.tabItem(key, this.tabLabels[index], this.tabRoutes[index])
      }, (key: string) => key)
    }
    .width('100%')
    .height(60)
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
