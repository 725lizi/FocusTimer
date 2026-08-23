import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = "DeviceManager";

/** 可用设备信息 */
export interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  deviceType: string; // 'phone' | 'tablet' | 'watch'
}

/**
 * 设备管理工具类
 * 负责设备发现、穿戴设备检测、流转管理
 */
export class DeviceManager {
  private static instance: DeviceManager | null = null;
  private deviceManager: distributedDeviceManager.DeviceManager | null = null;
  private availableDevices: DeviceInfo[] = [];

  private constructor() {}

  /** 获取单例 */
  static getInstance(): DeviceManager {
    if (!DeviceManager.instance) {
      DeviceManager.instance = new DeviceManager();
    }
    return DeviceManager.instance;
  }

  /**  初始化设备管理器 */
  init(bundleName: string): void {
    try {
      this.deviceManager = distributedDeviceManager.createDeviceManager(bundleName);
      hilog.info(DOMAIN, TAG, "设备管理器初始化成功");
    } catch (err) {
      hilog.error(DOMAIN, TAG, "设备管理器初始化失败");
    }
  }

  /** 搜索可用设备 */
  discoverDevices(): DeviceInfo[] {
    if (!this.deviceManager) {
      hilog.warn(DOMAIN, TAG, "设备管理器未初始化");
      return [];
    }

    try {
      const devices = this.deviceManager.getAvailableDeviceListSync();
      this.availableDevices = devices.map(device => ({
        deviceId: device.networkId ?? '',
        deviceName: device.deviceName ?? '未知设备',
        deviceType: this.parseDeviceType(device.deviceTypeId)
      }));
      hilog.info(DOMAIN, TAG, `发现 ${this.availableDevices.length} 个设备`);
      return this.availableDevices;
    } catch (err) {
      hilog.error(DOMAIN, TAG, "设备搜索失败");
      return [];
    }
  }

  /**  检查是否有穿戴设备连接 */
  hasWatchConnected(): boolean {
    return this.availableDevices.some(d => d.deviceType === 'watch');
  }

  /** 获取穿戴设备 */
  getWatchDevice(): DeviceInfo | undefined {
    return this.availableDevices.find(d => d.deviceType === 'watch');
  }

  /**  获取所有非穿戴设备（用于流转） */
  getTransferDevices(): DeviceInfo[] {
    return this.availableDevices.filter(d => d.deviceType !== 'watch');
  }

  /** 解析设备类型 */
  private parseDeviceType(typeId: number): string {
    switch (typeId) {
      case 0: return 'phone';
      case 1: return 'watch';
      case 2: return 'tablet';
      default: return 'phone';
    }
  }

  /**  释放资源 */
  destroy(): void {
    this.deviceManager = null;
    this.availableDevices = [];
    DeviceManager.instance = null;
  }
}