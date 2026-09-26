// services/ai/NoteMindMapOrchestrator.ets
// 笔记转脑图编排服务（设备相关薄编排层），结构严格对照 MindMapReviewOrchestrator.ets。
//
// 它把「单篇笔记」从数据库到渲染的链路串起来：
//   纯逻辑：笔记提示词 NoteMindMapPromptBuilder / 规则解析 RuleNoteMindMapBuilder /
//           JSON 提取规整 MindMapJsonExtractor / 来源决策 ReportStrategy / 错误映射 HttpErrorMapper；
//   设备能力：数据库 DatabaseHelper / Key 存储 ApiKeyStore / 网络状态 NetState /
//           流式客户端 DeepSeekClient / 组件库反序列化 JsonSerializer（来自只读 HAR：mindmap-harmony）。
//
// 一次生成的完整决策链（与周复盘脑图一致，保证「笔记脑图」永远有产出）：
//   1. 按 noteId 查笔记；不存在、读取失败 → 失败提示；加密笔记 → 本期拦截；
//   2. 先用确定性规则解析备好规则版脑图 JSON，规整后缓存为兜底；
//   3. 读「AI 开关 / 是否有 Key / 是否联网」三个条件，交 ReportStrategy 决定来源；
//   4. 不满足 AI 条件 → 直接把规则 JSON 反序列化成 MindTree 返回（正常路径）；
//   5. 满足 → DeepSeek 流式请求脑图 JSON：
//        - 网络层出错：按错误类别决定自动降级规则树，还是提示彻底失败；
//        - 请求成功但返回文本过 extract → normalize → deserialize 三道解析，
//          任一步失败都静默降级规则树，绝不让页面崩给用户看。
// 本层依赖数据库、网络、存储与组件库反序列化，无法离线单测，分支判断全部复用已单测的纯函数。

import { ApiKeyStore } from './ApiKeyStore';
import { DeepSeekClient } from './DeepSeekClient';
import { NetState } from './NetState';
import { NoteMindMapPromptBuilder } from './NoteMindMapPromptBuilder';
import { MindMapJsonExtractor } from './MindMapJsonExtractor';
import { RuleNoteMindMapBuilder } from './RuleNoteMindMapBuilder';
import { ReportStrategy, LlmErrorKind } from './ReportStrategy';
import { HttpErrorMapper } from './HttpErrorMapper';
import { ReportSource, ReportStatus, ReportStrategyInput } from './AiChatTypes';
import { MindMapReviewCallbacks } from './MindMapReviewOrchestrator';
import { MindTree, JsonSerializer } from 'mindmap-harmony';
import { DatabaseHelper } from '../../common/DatabaseHelper';
import { Constants } from '../../model/Constants';

/** AI 返回无法解析的内容时给用户的固定提示 */
const BAD_JSON_HINT: string = 'AI 返回无法解析，已用本地规则生成';
/** 连规则树都没能构建出来时的极端失败提示 */
const RULE_BUILD_FAILED_HINT: string = '笔记脑图生成失败，请稍后重试';
/** 笔记不存在或读取失败时的提示 */
const NOTE_NOT_FOUND_HINT: string = '笔记不存在或已删除';
/** 加密笔记本期不支持的提示 */
const ENCRYPTED_HINT: string = '加密笔记暂不支持生成脑图，请先解密';

export class NoteMindMapOrchestrator {
  private client: DeepSeekClient | null = null;
  // 兜底用的规则版脑图 JSON（裸根节点字符串）
  private ruleJson: string = '';
  // 终态守卫：onError 与 onComplete 可能先后触发，保证只结束一次
  private settled: boolean = false;

  /** 生成笔记脑图。noteId 为笔记主键，回调驱动界面更新 */
  public async generate(noteId: string, callbacks: MindMapReviewCallbacks): Promise<void> {
    this.settled = false;
    this.client = null;

    // 1) 按 id 查笔记
    let title: string = '';
    let content: string = '';
    try {
      const db: DatabaseHelper = DatabaseHelper.getInstance();
      const rs = await db.query(Constants.TABLE_NOTE, 'id = ?', [noteId], '');
      if (rs === null || !rs.goToFirstRow()) {
        if (rs !== null) {
          rs.close();
        }
        callbacks.onStatus('failed', 'rule', NOTE_NOT_FOUND_HINT);
        return;
      }
      const encrypted: number = rs.getLong(rs.getColumnIndex('is_encrypted'));
      title = rs.getString(rs.getColumnIndex('title'));
      content = rs.getString(rs.getColumnIndex('content'));
      rs.close();
      if (encrypted === 1) {
        callbacks.onStatus('failed', 'rule', ENCRYPTED_HINT);
        return;
      }
    } catch (err) {
      console.error('NoteMindMap load note failed: ' + JSON.stringify(err));
      callbacks.onStatus('failed', 'rule', NOTE_NOT_FOUND_HINT);
      return;
    }

    // 2) 先备规则版兜底脑图 JSON（build → normalize）
    try {
      const ruleRaw: string = RuleNoteMindMapBuilder.build(title, content);
      this.ruleJson = MindMapJsonExtractor.normalize(ruleRaw);
    } catch (err) {
      // 纯本地逻辑理论上不会抛；真到这里判为彻底失败
      console.error('NoteMindMap build rule json failed: ' + JSON.stringify(err));
      callbacks.onStatus('failed', 'rule', RULE_BUILD_FAILED_HINT);
      return;
    }

    // 3) 收集三个环境条件，交纯逻辑决定走 AI 还是规则
    const store: ApiKeyStore = ApiKeyStore.getInstance();
    const online: boolean = await NetState.isOnline();
    const input: ReportStrategyInput = {
      llmEnabled: store.isEnabledSync(),
      online: online,
      hasApiKey: store.hasApiKeySync()
    };
    const source: ReportSource = ReportStrategy.decideSource(input);

    // 4) 不满足 AI 条件：规则树直接产出（正常路径）
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

    // 5) 满足条件：走大模型流式（脑图只在结束时拿全文解析，过程中不逐字渲染）
    callbacks.onStatus('requesting', 'llm', '');
    const request = NoteMindMapPromptBuilder.buildRequest(title, content, store.getModelSync());

    this.client = new DeepSeekClient();
    this.client.startStream(store.getApiKeySync(), request, {
      onDelta: () => {
        // 结构化 JSON 中途片段无法渲染，只把状态切到「接收中」
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
          console.warn('NoteMindMap parse AI mindmap failed, fallback to rule: ' + JSON.stringify(err));
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
      console.error('NoteMindMap deserialize rule tree failed: ' + JSON.stringify(err));
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
