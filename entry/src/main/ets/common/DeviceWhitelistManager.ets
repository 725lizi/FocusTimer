import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';
import { DatabaseHelper } from './DatabaseHelper';

const DOMAIN = 0x0001;
const TAG = "DeviceWhitelistManager";

/** 设备信息接口 */
interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  deviceType: string;
  isTrusted: boolean;
  firstConnectedAt: number;
  lastConnectedAt: number;
}

/**
 * 设备白名单管理器
 * 管理信任设备列表
 */
export class DeviceWhitelistManager {
  private static instance: DeviceWhitelistManager | null = null;

  private constructor() {
  }

  public static getInstance(): DeviceWhitelistManager {
    if (DeviceWhitelistManager.instance === null) {
      DeviceWhitelistManager.instance = new DeviceWhitelistManager();
    }
    return DeviceWhitelistManager.instance;
  }

  /**
   * 校验设备 ID 是否合法（非空字符串）
   * 对应 addDevice / removeDevice 中的空 ID 校验逻辑
   */
  public static isValidDeviceId(deviceId: string): boolean {
    return deviceId.length > 0;
  }

  /**
   * 添加设备到白名单
   */
  public async addDevice(deviceId: string, deviceName: string, deviceType: string = 'unknown'): Promise<boolean> {
    try {
      if (!DeviceWhitelistManager.isValidDeviceId(deviceId)) {
        return false;
      }
      const db = DatabaseHelper.getInstance();
      const values: relationalStore.ValuesBucket = {
        device_id: deviceId,
        device_name: deviceName,
        device_type: deviceType,
        is_trusted: 1,
        first_connected_at: Date.now(),
        last_connected_at: Date.now()
      };
      const result = await db.insert(Constants.TABLE_DEVICE_WHITELIST, values);
      hilog.info(DOMAIN, TAG, '添加设备到白名单: %{public}s', deviceName);
      return result > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '添加设备失败');
      return false;
    }
  }

  /**
   * 从白名单移除设备
   */
  public async removeDevice(deviceId: string): Promise<boolean> {
    try {
      if (!DeviceWhitelistManager.isValidDeviceId(deviceId)) {
        return false;
      }
      const db = DatabaseHelper.getInstance();
      const result = await db.delete(Constants.TABLE_DEVICE_WHITELIST, 'device_id = ?', [deviceId]);
      hilog.info(DOMAIN, TAG, '移除设备: %{public}s', deviceId);
      return result > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '移除设备失败');
      return false;
    }
  }

  /**
   * 获取白名单设备列表
   */
  public async getWhitelistDevices(): Promise<DeviceInfo[]> {
    try {
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_DEVICE_WHITELIST, '', [], 'last_connected_at');
      const devices: DeviceInfo[] = [];
      if (resultSet) {
        while (resultSet.goToNextRow()) {
          const device: DeviceInfo = {
            deviceId: resultSet.getString(resultSet.getColumnIndex('device_id')),
            deviceName: resultSet.getString(resultSet.getColumnIndex('device_name')),
            deviceType: resultSet.getString(resultSet.getColumnIndex('device_type')),
            isTrusted: resultSet.getLong(resultSet.getColumnIndex('is_trusted')) === 1,
            firstConnectedAt: resultSet.getLong(resultSet.getColumnIndex('first_connected_at')),
            lastConnectedAt: resultSet.getLong(resultSet.getColumnIndex('last_connected_at'))
          };
          devices.push(device);
        }
        resultSet.close();
      }
      return devices;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取白名单设备列表失败');
      return [];
    }
  }

  /**
   * 更新设备最后连接时间
   */
  public async updateLastConnectedTime(deviceId: string): Promise<void> {
    try {
      const db = DatabaseHelper.getInstance();
      const updateValues: relationalStore.ValuesBucket = {
        last_connected_at: Date.now()
      };
      await db.update(
        Constants.TABLE_DEVICE_WHITELIST,
        updateValues,
        'device_id = ?',
        [deviceId]
      );
    } catch (err) {
      hilog.error(DOMAIN, TAG, '更新设备最后连接时间失败');
    }
  }
}