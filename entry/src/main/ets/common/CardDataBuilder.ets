// common/CardDataBuilder.ets
// 桌面卡片展示数据的纯逻辑组装器：只负责把原始数值格式化成卡片需要的文本，
// 不依赖 Context、不读写 preferences，便于离线单元测试。

// 卡片最终展示的数据结构
export interface CardData {
  title: string;
  focusTime: string;
  taskInfo: string;
  todayMinutes: string;
  // 专注状态（running/paused/done/idle）与动态倒计时剩余毫秒（running 时 >0）
  cardStatus: string;
  remainMs: number;
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
  /**
   * 按「专注状态」组装卡片数据（事件驱动更新用）。
   * @param todayMinutes 今日累计分钟数（进行中不含本次，完成后含本次）
   * @param focusMinutes 大字号展示的分钟数：
   *                     running=本次目标时长、paused=本次已专注、done/idle=本次时长或 0
   * @param subject 当前科目名称（可为空字符串）
   * @param status 专注状态：running（专注中）/ paused（已暂停）/ done（已完成）/ idle（空闲）
   */
  static buildWith(todayMinutes: number, focusMinutes: number, subject: string, status: string,
    remainMs: number = 0): CardData {
    const subj: string = subject || '';
    let title: string = '专注计时';
    let taskInfo: string = CardDataBuilder.formatTaskInfo(subj);

    if (status === 'running') {
      title = '专注中';
      taskInfo = subj ? `正在专注：${subj}` : '正在专注';
    } else if (status === 'paused') {
      title = '已暂停';
      taskInfo = subj ? `暂停于：${subj}` : '已暂停';
    } else {
      // done / idle：恢复默认标题与「今日待学」文案
      title = '专注计时';
      taskInfo = CardDataBuilder.formatTaskInfo(subj);
    }

    const data: CardData = {
      title: title,
      focusTime: CardDataBuilder.formatFocusTime(focusMinutes),
      taskInfo: taskInfo,
      todayMinutes: CardDataBuilder.formatTodayMinutes(todayMinutes),
      cardStatus: status,
      remainMs: remainMs
    };
    return data;
  }

  /**
   * 组装一张完整卡片所需的展示数据（空闲/默认状态，向后兼容）
   */
  static build(todayMinutes: number, lastDurationMinutes: number, subject: string): CardData {
    return CardDataBuilder.buildWith(todayMinutes, lastDurationMinutes, subject, 'idle', 0);
  }
}
