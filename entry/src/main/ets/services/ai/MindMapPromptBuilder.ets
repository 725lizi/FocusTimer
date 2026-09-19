// services/ai/MindMapPromptBuilder.ets
// 纯逻辑：把一周专注摘要组装成「思维导图节点 JSON」的提示词。
// 与 ReportPromptBuilder（写周报正文）并列，本文件只负责「结构树」这一种产出：
// 契约（根节点/四个一级分支/节点数与深度/叶子字数）全部写死在提示词里，
// 事实数字全部来自 WeeklyDataSummary，从提示词层面压制模型编数字与改结构。
//
// 不联网、不依赖 UI、不使用随机数：同一摘要必得同一 messages、同一请求体，可离线单测。

import { ChatMessage, ChatCompletionRequest } from './AiChatTypes';
import { WeeklyDataSummary } from './ReportPromptBuilder';

/** 参与排序的带分钟数的科目（纯中间结构，不外传） */
interface MindMapTagMinutes {
  tag: string;
  minutes: number;
}

export class MindMapPromptBuilder {
  /** 契约里固定的一级分支（顺序即输出顺序） */
  static readonly BRANCH_ORDER: string = '总体情况 / 科目分布 / 专注质量 / 下周行动';
  /** 叶子节点文案上限（提示词里说的是 16 个汉字，这里作为拼装时的强约束） */
  static readonly MAX_LEAF_CHARS: number = 16;
  /** 节点总数下限（含根） */
  static readonly MIN_NODE_COUNT: number = 8;
  /** 节点总数上限（含根） */
  static readonly MAX_NODE_COUNT: number = 20;
  /** 低于该分钟数视为「上周无有效记录」，环比只描述本周 */
  private static readonly LOW_BASE_MINUTES: number = 5;

  /**
   * system 角色：把模型关进「只输出一个 JSON 对象」的笼子里。
   * 明确禁止 markdown 围栏、解释文字、注释和尾逗号——这些正是流式返回里最常见的脏内容。
   */
  static buildSystemPrompt(): string {
    return '你是一名学习数据可视化助手，负责把真实专注统计转成思维导图节点 JSON。'
      + '严格约束：1）只输出一个思维导图节点 JSON 对象，不要 markdown 围栏（不要 ```json）、'
      + '不要代码块、不要任何解释文字、前后不要多余内容；2）JSON 的键和字符串值都必须用双引号，'
      + '数字直接写阿拉伯数字，不要注释、不要尾逗号；3）节点固定为 {id, text, children} 三字段，'
      + 'children 是数组（叶子节点用空数组）；4）根节点固定为 {"id":"root","text":"本周专注复盘","children":[...]}；'
      + `5）一级分支固定四个、顺序固定为：${MindMapPromptBuilder.BRANCH_ORDER}；`
      + `6）总节点数（含根）必须控制在 ${MindMapPromptBuilder.MIN_NODE_COUNT}~${MindMapPromptBuilder.MAX_NODE_COUNT} 个，`
      + '深度固定 2~3 层，且每个节点 id 全局唯一；'
      + `7）每个叶子节点的 text 不超过 ${MindMapPromptBuilder.MAX_LEAF_CHARS} 个汉字，精炼成短句或关键词；`
      + '8）所有数字只能来自用户给出的数据，禁止编造、估算或换算任何新数字；'
      + '9）数据为空时仍要输出完整结构，把鼓励写进节点文字，绝不允许编造数字。';
  }

  /** 环比的方向词（只用于文字描述，数字本身仍取 summary.changePercent） */
  private static changeDirectionLabel(changePercent: number): string {
    if (changePercent > 0) {
      return '增加';
    }
    if (changePercent < 0) {
      return '减少';
    }
    return '持平';
  }

  /** 各科目分钟数按「分钟降序、同名按名称升序」排好，保证同输入必得同顺序 */
  private static sortedTagMinutes(summary: WeeklyDataSummary): MindMapTagMinutes[] {
    const items: MindMapTagMinutes[] = [];
    summary.tagMinutes.forEach((minutes: number, tag: string) => {
      items.push({ tag: tag, minutes: minutes });
    });
    items.sort((a: MindMapTagMinutes, b: MindMapTagMinutes): number => {
      if (b.minutes !== a.minutes) {
        return b.minutes - a.minutes;
      }
      return a.tag < b.tag ? -1 : (a.tag > b.tag ? 1 : 0);
    });
    return items;
  }

  /** 科目分布文字：只列 Top3，且数字与 summary.tagMinutes 完全一致 */
  private static describeTags(summary: WeeklyDataSummary): string {
    const items: MindMapTagMinutes[] = MindMapPromptBuilder.sortedTagMinutes(summary);
    if (items.length === 0) {
      return '本周暂无科目标签记录';
    }
    const top: MindMapTagMinutes[] = items.slice(0, 3);
    const parts: string[] = [];
    top.forEach((item: MindMapTagMinutes) => {
      parts.push(`${item.tag} ${item.minutes} 分钟`);
    });
    return parts.join('，');
  }

  /** user 角色：先给「事实底稿」，再给「输出契约」，最后强调只输出 JSON */
  static buildUserPrompt(summary: WeeklyDataSummary): string {
    const lines: string[] = [];
    lines.push('以下是我本周的真实专注统计（时长单位：分钟）：');
    lines.push('- 本周总专注：' + summary.thisWeekMinutes + ' 分钟；'
      + '上周：' + summary.lastWeekMinutes + ' 分钟；'
      + '环比' + MindMapPromptBuilder.changeDirectionLabel(summary.changePercent)
      + ' ' + Math.abs(summary.changePercent) + '%');
    lines.push('- 专注次数：' + summary.sessionCount + ' 次；'
      + '活跃天数：' + summary.activeDays + ' 天；'
      + '平均每次：' + summary.avgSessionMinutes + ' 分钟；'
      + '被中断：' + summary.interruptedCount + ' 次');
    lines.push('- 各科目时长：' + MindMapPromptBuilder.describeTags(summary));

    lines.push('');
    lines.push('请输出思维导图节点 JSON，契约如下：');
    lines.push('1）只输出一个 JSON 对象，不要 markdown 围栏、不要解释文字；');
    lines.push('2）根节点固定为 {"id":"root","text":"本周专注复盘","children":[...]}；');
    lines.push('3）根下四个一级分支，顺序固定为「' + MindMapPromptBuilder.BRANCH_ORDER + '」；');
    lines.push('4）每个节点形如 {"id":"唯一字符串","text":"不超过 '
      + MindMapPromptBuilder.MAX_LEAF_CHARS + ' 个汉字","children":[]}，叶子节点 children 为空数组；');
    lines.push('5）总节点数（含根）控制在 ' + MindMapPromptBuilder.MIN_NODE_COUNT
      + '~' + MindMapPromptBuilder.MAX_NODE_COUNT + ' 个，深度固定 2~3 层；');
    lines.push('6）所有数字只能来自上面的数据，不要新增或换算任何数字；');
    lines.push('7）「下周行动」给 2~3 条具体可执行的建议，每条不超过 '
      + MindMapPromptBuilder.MAX_LEAF_CHARS + ' 个汉字。');

    if (summary.thisWeekMinutes === 0) {
      lines.push('重要：本周没有任何专注记录。四个分支仍要齐全，但只做鼓励与起步建议'
        + '（例如「本周还没开始，先来 25 分钟」），不得编造任何数字。');
    }
    lines.push('现在只输出这一个 JSON 对象。');
    return lines.join('\n');
  }

  /** 组装成 OpenAI 兼容的 messages 数组 */
  static buildMessages(summary: WeeklyDataSummary): ChatMessage[] {
    const messages: ChatMessage[] = [
      { role: 'system', content: MindMapPromptBuilder.buildSystemPrompt() },
      { role: 'user', content: MindMapPromptBuilder.buildUserPrompt(summary) }
    ];
    return messages;
  }

  /**
   * 组装完整请求体：走现有流式客户端（stream=true），在 onComplete 里拿全文再交给
   * MindMapJsonExtractor 提取。temperature 压到 0.4、max_tokens 给 900，
   * 既保证结构稳定，又留够放 20 个节点的空间。
   */
  static buildRequest(summary: WeeklyDataSummary, model: string): ChatCompletionRequest {
    const request: ChatCompletionRequest = {
      model: model,
      messages: MindMapPromptBuilder.buildMessages(summary),
      stream: true,
      temperature: 0.4,
      max_tokens: 900
    };
    return request;
  }
}
