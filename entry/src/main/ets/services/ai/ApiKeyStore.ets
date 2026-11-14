// services/ai/ApiKeyStore.ets
// 管理 DeepSeek API Key、模型名与 AI 开关的本地持久化。
//
// 安全说明（面试可讲）：
// 1) Key 绝不硬编码进代码、绝不随仓库提交，只存在本应用沙箱的 preferences 里，其他 App 无法读取；
// 2) 当前 SDK 未提供 encryptedPreferences，先用沙箱 preferences 落地（个人本地使用足够），
//    后续可无缝升级为 HUKS 密钥加密后再存储，对外方法保持不变；
// 3) 内存里只在需要发请求时读取，不打日志、不分享。

import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConfig } from './AiConfig';

const DOMAIN: number = 0x0001;
const TAG: string = 'ApiKeyStore';

export class ApiKeyStore {
  private static instance: ApiKeyStore | null = null;
  private context: Context | null = null;
  // 内存缓存：启动后读一次，避免每次生成都走异步 IO；为空表示尚未加载或未配置
  private cachedApiKey: string = '';
  private cachedEnabled: boolean = false;
  private cachedModel: string = AiConfig.DEFAULT_MODEL;
  // Queen（通义千问）的 Key 与模型，和 DeepSeek 分开存，画像洞察首选
  private cachedQueenApiKey: string = '';
  private cachedQueenModel: string = AiConfig.QUEEN_DEFAULT_MODEL;
  private loaded: boolean = false;

  private constructor() {
  }

  public static getInstance(): ApiKeyStore {
    if (ApiKeyStore.instance === null) {
      ApiKeyStore.instance = new ApiKeyStore();
    }
    return ApiKeyStore.instance;
  }

  public init(context: Context): void {
    this.context = context;
  }

  private async getPrefs(): Promise<preferences.Preferences | null> {
    if (this.context === null) {
      return null;
    }
    try {
      const prefs = await preferences.getPreferences(this.context, AiConfig.PREFS_NAME);
      return prefs;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '打开设置存储失败: ' + JSON.stringify(err));
      return null;
    }
  }

  /** 启动时调用一次，把配置载入内存缓存 */
  public async load(): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    this.cachedApiKey = (await prefs.get(AiConfig.KEY_API_KEY, '')) as string;
    this.cachedEnabled = (await prefs.get(AiConfig.KEY_LLM_ENABLED, false)) as boolean;
    this.cachedModel = (await prefs.get(AiConfig.KEY_MODEL, AiConfig.DEFAULT_MODEL)) as string;
    this.cachedQueenApiKey = (await prefs.get(AiConfig.KEY_QUEEN_API_KEY, '')) as string;
    this.cachedQueenModel =
      (await prefs.get(AiConfig.KEY_QUEEN_MODEL, AiConfig.QUEEN_DEFAULT_MODEL)) as string;
    this.loaded = true;
  }

  public async saveApiKey(apiKey: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(AiConfig.KEY_API_KEY, apiKey.trim());
    await prefs.flush();
    this.cachedApiKey = apiKey.trim();
  }

  public async clearApiKey(): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.delete(AiConfig.KEY_API_KEY);
    await prefs.flush();
    this.cachedApiKey = '';
  }

  public async setLlmEnabled(enabled: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(AiConfig.KEY_LLM_ENABLED, enabled);
    await prefs.flush();
    this.cachedEnabled = enabled;
  }

  public async setModel(model: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(AiConfig.KEY_MODEL, model);
    await prefs.flush();
    this.cachedModel = model;
  }

  /** 保存 Queen 的 API Key（与 DeepSeek 的 Key 分开） */
  public async saveQueenApiKey(apiKey: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(AiConfig.KEY_QUEEN_API_KEY, apiKey.trim());
    await prefs.flush();
    this.cachedQueenApiKey = apiKey.trim();
  }

  /** 设置 Queen 模型名 */
  public async setQueenModel(model: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(AiConfig.KEY_QUEEN_MODEL, model);
    await prefs.flush();
    this.cachedQueenModel = model;
  }

  // —— 同步读取（load 之后可用，供 UI 与降级决策即时判断）——
  public getApiKeySync(): string {
    return this.cachedApiKey;
  }

  public hasApiKeySync(): boolean {
    return this.cachedApiKey.length > 0;
  }

  public isEnabledSync(): boolean {
    return this.cachedEnabled;
  }

  public getModelSync(): string {
    return this.cachedModel.length > 0 ? this.cachedModel : AiConfig.DEFAULT_MODEL;
  }

  // —— Queen 同步读取（画像洞察编排使用）——
  public getQueenApiKeySync(): string {
    return this.cachedQueenApiKey;
  }

  public hasQueenApiKeySync(): boolean {
    return this.cachedQueenApiKey.length > 0;
  }

  public getQueenModelSync(): string {
    return this.cachedQueenModel.length > 0
      ? this.cachedQueenModel : AiConfig.QUEEN_DEFAULT_MODEL;
  }

  public isLoaded(): boolean {
    return this.loaded;
  }
}
