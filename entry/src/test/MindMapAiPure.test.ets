import { describe, it, expect } from '@ohos/hypium';
import {
  MindMapJsonExtractor,
  MindMapExtractError,
  MindMapExtractErrorCode,
  MindMapNode
} from '../main/ets/services/ai/MindMapJsonExtractor';
import { RuleMindMapBuilder } from '../main/ets/services/ai/RuleMindMapBuilder';
import { MindMapPromptBuilder } from '../main/ets/services/ai/MindMapPromptBuilder';
import { WeeklyDataSummary } from '../main/ets/services/ai/ReportPromptBuilder';
import { ChatMessage, ChatCompletionRequest } from '../main/ets/services/ai/AiChatTypes';

/** 构造一周摘要（默认给一份有数据、有环比、有科目、有一次中断的样本） */
function makeSummary(thisWeekMinutes: number, lastWeekMinutes: number, changePercent: number,
  sessionCount: number, activeDays: number, interruptedCount: number,
  avgSessionMinutes: number, tagMinutes: Map<string, number>): WeeklyDataSummary {
  const summary: WeeklyDataSummary = {
    weekStart: new Date(2026, 7, 24).getTime(),
    thisWeekMinutes: thisWeekMinutes,
    lastWeekMinutes: lastWeekMinutes,
    changePercent: changePercent,
    sessionCount: sessionCount,
    activeDays: activeDays,
    interruptedCount: interruptedCount,
    avgSessionMinutes: avgSessionMinutes,
    tagMinutes: tagMinutes
  };
  return summary;
}

/** 有数据样本：本周 150 分钟 / 上周 100 分钟 / 环比 +50% / 3 次 / 2 天 / 中断 1 次 / 平均 50 / 数学 80+英语 40+物理 30 */
function sampleSummary(): WeeklyDataSummary {
  const tags: Map<string, number> = new Map<string, number>();
  tags.set('数学', 80);
  tags.set('英语', 40);
  tags.set('物理', 30);
  return makeSummary(150, 100, 50, 3, 2, 1, 50, tags);
}

/** 零数据样本：全部为 0、无科目 */
function emptySummary(): WeeklyDataSummary {
  return makeSummary(0, 0, 0, 0, 0, 0, 0, new Map<string, number>());
}

/** 含长科目名的边界样本：8 字科目名 > 5 字「继续保持「」」的可用预算 */
function longTagSummary(): WeeklyDataSummary {
  const tags: Map<string, number> = new Map<string, number>();
  tags.set('高等数学分析专题', 60);
  tags.set('英语', 20);
  return makeSummary(80, 0, 0, 2, 1, 0, 40, tags);
}

/** 有数据但一个科目标签都没有：科目分布分支要走「暂无科目记录」路径 */
function noTagSummary(): WeeklyDataSummary {
  return makeSummary(60, 30, 100, 2, 2, 0, 30, new Map<string, number>());
}

/**
 * 把 normalize / RuleMindMapBuilder 的输出解析成根节点。
 * 输出契约是**裸节点**（顶层就是 {id, text, children}），所以这里直接返回解析结果，
 * 并对「顶层键只有 id/text/children、没有 root」做断言——组件库 JsonSerializer.deserialize
 * 不认 {root:...} 包裹，必须挡住这种形状回退。
 */
function parseTree(json: string): MindMapNode {
  const parsed: MindMapNode = JSON.parse(json) as MindMapNode;
  expect(parsed.id).assertEqual('root');
  expect(Array.isArray(parsed.children)).assertTrue();
  const extraKeys: string[] = Object.keys(parsed);
  expect(extraKeys.join(',')).assertEqual('id,text,children');
  return parsed;
}

/** 前序遍历收集全部节点（父在前、同级从左到右） */
function collectNodes(root: MindMapNode): MindMapNode[] {
  const out: MindMapNode[] = [];
  out.push(root);
  const children: MindMapNode[] | undefined = root.children;
  if (children !== undefined && Array.isArray(children)) {
    for (let i = 0; i < children.length; i++) {
      const sub: MindMapNode[] = collectNodes(children[i]);
      for (let j = 0; j < sub.length; j++) {
        out.push(sub[j]);
      }
    }
  }
  return out;
}

/** 树的最大深度（根单独算一层） */
function treeDepth(root: MindMapNode): number {
  let maxChildDepth: number = 0;
  const children: MindMapNode[] | undefined = root.children;
  if (children !== undefined && Array.isArray(children)) {
    for (let i = 0; i < children.length; i++) {
      const childDepth: number = treeDepth(children[i]);
      if (childDepth > maxChildDepth) {
        maxChildDepth = childDepth;
      }
    }
  }
  return maxChildDepth + 1;
}

/** 逐个校验节点：id 非空且唯一、text 非空且不超长、children 一定是数组 */
function assertTreeInvariants(root: MindMapNode, maxChars: number): number {
  const nodes: MindMapNode[] = collectNodes(root);
  const ids: string[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node: MindMapNode = nodes[i];
    const id: string = node.id === undefined ? '' : node.id;
    expect(id.length > 0).assertTrue();
    ids.push(id);
    const text: string = node.text === undefined ? '' : node.text;
    expect(text.length > 0).assertTrue();
    expect(text.length <= maxChars).assertTrue();
    expect(Array.isArray(node.children)).assertTrue();
  }
  expect(new Set<string>(ids).size).assertEqual(nodes.length);
  return nodes.length;
}

export default function mindMapAiPureTest() {
  describe('MindMapAiPure', () => {

    // ===================== MindMapJsonExtractor.extract =====================

    it('extractor_shouldStripJsonFence', 0, () => {
      // 输入：```json 围栏 + 换行 + JSON；输出：仅 JSON 对象文本
      const raw: string = '```json\n{"id":"root","text":"本周专注复盘","children":[]}\n```';
      const out: string = MindMapJsonExtractor.extract(raw);
      expect(out).assertEqual('{"id":"root","text":"本周专注复盘","children":[]}');
      expect(out.startsWith('{')).assertTrue();
      expect(out.includes('```')).assertFalse();
    });

    it('extractor_shouldPickJsonBetweenChatter', 0, () => {
      // 输入：前后都有口语；输出：首个 { 到末个 } 之间的内容，口语与后缀全被丢掉
      const raw: string = '好的，这是你要的思维导图：\n'
        + '{"root":{"id":"root","text":"本周专注复盘","children":[]}}\n'
        + '希望有帮助！还需要我调整吗？';
      const out: string = MindMapJsonExtractor.extract(raw);
      expect(out).assertEqual('{"root":{"id":"root","text":"本周专注复盘","children":[]}}');
      expect(out.includes('好的')).assertFalse();
      expect(out.includes('希望有帮助')).assertFalse();
    });

    it('extractor_pureJsonShouldPassThrough', 0, () => {
      // 输入：不带任何装饰的纯 JSON；输出：与输入完全一致
      const pure: string = '{"root":{"id":"root","text":"本周专注复盘","children":[{"id":"m0","text":"本周 150 分钟","children":[]}]}}';
      expect(MindMapJsonExtractor.extract(pure)).assertEqual(pure);
    });

    it('extractor_blankInputShouldThrowEmpty', 0, () => {
      // 输入：空白串；输出：抛 MindMapExtractError，code = EMPTY
      let caught: MindMapExtractError | null = null;
      try {
        MindMapJsonExtractor.extract('   \n\t ');
      } catch (err) {
        caught = err as MindMapExtractError;
      }
      expect(caught !== null).assertTrue();
      expect((caught as MindMapExtractError).code).assertEqual(MindMapExtractErrorCode.EMPTY);
      expect((caught as MindMapExtractError).name).assertEqual('MindMapExtractError');
    });

    it('extractor_textWithoutBracesShouldThrowNoJson', 0, () => {
      // 输入：一段没有大括号的说明文字；输出：抛 NO_JSON
      let caught: MindMapExtractError | null = null;
      try {
        MindMapJsonExtractor.extract('抱歉，我暂时无法生成思维导图。');
      } catch (err) {
        caught = err as MindMapExtractError;
      }
      expect(caught !== null).assertTrue();
      expect((caught as MindMapExtractError).code).assertEqual(MindMapExtractErrorCode.NO_JSON);
    });

    it('extractor_truncatedJsonShouldPassExtractButFailNormalize', 0, () => {
      // 输入：流式中断留下的截断 JSON——开头结尾都有括号，所以 extract 能取到内容，
      // 但中间被截断（children 数组没闭合），语法不合法
      const truncated: string = '{"root":{"id":"root","text":"本周专注复盘","children":[{"id":"m0","text":"总体情况"}';
      // extract 只做文本裁剪，不判断语法
      expect(MindMapJsonExtractor.extract(truncated)).assertEqual(truncated);
      // 真正的语法校验在 normalize：抛 INVALID
      let caught: MindMapExtractError | null = null;
      try {
        MindMapJsonExtractor.normalize(truncated);
      } catch (err) {
        caught = err as MindMapExtractError;
      }
      expect(caught !== null).assertTrue();
      expect((caught as MindMapExtractError).code).assertEqual(MindMapExtractErrorCode.INVALID);
    });

    it('extractor_onlyOpeningBraceShouldThrowNoJson', 0, () => {
      // 输入：连一个 } 都没有的残缺片段；输出：抛 NO_JSON（连截取区间都定不出来）
      const broken: string = '{"root":{"id":"root","text":"本周专注复盘","children":[{"id":"m0"';
      let caught: MindMapExtractError | null = null;
      try {
        MindMapJsonExtractor.extract(broken);
      } catch (err) {
        caught = err as MindMapExtractError;
      }
      expect(caught !== null).assertTrue();
      expect((caught as MindMapExtractError).code).assertEqual(MindMapExtractErrorCode.NO_JSON);
    });

    // ===================== MindMapJsonExtractor.normalize =====================

    it('normalize_duplicateIdsShouldBeReassignedByLevelOrder', 0, () => {
      // 输入：子节点 id 缺省、两个孙子 id 都写成 'dup'
      const raw: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"text":"总体情况","children":[{"id":"dup","text":"本周 150 分钟","children":[]},'
        + '{"id":"dup","text":"上周 100 分钟","children":[]}]},'
        + '{"id":"m0","text":"科目分布","children":[]}]}}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      // 输出：裸根节点（顶层无 root 键）。缺失 id 补号、重复 id 重排：
      // 原树里出现过的 id 会先被「预定」，所以缺省节点拿到 m1，第二个 'dup' 拿到下一个空闲号 m2
      expect(out).assertEqual('{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"m1","text":"总体情况","children":['
        + '{"id":"dup","text":"本周 150 分钟","children":[]},'
        + '{"id":"m2","text":"上周 100 分钟","children":[]}]},'
        + '{"id":"m0","text":"科目分布","children":[]}]}');
      const nodes: MindMapNode[] = collectNodes(parseTree(out));
      expect(nodes.length).assertEqual(5);
      // 根 id 固定 root，且所有 id 全局唯一
      expect(nodes[0].id).assertEqual('root');
      assertTreeInvariants(parseTree(out), MindMapJsonExtractor.MAX_TEXT_CHARS);
    });

    it('normalize_missingChildrenShouldBecomeEmptyArray', 0, () => {
      // 输入：叶子没有 children 字段，另一个节点的 children 被写成字符串
      const raw: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"a","text":"总体情况"},'
        + '{"id":"b","text":"科目分布","children":"不是数组"}]}}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      // 输出：两者都补/改正成 []，键序固定为 id/text/children
      expect(out).assertEqual('{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"a","text":"总体情况","children":[]},'
        + '{"id":"b","text":"科目分布","children":[]}]}');
      const root: MindMapNode = parseTree(out);
      expect(Array.isArray(root.children)).assertTrue();
      expect((root.children as MindMapNode[])[0].children?.length).assertEqual(0);
    });

    it('normalize_longTextShouldBeTruncatedTo24', 0, () => {
      // 输入：25 个字符的 text；输出：截断到 24 个字符、前半段保持不变
      const long: string = '一二三四五六七八九十一二三四五六七八九十一二三四五';
      expect(long.length).assertEqual(25);
      const raw: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"a","text":"' + long + '","children":[]}]}}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      const text: string = (parseTree(out).children as MindMapNode[])[0].text as string;
      expect(text.length).assertEqual(MindMapJsonExtractor.MAX_TEXT_CHARS);
      expect(text.length).assertEqual(24);
      expect(text).assertEqual(long.substring(0, 24));
    });

    it('normalize_shouldTrimTextAndFillBlank', 0, () => {
      // 输入：text 带首尾空格、另一个节点 text 为空串；输出：一个被 trim、一个补默认文案
      const raw: string = '{"root":{"id":"root","text":"  本周专注复盘  ","children":['
        + '{"id":"a","text":"  专注质量  ","children":[]},'
        + '{"id":"b","text":"   ","children":[]}]}}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      const children: MindMapNode[] = parseTree(out).children as MindMapNode[];
      expect(parseTree(out).text).assertEqual('本周专注复盘');
      expect(children[0].text).assertEqual('专注质量');
      expect((children[1].text as string).length > 0).assertTrue();
    });

    it('normalize_shouldAcceptBareNodeWithoutRootWrapper', 0, () => {
      // 输入：直接给一个裸节点（模型偶尔省略 root 包裹）；输出：裸节点，根 id 固定 root
      const raw: string = '{"id":"whatever","text":"本周专注复盘","children":[{"text":"总体情况"}]}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      const root: MindMapNode = parseTree(out);
      expect(root.id).assertEqual('root');
      expect(root.text).assertEqual('本周专注复盘');
      expect((root.children as MindMapNode[]).length).assertEqual(1);
      expect((root.children as MindMapNode[])[0].id).assertEqual('m0');
    });

    it('normalize_shouldAcceptEnvelopeAndBareNodeWithSameResult', 0, () => {
      // 同一棵树的两种输入形态：{root:...} 信封 与 裸节点；输出必须逐字一致（信封只在解析阶段被拆开）
      const envelope: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"m0","text":"总体情况","children":[{"id":"m1","text":"本周 150 分钟","children":[]}]},'
        + '{"id":"m2","text":"科目分布","children":[]}]}}';
      const bare: string = '{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"m0","text":"总体情况","children":[{"id":"m1","text":"本周 150 分钟","children":[]}]},'
        + '{"id":"m2","text":"科目分布","children":[]}]}';
      expect(MindMapJsonExtractor.normalize(envelope)).assertEqual(MindMapJsonExtractor.normalize(bare));
      // 且输出确实是裸节点
      expect(MindMapJsonExtractor.normalize(envelope)).assertEqual(bare);
      expect(MindMapJsonExtractor.normalize(bare)).assertEqual(bare);
    });

    it('normalize_outputShouldBeBareNodeWithoutRootKey', 0, () => {
      // 输出形状专项：顶层就是节点本身，键序 id/text/children，绝不能出现顶层 root 键
      const raw: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"id":"a","text":"总体情况","children":[]}]}}';
      const out: string = MindMapJsonExtractor.normalize(raw);
      expect(out.startsWith('{"id":"root","text":"本周专注复盘","children":[')).assertTrue();
      expect(out.includes('{"root":')).assertFalse();
      const root: MindMapNode = parseTree(out);
      expect(root.id).assertEqual('root');
      const keys: string[] = Object.keys(root);
      expect(keys.length).assertEqual(3);
      expect(keys[0]).assertEqual('id');
      expect(keys[1]).assertEqual('text');
      expect(keys[2]).assertEqual('children');
    });

    it('normalize_sameInputTwiceShouldBeIdentical', 0, () => {
      // 输入：同一段脏 JSON 连续规整两次；输出：两次字符串逐字相同（无随机、无时间依赖）
      const raw: string = '{"root":{"id":"root","text":"本周专注复盘","children":['
        + '{"text":"总体情况","children":[{"id":"x","text":"本周 150 分钟"}]},'
        + '{"text":"科目分布","children":[{"id":"x","text":"数学"}]}]}}';
      const first: string = MindMapJsonExtractor.normalize(raw);
      const second: string = MindMapJsonExtractor.normalize(raw);
      expect(first).assertEqual(second);
    });

    // ===================== RuleMindMapBuilder.build =====================

    it('ruleTree_shouldBeAcceptedByNormalizeAndKeepSameShape', 0, () => {
      // 输入：有数据的摘要；输出：规则树 JSON 原样通过 normalize（说明天然合规，不会被二次改写）
      const summary: WeeklyDataSummary = sampleSummary();
      const tree: string = RuleMindMapBuilder.build(summary);
      expect(MindMapJsonExtractor.normalize(tree)).assertEqual(tree);
    });

    it('ruleTree_shouldBeBareNodeWithoutRootKey', 0, () => {
      // 输出形状专项：顶层就是根节点，无 root 键，text 固定「本周专注复盘」
      const tree: string = RuleMindMapBuilder.build(sampleSummary());
      expect(tree.startsWith('{"id":"root","text":"本周专注复盘","children":[')).assertTrue();
      expect(tree.includes('{"root":')).assertFalse();
      expect(tree.includes('mindmap-harmonyos')).assertFalse();
      const root: MindMapNode = parseTree(tree);
      expect(root.id).assertEqual('root');
      expect(root.text).assertEqual('本周专注复盘');
      const keys: string[] = Object.keys(root);
      expect(keys.length).assertEqual(3);
      expect(keys[0]).assertEqual('id');
      expect(keys[1]).assertEqual('text');
      expect(keys[2]).assertEqual('children');
    });

    it('ruleTree_zeroDataShouldHaveFourBranches', 0, () => {
      // 输入：全零摘要；输出：四分支齐全、无任何编造数字、且仍通过 normalize
      const summary: WeeklyDataSummary = emptySummary();
      const tree: string = RuleMindMapBuilder.build(summary);
      expect(MindMapJsonExtractor.normalize(tree)).assertEqual(tree);

      const root: MindMapNode = parseTree(tree);
      expect(root.id).assertEqual('root');
      expect(root.text).assertEqual('本周专注复盘');
      const branches: MindMapNode[] = root.children as MindMapNode[];
      expect(branches.length).assertEqual(4);
      expect(branches[0].text).assertEqual('总体情况');
      expect(branches[1].text).assertEqual('科目分布');
      expect(branches[2].text).assertEqual('专注质量');
      expect(branches[3].text).assertEqual('下周行动');
      // 每个分支都必须有内容（叶子），不能是空壳
      expect(branches[0].children?.length).assertEqual(1);
      expect(branches[1].children?.length).assertEqual(1);
      expect(branches[2].children?.length).assertEqual(1);
      expect(branches[3].children?.length).assertEqual(2);
      // 零数据鼓励版：正文里一个数字都不许出现（节点 id 里的数字不算文案）
      const texts: string[] = collectNodes(root).map((n: MindMapNode) => n.text as string);
      expect(/[0-9]/.test(texts.join(''))).assertFalse();
    });

    it('ruleTree_shouldUseOnlySummaryNumbersAndKeepContract', 0, () => {
      // 输入：本周 150 / 上周 100 / 环比 50% / 3 次 / 2 天 / 中断 1 次 / 平均 50，科目 数学80 英语40 物理30
      const summary: WeeklyDataSummary = sampleSummary();
      const tree: string = RuleMindMapBuilder.build(summary);
      const root: MindMapNode = parseTree(tree);

      // 契约一：四个一级分支、顺序固定
      const branches: MindMapNode[] = root.children as MindMapNode[];
      expect(branches.length).assertEqual(4);
      expect(branches[0].text).assertEqual('总体情况');
      expect(branches[1].text).assertEqual('科目分布');
      expect(branches[2].text).assertEqual('专注质量');
      expect(branches[3].text).assertEqual('下周行动');
      // 契约二：根文案固定
      expect(root.text).assertEqual('本周专注复盘');

      // 契约三：数字全部来自 summary
      expect(tree.includes('本周 150 分钟')).assertTrue();
      expect(tree.includes('环比增加 50%')).assertTrue();
      expect(tree.includes('上周 100 分钟')).assertTrue();
      expect(tree.includes('平均每次 50 分钟')).assertTrue();
      expect(tree.includes('中断 1 次')).assertTrue();
      // 科目 Top3：数学 80 排第一，物理 30 作为第三名也必须在
      const tagBranch: MindMapNode[] = branches[1].children as MindMapNode[];
      expect(tagBranch[0].text).assertEqual('数学');
      expect(tagBranch[1].text).assertEqual('80 分钟');
      expect(tree.includes('物理')).assertTrue();
      // 契约四：节点总数与深度落在区间内，叶子文案不超长
      const nodeCount: number = assertTreeInvariants(root, RuleMindMapBuilder.MAX_TEXT_CHARS);
      expect(nodeCount >= MindMapPromptBuilder.MIN_NODE_COUNT).assertTrue();
      expect(nodeCount <= MindMapPromptBuilder.MAX_NODE_COUNT).assertTrue();
      const depth: number = treeDepth(root);
      expect(depth >= 2).assertTrue();
      expect(depth <= 3).assertTrue();
      // 契约五：同输入两次结果一致
      expect(RuleMindMapBuilder.build(sampleSummary())).assertEqual(tree);
    });

    it('ruleTree_longTagShouldStillFitLeafLimit', 0, () => {
      // 输入：8 字科目名（超出「继续保持「」」剩余预算）；输出：动作文案仍不超过 16 字且通过 normalize
      const summary: WeeklyDataSummary = longTagSummary();
      const tree: string = RuleMindMapBuilder.build(summary);
      expect(MindMapJsonExtractor.normalize(tree)).assertEqual(tree);
      assertTreeInvariants(parseTree(tree), RuleMindMapBuilder.MAX_TEXT_CHARS);
    });

    it('ruleTree_hasDataButNoTagsShouldStillKeepDepthAndContract', 0, () => {
      // 输入：有专注记录但没有任何科目标签（科目分布走占位路径）；输出：深度与节点数仍落在契约区间
      const summary: WeeklyDataSummary = noTagSummary();
      const tree: string = RuleMindMapBuilder.build(summary);
      expect(MindMapJsonExtractor.normalize(tree)).assertEqual(tree);
      expect(tree.includes('本周暂无科目记录')).assertTrue();
      // 环比 100% 来自 summary，且仍是同级叶子
      expect(tree.includes('环比增加 100%')).assertTrue();

      const root: MindMapNode = parseTree(tree);
      const nodeCount: number = assertTreeInvariants(root, RuleMindMapBuilder.MAX_TEXT_CHARS);
      expect(nodeCount >= MindMapPromptBuilder.MIN_NODE_COUNT).assertTrue();
      expect(nodeCount <= MindMapPromptBuilder.MAX_NODE_COUNT).assertTrue();
      const depth: number = treeDepth(root);
      expect(depth >= 2).assertTrue();
      expect(depth <= 3).assertTrue();
    });

    // ===================== MindMapPromptBuilder =====================

    it('prompt_shouldCarryExplicitJsonOnlyContract', 0, () => {
      // 输入：有数据摘要；输出：system 明令只输出 JSON 对象、禁围栏禁解释，user 带全部契约与真实数字
      const summary: WeeklyDataSummary = sampleSummary();
      const messages: ChatMessage[] = MindMapPromptBuilder.buildMessages(summary);
      expect(messages.length).assertEqual(2);
      expect(messages[0].role).assertEqual('system');
      expect(messages[1].role).assertEqual('user');

      const system: string = messages[0].content;
      expect(system).assertContain('只输出一个思维导图节点 JSON 对象');
      expect(system).assertContain('不要 markdown 围栏');
      expect(system).assertContain('不要任何解释文字');
      expect(system).assertContain('本周专注复盘');
      expect(system).assertContain('总体情况 / 科目分布 / 专注质量 / 下周行动');

      const user: string = messages[1].content;
      expect(user).assertContain('本周总专注：150 分钟');
      expect(user).assertContain('上周：100 分钟');
      expect(user).assertContain('环比增加 50%');
      expect(user).assertContain('数学 80 分钟');
    });

    it('prompt_messagesShouldBeDeterministic', 0, () => {
      // 输入：同一摘要两次构造；输出：messages 逐字相同（无时间戳、无随机）
      const first: ChatMessage[] = MindMapPromptBuilder.buildMessages(sampleSummary());
      const second: ChatMessage[] = MindMapPromptBuilder.buildMessages(sampleSummary());
      expect(first.length).assertEqual(second.length);
      expect(first[0].content).assertEqual(second[0].content);
      expect(first[1].content).assertEqual(second[1].content);
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('prompt_buildRequestShouldBeStreamedWithFixedParams', 0, () => {
      // 输入：零数据摘要 + 模型名；输出：stream=true、temperature 0.4、max_tokens 900，两条消息
      const request: ChatCompletionRequest = MindMapPromptBuilder.buildRequest(emptySummary(), 'deepseek-chat');
      expect(request.stream).assertTrue();
      expect(request.model).assertEqual('deepseek-chat');
      expect(request.temperature).assertEqual(0.4);
      expect(request.max_tokens).assertEqual(900);
      expect(request.messages.length).assertEqual(2);
      expect(JSON.stringify(MindMapPromptBuilder.buildRequest(emptySummary(), 'deepseek-chat')))
        .assertEqual(JSON.stringify(request));
    });

    it('prompt_zeroDataShouldStillAskForStructureWithoutFakeNumbers', 0, () => {
      // 输入：零数据摘要；输出：仍要求四分支齐全与鼓励起步，并明确禁止编造数字
      const summary: WeeklyDataSummary = emptySummary();
      const user: string = MindMapPromptBuilder.buildMessages(summary)[1].content;
      expect(user).assertContain('本周总专注：0 分钟');
      expect(user).assertContain('本周没有任何专注记录');
      expect(user).assertContain('四个分支仍要齐全');
      expect(user).assertContain('不得编造任何数字');
      expect(user).assertContain('总体情况 / 科目分布 / 专注质量 / 下周行动');
    });
  });
}
