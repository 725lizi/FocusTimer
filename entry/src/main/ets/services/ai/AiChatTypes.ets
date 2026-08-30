// services/ai/AiChatTypes.ets
// 大模型对话相关的纯类型定义（DeepSeek 使用 OpenAI 兼容的 Chat Completions 协议）。
// 这里只定义结构，不写任何网络/UI 逻辑，便于纯逻辑层离线单测。

/** 对话角色：system 定调、user 是用户输入、assistant 是模型回复 */
export type ChatRole = 'system' | 'user' | 'assistant';

/** 一条对话消息 */
export interface ChatMessage {
  role: ChatRole;
  content: string;
}

/** 发给大模型的请求体（OpenAI 兼容） */
export interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  stream: boolean;
  temperature: number;
  max_tokens: number;
}

/** 流式返回中单个 chunk 里 delta 的结构（只取我们需要的字段） */
export interface StreamDelta {
  content?: string;
}

/** 流式返回中 choices 数组单项的结构 */
export interface StreamChoice {
  delta: StreamDelta;
  finish_reason: string | null;
}

/** SSE 每一行 data: 对应的 JSON 结构（只声明用到的字段） */
export interface StreamChunk {
  choices: StreamChoice[];
}

/** 报告来源：大模型 / 本地规则兜底 */
export type ReportSource = 'llm' | 'rule';

/** 报告生成过程状态机 */
export type ReportStatus =
  'idle'        // 未开始
  | 'requesting' // 已发起请求，等待首字节
  | 'streaming'  // 正在流式接收
  | 'fallback'   // 已降级到规则版
  | 'succeeded'  // 成功结束
  | 'failed';    // 彻底失败（规则版也没产出时）

/** 供「是否走大模型」决策使用的环境条件 */
export interface ReportStrategyInput {
  /** 用户是否在设置里开启了 AI 周报 */
  llmEnabled: boolean;
  /** 当前是否有网络 */
  online: boolean;
  /** 是否已配置可用的 API Key */
  hasApiKey: boolean;
}
