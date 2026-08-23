import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from './DatabaseHelper';
import { Constants } from '../model/Constants';

const DOMAIN = 0x0001;
const TAG = "CalendarSyncManager";

/** 学习时段数据接口 */
interface StudyTimelineItem {
  taskName: string;
  startTime: number;
  endTime: number;
  duration: number;
  subjectTagId: string;
}

/**
 * 日历数据互通管理器
 * 将学习记录同步至系统日历
 */
export class CalendarSyncManager {
  private static instance: CalendarSyncManager | null = null;

  private constructor() {
  }

  public static getInstance(): CalendarSyncManager {
    if (CalendarSyncManager.instance === null) {
      CalendarSyncManager.instance = new CalendarSyncManager();
    }
    return CalendarSyncManager.instance;
  }

  /**
   * 获取每日学习时段（用于日历展示）
   */
  public async getDailyStudyTimeline(date: Date): Promise<StudyTimelineItem[]> {
    try {
      const db = DatabaseHelper.getInstance();
      const dayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
      const dayEnd = dayStart + 24 * 60 * 60 * 1000;

      const resultSet = await db.query(
        Constants.TABLE_STUDY_SESSION,
        'start_time >= ? AND start_time < ?',
        [String(dayStart), String(dayEnd)],
        'start_time'
      );

      const timeline: StudyTimelineItem[] = [];
      if (resultSet) {
        while (resultSet.goToNextRow()) {
          const item: StudyTimelineItem = {
            taskName: resultSet.getString(resultSet.getColumnIndex('task_name')),
            startTime: resultSet.getLong(resultSet.getColumnIndex('start_time')),
            endTime: resultSet.getLong(resultSet.getColumnIndex('end_time')),
            duration: resultSet.getLong(resultSet.getColumnIndex('duration')),
            subjectTagId: resultSet.getString(resultSet.getColumnIndex('subject_tag_id'))
          };
          timeline.push(item);
        }
        resultSet.close();
      }
      return timeline;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取每日学习时段失败');
      return [];
    }
  }

  /**
   * 获取本周学习趋势（用于折线图）
   */
  public async getWeeklyTrend(): Promise<number[]> {
    try {
      const db = DatabaseHelper.getInstance();
      const weekStart = this.getWeekStartTime();

      const resultSet = await db.query(
        Constants.TABLE_STUDY_SESSION,
        'start_time >= ?',
        [String(weekStart)]
      );

      const dailyMinutes: number[] = [0, 0, 0, 0, 0, 0, 0];

      if (resultSet) {
        while (resultSet.goToNextRow()) {
          const startTime = resultSet.getLong(resultSet.getColumnIndex('start_time'));
          const duration = resultSet.getLong(resultSet.getColumnIndex('duration'));
          const date = new Date(startTime);
          const dayIndex = (date.getDay() || 7) - 1;
          dailyMinutes[dayIndex] += duration;
        }
        resultSet.close();
      }
      return dailyMinutes;
    } catch (err) {
      return [0, 0, 0, 0, 0, 0, 0];
    }
  }

  private getWeekStartTime(): number {
    const now = new Date();
    const dayOfWeek = now.getDay() || 7;
    const mondayOffset = (dayOfWeek - 1) * 24 * 60 * 60 * 1000;
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    weekStart.setTime(weekStart.getTime() - mondayOffset);
    weekStart.setHours(0, 0, 0, 0);
    return weekStart.getTime();
  }
}