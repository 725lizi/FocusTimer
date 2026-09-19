// services/ai/RuleMindMapBuilder.ets
// 纯逻辑：不调大模型，直接用同一套契约「拼」出一棵规范的思维导图 JSON。
//
// 定位与 ReportStrategy 的规则版周报一致：无网、未配 Key、模型失败或返回不可解析时兜底，
// 保证「思维导图」这个功能永远有产出。因此这里的结构必须与 MindMapPromptBuilder 的提示词契约
// 完全对齐（同一根节点、同一四个一级分支、叶子不超过 16 个汉字、节点数落在 8~20 区间、深度 2~3），
// 且所有数字都来自 WeeklyDataSummary——零数据时只给鼓励、不编数字。
//
// 输出形状是**裸根节点**（顶层 {id, text, children}）：组件库 JsonSerializer.deserialize
// 只接受裸节点或 {format:'mindmap-harmonyos', version:1, root:{...}} 信封，本侧统一走裸节点，不补信封。
//
// 无网络、无 UI、无随机：同一摘要必得同一 JSON 字符串，且输出一定能被 MindMapJsonExtractor.normalize 接受。

import { WeeklyDataSummary } from './ReportPromptBuilder';

/** 参与排序的科目分钟 */
interface RuleTagMinutes {
  tag: string;
  minutes: number;
}

/** 待落地的节点：用 {text, children} 描述结构，id 交给 finalize 统一按层序编号 */
interface RuleNodeDraft {
  text: string;
  children: RuleNodeDraft[];
}

/** 最终节点：契约要求的 {id, text, children}，顶层直接输出它（不套信封） */
interface RuleMindMapNode {
  id: string;
  text: string;
  children: RuleMindMapNode[];
}

export class RuleMindMapBuilder {
  /** 与提示词完全一致的四个一级分支（顺序即输出顺序） */
  static readonly BRANCH_TITLES: string[] = ['总体情况', '科目分布', '专注质量', '下周行动'];
  /** 根节点文案（固定） */
  static readonly ROOT_TEXT: string = '本周专注复盘';
  /** 叶子文案上限（汉字个数） */
  static readonly MAX_TEXT_CHARS: number = 16;
  /** 科目分支最多展示的科目数 */
  static readonly MAX_TAG_NODES: number = 3;

  /** 各科目按「分钟降序、同名按名称升序」排序，保证同输入必得同顺序 */
  private static sortedTags(tagMinutes: Map<string, number>): RuleTagMinutes[] {
    const items: RuleTagMinutes[] = [];
    tagMinutes.forEach((minutes: number, tag: string) => {
      items.push({ tag: tag, minutes: minutes });
    });
    items.sort((a: RuleTagMinutes, b: RuleTagMinutes): number => {
      if (b.minutes !== a.minutes) {
        return b.minutes - a.minutes;
      }
      if (a.tag === b.tag) {
        return 0;
      }
      return a.tag < b.tag ? -1 : 1;
    });
    return items;
  }

  /** 只保留 Top3（契约：科目分支最多三个科目） */
  private static topTags(tagMinutes: Map<string, number>): RuleTagMinutes[] {
    return RuleMindMapBuilder.sortedTags(tagMinutes)
      .slice(0, RuleMindMapBuilder.MAX_TAG_NODES);
  }

  /** 节点文案超长即截断（budget 为本次文案可用的汉字数，默认 16） */
  private static clip(text: string, budget: number = RuleMindMapBuilder.MAX_TEXT_CHARS): string {
    const trimmed: string = text.trim();
    if (trimmed.length > budget) {
      return trimmed.substring(0, budget);
    }
    return trimmed;
  }

  /** 规则版判断：是否「环比上周有增长」 */
  private static isGrowing(summary: WeeklyDataSummary): boolean {
    if (summary.lastWeekMinutes <= 0) {
      return summary.thisWeekMinutes > 0;
    }
    return summary.thisWeekMinutes > summary.lastWeekMinutes;
  }

  /**
   * 分支一：总体情况（本周时长 + 环比 + 上周）。
   * 这里刻意全部做成叶子：契约要求整棵树深度 2~3，四个一级分支本身已占一层，
   * 分支下再挂一层就会到第 4 层，所以「总体情况」只用同级叶子表达。
   */
  private static overallChildren(summary: WeeklyDataSummary): RuleNodeDraft[] {
    const items: RuleNodeDraft[] = [];
    items.push({ text: '本周 ' + summary.thisWeekMinutes + ' 分钟', children: [] });

    if (summary.lastWeekMinutes <= 0) {
      items.push({ text: '上周为 0 分钟', children: [] });
      items.push({ text: '上周暂无记录', children: [] });
    } else if (summary.changePercent === 0) {
      items.push({ text: '环比持平 0%', children: [] });
      items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
    } else if (summary.changePercent > 0) {
      items.push({ text: '环比增加 ' + summary.changePercent + '%', children: [] });
      items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
    } else {
      items.push({ text: '环比减少 ' + Math.abs(summary.changePercent) + '%', children: [] });
      items.push({ text: '上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
    }
    return items;
  }

  /** 分支二：科目分布（tagMinutes Top3）。与其它分支一样只用同级叶子，保证整树深度 2~3。 */
  private static tagChildren(summary: WeeklyDataSummary): RuleNodeDraft[] {
    if (summary.tagMinutes.size === 0) {
      return [
        { text: '本周暂无科目记录', children: [] },
        { text: '下次专注带上标签', children: [] }
      ];
    }

    const items: RuleNodeDraft[] = [];
    RuleMindMapBuilder.topTags(summary.tagMinutes).forEach((item: RuleTagMinutes) => {
      items.push({ text: RuleMindMapBuilder.clip(item.tag), children: [] });
      items.push({ text: item.minutes + ' 分钟', children: [] });
    });
    return items;
  }

  /**
   * 分支三：专注质量（平均时长 + 中断次数）。
   * 同样只用同级叶子：一级分支下再挂一层就到第 4 层，会超出契约的深度 2~3。
   */
  private static qualityChildren(summary: WeeklyDataSummary): RuleNodeDraft[] {
    const items: RuleNodeDraft[] = [];
    items.push({ text: '平均每次 ' + summary.avgSessionMinutes + ' 分钟', children: [] });
    items.push({ text: '中断 ' + summary.interruptedCount + ' 次', children: [] });

    if (summary.interruptedCount === 0) {
      items.push({ text: '全程未被打断', children: [] });
    } else {
      items.push({ text: '被打断后尽快回到桌前', children: [] });
    }
    return items;
  }

  /** 零数据：四个分支仍齐全，只给鼓励结构、一个数字都不编 */
  private static emptyDataChildren(): RuleNodeDraft[] {
    return [
      {
        text: RuleMindMapBuilder.BRANCH_TITLES[0],
        children: [{ text: '本周还没有专注记录', children: [] }]
      },
      {
        text: RuleMindMapBuilder.BRANCH_TITLES[1],
        children: [{ text: '还没有科目用时', children: [] }]
      },
      {
        text: RuleMindMapBuilder.BRANCH_TITLES[2],
        children: [{ text: '本周暂无中断记录', children: [] }]
      },
      {
        text: RuleMindMapBuilder.BRANCH_TITLES[3],
        children: [
          { text: '先从一次专注开始', children: [] },
          { text: '完成一次就给自己点赞', children: [] }
        ]
      }
    ];
  }

  /** 分支四：下周行动（基于真实数字的 2 条模板建议） */
  private static actionChildren(summary: WeeklyDataSummary): RuleNodeDraft[] {
    const items: RuleNodeDraft[] = [];

    if (summary.thisWeekMinutes <= 0) {
      items.push({ text: '先完成本周第一次专注', children: [] });
      items.push({ text: '给这次专注打上标签', children: [] });
      return items;
    }

    // 建议一：盯住「主力科目」（按真实分钟取 Top1，提醒不要偏科）
    if (summary.tagMinutes.size > 0) {
      const top: RuleTagMinutes = RuleMindMapBuilder.topTags(summary.tagMinutes)[0];
      const prefix: string = '继续保持「';
      const suffix: string = '」';
      const tagBudget: number = RuleMindMapBuilder.MAX_TEXT_CHARS - prefix.length - suffix.length;
      items.push({
        text: prefix + RuleMindMapBuilder.clip(top.tag, tagBudget) + suffix,
        children: []
      });
    } else {
      items.push({ text: '给每次专注补上科目标签', children: [] });
    }

    // 建议二：按本周真实状态给「加量 / 稳住 / 起步」三选一
    const hasEnoughSamples: boolean = summary.sessionCount >= 2;
    if (RuleMindMapBuilder.isGrowing(summary)) {
      if (hasEnoughSamples) {
        items.push({ text: '趁势把周时长再提一点', children: [] });
      } else {
        items.push({
          text: '保持势头，试着做 2 次',
          children: [{ text: '把专注排进固定时段', children: [] }]
        });
      }
    } else if (summary.lastWeekMinutes > 0) {
      items.push({ text: '先追平上周 ' + summary.lastWeekMinutes + ' 分钟', children: [] });
    } else if (hasEnoughSamples) {
      items.push({ text: '保持节奏，别断更', children: [] });
    } else {
      items.push({
        text: '先稳住每天一次',
        children: [{ text: '小步快跑胜过猛冲一回', children: [] }]
      });
    }
    return items;
  }

  /** 按契约顺序拼出四个一级分支 */
  private static branchChildren(summary: WeeklyDataSummary): RuleNodeDraft[] {
    const branches: RuleNodeDraft[] = [];
    branches.push({ text: RuleMindMapBuilder.BRANCH_TITLES[0], children: RuleMindMapBuilder.overallChildren(summary) });
    branches.push({ text: RuleMindMapBuilder.BRANCH_TITLES[1], children: RuleMindMapBuilder.tagChildren(summary) });
    branches.push({ text: RuleMindMapBuilder.BRANCH_TITLES[2], children: RuleMindMapBuilder.qualityChildren(summary) });
    branches.push({ text: RuleMindMapBuilder.BRANCH_TITLES[3], children: RuleMindMapBuilder.actionChildren(summary) });
    return branches;
  }

  /** 层序（先父后子、同级从左到右）编号：根固定 root，其余 m0、m1… */
  private static finalize(draft: RuleNodeDraft, isRoot: boolean, seq: number[]): RuleMindMapNode {
    let id: string;
    if (isRoot) {
      id = 'root';
    } else {
      id = 'm' + seq[0];
      seq[0] = seq[0] + 1;
    }
    const children: RuleMindMapNode[] = [];
    for (let i = 0; i < draft.children.length; i++) {
      children.push(RuleMindMapBuilder.finalize(draft.children[i], false, seq));
    }
    const node: RuleMindMapNode = { id: id, text: RuleMindMapBuilder.clip(draft.text), children: children };
    return node;
  }

  /**
   * 生成规则版思维导图 JSON（与模型输出同一格式、同一契约）。
   * 输出是**裸根节点**（顶层就是 {id, text, children}），与组件库 JsonSerializer.deserialize
   * 接受的形态一致，不套 {root:...} 信封；该 JSON 也能直接喂给 MindMapJsonExtractor.normalize 做二次保险。
   */
  static build(summary: WeeklyDataSummary): string {
    const hasData: boolean = summary.thisWeekMinutes > 0;
    const children: RuleNodeDraft[] = hasData
      ? RuleMindMapBuilder.branchChildren(summary)
      : RuleMindMapBuilder.emptyDataChildren();

    const draft: RuleNodeDraft = { text: RuleMindMapBuilder.ROOT_TEXT, children: children };
    const root: RuleMindMapNode = RuleMindMapBuilder.finalize(draft, true, [0]);
    return JSON.stringify(root);
  }
}
