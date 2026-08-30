// services/ai/AiConfig.ets
// AI 周报相关的集中配置（端点、默认模型、超时、本地存储键名）。
// 注意：API Key 绝不写死在这里，它只保存在应用沙箱 preferences 中，由用户在设置页填写。

export class AiConfig {
  /** DeepSeek 的 OpenAI 兼容对话端点 */
  static readonly BASE_URL: string = 'https://api.deepseek.com';
  static readonly CHAT_PATH: string = '/chat/completions';
  /** 默认模型，可在设置里改 */
  static readonly DEFAULT_MODEL: string = 'deepseek-chat';
  /** 建连超时（毫秒） */
  static readonly CONNECT_TIMEOUT_MS: number = 15000;
  /** 读取（等待首字节/整段流式）超时（毫秒），流式生成较慢，给足时间 */
  static readonly READ_TIMEOUT_MS: number = 60000;
  /** 保存 Key 与开关的 preferences 文件名 */
  static readonly PREFS_NAME: string = 'ai_settings';
  static readonly KEY_API_KEY: string = 'deepseek_api_key';
  static readonly KEY_MODEL: string = 'deepseek_model';
  static readonly KEY_LLM_ENABLED: string = 'llm_enabled';
}
