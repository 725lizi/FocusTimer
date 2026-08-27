/**
 * 桌面卡片数据构造（纯逻辑）
 *
 * 对应 Index.ets updateWidgetTodayMinutes 中桌面卡片绑定数据的构造语义：
 *  - title      ：卡片标题
 *  - focusTime  ：展示的计时时长（当前固定展示默认值）
 *  - taskInfo   ：今日待学科目提示
 *  - todayMinutes：今日累计专注分钟数（格式化文案）
 */
export interface WidgetCardData {
  title: string;
  focusTime: string;
  taskInfo: string;
  todayMinutes: string;
}

export class CardDataBuilder {
  static readonly CARD_TITLE: string = '专注计时';
  static readonly DEFAULT_FOCUS_TIME: string = '25:00';
  static readonly DEFAULT_TASK_INFO: string = '今日待学：高等数学';

  /**
   * 构造桌面卡片绑定数据
   * @param todayMinutes 今日累计专注分钟数
   */
  static build(todayMinutes: number): WidgetCardData {
    const data: WidgetCardData = {
      title: CardDataBuilder.CARD_TITLE,
      focusTime: CardDataBuilder.DEFAULT_FOCUS_TIME,
      taskInfo: CardDataBuilder.DEFAULT_TASK_INFO,
      todayMinutes: `${todayMinutes}分钟`
    };
    return data;
  }
}
