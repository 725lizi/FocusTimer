import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { distributedDataObject } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import window from '@ohos.window';

import { DatabaseHelper } from '../common/DatabaseHelper';
import { ContinuationManager } from '../common/ContinuationManager';
import { FocusSessionStore } from '../common/FocusSessionStore';
import { ApiKeyStore } from '../services/ai/ApiKeyStore';
import { EmbeddingKeyStore } from '../services/rag/EmbeddingKeyStore';
import { RagRuntime } from '../services/rag/RagRuntime';

const DOMAIN = 0x0001;
const TAG = "FocusTimer";

// ============ 数据模型 ============

/** 专注计时数据模型 - 用于分布式同步 */
export class FocusData {
  currentSecond: number = 1500;
  totalSecond: number = 1500;
  isRunning: boolean = false;
  noteText: string = "";
  focusMode: boolean = false;
}

/** 笔记数据模型 */
export class NoteData {
  id: string = "";
  title: string = "";
  content: string = "";
  lastEditTime: number = 0;
}

// ============ 全局分布式对象 ============
let globalFocusObj: distributedDataObject.DataObject | null = null;
let globalNoteObj: distributedDataObject.DataObject | null = null;

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, "EntryAbility onCreate");

    // 等待本地数据库初始化完成，避免后续插入返回 -1
    await DatabaseHelper.getInstance().init(this.context);

    // 初始化跨设备接续管理器（从 Preferences 恢复未完成的计时状态）
    ContinuationManager.getInstance().init(this.context);
    // 初始化专注记录仓库（统一专注会话读写入口）
    FocusSessionStore.getInstance().init(this.context);

    // 初始化 AI Key 存储（应用沙箱）；异步载入已保存的 Key/开关，不阻塞启动，失败内部已兜底
    ApiKeyStore.getInstance().init(this.context);
    ApiKeyStore.getInstance().load().catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, 'AI 设置加载失败: ' + JSON.stringify(err));
    });

    // 初始化 RAG 向量化 Key 存储，并把已持久化的向量块加载回内存（重启后立即可检索）
    EmbeddingKeyStore.getInstance().init(this.context);
    EmbeddingKeyStore.getInstance().load().catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, '向量化设置加载失败: ' + JSON.stringify(err));
    });
    RagRuntime.getInstance().hydrate().then((count: number) => {
      hilog.info(DOMAIN, TAG, `RAG 已恢复 ${count} 个向量块`);
    }).catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, 'RAG 向量恢复失败: ' + JSON.stringify(err));
    });

    this.initDistributedFocus();
    this.initDistributedNote();
  }

  /** 初始化专注计时分布式数据对象 */
  private initDistributedFocus(): void {
    try {
      globalFocusObj = distributedDataObject.create(this.context, new FocusData());
      hilog.info(DOMAIN, TAG, "分布式专注对象创建成功");
    } catch (err) {
      hilog.error(DOMAIN, TAG, "分布式专注对象创建失败");
    }
  }

  /** 初始化笔记分布式数据对象 */
  private initDistributedNote(): void {
    try {
      globalNoteObj = distributedDataObject.create(this.context, new NoteData());
      hilog.info(DOMAIN, TAG, "分布式笔记对象创建成功");
    } catch (err) {
      hilog.error(DOMAIN, TAG, "分布式笔记对象创建失败");
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent("pages/Index", (err) => {
      if (err) {
        hilog.error(DOMAIN, TAG, "页面加载失败: " + JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, "页面加载成功");
    });
  }

  onDestroy(): void {
    if (globalFocusObj) {
      globalFocusObj = null;
    }
    if (globalNoteObj) {
      globalNoteObj = null;
    }
    hilog.info(DOMAIN, TAG, "EntryAbility 销毁完成");
  }
}
