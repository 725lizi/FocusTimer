// services/rag/QaPromptBuilder.ets
// 纯逻辑：构造给大模型的系统提示与用户提示。核心是「把模型关进材料里」：
// 只准依据提供的个人材料回答、材料不足要明说、引用处标注材料编号，从提示词层面压制幻觉。

export class QaPromptBuilder {
  /** 有材料时的系统约束 */
  static readonly SYSTEM_GROUNDED: string =
    '你是用户的专属学习助手，只能根据下面提供的「个人学习材料」回答问题。' +
    '要求：1）优先依据材料，不要编造材料里没有的事实；2）若材料不足以回答，明确说“你的笔记里没有足够相关内容”；' +
    '3）回答简洁有条理；4）凡用到某条材料，在该句末尾标注对应编号，如[材料1]。';

  /** 没有靠谱材料时的系统约束：诚实声明、可给通用建议但不得假装来自用户笔记 */
  static readonly SYSTEM_NO_EVIDENCE: string =
    '你是用户的学习助手。用户的个人笔记中没有检索到与问题相关的材料。' +
    '请先用一句话说明“没有在你的笔记里找到相关记录”，再在明确标注为通用建议的前提下给出有帮助的一般性回答，不得假装引用了用户笔记。';

  /** 有材料：拼上材料正文和问题 */
  static buildGroundedUserPrompt(question: string, contextBlock: string): string {
    return `个人学习材料：\n${contextBlock}\n\n问题：${question}\n请严格依据上述材料作答并标注材料编号。`;
  }

  /** 无材料：只带问题 */
  static buildNoEvidenceUserPrompt(question: string): string {
    return `问题：${question}`;
  }
}
