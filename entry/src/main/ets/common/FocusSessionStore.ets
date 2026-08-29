import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StudySession } from '../services/AIAnalysisService';
import { ContinuationManager } from './ContinuationManager';

const DOMAIN = 0x0001;
const TAG = 'FocusSessionStore';
// 轻量专注历史所在的 preferences 文件名与键（与历史实现保持一致，本阶段不改变数据走向）
const SESSION_PREFS = 'study_data';
const SESSIONS_KEY = 'sessions';

/**
 * 专注记录仓库（Repository 门面）
 *
 * 统一「专注会话」的读写入口，收拢原先散落在 Index / Statistics 中对
 * preferences 的直读直写，以及经 ContinuationManager 落关系库的写入。
 *
 * 边界（本阶段只封装、不迁移）：
 *  - 轻量历史 StudySession[] 仍以 JSON 存在 preferences 的 study_data/sessions；
 *  - 结构化记录仍由 ContinuationManager 写入关系库 TABLE_STUDY_SESSION；
 *  - 接续状态(continuation_session)、桌面卡片(focusUserPrefs) 各有专属职责，不在此处收拢。
 *
 * 页面/服务以后只依赖本类，后续若把双存储合并为单一数据源，只需改本类内部。
 */
export class FocusSessionStore {
  private static instance: FocusSessionStore | null = null;
  private context: Context | null = null;

  private constructor() {
  }

  public static getInstance(): FocusSessionStore {
    if (FocusSessionStore.instance === null) {
      FocusSessionStore.instance = new FocusSessionStore();
    }
    return FocusSessionStore.instance;
  }

  public init(context: Context): void {
    this.context = context;
  }

  /** 读取全部专注会话（保持存储原顺序）；异常或无数据时返回空数组 */
  public async getAllSessions(): Promise<StudySession[]> {
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      const raw = await prefs.get(SESSIONS_KEY, '[]') as string;
      return JSON.parse(raw) as StudySession[];
    } catch (err) {
      hilog.error(DOMAIN, TAG, '读取专注会话失败: ' + JSON.stringify(err));
      return [];
    }
  }

  /** 追加一条专注会话（读-改-写，与历史实现行为一致） */
  public async appendSession(session: StudySession): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      const sessions = await this.getAllSessions();
      sessions.push(session);
      await prefs.put(SESSIONS_KEY, JSON.stringify(sessions));
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '保存专注会话失败: ' + JSON.stringify(err));
    }
  }

  /** 读取今日（本地零点起）的专注会话 */
  public async getTodaySessions(): Promise<StudySession[]> {
    const all = await this.getAllSessions();
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    return all.filter((item: StudySession) => item.startTime >= dayStart.getTime());
  }

  /** 写入一条结构化专注记录到关系库（委托 ContinuationManager，保持原走向） */
  public insertStudyRecord(
    taskName: string,
    startTime: number,
    endTime: number,
    durationMinutes: number,
    subjectTagId: string
  ): Promise<number> {
    return ContinuationManager.getInstance().saveStudySessionToDb(
      taskName, startTime, endTime, durationMinutes, subjectTagId
    );
  }

  /** 今日累计专注分钟数（关系库口径，委托 ContinuationManager） */
  public getTodayTotalMinutes(): Promise<number> {
    return ContinuationManager.getInstance().loadTodayTotalMinutes();
  }
}
