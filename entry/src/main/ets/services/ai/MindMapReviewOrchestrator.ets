// services/ai/MindMapReviewOrchestrator.ets
// 复盘脑图编排服务（设备相关薄编排层），结构严格对照同目录 AiReportOrchestrator.ets。
//
// 它把「已经单测好的纯逻辑」与「设备能力」按顺序串起来：
//   纯逻辑：周摘要 buildSummary / 脑图提示词 buildRequest / 规则脑图 RuleMindMapBuilder /
//           JSON 提取规整 MindMapJsonExtractor / 来源决策 ReportStrategy / 错误映射 HttpErrorMapper；
//   设备能力：Key 存储 ApiKeyStore / 网络状态 NetState / 流式客户端 DeepSeekClient /
//           组件库反序列化 JsonSerializer（来自只读 HAR：mindmap-harmony）。
//
// 一次生成的完整决策链（与 AI 周报一致，保证「脑图」这个功能永远有产出）：
//   1. 先用本地统计拼出规则版脑图 JSON，规整后缓存为兜底（无论走不走 AI 都先有一份）；
//   2. 读「AI 开关 / 是否有 Key / 是否联网」三个条件，交纯逻辑 ReportStrategy 决定来源；
//   3. 不满足 AI 条件 → 直接把规则 JSON 反序列化成 MindTree 返回（正常路径，不是出错）；
//   4. 满足 → DeepSeek 流式请求脑图 JSON：
//        - 网络层出错：按错误类别决定自动降级规则树，还是提示彻底失败；
//        - 请求即使成功，返回文本也要过 extract → normalize → deserialize 三道解析，
//          任一步失败（坏 JSON / 空文本）都静默降级规则树，绝不让页面崩给用户看。
// 本层依赖网络、存储与组件库反序列化，无法离线单测，因此分支判断全部复用已单测的纯函数。

import { StudySession } from '../LearningAnalysisService';
import { ApiKeyStore } from './ApiKeyStore';
import { DeepSeekClient } from './DeepSeekClient';
import { NetState } from './NetState';
import { ReportPromptBuilder, WeeklyDataSummary } from './ReportPromptBuilder';
import { MindMapPromptBuilder } from './MindMapPromptBuilder';
import { MindMapJsonExtractor } from './MindMapJsonExtractor';
import { RuleMindMapBuilder } from './RuleMindMapBuilder';
import { ReportStrategy, LlmErrorKind } from './ReportStrategy';
import { HttpErrorMapper } from './HttpErrorMapper';
import { ReportSource, ReportStatus, ReportStrategyInput } from './AiChatTypes';
import { MindTree, JsonSerializer } from 'mindmap-harmony';

/** AI 返回了无法解析的内容（坏 JSON / 空文本）时给用户的固定提示 */
const BAD_JSON_HINT: string = 'AI 返回无法解析，已用本地统计生成';
/** 连本地规则树都没能构建出来时的极端失败提示（正常不会走到） */
const RULE_BUILD_FAILED_HINT: string = '复盘脑图生成失败，请稍后重试';

/** 给界面的回调：状态变化 / 结束（最终脑图树 + 来源 + 提示） */
export interface MindMapReviewCallbacks {
  onStatus: (status: ReportStatus, source: ReportSource, hint: string) => void;
  onDone: (tree: MindTree, source: ReportSource, hint: string) => void;
}

export class MindMapReviewOrchestrator {
  private client: DeepSeekClient | null = null;
  // 兜底用的规则版脑图 JSON（裸根节点字符串），AI 出错或返回脏数据时直接反序列化使用
  private ruleJson: string = '';
  // 终态守卫：onError 与 onComplete 可能先后触发，保证只结束一次
  private settled: boolean = false;

  /** 生成复盘脑图。sessions 为专注记录（内部按本周聚合），回调驱动界面更新 */
  public async generate(sessions: StudySession[], callbacks: MindMapReviewCallbacks): Promise<void> {
    this.settled = false;
    this.client = null;

    // 1) 聚合本周摘要，并先备好规则版兜底脑图 JSON（build → normalize）
    const summary: WeeklyDataSummary = ReportPromptBuilder.buildSummary(sessions, new Date());
    try {
      const ruleRaw: string = RuleMindMapBuilder.build(summary);
      this.ruleJson = MindMapJsonExtractor.normalize(ruleRaw);
    } catch (err) {
      // 纯本地逻辑理论上不会抛；真到这里说明规则树也无法产出，判为彻底失败
      console.error('MindMapReview build rule json failed: ' + JSON.stringify(err));
      callbacks.onStatus('failed', 'rule', RULE_BUILD_FAILED_HINT);
      return;
    }

    // 2) 收集三个环境条件，交纯逻辑决定走 AI 还是规则
    const store: ApiKeyStore = ApiKeyStore.getInstance();
    const online: boolean = await NetState.isOnline();
    const input: ReportStrategyInput = {
      llmEnabled: store.isEnabledSync(),
      online: online,
      hasApiKey: store.hasApiKeySync()
    };
    const source: ReportSource = ReportStrategy.decideSource(input);

    // 3) 不满足 AI 条件：规则树直接产出（正常路径）
    if (source === 'rule') {
      const reason: string = ReportStrategy.ruleReason(input);
      const fallback: MindTree | null = this.buildFallbackTree();
      if (fallback === null) {
        callbacks.onStatus('failed', 'rule', RULE_BUILD_FAILED_HINT);
        return;
      }
      callbacks.onStatus('succeeded', 'rule', reason);
      callbacks.onDone(fallback, 'rule', reason);
      return;
    }

    // 4) 满足条件：走大模型流式（脑图只在结束时拿全文解析，过程中不逐字渲染）
    callbacks.onStatus('requesting', 'llm', '');
    const request = MindMapPromptBuilder.buildRequest(summary, store.getModelSync());

    this.client = new DeepSeekClient();
    this.client.startStream(store.getApiKeySync(), request, {
      onDelta: () => {
        // 脑图是结构化 JSON，中途片段无法渲染，只把状态切到「接收中」
        callbacks.onStatus('streaming', 'llm', '');
      },
      onError: (kind: LlmErrorKind) => {
        if (this.settled) {
          return;
        }
        this.settled = true;
        if (ReportStrategy.shouldFallback(kind)) {
          // 非用户取消的网络/服务错误：自动降级规则树，保证有产出
          this.finishWithFallback(callbacks, HttpErrorMapper.userMessage(kind));
        } else {
          callbacks.onStatus('failed', 'llm', HttpErrorMapper.userMessage(kind));
        }
      },
      onComplete: (fullText: string) => {
        if (this.settled) {
          return;
        }
        this.settled = true;

        // 依次 extract → normalize → deserialize，任一步抛错都降级规则树
        let tree: MindTree | null = null;
        try {
          const extracted: string = MindMapJsonExtractor.extract(fullText);
          const normalized: string = MindMapJsonExtractor.normalize(extracted);
          tree = JsonSerializer.deserialize(normalized);
        } catch (err) {
          // MindMapExtractError / MindMapSerializeError / 空文本都在此统一兜底
          console.warn('MindMapReview parse AI mindmap failed, fallback to rule: ' + JSON.stringify(err));
          this.finishWithFallback(callbacks, BAD_JSON_HINT);
          return;
        }
        if (tree === null) {
          this.finishWithFallback(callbacks, BAD_JSON_HINT);
          return;
        }
        callbacks.onStatus('succeeded', 'llm', '');
        callbacks.onDone(tree, 'llm', '');
      }
    });
  }

  /** 把缓存的规则版 JSON 反序列化成 MindTree；失败返回 null（不向上抛） */
  private buildFallbackTree(): MindTree | null {
    try {
      return JsonSerializer.deserialize(this.ruleJson);
    } catch (err) {
      console.error('MindMapReview deserialize rule tree failed: ' + JSON.stringify(err));
      return null;
    }
  }

  /** 统一的降级收尾：尽量用规则树结束；规则树也拿不到才判彻底失败 */
  private finishWithFallback(callbacks: MindMapReviewCallbacks, hint: string): void {
    const fallback: MindTree | null = this.buildFallbackTree();
    if (fallback === null) {
      callbacks.onStatus('failed', 'rule', RULE_BUILD_FAILED_HINT);
      return;
    }
    callbacks.onStatus('fallback', 'rule', hint);
    callbacks.onDone(fallback, 'rule', hint);
  }

  /** 取消正在进行的生成（例如离开页面） */
  public cancel(): void {
    if (this.client !== null) {
      this.client.cancel();
      this.client = null;
    }
  }
}
