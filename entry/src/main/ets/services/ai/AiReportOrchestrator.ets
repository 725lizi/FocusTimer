// services/ai/AiReportOrchestrator.ets
// AI 周报编排服务（设备相关薄编排层）：把前面已经测好的纯逻辑层与设备能力按顺序串起来。
//
// 一次生成的完整决策链：
//   1. 先把「本地规则版周报」准备好作为兜底（无论走不走 AI 都先有一份，保证永远有产出）；
//   2. 读取「AI 开关 / 是否有 Key / 是否联网」三个条件，交给纯逻辑 ReportStrategy 决定来源；
//   3. 不满足 AI 条件 → 直接给规则版（这是正常路径，不是出错）；
//   4. 满足 → DeepSeekClient 流式请求，逐段回调；出错按类别决定是否自动降级到规则版。
// 本层依赖网络与存储、无法离线单测，因此所有分支判断都复用已单测的纯函数（Strategy/Mapper）。

import { LearningAnalysisService, StudySession } from '../LearningAnalysisService';
import { ApiKeyStore } from './ApiKeyStore';
import { DeepSeekClient } from './DeepSeekClient';
import { NetState } from './NetState';
import { ReportPromptBuilder } from './ReportPromptBuilder';
import { ReportStrategy, LlmErrorKind } from './ReportStrategy';
import { HttpErrorMapper } from './HttpErrorMapper';
import { ReportSource, ReportStatus, ReportStrategyInput } from './AiChatTypes';

/** 给界面的回调：状态变化 / 流式增量（累计全文） / 结束（最终文本+来源+提示） */
export interface AiReportCallbacks {
  onStatus: (status: ReportStatus, source: ReportSource, hint: string) => void;
  onDelta: (fullText: string) => void;
  onDone: (text: string, source: ReportSource, hint: string) => void;
}

export class AiReportOrchestrator {
  private client: DeepSeekClient | null = null;
  // 兜底用的规则版文本，AI 出错时直接用它，不必临时再算
  private ruleText: string = '';
  // 终态守卫：onError 与 onComplete 可能先后触发，保证只结束一次
  private settled: boolean = false;

  /** 生成周报。sessions 为最近的专注记录，回调驱动界面更新 */
  public async generate(sessions: StudySession[], callbacks: AiReportCallbacks): Promise<void> {
    this.settled = false;

    // 1) 先备好规则版兜底
    this.ruleText = await LearningAnalysisService.getInstance().generateWeeklyReport(sessions);

    // 2) 收集三个环境条件
    const store: ApiKeyStore = ApiKeyStore.getInstance();
    const online: boolean = await NetState.isOnline();
    const input: ReportStrategyInput = {
      llmEnabled: store.isEnabledSync(),
      online: online,
      hasApiKey: store.hasApiKeySync()
    };
    const source: ReportSource = ReportStrategy.decideSource(input);

    // 3) 不满足 AI 条件：规则版直接产出（正常路径）
    if (source === 'rule') {
      const reason: string = ReportStrategy.ruleReason(input);
      callbacks.onStatus('succeeded', 'rule', reason);
      callbacks.onDone(this.ruleText, 'rule', reason);
      return;
    }

    // 4) 满足条件：走大模型流式
    callbacks.onStatus('requesting', 'llm', '');
    const summary = ReportPromptBuilder.buildSummary(sessions, new Date());
    const request = ReportPromptBuilder.buildStreamRequest(summary, store.getModelSync());
    let accumulated: string = '';

    this.client = new DeepSeekClient();
    this.client.startStream(store.getApiKeySync(), request, {
      onDelta: (delta: string) => {
        accumulated += delta;
        callbacks.onStatus('streaming', 'llm', '');
        callbacks.onDelta(accumulated);
      },
      onError: (kind: LlmErrorKind, message: string) => {
        if (this.settled) {
          return;
        }
        this.settled = true;
        if (ReportStrategy.shouldFallback(kind)) {
          // 非用户取消的错误：自动降级到规则版，保证有产出
          const hint: string = HttpErrorMapper.userMessage(kind);
          callbacks.onStatus('fallback', 'rule', hint);
          callbacks.onDone(this.ruleText, 'rule', hint);
        } else {
          callbacks.onStatus('failed', 'llm', HttpErrorMapper.userMessage(kind));
        }
      },
      onComplete: (fullText: string) => {
        if (this.settled) {
          return;
        }
        this.settled = true;
        const text: string = fullText.trim();
        if (text.length === 0) {
          // 模型返回空也兜底
          const hint: string = HttpErrorMapper.userMessage('empty');
          callbacks.onStatus('fallback', 'rule', hint);
          callbacks.onDone(this.ruleText, 'rule', hint);
          return;
        }
        callbacks.onStatus('succeeded', 'llm', '');
        callbacks.onDone(text, 'llm', '');
      }
    });
  }

  /** 取消正在进行的生成（例如离开页面） */
  public cancel(): void {
    if (this.client !== null) {
      this.client.cancel();
      this.client = null;
    }
  }
}
