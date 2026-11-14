// services/profile/FocusInsightParser.ets
// 模型分工：确定性解析（纯函数、不联网、不依赖系统 API），由 DeepSeek 负责。
// 把 Queen 返回的脏文本（可能带代码围栏、前后口语）鲁棒地解析成 FocusInsight[]；
// 只做结构转换，不做证据校验（证据合法性由 FocusInsightValidator 负责）。

import { FocusInsight, ProfileWindow } from './FocusProfileTypes';

/** AI 返回的顶层结构（insights 可能缺失，用可选字段） */
interface RawInsightWrapper {
  insights?: Object;
}

/** AI 返回的单条洞察原始结构（字段都可能缺失） */
interface RawInsightItem {
  summary?: string;
  action?: string;
  evidenceIds?: Object;
}

export class FocusInsightParser {
  /** 解析 AI 原文为洞察数组；任何一步失败都抛错，由编排层降级规则版 */
  static parse(raw: string, windowDays: ProfileWindow): FocusInsight[] {
    const jsonText: string = FocusInsightParser.extract(raw);
    let parsed: Object;
    try {
      parsed = JSON.parse(jsonText) as Object;
    } catch (err) {
      throw new Error('AI 洞察不是合法 JSON');
    }
    const wrapper: RawInsightWrapper = parsed as RawInsightWrapper;
    const rawInsights: Object | undefined = wrapper.insights;
    if (!Array.isArray(rawInsights)) {
      throw new Error('AI 洞察缺少 insights 数组');
    }
    const list: Object[] = rawInsights as Object[];
    const out: FocusInsight[] = [];
    let seq: number = 0;
    for (const item of list) {
      const insight: FocusInsight | null = FocusInsightParser.toInsight(item, windowDays, seq);
      if (insight !== null) {
        out.push(insight);
        seq++;
      }
    }
    if (out.length === 0) {
      throw new Error('AI 洞察没有可识别的有效项');
    }
    return out;
  }

  /** 从脏文本提取 JSON 对象文本：剥围栏、截首个 { 到末个 } */
  private static extract(raw: string): string {
    if (raw === null || raw === undefined) {
      throw new Error('AI 洞察返回为空');
    }
    let text: string = raw.trim();
    if (text.length === 0) {
      throw new Error('AI 洞察返回为空');
    }
    if (text.startsWith('```')) {
      const nl: number = text.indexOf('\n');
      text = nl >= 0 ? text.substring(nl + 1) : text.substring(3);
    }
    text = text.trim();
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    const start: number = text.indexOf('{');
    const end: number = text.lastIndexOf('}');
    if (start < 0 || end < 0 || end < start) {
      throw new Error('AI 洞察里没有 JSON 对象');
    }
    return text.substring(start, end + 1);
  }

  /** 把单个原始对象转成 FocusInsight；字段不合法返回 null */
  private static toInsight(item: Object, windowDays: ProfileWindow, seq: number): FocusInsight | null {
    if (item === null || item === undefined || typeof item !== 'object') {
      return null;
    }
    const obj: RawInsightItem = item as RawInsightItem;
    const summary: string = FocusInsightParser.readString(obj.summary);
    const action: string = FocusInsightParser.readString(obj.action);
    const evidenceIds: string[] = FocusInsightParser.readIds(obj.evidenceIds);
    if (summary.length === 0 || action.length === 0 || evidenceIds.length === 0) {
      return null;
    }
    const insight: FocusInsight = {
      id: `f${windowDays}-llm-${seq}`,
      windowDays: windowDays,
      summary: summary,
      evidenceIds: evidenceIds,
      action: action,
      source: 'llm'
    };
    return insight;
  }

  private static readString(value: string | undefined): string {
    if (typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  private static readIds(value: Object | undefined): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const arr: Object[] = value as Object[];
    const out: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const v of arr) {
      if (typeof v === 'string') {
        const id: string = (v as string).trim();
        if (id.length > 0 && !seen.has(id)) {
          seen.add(id);
          out.push(id);
        }
      }
    }
    return out;
  }
}
