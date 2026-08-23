@Entry
@Component
struct FocusTimercardCard {
  /*
   * 卡片数据，由 FormExtAbility 通过 formBindingData 传入
   */
  @LocalStorageProp('title') title: string = '专注计时';
  @LocalStorageProp('focusTime') focusTime: string = '25:00';
  @LocalStorageProp('taskInfo') taskInfo: string = '今日待学：高等数学';
  @LocalStorageProp('todayMinutes') todayMinutes: string = '0分钟';

  readonly actionType: string = 'router';
  readonly abilityName: string = 'EntryAbility';
  readonly message: string = 'openFocusTimer';

  build() {
    Column() {
      // 标题
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 12, top: 8, bottom: 2 })

      // 倒计时
      Text(this.focusTime)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4A90D9')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 4 })

      // 今日任务
      Text(this.taskInfo)
        .fontSize(11)
        .fontColor('#666666')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 12, right: 12, top: 4 })

      // 今日专注时长
      Text(`今日专注：${this.todayMinutes}`)
        .fontSize(11)
        .fontColor('#888888')
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F7FA')
    .onClick(() => {
      // 点击卡片打开 App
      postCardAction(this, {
        action: this.actionType,
        abilityName: this.abilityName,
        params: {
          message: this.message
        }
      });
    })
  }
}