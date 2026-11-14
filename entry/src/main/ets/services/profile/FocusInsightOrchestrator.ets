// services/profile/FocusInsightOrchestrator.ets
// 模型分工：设备相关薄编排层（依赖网络、Key 存储、流式客户端），由 Queen 负责多步推理与编排。
// 决策链（保证画像永远有产出，且来源诚实可追溯）：
//   1) 先跑确定性统计，并备好规则版洞察作为兜底；数据不足时直接返回提示，不调用 AI；
//   2) 读「AI 开关 / 网络 / 是否有可用 Key」，不满足就返回规则版（正常路径，不是出错）；
//   3) 满足则按 Queen → DeepSeek 顺序尝试，只调用配置了 Key 的端点；
//   4) AI 返回文本经解析、证据校验，只保留引用真实事实 id 的洞察；
//   5) 任一端点出错、解析失败或证据全非法，自动降级规则版；用户取消则不做收尾。
// 来源严格区分：llm=云端 AI 成功、rule=本地规则（含降级）、insufficient=数据不足。

import { StudySession } from '../LearningAnalysisService';
import { AiConfig } from '../ai/AiConfig';
import { ApiKeyStore } from '../ai/ApiKeyStore';
import { DeepSeekClient } from '../ai/DeepSeekClient';
import { NetState } from '../ai/NetState';
import { LlmErrorKind } from '../ai/ReportStrategy';
import {
  ChatCompletionRequest, ChatMessage, ReportSource, ReportStatus
} from '../ai/AiChatTypes';
import { FocusProfileStats } from './FocusProfileStats';
import { FocusInsightRules } from './FocusInsightRules';
import { FocusInsightPrompt } from './FocusInsightPrompt';
import { FocusInsightParser } from './FocusInsightParser';
import { FocusInsightValidator } from './FocusInsightValidator';
import {
  FocusInsight, FocusInsightBundle, FocusProfileStatsResult, ProfileWindow
} from './FocusProfileTypes';

/** 一个可用 AI 端点的完整调用信息 */
interface ProfileEndpoint {
  /** 端点名称（仅用于日志） */
  label: string;
  /** OpenAI 兼容根地址 */
  baseUrl: string;
  /** 模型名 */
  model: string;
  /** 该端点对应的 Key */
  apiKey: string;
}

/** 给界面的回调：状态变化 / 结束（最终洞察包） */
export interface FocusInsightCallbacks {
  onStatus: (status: ReportStatus, source: ReportSource, hint: string) => void;
  onDone: (bundle: FocusInsightBundle) => void;
}

export class FocusInsightOrchestrator {
  private activeClient: DeepSeekClient | null = null;
  // 用户是否已取消；取消后不再尝试后续端点、不做收尾
  private cancelled: boolean = false;

  /** 生成画像洞察。sessions 为全部专注记录，windowDays 为 7 或 30 */
  public async generate(sessions: StudySession[], windowDays: ProfileWindow,
    callbacks: FocusInsightCallbacks): Promise<void> {
    this.reset();
    const now: number = Date.now();

    // 1) 确定性统计 + 规则兜底（无论走不走 AI 都先备好）
    const result: FocusProfileStatsResult = FocusProfileStats.build(sessions, windowDays, now);
    const ruleBundle: FocusInsightBundle = FocusInsightRules.build(result, now);

    // 数据不足：直接返回 insufficient 提示，不调用 AI
    if (result.insufficientData) {
      callbacks.onStatus('succeeded', 'rule', ruleBundle.hint);
      callbacks.onDone(ruleBundle);
      return;
    }

    // 2) 环境条件与可用端点
    const store: ApiKeyStore = ApiKeyStore.getInstance();
    const online: boolean = await NetState.isOnline();
    const endpoints: ProfileEndpoint[] = FocusInsightOrchestrator.buildEndpoints(store);

    if (!store.isEnabledSync() || !online || endpoints.length === 0) {
      const hint: string = FocusInsightOrchestrator.ruleHint(store, online, endpoints.length);
      callbacks.onStatus('succeeded', 'rule', hint);
      callbacks.onDone(FocusInsightOrchestrator.withHint(ruleBundle, hint));
      return;
    }

    // 3) 按 Queen → DeepSeek 顺序尝试，成功即停
    callbacks.onStatus('requesting', 'llm', '');
    let llmInsights: FocusInsight[] | null = null;
    for (const ep of endpoints) {
      if (this.cancelled) {
        break;
      }
      try {
        llmInsights = await this.tryEndpoint(ep, result);
        break;
      } catch (err) {
        console.warn('画像洞察端点 ' + ep.label + ' 失败: ' + JSON.stringify(err));
        llmInsights = null;
      }
    }

    if (this.cancelled) {
      return;
    }

    if (llmInsights !== null && llmInsights.length > 0) {
      const bundle: FocusInsightBundle = {
        windowDays: windowDays,
        source: 'llm',
        insights: llmInsights,
        hint: '',
        generatedAt: now
      };
      callbacks.onStatus('succeeded', 'llm', '');
      callbacks.onDone(bundle);
      return;
    }

    // 4) 全部失败：降级规则版
    const hint: string = '云端 AI 暂不可用，已用本地规则生成';
    callbacks.onStatus('fallback', 'rule', hint);
    callbacks.onDone(FocusInsightOrchestrator.withHint(ruleBundle, hint));
  }

  /** 组装可用端点：Queen 优先，DeepSeek 备用；只包含已配置 Key 的端点 */
  private static buildEndpoints(store: ApiKeyStore): ProfileEndpoint[] {
    const list: ProfileEndpoint[] = [];
    if (store.hasQueenApiKeySync()) {
      list.push({
        label: 'Queen',
        baseUrl: AiConfig.QUEEN_BASE_URL,
        model: store.getQueenModelSync(),
        apiKey: store.getQueenApiKeySync()
      });
    }
    if (store.hasApiKeySync()) {
      list.push({
        label: 'DeepSeek',
        baseUrl: AiConfig.BASE_URL,
        model: store.getModelSync(),
        apiKey: store.getApiKeySync()
      });
    }
    return list;
  }

  /** 调用单个端点：流式请求 → 解析 → 证据校验，返回合法洞察；失败 reject */
  private tryEndpoint(ep: ProfileEndpoint,
    result: FocusProfileStatsResult): Promise<FocusInsight[]> {
    return new Promise((resolve, reject) => {
      const messages: ChatMessage[] = FocusInsightPrompt.buildMessages(result);
      const request: ChatCompletionRequest = {
        model: ep.model,
        messages: messages,
        stream: true,
        temperature: 0.3,
        max_tokens: 2000
      };
      const client: DeepSeekClient = new DeepSeekClient();
      this.activeClient = client;
      let settled: boolean = false;

      client.startStream(ep.apiKey, request, {
        onDelta: (_delta: string) => {
          // 结构化 JSON 中途片段不可用，忽略
        },
        onError: (kind: LlmErrorKind, message: string) => {
          if (settled) {
            return;
          }
          settled = true;
          if (kind === 'cancelled') {
            this.cancelled = true;
          }
          reject(new Error(message));
        },
        onComplete: (fullText: string) => {
          if (settled) {
            return;
          }
          settled = true;
          try {
            const parsed: FocusInsight[] = FocusInsightParser.parse(fullText, result.windowDays);
            const valid: FocusInsight[] = FocusInsightValidator.filterValid(parsed, result.facts);
            if (valid.length === 0) {
              reject(new Error('AI 洞察证据全部不合法'));
              return;
            }
            resolve(valid);
          } catch (err) {
            reject(err instanceof Error ? err : new Error('AI 洞察解析失败'));
          }
        }
      }, ep.baseUrl);
    });
  }

  /** 规则版原因提示（诚实告知为什么没走 AI） */
  private static ruleHint(store: ApiKeyStore, online: boolean, endpointCount: number): string {
    if (!store.isEnabledSync()) {
      return 'AI 未开启，使用本地规则生成';
    }
    if (!online) {
      return '当前无网络，已自动使用本地规则生成';
    }
    if (endpointCount === 0) {
      return '未配置可用 API Key，使用本地规则生成';
    }
    return '使用本地规则生成';
  }

  /** 复制一份规则 bundle 并覆盖提示，不改动原对象 */
  private static withHint(bundle: FocusInsightBundle, hint: string): FocusInsightBundle {
    const out: FocusInsightBundle = {
      windowDays: bundle.windowDays,
      source: bundle.source,
      insights: bundle.insights,
      hint: hint,
      generatedAt: bundle.generatedAt
    };
    return out;
  }

  /** 取消正在进行的生成 */
  public cancel(): void {
    this.cancelled = true;
    if (this.activeClient !== null) {
      this.activeClient.cancel();
      this.activeClient = null;
    }
  }

  private reset(): void {
    this.cancelled = false;
    this.activeClient = null;
  }
}
