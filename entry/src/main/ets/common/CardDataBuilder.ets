// common/CardDataBuilder.ets
// 桌面卡片展示数据的纯逻辑组装器：只负责把原始数值格式化成卡片需要的文本，
// 不依赖 Context、不读写 preferences，便于离线单元测试。

// 卡片最终展示的数据结构
export interface CardData {
  title: string;
  focusTime: string;
  taskInfo: string;
  todayMinutes: string;
}

/**
 * 卡片数据构建器（纯函数集合）
 *
 * 从 EntryFormAbility 中抽出的可测部分：分钟数格式化、科目文案、今日时长文案与整体组装。
 * 同样输入必得同样输出，不触碰系统能力，可直接在本地单元测试中验证。
 */
export class CardDataBuilder {
  /**
   * 把上次专注分钟数格式化为卡片上的 mm:00 文本（向下取整，个位数补 0）
   */
  static formatFocusTime(lastDurationMinutes: number): string {
    const min: number = Math.floor(lastDurationMinutes);
    return `${min < 10 ? '0' + min : min}:00`;
  }

  /**
   * 生成「今日待学：xxx」文案，科目为空时回退为「未选择」
   */
  static formatTaskInfo(subject: string): string {
    return subject ? `今日待学：${subject}` : '今日待学：未选择';
  }

  /**
   * 生成「N分钟」的今日累计时长文案
   */
  static formatTodayMinutes(todayMinutes: number): string {
    return `${todayMinutes}分钟`;
  }

  /**
   * 组装一张完整卡片所需的展示数据（纯组装，不访问存储）
   * @param todayMinutes 今日累计分钟数
   * @param lastDurationMinutes 上次专注分钟数
   * @param subject 当前科目名称（可为空字符串）
   */
  static build(todayMinutes: number, lastDurationMinutes: number, subject: string): CardData {
    const data: CardData = {
      title: '专注计时',
      focusTime: CardDataBuilder.formatFocusTime(lastDurationMinutes),
      taskInfo: CardDataBuilder.formatTaskInfo(subject),
      todayMinutes: CardDataBuilder.formatTodayMinutes(todayMinutes)
    };
    return data;
  }
}
