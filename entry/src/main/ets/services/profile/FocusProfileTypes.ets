// services/profile/FocusProfileTypes.ets
// 模型分工：本文件是确定性数据结构（Schema），不联网、不依赖系统 API，由 DeepSeek 负责。
// 专注画像（Focus Profile）模块共用的纯数据类型，可完整离线单测。

/** 画像时间窗口：近 7 天 / 近 30 天（滚动窗口，以当前时刻为基准往前推） */
export type ProfileWindow = 7 | 30;

/** 统计事实的种类：每条事实对应一个可人工复算的指标 */
export type FocusFactType =
  | 'total_minutes'      // 窗口内总专注分钟
  | 'avg_daily_minutes'  // 日均专注分钟
  | 'category_share'     // 某类别时长占比
  | 'segment_share'      // 某时段时长占比
  | 'session_duration'   // 单次时长（均值/中位数）
  | 'frequency'          // 记录频率
  | 'week_change';       // 周际变化（仅 30 天窗口）

/**
 * 一条统计事实（证据对象）。
 * 画像里每条 AI 洞察都通过 evidence_ids 引用这些事实 id，
 * 点开就能看到结论是根据哪些原始记录、用什么口径算出来的。
 */
export interface FocusFact {
  /** 事实唯一 id，洞察的 evidence_ids 引用它 */
  id: string;
  /** 事实种类 */
  type: FocusFactType;
  /** 给人看的标签（如「总专注时长」「高数占比」） */
  label: string;
  /** 事实数值（分钟、百分比、次数等） */
  value: number;
  /** 数值单位：分钟 / 百分比 / 次 */
  unit: string;
  /** 支撑该事实的原始专注记录 id 列表，保证可追溯 */
  sourceSessionIds: string[];
  /** 计算口径说明（人话）；数据不足、推算或做过清洗时在这里标明 */
  calcNote: string;
}

/** 类别分布项：某个标签（科目）的时长与占比 */
export interface CategoryShare {
  /** 类别名（标签）；空标签统一归到「未分类」 */
  category: string;
  /** 该类别总分钟 */
  minutes: number;
  /** 占窗口总时长百分比，0~100，保留一位小数 */
  share: number;
}

/** 时段分布项：某个时段的时长与占比 */
export interface SegmentShare {
  /** 时段稳定标识（如 morning / noon），便于程序处理 */
  segmentKey: string;
  /** 时段中文名（如「上午（9-12点）」） */
  label: string;
  /** 该时段总分钟 */
  minutes: number;
  /** 占窗口总时长百分比，0~100，保留一位小数 */
  share: number;
}

/** 一个窗口的确定性统计结果（全部由程序现算，不掺 AI 推断） */
export interface FocusProfileStatsResult {
  /** 窗口天数 7 / 30 */
  windowDays: ProfileWindow;
  /** 窗口起始时间戳（含） */
  windowStart: number;
  /** 窗口结束时间戳（=传入的当前时刻） */
  windowEnd: number;
  /** 纳入统计的记录条数（样本量） */
  sampleSize: number;
  /** 有专注记录的天数（按本地零点切分去重） */
  activeDays: number;
  /** 总专注分钟 */
  totalMinutes: number;
  /** 日均专注分钟 = 总时长 / 窗口天数（注意分母是 7 或 30，不是 activeDays） */
  avgDailyMinutes: number;
  /** 类别分布，按分钟降序 */
  categoryShares: CategoryShare[];
  /** 时段分布，固定 6 个时段顺序，无记录的时段分钟为 0 */
  segmentShares: SegmentShare[];
  /** 平均单次专注分钟，保留一位小数 */
  avgSessionDuration: number;
  /** 单次专注分钟中位数，保留一位小数 */
  medianSessionDuration: number;
  /** 平均每活跃天记录条数（记录频率），保留一位小数 */
  sessionsPerActiveDay: number;
  /** 周际变化百分比（最近 7 天 vs 再往前 7 天）；无法计算时为 NaN，调用方需自行判空 */
  weekOverWeekChange: number;
  /** 是否数据不足（样本量或活跃天数过少），为 true 时不据此下确定性结论 */
  insufficientData: boolean;
  /** 全部统计事实（带 id 的证据对象），AI 洞察只引用这里的事实 */
  facts: FocusFact[];
}

/**
 * 洞察来源：严格区分三类，防止把本地规则兜底误说成云端 AI 成功。
 * llm=云端 AI 生成且证据校验通过；rule=本地规则引擎生成（含无网/无 Key/AI 出错后的降级）；
 * insufficient=数据不足，只给提示、不硬下规律结论。
 */
export type InsightSource = 'llm' | 'rule' | 'insufficient';

/** 一条证据化专注洞察：结论 + 支撑它的事实 id + 可执行行动建议 */
export interface FocusInsight {
  /** 洞察 id */
  id: string;
  /** 所属窗口天数 */
  windowDays: ProfileWindow;
  /** 结论正文（人话，一句话讲清规律） */
  summary: string;
  /** 支撑该结论的事实 id 列表（引用 FocusFact.id，非空且必须真实存在） */
  evidenceIds: string[];
  /** 基于该规律的行动建议（可执行的一句话） */
  action: string;
  /** 来源：llm / rule / insufficient */
  source: InsightSource;
}

/** 一个窗口的完整洞察包：洞察列表 + 整体来源 + 给用户的提示 */
export interface FocusInsightBundle {
  /** 所属窗口天数 */
  windowDays: ProfileWindow;
  /** 整体来源；数据不足时为 insufficient，规则兜底为 rule，AI 成功为 llm */
  source: InsightSource;
  /** 洞察列表（数据不足时也至少有一条提示性洞察） */
  insights: FocusInsight[];
  /** 给用户的提示（降级原因、数据不足说明等，正常成功时为空字符串） */
  hint: string;
  /** 生成时间戳（毫秒） */
  generatedAt: number;
}
