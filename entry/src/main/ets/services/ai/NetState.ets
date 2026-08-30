// services/ai/NetState.ets
// 网络可达性检测：判断当前是否存在默认可用网络（是否联网）。
// 属于设备相关能力，单独薄薄封装一层，便于编排服务调用，也便于以后替换实现。

import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'NetState';

export class NetState {
  /**
   * 是否联网。检测本身若抛错（权限/服务异常），保守按「离线」处理，
   * 这样编排层会直接走本地规则版，绝不会因为检测失败而卡住。
   */
  static async isOnline(): Promise<boolean> {
    try {
      const online: boolean = await connection.hasDefaultNet();
      return online;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '网络检测失败，按离线处理: ' + JSON.stringify(err));
      return false;
    }
  }
}
