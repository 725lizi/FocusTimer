import { relationalStore } from '@kit.ArkData';
import { distributedDataObject } from '@kit.ArkData';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';
import { StudySessionRecord } from '../model/SubjectTagModel';
import { DatabaseHelper } from './DatabaseHelper';

const DOMAIN = 0x0001;
const TAG = "ContinuationManager";
const SESSION_PREFS = 'continuation_session';
const SESSION_KEY = 'session_state';
const NOTE_DRAFT_KEY = 'note_draft_state';

// 定义会话状态接口
export interface SessionState {
  active: boolean;
  taskName: string;
  subjectTagId: string;
  remainSeconds: number;
  totalSeconds: number;
  todayTotalMinutes: number;
  isPaused: boolean;
  updatedAt: number;
}
// 笔记草稿状态接口
export interface NoteDraftState {
  title: string;
  content: string;
  subjectTagId: string;
  isEncrypted: boolean;
  updatedAt: number;
}
/**
 * 跨设备任务接续管理器
 */
export class ContinuationManager {
  private static instance: ContinuationManager | null = null;
  private sessionObj: distributedDataObject.DataObject | null = null;
  private context: Context | null = null;
  private sessionState: SessionState = {
    active: false,
    taskName: '',
    subjectTagId: '',
    remainSeconds: 0,
    totalSeconds: 0,
    todayTotalMinutes: 0,
    isPaused: false,
    updatedAt: 0
  };

  private constructor() {
  }

  public static getInstance(): ContinuationManager {
    if (ContinuationManager.instance === null) {
      ContinuationManager.instance = new ContinuationManager();
    }
    return ContinuationManager.instance;
  }
  private noteDraftState: NoteDraftState = {
    title: '',
    content: '',
    subjectTagId: '',
    isEncrypted: false,
    updatedAt: 0
  };

  // 初始化完成的 Promise，供外部等待状态加载完毕
  private initPromise: Promise<void> | null = null;

  public init(context: Context): void {
    this.context = context;
    this.initPromise = this.doInit();
  }

  private async doInit(): Promise<void> {
    try {
      this.sessionObj = distributedDataObject.create(this.context, this.sessionState);
      // 启动时从 Preferences 恢复持久化的会话状态（必须 await，否则时序错乱）
      await this.loadSessionStateFromPrefs();
      await this.loadNoteDraftFromPrefs();
      hilog.info(DOMAIN, TAG, '跨设备接续管理器初始化成功, active=' + this.sessionState.active);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '跨设备接续管理器初始化失败: ' + JSON.stringify(err));
    }
  }

  /** 等待初始化完成（状态从 Preferences 加载完毕） */
  public async ensureInitialized(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
  }

  // ====== 会话状态持久化 ======
  private async loadSessionStateFromPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      const saved = await prefs.get(SESSION_KEY, '') as string;
      if (saved) {
        this.sessionState = JSON.parse(saved) as SessionState;
        hilog.info(DOMAIN, TAG, '从 Preferences 恢复会话状态, active=' + this.sessionState.active);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '恢复会话状态失败: ' + JSON.stringify(err));
    }
  }

  private async saveSessionStateToPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      await prefs.put(SESSION_KEY, JSON.stringify(this.sessionState));
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '持久化会话状态失败: ' + JSON.stringify(err));
    }
  }

  private async clearSessionStateFromPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      await prefs.delete(SESSION_KEY);
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '清除会话状态失败: ' + JSON.stringify(err));
    }
  }

  // ====== 笔记草稿持久化 ======
  private async loadNoteDraftFromPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      const saved = await prefs.get(NOTE_DRAFT_KEY, '') as string;
      if (saved) {
        this.noteDraftState = JSON.parse(saved) as NoteDraftState;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '恢复笔记草稿失败: ' + JSON.stringify(err));
    }
  }

  private async saveNoteDraftToPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      await prefs.put(NOTE_DRAFT_KEY, JSON.stringify(this.noteDraftState));
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '持久化笔记草稿失败: ' + JSON.stringify(err));
    }
  }

  private async clearNoteDraftFromPrefs(): Promise<void> {
    if (!this.context) return;
    try {
      const prefs = await preferences.getPreferences(this.context, SESSION_PREFS);
      await prefs.delete(NOTE_DRAFT_KEY);
      await prefs.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '清除笔记草稿失败: ' + JSON.stringify(err));
    }
  }

  /**
   * 保存笔记草稿状态（跨设备接续）
   */
  public async saveNoteDraft(
    title: string,
    content: string,
    subjectTagId: string,
    isEncrypted: boolean
  ): Promise<void> {
    try {
      this.noteDraftState.title = title;
      this.noteDraftState.content = content;
      this.noteDraftState.subjectTagId = subjectTagId;
      this.noteDraftState.isEncrypted = isEncrypted;
      this.noteDraftState.updatedAt = Date.now();
      await this.saveNoteDraftToPrefs();
      hilog.info(DOMAIN, TAG, '笔记草稿已保存');
    } catch (err) {
      hilog.error(DOMAIN, TAG, '保存笔记草稿失败');
    }
  }

  /**
   * 获取笔记草稿状态
   */
  public getNoteDraft(): NoteDraftState {
    return this.noteDraftState;
  }

  /**
   * 清除笔记草稿状态
   */
  public async clearNoteDraft(): Promise<void> {
    try {
      this.noteDraftState.title = '';
      this.noteDraftState.content = '';
      this.noteDraftState.subjectTagId = '';
      this.noteDraftState.isEncrypted = false;
      this.noteDraftState.updatedAt = 0;
      await this.clearNoteDraftFromPrefs();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '清除笔记草稿失败');
    }
  }

  public async saveSessionState(
    isActive: boolean,
    taskName: string,
    subjectTagId: string,
    remainSeconds: number,
    totalSeconds: number,
    todayTotalMinutes: number,
    isPaused: boolean
  ): Promise<void> {
    try {
      this.sessionState.active = isActive;
      this.sessionState.taskName = taskName;
      this.sessionState.subjectTagId = subjectTagId;
      this.sessionState.remainSeconds = remainSeconds;
      this.sessionState.totalSeconds = totalSeconds;
      this.sessionState.todayTotalMinutes = todayTotalMinutes;
      this.sessionState.isPaused = isPaused;
      this.sessionState.updatedAt = Date.now();
      await this.saveSessionStateToPrefs();
      hilog.info(DOMAIN, TAG, '会话状态已保存并持久化, active=' + isActive + ', remain=' + remainSeconds);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '保存会话状态失败');
    }
  }

  public getSessionState(): SessionState {
    return this.sessionState;
  }

  public async clearSessionState(): Promise<void> {
    try {
      this.sessionState.active = false;
      this.sessionState.taskName = '';
      this.sessionState.subjectTagId = '';
      this.sessionState.remainSeconds = 0;
      this.sessionState.totalSeconds = 0;
      this.sessionState.isPaused = false;
      this.sessionState.updatedAt = Date.now();
      await this.clearSessionStateFromPrefs();
    } catch (err) {
      hilog.error(DOMAIN, TAG, '清除会话状态失败');
    }
  }

  public async saveStudySessionToDb(
    taskName: string,
    startTime: number,
    endTime: number,
    durationMinutes: number,
    subjectTagId: string
  ): Promise<number> {
    try {
      const db = DatabaseHelper.getInstance();
      const record = new StudySessionRecord();
      record.taskName = taskName;
      record.startTime = startTime;
      record.endTime = endTime;
      record.duration = durationMinutes;
      record.subjectTagId = subjectTagId;
      record.updatedAt = Date.now();

      const values: relationalStore.ValuesBucket = {
        task_name: record.taskName,
        start_time: record.startTime,
        end_time: record.endTime,
        duration: record.duration,
        subject_tag_id: record.subjectTagId,
        is_offline: record.isOffline ? 1 : 0,
        is_synced: record.isSynced ? 1 : 0,
        updated_at: record.updatedAt
      };

      const result = await db.insert(Constants.TABLE_STUDY_SESSION, values);
      hilog.info(DOMAIN, TAG, '学习会话已保存到数据库, id: %{public}d', result);
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '保存学习会话失败');
      return -1;
    }
  }

  public async loadTodayTotalMinutes(): Promise<number> {
    try {
      const db = DatabaseHelper.getInstance();
      const dayStart = new Date();
      dayStart.setHours(0, 0, 0, 0);

      const resultSet = await db.query(
        Constants.TABLE_STUDY_SESSION,
        'start_time >= ?',
        [String(dayStart.getTime())]
      );

      let totalMinutes = 0;
      if (resultSet) {
        while (resultSet.goToNextRow()) {
          totalMinutes += resultSet.getLong(resultSet.getColumnIndex('duration'));
        }
        resultSet.close();
      }
      return totalMinutes;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '加载今日总分钟数失败');
      return 0;
    }
  }
}
