// services/ai/RuleNoteMindMapBuilder.ets
// 纯逻辑：不调大模型，用确定性规则把「单篇笔记」解析成思维导图 JSON。
//
// 定位与 RuleMindMapBuilder（周复盘兜底）一致：无网、未配 Key、模型失败或返回不可解析时兜底，
// 保证「笔记转脑图」这个功能永远有产出。区别在输入——周复盘吃统计摘要（结构写死），本文件吃任意笔记文本，
// 层级不写死，而是按笔记自身的编号 / 项目符号 / 行首缩进推断。
//
// 输出形状是**裸根节点**（顶层就是 {id, text, children}）：与 MindMapJsonExtractor.normalize、
// 组件库 JsonSerializer.deserialize 接受的形态一致；不带 markdown 围栏、不套 {root:...} 信封。
//
// 无网络、无 UI、无随机、不取当前时间：同一篇笔记必得同一 JSON 字符串。
//
// 解析口径（逐条对应卡 C-01 第 4.2 节）：
//   1）「一、二、三、…十」「第X章 / 第X篇 / 第X部分」→ 1 级；「1. / 1、 / 1）」→ 2 级；
//      「（1） / (1) / 1.1」→ 3 级；「· / • / - / * / ‣」与行首 2 个以上空格缩进 → 在当前层级基础上再深一级
//      （最深 4 级）；同类标记连续出现即为同级（编号标记的级由标记类型直接决定，天然同级）。
//   2）整篇没有任何编号 / 项目符号标记时按散文处理：按空行分段，每段一个 1 级分支（段文字取前 20 汉字）；
//      只有一段时按 。！？ 切句，每句一个 1 级叶子，最多 6 句。
//   3）节点文字剥离标记与首尾空白；为空用「未命名」；超过 20 汉字截断。
//   4）根节点 text = 笔记标题，空标题用「笔记脑图」。
//   5）节点总数（含根）≤ 60、根之下最多 4 级；超出部分丢弃；正文为空时输出根 +「（空笔记）」叶子。
//
// 卡里没写死、由本实现补口径的两处（就近注释，便于独立复算时对齐）：
//   a）缩进 / 项目符号的「级」用缩进栈推断：同缩进同级、更深一级、回退时回到对应层级；
//      出现编号标记时清空缩进栈（编号的级是绝对的，旧的相对栈作废）。
//   b）标记模式下的普通行（既无编号也无符号）视为上一行的续行，挂到上一节点之下；同缩进互为同级。

/** 输出节点：与 MindMapJsonExtractor / 组件库 JsonSerializer.deserialize 同一形状 */
interface NoteRuleNode {
  id: string;
  text: string;
  children: NoteRuleNode[];
}

/** 待落地草稿：只描述结构与文字，id 交给 finalize 统一按「先父后子、同级从左到右」编号 */
interface NoteRuleDraft {
  text: string;
  children: NoteRuleDraft[];
}

/** 缩进栈的一帧：某个缩进宽度对应的「级」 */
interface NoteIndentFrame {
  indent: number;
  level: number;
}

/** 一行的标记解析结果 */
interface NoteLineMark {
  /** 编号标记给出的绝对层级：1 / 2 / 3；0 表示这行没有编号标记 */
  absoluteLevel: number;
  /** 是否为项目符号行（· / • / - / * / ‣） */
  bullet: boolean;
  /** 行首缩进宽度（空格与制表符个数） */
  indent: number;
  /** 剥离标记后的正文（未 trim） */
  text: string;
}

/** finalize 的待办：草稿 + 它要挂上去的已落地父节点 */
interface NoteFinalizeTask {
  draft: NoteRuleDraft;
  parent: NoteRuleNode;
}

export class RuleNoteMindMapBuilder {
  /** 根节点固定 id（与 MindMapJsonExtractor.ROOT_ID 一致） */
  static readonly ROOT_ID: string = 'root';
  /** 根节点文案兜底：笔记标题为空时使用 */
  static readonly ROOT_TEXT_FALLBACK: string = '笔记脑图';
  /** 空笔记兜底叶子文案 */
  static readonly EMPTY_NOTE_TEXT: string = '（空笔记）';
  /** 剥离标记后没有文字时的兜底文案 */
  static readonly UNNAMED_TEXT: string = '未命名';
  /** 单个节点文案上限（汉字个数） */
  static readonly MAX_TEXT_CHARS: number = 20;
  /** 节点总数上限（含根） */
  static readonly MAX_NODE_COUNT: number = 60;
  /** 「级」上限：根之下最多 4 级（对应卡里「最深 4 级」） */
  static readonly MAX_LEVEL: number = 4;
  /** 单段散文最多切出的句子数 */
  static readonly MAX_PROSE_SENTENCES: number = 6;
  /** 自动编号前缀：m0、m1、m2 …… */
  static readonly AUTO_ID_PREFIX: string = 'm';

  /** 项目符号字符集 */
  private static readonly BULLET_CHARS: string = '·•-*‣';
  /** 汉字数词（一、二、三……十） */
  private static readonly HAN_NUMERALS: string = '一二三四五六七八九十';
  /** 汉字数词后面允许的分隔符 */
  private static readonly HAN_DELIMITERS: string = '、,，.．)）';
  /** 阿拉伯数字编号后面允许的分隔符 */
  private static readonly NUM_DELIMITERS: string = '.、)）';
  /** 「第X章」里 X 允许的字符（阿拉伯数字 + 汉字数词） */
  private static readonly CHAPTER_NUMERALS: string = '0123456789一二三四五六七八九十百千零〇';
  /** 句末标点：按卡里说的句号 / 问号 / 感叹号切句 */
  private static readonly SENTENCE_ENDINGS: string = '。！？';
  /** 标记之后要一并剥掉的连接符与空白 */
  private static readonly MARK_PADDING: string = ' \t、.．)）:：';

  /** 行尾 \r 处理：兼容 CRLF 文本，保证同一篇笔记在 Windows / Unix 换行下结果一致 */
  private static stripCr(line: string): string {
    if (line.length > 0 && line.charAt(line.length - 1) === '\r') {
      return line.substring(0, line.length - 1);
    }
    return line;
  }

  /** 是否 ASCII 数字 */
  private static isDigit(ch: string): boolean {
    return ch.length === 1 && ch >= '0' && ch <= '9';
  }

  /** 「第X章 / 第X篇 / 第X部分」标记长度（0 表示不是这种标记） */
  private static chapterMarkLength(body: string): number {
    if (!body.startsWith('第')) {
      return 0;
    }
    let index: number = 1;
    while (index < body.length
      && RuleNoteMindMapBuilder.CHAPTER_NUMERALS.indexOf(body.charAt(index)) >= 0) {
      index += 1;
    }
    if (index === 1) {
      return 0; // 「第」后面必须有数字或汉字数词
    }
    if (body.startsWith('部分', index)) {
      return index + 2;
    }
    const unit: string = body.charAt(index);
    if (unit === '章' || unit === '篇') {
      return index + 1;
    }
    return 0;
  }

  /** 「（1） / (1) / 1.1」标记长度（0 表示不是这种标记） */
  private static subMarkLength(body: string): number {
    const first: string = body.length > 0 ? body.charAt(0) : '';
    if (first === '（' || first === '(') {
      let index: number = 1;
      while (index < body.length && RuleNoteMindMapBuilder.isDigit(body.charAt(index))) {
        index += 1;
      }
      if (index > 1) {
        const close: string = index < body.length ? body.charAt(index) : '';
        if (close === '）' || close === ')') {
          return index + 1;
        }
      }
    }
    // 1.1 这种点号分层：卡里归为 3 级
    let head: number = 0;
    while (head < body.length && RuleNoteMindMapBuilder.isDigit(body.charAt(head))) {
      head += 1;
    }
    if (head > 0 && head < body.length && body.charAt(head) === '.') {
      let tail: number = head + 1;
      while (tail < body.length && RuleNoteMindMapBuilder.isDigit(body.charAt(tail))) {
        tail += 1;
      }
      if (tail > head + 1) {
        return tail;
      }
    }
    return 0;
  }

  /** 「1. / 1、 / 1）」标记长度（0 表示不是这种标记） */
  private static numMarkLength(body: string): number {
    let index: number = 0;
    while (index < body.length && RuleNoteMindMapBuilder.isDigit(body.charAt(index))) {
      index += 1;
    }
    if (index === 0 || index >= body.length) {
      return 0;
    }
    if (RuleNoteMindMapBuilder.NUM_DELIMITERS.indexOf(body.charAt(index)) >= 0) {
      return index + 1;
    }
    return 0;
  }

  /** 「一、」标记长度（0 表示不是这种标记） */
  private static hanMarkLength(body: string): number {
    if (body.length < 2) {
      return 0;
    }
    if (RuleNoteMindMapBuilder.HAN_NUMERALS.indexOf(body.charAt(0)) < 0) {
      return 0;
    }
    if (RuleNoteMindMapBuilder.HAN_DELIMITERS.indexOf(body.charAt(1)) >= 0) {
      return 2;
    }
    return 0;
  }

  /** 是否项目符号行。「-3.5 分钟」这类负数开头的普通行不算符号行 */
  private static isBullet(body: string): boolean {
    if (body.length === 0) {
      return false;
    }
    const first: string = body.charAt(0);
    if (RuleNoteMindMapBuilder.BULLET_CHARS.indexOf(first) < 0) {
      return false;
    }
    if (first === '-' && body.length > 1 && RuleNoteMindMapBuilder.isDigit(body.charAt(1))) {
      return false;
    }
    return true;
  }

  /** 把标记后面的连接符与空白一并剥掉，避免节点文字以「、」「）」这类符号开头 */
  private static stripMarkPadding(text: string): string {
    let index: number = 0;
    while (index < text.length
      && RuleNoteMindMapBuilder.MARK_PADDING.indexOf(text.charAt(index)) >= 0) {
      index += 1;
    }
    return text.substring(index);
  }

  /** 解析一行：先量行首缩进，再按「编号 → 项目符号 → 普通行」的顺序认标记 */
  private static parseMark(rawLine: string): NoteLineMark {
    const line: string = RuleNoteMindMapBuilder.stripCr(rawLine);
    let indent: number = 0;
    while (indent < line.length && (line.charAt(indent) === ' ' || line.charAt(indent) === '\t')) {
      indent += 1;
    }
    const body: string = line.substring(indent);
    if (body.length === 0) {
      return { absoluteLevel: 0, bullet: false, indent: indent, text: '' };
    }

    const chapter: number = RuleNoteMindMapBuilder.chapterMarkLength(body);
    if (chapter > 0) {
      return {
        absoluteLevel: 1,
        bullet: false,
        indent: indent,
        text: RuleNoteMindMapBuilder.stripMarkPadding(body.substring(chapter))
      };
    }
    // 先判 3 级再判 2 级：1.1 也以「1.」开头，顺序反了会被吞成 2 级
    const sub: number = RuleNoteMindMapBuilder.subMarkLength(body);
    if (sub > 0) {
      return {
        absoluteLevel: 3,
        bullet: false,
        indent: indent,
        text: RuleNoteMindMapBuilder.stripMarkPadding(body.substring(sub))
      };
    }
    const num: number = RuleNoteMindMapBuilder.numMarkLength(body);
    if (num > 0) {
      return {
        absoluteLevel: 2,
        bullet: false,
        indent: indent,
        text: RuleNoteMindMapBuilder.stripMarkPadding(body.substring(num))
      };
    }
    const han: number = RuleNoteMindMapBuilder.hanMarkLength(body);
    if (han > 0) {
      return {
        absoluteLevel: 1,
        bullet: false,
        indent: indent,
        text: RuleNoteMindMapBuilder.stripMarkPadding(body.substring(han))
      };
    }
    if (RuleNoteMindMapBuilder.isBullet(body)) {
      return {
        absoluteLevel: 0,
        bullet: true,
        indent: indent,
        text: RuleNoteMindMapBuilder.stripMarkPadding(body.substring(1))
      };
    }
    return { absoluteLevel: 0, bullet: false, indent: indent, text: body };
  }

  /**
   * 相对层级（项目符号 / 普通行 / 缩进行走这里）：
   * 同缩进同级、更深一级、回退时回到栈里对应的层级；栈空时以最近的编号层级（没有则上一行层级）为基准再深一级。
   */
  private static relativeLevel(indent: number, lastLevel: number, numberedLevel: number,
    indentStack: NoteIndentFrame[]): number {
    while (indentStack.length > 0 && indentStack[indentStack.length - 1].indent > indent) {
      indentStack.pop();
    }
    if (indentStack.length > 0) {
      const top: NoteIndentFrame = indentStack[indentStack.length - 1];
      if (top.indent === indent) {
        return top.level;
      }
      const deeper: number = top.level + 1 > RuleNoteMindMapBuilder.MAX_LEVEL
        ? RuleNoteMindMapBuilder.MAX_LEVEL : top.level + 1;
      indentStack.push({ indent: indent, level: deeper });
      return deeper;
    }
    const base: number = numberedLevel > lastLevel ? numberedLevel : lastLevel;
    const level: number = base + 1 > RuleNoteMindMapBuilder.MAX_LEVEL
      ? RuleNoteMindMapBuilder.MAX_LEVEL : base + 1;
    indentStack.push({ indent: indent, level: level });
    return level;
  }

  /** 整篇是否存在编号 / 项目符号标记：存在就走「标记模式」，否则按散文处理 */
  private static hasStructuredMark(lines: string[]): boolean {
    for (let i = 0; i < lines.length; i++) {
      const mark: NoteLineMark = RuleNoteMindMapBuilder.parseMark(lines[i]);
      if (mark.absoluteLevel > 0 || mark.bullet) {
        return true;
      }
    }
    return false;
  }

  /**
   * 标记模式：逐行认标记、按级挂到父节点上。
   * 用 path[0] 当「根」的占位草稿，path 里第 n 个草稿正好是 n 级节点的候选父节点。
   */
  private static buildByMarks(lines: string[]): NoteRuleDraft[] {
    const rootChildren: NoteRuleDraft[] = [];
    const holder: NoteRuleDraft = { text: '', children: rootChildren };
    const path: NoteRuleDraft[] = [holder];

    let lastLevel: number = 0;
    let numberedLevel: number = 0;
    const indentStack: NoteIndentFrame[] = [];

    for (let i = 0; i < lines.length; i++) {
      const mark: NoteLineMark = RuleNoteMindMapBuilder.parseMark(lines[i]);
      if (mark.absoluteLevel === 0 && !mark.bullet && mark.text.trim().length === 0) {
        continue; // 空行、纯缩进行直接跳过
      }

      let level: number;
      if (mark.absoluteLevel > 0) {
        level = mark.absoluteLevel;
        numberedLevel = level;
        while (indentStack.length > 0) {
          indentStack.pop(); // 编号的级是绝对的，旧的相对缩进栈作废
        }
      } else {
        level = RuleNoteMindMapBuilder.relativeLevel(mark.indent, lastLevel, numberedLevel, indentStack);
      }

      while (path.length > level) {
        path.pop();
      }
      const draft: NoteRuleDraft = {
        text: RuleNoteMindMapBuilder.cleanText(mark.text),
        children: []
      };
      path[path.length - 1].children.push(draft);
      path.push(draft);
      lastLevel = level;
    }
    return rootChildren;
  }

  /** 按空行分段：返回每段的文字（段内多行用单个空格拼接） */
  private static splitParagraphs(lines: string[]): string[] {
    const paragraphs: string[] = [];
    let buffer: string = '';
    for (let i = 0; i < lines.length; i++) {
      const line: string = RuleNoteMindMapBuilder.stripCr(lines[i]).trim();
      if (line.length === 0) {
        if (buffer.length > 0) {
          paragraphs.push(buffer);
          buffer = '';
        }
      } else if (buffer.length === 0) {
        buffer = line;
      } else {
        buffer = buffer + ' ' + line;
      }
    }
    if (buffer.length > 0) {
      paragraphs.push(buffer);
    }
    return paragraphs;
  }

  /** 单段散文切句：按 。！？ 切，句末标点随句保留；末尾没有标点的残句也单独成句 */
  private static splitSentences(text: string): string[] {
    const sentences: string[] = [];
    let buffer: string = '';
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      buffer += ch;
      if (RuleNoteMindMapBuilder.SENTENCE_ENDINGS.indexOf(ch) >= 0) {
        const sentence: string = buffer.trim();
        if (sentence.length > 0) {
          sentences.push(sentence);
        }
        buffer = '';
      }
    }
    const rest: string = buffer.trim();
    if (rest.length > 0) {
      sentences.push(rest);
    }
    return sentences;
  }

  /** 散文模式：多段 → 每段一个 1 级分支；只有一段 → 切成句子的 1 级叶子（最多 6 句） */
  private static buildByProse(lines: string[]): NoteRuleDraft[] {
    const drafts: NoteRuleDraft[] = [];
    const paragraphs: string[] = RuleNoteMindMapBuilder.splitParagraphs(lines);

    if (paragraphs.length >= 2) {
      for (let i = 0; i < paragraphs.length; i++) {
        drafts.push({ text: RuleNoteMindMapBuilder.cleanText(paragraphs[i]), children: [] });
      }
      return drafts;
    }

    const only: string = paragraphs.length === 1 ? paragraphs[0] : '';
    const sentences: string[] = RuleNoteMindMapBuilder.splitSentences(only);
    const limit: number = sentences.length > RuleNoteMindMapBuilder.MAX_PROSE_SENTENCES
      ? RuleNoteMindMapBuilder.MAX_PROSE_SENTENCES : sentences.length;
    for (let i = 0; i < limit; i++) {
      drafts.push({ text: RuleNoteMindMapBuilder.cleanText(sentences[i]), children: [] });
    }
    if (drafts.length === 0) {
      drafts.push({ text: RuleNoteMindMapBuilder.EMPTY_NOTE_TEXT, children: [] });
    }
    return drafts;
  }

  /** 节点文字：trim → 空用「未命名」→ 超过 20 字截断 */
  private static cleanText(raw: string): string {
    const text: string = raw === null || raw === undefined ? '' : raw.trim();
    if (text.length === 0) {
      return RuleNoteMindMapBuilder.UNNAMED_TEXT;
    }
    if (text.length > RuleNoteMindMapBuilder.MAX_TEXT_CHARS) {
      return text.substring(0, RuleNoteMindMapBuilder.MAX_TEXT_CHARS);
    }
    return text;
  }

  /** 根节点文字：标题去空白后非空就用标题（同样受 20 字上限约束），否则用「笔记脑图」 */
  private static rootText(noteTitle: string): string {
    if (noteTitle === null || noteTitle === undefined) {
      return RuleNoteMindMapBuilder.ROOT_TEXT_FALLBACK;
    }
    const title: string = noteTitle.trim();
    if (title.length === 0) {
      return RuleNoteMindMapBuilder.ROOT_TEXT_FALLBACK;
    }
    if (title.length > RuleNoteMindMapBuilder.MAX_TEXT_CHARS) {
      return title.substring(0, RuleNoteMindMapBuilder.MAX_TEXT_CHARS);
    }
    return title;
  }

  /** 把草稿的子节点反序压栈：弹出顺序即「先父后子、同级从左到右」的先序 */
  private static pushChildren(draft: NoteRuleDraft, node: NoteRuleNode, stack: NoteFinalizeTask[]): void {
    for (let i = draft.children.length - 1; i >= 0; i--) {
      stack.push({ draft: draft.children[i], parent: node });
    }
  }

  /** 草稿树 → 契约树：根固定 id=root，其余按先序编 m0、m1…；节点总数超过 60 的部分整批丢弃 */
  private static finalize(rootDraft: NoteRuleDraft): NoteRuleNode {
    const root: NoteRuleNode = {
      id: RuleNoteMindMapBuilder.ROOT_ID,
      text: RuleNoteMindMapBuilder.cleanText(rootDraft.text),
      children: []
    };
    let emitted: number = 1;
    let seq: number = 0;
    const stack: NoteFinalizeTask[] = [];
    RuleNoteMindMapBuilder.pushChildren(rootDraft, root, stack);

    while (stack.length > 0) {
      if (emitted >= RuleNoteMindMapBuilder.MAX_NODE_COUNT) {
        break; // 到达上限：剩下的草稿全部丢弃
      }
      const task: NoteFinalizeTask | undefined = stack.pop();
      if (task === undefined) {
        break;
      }
      const node: NoteRuleNode = {
        id: RuleNoteMindMapBuilder.AUTO_ID_PREFIX + seq,
        text: RuleNoteMindMapBuilder.cleanText(task.draft.text),
        children: []
      };
      seq += 1;
      emitted += 1;
      task.parent.children.push(node);
      RuleNoteMindMapBuilder.pushChildren(task.draft, node, stack);
    }
    return root;
  }

  /**
   * 生成规则版笔记脑图 JSON（与模型输出同一形状、同一契约）。
   * 输出是**裸根节点**（顶层就是 {id, text, children}），可直接交给 MindMapJsonExtractor.normalize
   * 与组件库 JsonSerializer.deserialize；正文为空时输出根 +「（空笔记）」叶子，保证永远有产出。
   */
  static build(noteTitle: string, noteContent: string): string {
    const content: string = noteContent === null || noteContent === undefined ? '' : noteContent;
    let drafts: NoteRuleDraft[];
    if (content.trim().length === 0) {
      drafts = [{ text: RuleNoteMindMapBuilder.EMPTY_NOTE_TEXT, children: [] }];
    } else {
      const lines: string[] = content.split('\n');
      drafts = RuleNoteMindMapBuilder.hasStructuredMark(lines)
        ? RuleNoteMindMapBuilder.buildByMarks(lines)
        : RuleNoteMindMapBuilder.buildByProse(lines);
    }
    const rootDraft: NoteRuleDraft = { text: RuleNoteMindMapBuilder.rootText(noteTitle), children: drafts };
    return JSON.stringify(RuleNoteMindMapBuilder.finalize(rootDraft));
  }
}
