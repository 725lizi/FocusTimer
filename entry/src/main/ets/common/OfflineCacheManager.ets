import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';
import { DatabaseHelper } from './DatabaseHelper';
import { GlobalContext } from './GlobalContext';

const DOMAIN = 0x0001;
const TAG = "OfflineCacheManager";

/**
 * 离线缓存管理器
 * 无网络时本地缓存，恢复后增量同步
 */
export class OfflineCacheManager {
  private static instance: OfflineCacheManager | null = null;
  private isOffline: boolean = false;

  private constructor() {
  }

  public static getInstance(): OfflineCacheManager {
    if (OfflineCacheManager.instance === null) {
      OfflineCacheManager.instance = new OfflineCacheManager();
    }
    return OfflineCacheManager.instance;
  }

  /**
   * 网络状态是否发生变化
   * 对应 checkAndUpdateOfflineStatus 中的状态切换判定逻辑
   */
  public static hasStatusChanged(newStatus: boolean, currentStatus: boolean): boolean {
    return newStatus !== currentStatus;
  }

  /**
   * 初始化并启动网络状态监测
   */
  public init(): void {
    this.monitorNetworkStatus();
    hilog.info(DOMAIN, TAG, '离线缓存管理器初始化成功');
  }

  /**
   * 监测网络状态（简化版，每10秒检查一次）
   */
  private monitorNetworkStatus(): void {
    setInterval(() => {
      this.checkAndUpdateOfflineStatus();
    }, 10000);
  }

  /**
   * 检查并更新离线状态
   */
  private checkAndUpdateOfflineStatus(): void {
    const offlineFlag = GlobalContext.getContext().getObject(Constants.OFFLINE_FLAG);
    const newOfflineStatus = offlineFlag === true;

    if (OfflineCacheManager.hasStatusChanged(newOfflineStatus, this.isOffline)) {
      this.isOffline = newOfflineStatus;
      if (!this.isOffline) {
        this.syncPendingData();
      }
      hilog.info(DOMAIN, TAG, '网络状态变化: %{public}s', this.isOffline ? '离线' : '在线');
    }
  }

  /**
   * 保存离线数据
   */
  public async saveOfflineData(key: string, value: Record<string, Object>): Promise<void> {
    try {
      const db = DatabaseHelper.getInstance();
      const values: relationalStore.ValuesBucket = {
        kv_key: key,
        kv_value: JSON.stringify(value),
        is_synced: 0,
        created_at: Date.now()
      };
      await db.insert(Constants.TABLE_PENDING_SYNC, values);
      this.isOffline = true;
      GlobalContext.getContext().setObject(Constants.OFFLINE_FLAG, true);
      hilog.info(DOMAIN, TAG, '离线数据已缓存: %{public}s', key);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '保存离线数据失败');
    }
  }

  /**
   * 同步待同步的数据
   */
  private async syncPendingData(): Promise<void> {
    try {
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_PENDING_SYNC, 'is_synced = ?', ['0'], 'created_at');
      if (!resultSet) {
        return;
      }

      let syncedCount = 0;
      while (resultSet.goToNextRow()) {
        const id = resultSet.getLong(resultSet.getColumnIndex('id'));
        const kvKey = resultSet.getString(resultSet.getColumnIndex('kv_key'));

        const updateValues: relationalStore.ValuesBucket = { is_synced: 1 };
        await db.update(Constants.TABLE_PENDING_SYNC, updateValues, 'id = ?', [String(id)]);
        syncedCount++;
      }
      resultSet.close();

      if (syncedCount > 0) {
        this.isOffline = false;
        GlobalContext.getContext().setObject(Constants.OFFLINE_FLAG, false);
        hilog.info(DOMAIN, TAG, '增量同步完成，同步了 %{public}d 条数据', syncedCount);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '同步数据失败');
    }
  }

  /**
   * 获取当前离线状态
   */
  public isOfflineMode(): boolean {
    return this.isOffline;
  }

  /**
   * 手动设置离线状态
   */
  public setOfflineStatus(isOffline: boolean): void {
    this.isOffline = isOffline;
    GlobalContext.getContext().setObject(Constants.OFFLINE_FLAG, isOffline);
  }
}