// services/rag/EmbeddingKeyStore.ets
// 向量化服务（embedding）的 Key 与模型本地持久化，和聊天用的 DeepSeek Key 分开存放：
// 因为 DeepSeek 不提供 embedding，向量化通常是另一家服务（如硅基流动），Key 不同。
// 安全策略同 ApiKeyStore：只存应用沙箱 preferences，不硬编码、不打日志、不随仓库提交。

import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RagConfig } from './RagConfig';

const DOMAIN: number = 0x0001;
const TAG: string = 'EmbeddingKeyStore';

export class EmbeddingKeyStore {
  private static instance: EmbeddingKeyStore | null = null;
  private context: Context | null = null;
  private cachedKey: string = '';
  private cachedModel: string = RagConfig.DEFAULT_EMBED_MODEL;
  private loaded: boolean = false;

  private constructor() {
  }

  public static getInstance(): EmbeddingKeyStore {
    if (EmbeddingKeyStore.instance === null) {
      EmbeddingKeyStore.instance = new EmbeddingKeyStore();
    }
    return EmbeddingKeyStore.instance;
  }

  public init(context: Context): void {
    this.context = context;
  }

  private async getPrefs(): Promise<preferences.Preferences | null> {
    if (this.context === null) {
      return null;
    }
    try {
      const prefs = await preferences.getPreferences(this.context, RagConfig.PREFS_NAME);
      return prefs;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '打开向量化设置存储失败: ' + JSON.stringify(err));
      return null;
    }
  }

  /** 启动时调用一次，载入内存缓存 */
  public async load(): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    this.cachedKey = (await prefs.get(RagConfig.KEY_EMBED_API_KEY, '')) as string;
    this.cachedModel = (await prefs.get(RagConfig.KEY_EMBED_MODEL, RagConfig.DEFAULT_EMBED_MODEL)) as string;
    this.loaded = true;
  }

  public async saveApiKey(apiKey: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(RagConfig.KEY_EMBED_API_KEY, apiKey.trim());
    await prefs.flush();
    this.cachedKey = apiKey.trim();
  }

  public async setModel(model: string): Promise<void> {
    const prefs = await this.getPrefs();
    if (prefs === null) {
      return;
    }
    await prefs.put(RagConfig.KEY_EMBED_MODEL, model);
    await prefs.flush();
    this.cachedModel = model;
  }

  public getApiKeySync(): string {
    return this.cachedKey;
  }

  public hasApiKeySync(): boolean {
    return this.cachedKey.length > 0;
  }

  public getModelSync(): string {
    return this.cachedModel.length > 0 ? this.cachedModel : RagConfig.DEFAULT_EMBED_MODEL;
  }

  public isLoaded(): boolean {
    return this.loaded;
  }
}
