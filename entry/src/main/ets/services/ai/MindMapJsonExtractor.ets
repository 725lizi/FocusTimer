// services/ai/MindMapJsonExtractor.ets
// 纯逻辑：把大模型返回的「思维导图 JSON」从脏文本里挖出来，再规整成前端一定能画的结构树。
//
// 为什么必须有两步：
//   1）extract —— 模型即使被要求“只输出 JSON”，流式返回里仍常带 ```json 围栏或前后口语，
//      直接 JSON.parse 必崩，所以先做文本层剥离与首尾括号裁剪；
//   2）normalize —— 模型给出的 id 可能缺失/重复、text 可能过长、children 可能写成 null，
//      这里统一补齐成 {id, text, children} 且键序固定，保证画图代码不用再做防御。
//
// 输出形状是**裸根节点**（顶层就是 {id, text, children}）：组件库 JsonSerializer.deserialize
// 只接受裸节点或 {format:'mindmap-harmonyos', version:1, root:{...}} 信封，本侧统一输出裸节点，
// 不补 format 字段走信封。模型若给出 {root:...} 包裹，只在解析阶段拆开，不影响输出形状。
//
// 全程无网络、无 UI、无随机：同一入参必得同一出参，可离线单测。

/** 提取阶段可能出现的错误类别 */
export enum MindMapExtractErrorCode {
  /** 模型返回是空字符串 / 只有空白 */
  EMPTY = 'EMPTY',
  /** 文本里找不到任何 JSON 对象（首尾大括号不存在） */
  NO_JSON = 'NO_JSON',
  /** 内容不是合法 JSON（截断、语法错误、根节点不是对象） */
  INVALID = 'INVALID'
}

/** 规整流程里可能出现的错误类别（规整失败只有“空内容 / 不是合法 JSON”两类） */
export type MindMapNormalizeErrorCode = MindMapExtractErrorCode.EMPTY | MindMapExtractErrorCode.INVALID;

/** 规整过程中的错误：带 code 便于上层决定是重试、降级还是直接提示 */
export class MindMapExtractError extends Error {
  /**
   * 错误类别。extract 可能抛 EMPTY / NO_JSON / INVALID 三类，
   * normalize 只会抛 EMPTY / INVALID（见 MindMapNormalizeErrorCode），
   * 因此这里用更宽的 MindMapExtractErrorCode 承接，避免 extract 抛 NO_JSON 时类型不兼容。
   */
  code: MindMapExtractErrorCode;

  constructor(code: MindMapExtractErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'MindMapExtractError';
  }
}

/** 思维导图节点（输入时字段可能缺失，输出时三者齐全） */
export interface MindMapNode {
  id?: string;
  text?: string;
  children?: MindMapNode[];
}

/**
 * 解析阶段使用的「{root: ...} 信封」中间态。
 * 只用于兼容模型偶尔给出的包裹写法，**不是输出形状**：
 * 最终输出统一是裸根节点，因为组件库 JsonSerializer.deserialize 只认裸节点
 * 或 {format:'mindmap-harmonyos', version:1, root:{...}} 两种输入。
 */
interface MindMapEnvelope {
  root: MindMapNode;
}

/** 规整过程中的中间结构：id/text/children 一定齐全 */
interface NormalizedNode {
  id: string;
  text: string;
  children: NormalizedNode[];
}

/** 规整过程的共享状态：已占用 id、原树预定 id、补号游标 */
interface NormalizeState {
  used: Set<string>;
  reserved: Set<string>;
  autoSeq: number;
}

export class MindMapJsonExtractor {
  /** 叶子/节点文案硬上限：超过即截断（契约里给模型的要求是 16 字，这里留出冗余到 24） */
  static readonly MAX_TEXT_CHARS: number = 24;
  /** 根节点固定 id */
  static readonly ROOT_ID: string = 'root';
  /** 自动补号前缀：m0、m1、m2 …… */
  static readonly AUTO_ID_PREFIX: string = 'm';

  /**
   * 从模型原文里挖出 JSON 对象文本。
   * 顺序：trim → 去掉 ```json / ``` 围栏 → 截取首个 { 到末个 } 之间的内容。
   * 找不到括号抛 NO_JSON，空串抛 EMPTY。
   */
  static extract(raw: string): string {
    if (raw === null || raw === undefined) {
      throw new MindMapExtractError(MindMapExtractErrorCode.EMPTY, '模型返回为空');
    }
    let text: string = raw.trim();
    if (text.length === 0) {
      throw new MindMapExtractError(MindMapExtractErrorCode.EMPTY, '模型返回为空');
    }

    text = MindMapJsonExtractor.stripFences(text).trim();
    if (text.length === 0) {
      throw new MindMapExtractError(MindMapExtractErrorCode.EMPTY, '模型返回只有代码围栏没有内容');
    }

    const start: number = text.indexOf('{');
    const end: number = text.lastIndexOf('}');
    if (start < 0 || end < 0 || end < start) {
      throw new MindMapExtractError(MindMapExtractErrorCode.NO_JSON, '返回内容里没有 JSON 对象');
    }
    return text.substring(start, end + 1);
  }

  /** 去掉 markdown 代码围栏：开头的 ```json / ``` 与结尾的 ``` 各去掉一次即可 */
  private static stripFences(text: string): string {
    let out: string = text;
    if (out.startsWith('```')) {
      const firstLineEnd: number = out.indexOf('\n');
      if (firstLineEnd >= 0) {
        // ```json 与正文在同一行的情况由后面的括号裁剪兜底
        out = out.substring(firstLineEnd + 1);
      } else {
        out = out.substring('```'.length);
      }
    }
    out = out.trim();
    if (out.endsWith('```')) {
      out = out.substring(0, out.length - '```'.length);
    }
    return out;
  }

  /**
   * JSON 文本 → 规范化 JSON 文本（裸根节点）。
   * 保证：根 id 固定 'root'；其余节点 id 缺失/重复时按层级重排为 m0、m1…；
   * text 一定是 trim 过、超长即截断的字符串；children 一定存在（叶子为空数组）；
   * 输出键序固定 id/text/children、顶层就是节点本身（不套 {root:...} 信封），同一入参必得同一字符串。
   * 入参两种形态都收：模型给裸节点、或给 {root:...} 信封（信封只在这里被拆开，不参与输出）。
   * parse 失败或根节点不是对象抛 INVALID。
   */
  static normalize(rawJson: string): string {
    if (rawJson === null || rawJson === undefined) {
      throw new MindMapExtractError(MindMapExtractErrorCode.EMPTY, '待规整内容为空');
    }
    const text: string = rawJson.trim();
    if (text.length === 0) {
      throw new MindMapExtractError(MindMapExtractErrorCode.EMPTY, '待规整内容为空');
    }

    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (err) {
      throw new MindMapExtractError(MindMapExtractErrorCode.INVALID, '不是合法 JSON');
    }
    // 容错：模型给裸节点（没有 root 包裹）或给 {root:...} 信封都能取到根节点
    const rawRoot: MindMapNode | null = MindMapJsonExtractor.pickRawRoot(parsed);
    if (rawRoot === null) {
      throw new MindMapExtractError(MindMapExtractErrorCode.INVALID, 'JSON 根节点不是对象');
    }

    // 先登记所有「原本就用过的 id」：这样重排出来的 m0/m1… 不会撞上后面还没处理到的节点，
    // 从而保证「同一入参必得同一结果」且 id 全局唯一（被顶掉的原 id 会被重新编号）。
    const reserved: Set<string> = new Set<string>();
    MindMapJsonExtractor.collectReservedIds(rawRoot, reserved);
    reserved.delete(MindMapJsonExtractor.ROOT_ID); // root 永远留给根节点

    const state: NormalizeState = {
      used: new Set<string>(),
      reserved: reserved,
      autoSeq: 0
    };
    const root: NormalizedNode = MindMapJsonExtractor.normalizeNode(rawRoot, true, state);
    // 直接输出裸根节点：组件库以此形态反序列化，顶层不再有 root 键
    return JSON.stringify(root);
  }

  /** 预扫描：收集原始树里所有非空字符串 id（不做去重，Set 天然去重） */
  private static collectReservedIds(node: MindMapNode, reserved: Set<string>): void {
    if (node === null || node === undefined || typeof node !== 'object') {
      return;
    }
    if (typeof node.id === 'string' && node.id.trim().length > 0) {
      reserved.add(node.id.trim());
    }
    const rawChildren: MindMapNode[] | undefined = node.children;
    if (Array.isArray(rawChildren)) {
      const list: MindMapNode[] = rawChildren as MindMapNode[];
      for (let i = 0; i < list.length; i++) {
        MindMapJsonExtractor.collectReservedIds(list[i], reserved);
      }
    }
  }

  /**
   * 依次尝试 parsed.root（{root:...} 信封）与 parsed 自身（裸节点），都拿不到对象就返回 null。
   * 入参是 JSON.parse 的原始结果，所以类型是 Object、内部再收窄。
   * 这是解析阶段的兼容逻辑，与输出形状无关——输出永远是裸根节点。
   */
  private static pickRawRoot(parsed: Object): MindMapNode | null {
    if (parsed === null || parsed === undefined || typeof parsed !== 'object') {
      return null;
    }
    const envelope: MindMapEnvelope = parsed as MindMapEnvelope;
    const wrapped: MindMapNode | undefined = envelope.root;
    if (wrapped !== null && wrapped !== undefined && typeof wrapped === 'object') {
      return wrapped;
    }
    const bare: MindMapNode = parsed as MindMapNode;
    if (typeof bare.text === 'string') {
      return bare;
    }
    return null;
  }

  /** 单个节点的取值：只接受非空字符串，其余（含 null/undefined）一律用兜底值 */
  private static readString(value: string | undefined, fallback: string): string {
    if (typeof value !== 'string') {
      return fallback;
    }
    return value;
  }

  /** text 规整：trim；空则兜底为「专注记录」；超过 24 字符直接截断 */
  private static normalizeText(value: string | undefined): string {
    const text: string = MindMapJsonExtractor.readString(value, '').trim();
    if (text.length === 0) {
      return '专注记录';
    }
    if (text.length > MindMapJsonExtractor.MAX_TEXT_CHARS) {
      return text.substring(0, MindMapJsonExtractor.MAX_TEXT_CHARS);
    }
    return text;
  }

  /** id 规整：trim 后非空、未被占用、且不抢 root 才保留；否则返回空串交由重排逻辑补号 */
  private static normalizeId(value: string | undefined, used: Set<string>): string {
    const id: string = MindMapJsonExtractor.readString(value, '').trim();
    if (id.length === 0) {
      return '';
    }
    if (id === MindMapJsonExtractor.ROOT_ID) {
      // 'root' 专属根节点，非根节点即使写了也视为冲突
      return '';
    }
    if (used.has(id)) {
      return '';
    }
    return id;
  }

  /** 依次取 m0、m1、m2…：跳过已使用与被预定的编号，取到即占用，天然唯一 */
  private static nextAutoId(state: NormalizeState): string {
    let candidate: string = '';
    while (true) {
      candidate = MindMapJsonExtractor.AUTO_ID_PREFIX + state.autoSeq;
      state.autoSeq += 1;
      if (!state.used.has(candidate) && !state.reserved.has(candidate)
        && candidate !== MindMapJsonExtractor.ROOT_ID) {
        return candidate;
      }
    }
  }

  /**
   * 递归规整一个节点（状态放在 NormalizeState 里，避免静态类残留实例字段）。
   * 层级重排策略：根固定 'root'；其余节点沿用合法且不重复的原 id，
   * 缺失或重复的按层序（先父后子、同级从左到右）依次补 m0、m1……
   * 由于父节点先于子节点处理，补出的编号天然与树的前序遍历一致。
   */
  private static normalizeNode(raw: MindMapNode, isRoot: boolean,
    state: NormalizeState): NormalizedNode {
    const text: string = MindMapJsonExtractor.normalizeText(raw.text);

    let id: string;
    if (isRoot) {
      id = MindMapJsonExtractor.ROOT_ID;
    } else {
      id = MindMapJsonExtractor.normalizeId(raw.id, state.used);
      if (id.length === 0) {
        id = MindMapJsonExtractor.nextAutoId(state);
      }
    }
    state.used.add(id);

    const children: NormalizedNode[] = [];
    const rawChildren: MindMapNode[] | undefined = raw.children;
    if (Array.isArray(rawChildren)) {
      const list: MindMapNode[] = rawChildren as MindMapNode[];
      for (let i = 0; i < list.length; i++) {
        const child: MindMapNode = list[i];
        if (child === null || child === undefined || typeof child !== 'object') {
          continue; // 数组里混进 null/字符串等脏数据：跳过而不是崩溃
        }
        children.push(MindMapJsonExtractor.normalizeNode(child, false, state));
      }
    }

    const node: NormalizedNode = { id: id, text: text, children: children };
    return node;
  }
}
