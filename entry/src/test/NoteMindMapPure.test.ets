import { describe, it, expect } from '@ohos/hypium';
import { MindMapJsonExtractor, MindMapNode } from '../main/ets/services/ai/MindMapJsonExtractor';
import { NoteMindMapPromptBuilder } from '../main/ets/services/ai/NoteMindMapPromptBuilder';
import { RuleNoteMindMapBuilder } from '../main/ets/services/ai/RuleNoteMindMapBuilder';
import { ChatMessage, ChatCompletionRequest } from '../main/ets/services/ai/AiChatTypes';

/** 黄金笔记：一、→ 1 级，1. → 2 级，（1）→ 3 级，用来复算「编号如实映射层级」这条契约 */
function goldenNote(): string {
  return '一、学习计划\n'
    + '1. 基础语法\n'
    + '（1）变量与类型\n'
    + '（2）函数与类\n'
    + '2. 异步编程\n'
    + '二、实践安排\n';
}

/**
 * 把规则树 JSON 解析成根节点。
 * 输出契约是**裸节点**（顶层就是 {id, text, children}）：组件库 JsonSerializer.deserialize
 * 不认 {root:...} 包裹，所以这里连顶层键也一并断言死。
 */
function parseTree(json: string): MindMapNode {
  const parsed: MindMapNode = JSON.parse(json) as MindMapNode;
  expect(parsed.id).assertEqual('root');
  expect(Array.isArray(parsed.children)).assertTrue();
  const keys: string[] = Object.keys(parsed);
  expect(keys.join(',')).assertEqual('id,text,children');
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

export default function noteMindMapPureTest() {
  describe('NoteMindMapPure', () => {

    // ===================== NoteMindMapPromptBuilder =====================

    it('prompt_sameNoteShouldBuildIdenticalMessages', 0, () => {
      // 输入：同一篇笔记构造两次；输出：两条消息、角色固定，且两次结果逐字相同（无时间戳、无随机）
      const first: ChatMessage[] = NoteMindMapPromptBuilder.buildMessages('数学笔记', goldenNote());
      const second: ChatMessage[] = NoteMindMapPromptBuilder.buildMessages('数学笔记', goldenNote());
      expect(first.length).assertEqual(2);
      expect(first[0].role).assertEqual('system');
      expect(first[1].role).assertEqual('user');
      expect(first[0].content).assertEqual(second[0].content);
      expect(first[1].content).assertEqual(second[1].content);
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('prompt_systemShouldDemandJsonOnlyThreeFieldNodes', 0, () => {
      // 输入：无参构造 system 提示词；输出：只输出 JSON、禁围栏禁解释、三字段、层数/字数/节点数上限、空笔记兜底齐备
      const system: string = NoteMindMapPromptBuilder.buildSystemPrompt();
      expect(system).assertContain('只输出一个 JSON 对象');
      expect(system).assertContain('JSON');
      expect(system).assertContain('markdown');
      expect(system).assertContain('{id, text, children}');
      expect(system).assertContain('（1）');
      expect(system).assertContain('20 个汉字');
      expect(system).assertContain('40');
      expect(system).assertContain('（空笔记）');
    });

    it('prompt_userShouldKeepTitleAndContentVerbatim', 0, () => {
      // 输入：标题 + 一段正文；输出：user 里标题与正文原样出现（不改写），结尾要求只输出这一个 JSON
      const content: string = goldenNote();
      const user: string = NoteMindMapPromptBuilder.buildUserPrompt('数学笔记', content);
      expect(user).assertContain('笔记标题：数学笔记');
      expect(user).assertContain(content);
      expect(user).assertContain('输出契约');
      expect(user.trim().endsWith('现在只输出这一个 JSON 对象。')).assertTrue();
    });

    it('prompt_buildRequestShouldCarryFixedGenerationParams', 0, () => {
      // 输入：笔记 + 模型名；输出：stream=true、temperature=0.3、max_tokens=1800、model 透传、两条消息
      const request: ChatCompletionRequest =
        NoteMindMapPromptBuilder.buildRequest('数学笔记', goldenNote(), 'deepseek-chat');
      expect(request.stream).assertTrue();
      expect(request.temperature).assertEqual(0.3);
      expect(request.max_tokens).assertEqual(1800);
      expect(request.model).assertEqual('deepseek-chat');
      expect(request.messages.length).assertEqual(2);
      expect(JSON.stringify(NoteMindMapPromptBuilder.buildRequest('数学笔记', goldenNote(), 'deepseek-chat')))
        .assertEqual(JSON.stringify(request));
    });

    it('emptyInput_shouldFallBackWithoutThrowing', 0, () => {
      // 输入：空标题 + 空正文；输出：提示词里给出「笔记脑图」「（空笔记）」兜底口径，规则版给出根 +「（空笔记）」叶子
      const messages: ChatMessage[] = NoteMindMapPromptBuilder.buildMessages('', '');
      expect(messages.length).assertEqual(2);
      expect(messages[0].content).assertContain('（空笔记）');
      expect(messages[1].content).assertContain('笔记脑图');
      expect(messages[1].content).assertContain('（空笔记）');

      const tree: string = RuleNoteMindMapBuilder.build('', '');
      expect(tree).assertEqual('{"id":"root","text":"笔记脑图","children":['
        + '{"id":"m0","text":"（空笔记）","children":[]}]}');
      const root: MindMapNode = parseTree(tree);
      expect(root.text).assertEqual('笔记脑图');
      expect((root.children as MindMapNode[]).length).assertEqual(1);
      expect((root.children as MindMapNode[])[0].text).assertEqual('（空笔记）');
    });

    // ===================== RuleNoteMindMapBuilder：编号 / 符号层级 =====================

    it('ruleTree_numberedNoteShouldMapOneTwoThreeLevels', 0, () => {
      // 输入：一、/ 1. / （1）三级编号笔记；输出：根取标题，两个 1 级分支，2 级挂在对应 1 级下，3 级挂在 2 级下
      const tree: string = RuleNoteMindMapBuilder.build('数学笔记', goldenNote());
      expect(tree).assertEqual('{"id":"root","text":"数学笔记","children":['
        + '{"id":"m0","text":"学习计划","children":['
        + '{"id":"m1","text":"基础语法","children":['
        + '{"id":"m2","text":"变量与类型","children":[]},'
        + '{"id":"m3","text":"函数与类","children":[]}]},'
        + '{"id":"m4","text":"异步编程","children":[]}]},'
        + '{"id":"m5","text":"实践安排","children":[]}]}');

      const root: MindMapNode = parseTree(tree);
      expect(root.text).assertEqual('数学笔记');
      const branches: MindMapNode[] = root.children as MindMapNode[];
      expect(branches.length).assertEqual(2);
      expect(branches[0].text).assertEqual('学习计划');
      expect(branches[1].text).assertEqual('实践安排');
      const second: MindMapNode[] = branches[0].children as MindMapNode[];
      expect(second.length).assertEqual(2);
      expect(second[0].text).assertEqual('基础语法');
      expect(second[1].text).assertEqual('异步编程');
      const third: MindMapNode[] = second[0].children as MindMapNode[];
      expect(third.length).assertEqual(2);
      expect(third[0].text).assertEqual('变量与类型');
      expect(third[1].text).assertEqual('函数与类');
      expect(second[1].children?.length).assertEqual(0);
      expect(treeDepth(root)).assertEqual(4);
    });

    it('ruleTree_bulletLinesShouldStaySiblingsUnderNumberedParent', 0, () => {
      // 输入：1 级编号 + 三条同类项目符号（- 与 · 混用）；输出：三条符号并列挂在「计划」之下，不互相嵌套
      const tree: string = RuleNoteMindMapBuilder.build('列表笔记', '一、计划\n- 第一条\n· 第二条\n- 第三条\n');
      expect(tree).assertEqual('{"id":"root","text":"列表笔记","children":['
        + '{"id":"m0","text":"计划","children":['
        + '{"id":"m1","text":"第一条","children":[]},'
        + '{"id":"m2","text":"第二条","children":[]},'
        + '{"id":"m3","text":"第三条","children":[]}]}]}');
      const root: MindMapNode = parseTree(tree);
      expect((root.children as MindMapNode[])[0].children?.length).assertEqual(3);
      expect(treeDepth(root)).assertEqual(3);
    });

    it('ruleTree_indentedLinesShouldNestOneLevelDeeper', 0, () => {
      // 输入：编号下的 2 空格缩进行、以及缩进的项目符号；输出：都比上一行深一级，同级缩进互为同级
      const indentTree: string =
        RuleNoteMindMapBuilder.build('缩进笔记', '一、计划\n  细节一\n  细节二\n');
      expect(indentTree).assertEqual('{"id":"root","text":"缩进笔记","children":['
        + '{"id":"m0","text":"计划","children":['
        + '{"id":"m1","text":"细节一","children":[]},'
        + '{"id":"m2","text":"细节二","children":[]}]}]}');

      const nestedBullet: string = RuleNoteMindMapBuilder.build('嵌套', '- 甲\n  - 乙\n');
      expect(nestedBullet).assertEqual('{"id":"root","text":"嵌套","children":['
        + '{"id":"m0","text":"甲","children":[{"id":"m1","text":"乙","children":[]}]}]}');
      expect(treeDepth(parseTree(nestedBullet))).assertEqual(3);
    });

    it('ruleTree_shouldStripMarksAndClipTextTo20', 0, () => {
      // 输入：标记后带多余空白 + 25 字长句 + 3 级标记；输出：标记与首尾空白被剥离、长句截断到 20 字
      const long25: string = '一二三四五六七八九十一二三四五六七八九十一二三四五';
      expect(long25.length).assertEqual(25);
      const content: string = '一、   ' + long25 + '   \n（1）   变量与类型   \n';
      const tree: string = RuleNoteMindMapBuilder.build('学习方法', content);
      expect(tree.includes('一、')).assertFalse();
      expect(tree.includes('（1）')).assertFalse();
      const root: MindMapNode = parseTree(tree);
      const branches: MindMapNode[] = root.children as MindMapNode[];
      expect(branches.length).assertEqual(1);
      expect(branches[0].text).assertEqual(long25.substring(0, 20));
      expect((branches[0].text as string).length).assertEqual(20);
      const sub: MindMapNode[] = branches[0].children as MindMapNode[];
      expect(sub.length).assertEqual(1);
      expect(sub[0].text).assertEqual('变量与类型');
    });

    // ===================== RuleNoteMindMapBuilder：散文兜底 =====================

    it('ruleTree_proseParagraphsShouldMapToLevelOneBranches', 0, () => {
      // 输入：没有任何标记、三个空行分隔的段落；输出：一级分支数 = 段数，段文字取前 20 汉字
      const content: string = '今天学习了 ArkTS 的基础语法。\n\n'
        + '明天准备做一个小练习。\n\n'
        + '后天复习一遍。\n';
      const tree: string = RuleNoteMindMapBuilder.build('英语学习笔记', content);
      expect(tree).assertEqual('{"id":"root","text":"英语学习笔记","children":['
        + '{"id":"m0","text":"今天学习了 ArkTS 的基础语法。","children":[]},'
        + '{"id":"m1","text":"明天准备做一个小练习。","children":[]},'
        + '{"id":"m2","text":"后天复习一遍。","children":[]}]}');
      const root: MindMapNode = parseTree(tree);
      expect((root.children as MindMapNode[]).length).assertEqual(3);
      expect(treeDepth(root)).assertEqual(2);
      assertTreeInvariants(root, RuleNoteMindMapBuilder.MAX_TEXT_CHARS);
    });

    it('ruleTree_singleParagraphShouldSplitSentencesUpToSix', 0, () => {
      // 输入：只有一段散文；输出：按 。！？ 切句，每句一个 1 级叶子，最多 6 句
      const oneParagraph: string = '今天学习了 ArkTS 的基础语法。明天准备做一个小练习？后天复习一遍！';
      const single: MindMapNode = parseTree(RuleNoteMindMapBuilder.build('单段笔记', oneParagraph));
      const sentences: MindMapNode[] = single.children as MindMapNode[];
      expect(sentences.length).assertEqual(3);
      expect(sentences[0].text).assertEqual('今天学习了 ArkTS 的基础语法。');
      expect(sentences[1].text).assertEqual('明天准备做一个小练习？');
      expect(sentences[2].text).assertEqual('后天复习一遍！');

      const eightSentences: string = '第一句。第二句。第三句。第四句。第五句。第六句。第七句。第八句。';
      const capped: MindMapNode = parseTree(RuleNoteMindMapBuilder.build('多句', eightSentences));
      const leaves: MindMapNode[] = capped.children as MindMapNode[];
      expect(leaves.length).assertEqual(6);
      expect(leaves.length <= 6).assertTrue();
      expect(leaves[5].text).assertEqual('第六句。');
    });

    // ===================== RuleNoteMindMapBuilder：上限 / 确定性 / 形状 =====================

    it('ruleTree_hugeNoteShouldRespectSixtyNodeLimit', 0, () => {
      // 输入：61 个以上节点的长笔记；输出：节点总数（含根）截到 60，深度仍不超过 4 层，超出部分被丢弃
      let content: string = '一、总览\n';
      for (let i = 0; i < 30; i++) {
        content += '1. 主题' + i + '\n（1）要点\n';
      }
      const tree: string = RuleNoteMindMapBuilder.build('超长笔记', content);
      const root: MindMapNode = parseTree(tree);
      const nodeCount: number = assertTreeInvariants(root, RuleNoteMindMapBuilder.MAX_TEXT_CHARS);
      expect(nodeCount).assertEqual(RuleNoteMindMapBuilder.MAX_NODE_COUNT);
      expect(nodeCount).assertEqual(60);
      expect(nodeCount <= 60).assertTrue();
      expect(treeDepth(root)).assertEqual(4);
      expect(treeDepth(root) <= RuleNoteMindMapBuilder.MAX_LEVEL).assertTrue();
    });

    it('ruleTree_sameNoteTwiceShouldBeIdentical', 0, () => {
      // 输入：同一篇笔记连续 build 两次；输出：两次字符串逐字相同（确定性，无随机、无时间依赖）
      const first: string = RuleNoteMindMapBuilder.build('数学笔记', goldenNote());
      const second: string = RuleNoteMindMapBuilder.build('数学笔记', goldenNote());
      expect(first).assertEqual(second);
      expect(RuleNoteMindMapBuilder.build('', '')).assertEqual(RuleNoteMindMapBuilder.build('', ''));
      expect(RuleNoteMindMapBuilder.build('空杂讯', '\n\n  \n')).assertEqual(RuleNoteMindMapBuilder.build('空杂讯', '\n  \n\n'));
    });

    it('ruleTree_outputShouldBeBareRootNodeJson', 0, () => {
      // 输入：默认黄金笔记；输出：可被 JSON.parse，顶层就是根节点，三字段齐全、无 root 包裹、无 markdown 围栏
      const tree: string = RuleNoteMindMapBuilder.build('数学笔记', goldenNote());
      expect(tree.startsWith('{"id":"root","text":"数学笔记","children":[')).assertTrue();
      expect(tree.includes('{"root":')).assertFalse();
      expect(tree.includes('```')).assertFalse();
      const root: MindMapNode = parseTree(tree);
      expect(root.id).assertEqual('root');
      expect(root.text).assertEqual('数学笔记');
      const keys: string[] = Object.keys(root);
      expect(keys.length).assertEqual(3);
      expect(keys[0]).assertEqual('id');
      expect(keys[1]).assertEqual('text');
      expect(keys[2]).assertEqual('children');
      assertTreeInvariants(root, RuleNoteMindMapBuilder.MAX_TEXT_CHARS);
    });

    it('ruleTree_outputShouldSatisfyExtractorNormalize', 0, () => {
      // 输入：编号 / 符号 / 散文 / 空笔记四种产出；输出：全部原样通过 MindMapJsonExtractor.normalize（说明天然合规）
      expect(MindMapJsonExtractor.normalize(RuleNoteMindMapBuilder.build('数学笔记', goldenNote())))
        .assertEqual(RuleNoteMindMapBuilder.build('数学笔记', goldenNote()));
      expect(MindMapJsonExtractor.normalize(RuleNoteMindMapBuilder.build('列表笔记', '一、计划\n- 第一条\n')))
        .assertEqual(RuleNoteMindMapBuilder.build('列表笔记', '一、计划\n- 第一条\n'));
      expect(MindMapJsonExtractor.normalize(RuleNoteMindMapBuilder.build('散文', '今天学习了 ArkTS。\n\n明天继续复习。')))
        .assertEqual(RuleNoteMindMapBuilder.build('散文', '今天学习了 ArkTS。\n\n明天继续复习。'));
      expect(MindMapJsonExtractor.normalize(RuleNoteMindMapBuilder.build('', '')))
        .assertEqual(RuleNoteMindMapBuilder.build('', ''));
    });

    it('ruleTree_nodeIdsShouldBeUniqueAndInPreOrder', 0, () => {
      // 输入：黄金笔记；输出：根固定 root，其余 id 按「先父后子、同级从左到右」编 m0、m1…，且全局唯一
      const root: MindMapNode = parseTree(RuleNoteMindMapBuilder.build('数学笔记', goldenNote()));
      const ids: string[] = collectNodes(root).map((node: MindMapNode) => node.id as string);
      expect(ids.join(',')).assertEqual('root,m0,m1,m2,m3,m4,m5');
      expect(new Set<string>(ids).size).assertEqual(ids.length);
      expect(collectNodes(root).length).assertEqual(7);
    });
  });
}
