// services/ai/NoteMindMapPromptBuilder.ets
// 纯逻辑：把「单篇笔记」组装成「笔记转脑图 JSON」的提示词与请求体。
//
// 与 MindMapPromptBuilder（周复盘：根 + 四个统计分支）并列但互不影响：周复盘的根与一级分支是统计专用结构，
// 本文件面对的是任意笔记文本，根节点取笔记标题、层级由笔记自身的编号/缩进决定，
// 所以契约里不写死任何分支名，只约束「三字段节点 + 2~4 层 + 只用原文事实 + 节点总数 ≤ 40」。
//
// 不联网、不依赖 UI、不使用随机数与当前时间：同一篇笔记必得同一 messages、同一请求体，可离线单测。

import { ChatMessage, ChatCompletionRequest } from './AiChatTypes';

export class NoteMindMapPromptBuilder {
  /** 根节点文案兜底：笔记标题为空时使用 */
  static readonly ROOT_TEXT_FALLBACK: string = '笔记脑图';
  /** 空笔记兜底叶子文案 */
  static readonly EMPTY_NOTE_TEXT: string = '（空笔记）';
  /** 单个节点文案上限（汉字个数） */
  static readonly MAX_NODE_TEXT_CHARS: number = 20;
  /** 全文节点总数上限（含根） */
  static readonly MAX_NODE_COUNT: number = 40;
  /** 层级上限：根之下最多 4 级 */
  static readonly MAX_LEVEL_COUNT: number = 4;
  /** 散文体笔记归纳出的一级分支数区间 */
  static readonly MIN_PROSE_BRANCHES: number = 3;
  static readonly MAX_PROSE_BRANCHES: number = 6;
  /** 生成参数：笔记转结构要忠实原文，把随机性压到 0.3 */
  static readonly TEMPERATURE: number = 0.3;
  static readonly MAX_TOKENS: number = 1800;

  /** 根节点文案：标题去空白后非空就用标题，否则用兜底文案 */
  private static resolveRootText(noteTitle: string): string {
    if (noteTitle === null || noteTitle === undefined) {
      return NoteMindMapPromptBuilder.ROOT_TEXT_FALLBACK;
    }
    const title: string = noteTitle.trim();
    if (title.length === 0) {
      return NoteMindMapPromptBuilder.ROOT_TEXT_FALLBACK;
    }
    return title;
  }

  /** 正文是否为空（只有空白也算空） */
  private static isBlankContent(noteContent: string): boolean {
    if (noteContent === null || noteContent === undefined) {
      return true;
    }
    return noteContent.trim().length === 0;
  }

  /**
   * system 角色：把模型关进「只输出一个 JSON 对象」的笼子里，
   * 并把卡 C-01 第 3.2 节的九条约束逐条写死（文字可组织，语义不许漏）。
   */
  static buildSystemPrompt(): string {
    return '你是一名文本结构化助手，负责把任意笔记或文本转成思维导图节点 JSON。'
      + '严格约束：1）只输出一个 JSON 对象，不要 markdown 围栏（不要 ```json）、不要代码块、'
      + '不要任何解释文字、不要注释、不要尾逗号，前后不要多余内容；'
      + '2）节点固定为 {id, text, children} 三字段，键与字符串值都用双引号，children 是数组（叶子节点用空数组），'
      + 'id 全局唯一；'
      + '3）根节点固定为 {"id":"root","text":"笔记标题","children":[...]}，text 用笔记标题，'
      + '标题为空时用「' + NoteMindMapPromptBuilder.ROOT_TEXT_FALLBACK + '」；'
      + '4）层级 2~' + NoteMindMapPromptBuilder.MAX_LEVEL_COUNT + ' 层：笔记原有的多级编号'
      + '（一、/ 1. / （1）等）与行首缩进必须如实映射成父子层级，不得跨级合并；'
      + '5）没有编号的散文，按语义归纳成 ' + NoteMindMapPromptBuilder.MIN_PROSE_BRANCHES
      + '~' + NoteMindMapPromptBuilder.MAX_PROSE_BRANCHES + ' 个一级分支，分支名用简短词组；'
      + '6）每个节点的 text 是关键词或短句，不超过 ' + NoteMindMapPromptBuilder.MAX_NODE_TEXT_CHARS
      + ' 个汉字；'
      + '7）只允许使用笔记中出现的事实与关键词，禁止新增事实、数字、人名或主观评价；'
      + '8）全文节点总数（含根）不超过 ' + NoteMindMapPromptBuilder.MAX_NODE_COUNT + ' 个；'
      + '9）正文为空时只输出根节点加一个 text 为「' + NoteMindMapPromptBuilder.EMPTY_NOTE_TEXT
      + '」的叶子。';
  }

  /**
   * user 角色：先给「笔记标题 + 原文照贴的正文」，再给输出契约（对应 system 的第 2~9 条），
   * 最后强调只输出这一个 JSON 对象。正文不做任何改写，原样嵌入。
   */
  static buildUserPrompt(noteTitle: string, noteContent: string): string {
    const rootText: string = NoteMindMapPromptBuilder.resolveRootText(noteTitle);
    const content: string = noteContent === null || noteContent === undefined ? '' : noteContent;
    const blank: boolean = NoteMindMapPromptBuilder.isBlankContent(noteContent);

    const lines: string[] = [];
    lines.push('请把下面这篇笔记转成思维导图节点 JSON。');
    lines.push('');
    lines.push('笔记标题：' + rootText);
    lines.push('笔记正文（原文照贴，不要改写）：');
    lines.push(content);
    lines.push('');
    lines.push('输出契约：');
    lines.push('1）只输出一个 JSON 对象，不要 markdown 围栏、不要代码块、不要解释文字、不要注释、不要尾逗号；');
    lines.push('2）节点固定为 {"id":"唯一字符串","text":"关键词或短句","children":[]}，'
      + 'children 是数组、叶子节点为空数组、id 全局唯一；');
    lines.push('3）根节点固定为 {"id":"root","text":"' + rootText + '","children":[...]}，'
      + 'text 用笔记标题（标题为空时用「' + NoteMindMapPromptBuilder.ROOT_TEXT_FALLBACK + '」）；');
    lines.push('4）层级 2~' + NoteMindMapPromptBuilder.MAX_LEVEL_COUNT
      + ' 层：笔记原有的多级编号（一、/ 1. / （1）等）与行首缩进要如实映射成父子层级，不得跨级合并；');
    lines.push('5）没有编号的散文归纳成 ' + NoteMindMapPromptBuilder.MIN_PROSE_BRANCHES
      + '~' + NoteMindMapPromptBuilder.MAX_PROSE_BRANCHES + ' 个一级分支，分支名用简短词组；');
    lines.push('6）每个节点的 text 不超过 ' + NoteMindMapPromptBuilder.MAX_NODE_TEXT_CHARS + ' 个汉字；');
    lines.push('7）只使用上面笔记里出现过的事实与关键词，不要新增事实、数字、人名或主观评价；');
    lines.push('8）全文节点总数（含根）不超过 ' + NoteMindMapPromptBuilder.MAX_NODE_COUNT
      + ' 个；正文为空时只输出根节点加一个 text 为「' + NoteMindMapPromptBuilder.EMPTY_NOTE_TEXT
      + '」的叶子。');
    if (blank) {
      lines.push('重要：本笔记正文为空，请只输出根节点与「' + NoteMindMapPromptBuilder.EMPTY_NOTE_TEXT
        + '」叶子，不要编造任何内容。');
    }
    lines.push('现在只输出这一个 JSON 对象。');
    return lines.join('\n');
  }

  /** 组装成 OpenAI 兼容的 messages 数组（system + user 两条） */
  static buildMessages(noteTitle: string, noteContent: string): ChatMessage[] {
    const messages: ChatMessage[] = [
      { role: 'system', content: NoteMindMapPromptBuilder.buildSystemPrompt() },
      { role: 'user', content: NoteMindMapPromptBuilder.buildUserPrompt(noteTitle, noteContent) }
    ];
    return messages;
  }

  /**
   * 组装完整请求体：走现有流式客户端（stream=true），在 onComplete 里拿全文再交给
   * MindMapJsonExtractor 提取。temperature 压到 0.3、max_tokens 给 1800，
   * 既保证结构忠实原文，又留够放 40 个节点的空间。
   */
  static buildRequest(noteTitle: string, noteContent: string, model: string): ChatCompletionRequest {
    const request: ChatCompletionRequest = {
      model: model,
      messages: NoteMindMapPromptBuilder.buildMessages(noteTitle, noteContent),
      stream: true,
      temperature: NoteMindMapPromptBuilder.TEMPERATURE,
      max_tokens: NoteMindMapPromptBuilder.MAX_TOKENS
    };
    return request;
  }
}
