/**
 * 轻量 Markdown 渲染（纯逻辑，不依赖任何系统 API，可离线单测）。
 *
 * 背景：规则引擎与大模型返回的周报都用 Markdown 的「**文字**」表示加粗，
 * 但 ArkUI 的 Text 不会解析 Markdown，会把星号原样显示成「**总体情况**」，既不整洁也没有加粗效果。
 * 这里只做一件事：把一段文本按 ** 切成若干片段，标记每段是否应加粗；
 * 界面层再用 Text + Span 按 bold 决定字重，从而「既去掉星号、又保留加粗层次」。
 *
 * 刻意只支持加粗这一种语法（YAGNI）：周报里没有标题/列表/代码块等更多 Markdown 需求，
 * 不引入完整 Markdown 库，保持零依赖、可测、好懂。
 */

/** 一段文本及其是否加粗 */
export interface TextSpan {
  text: string;
  bold: boolean;
}

export class MarkdownLite {
  /**
   * 把含 **加粗** 标记的文本解析成片段数组。
   * 规则：
   *  - 以 ** 切分，第 0、2、4… 段为普通文本，第 1、3、5… 段为加粗文本；
   *  - 空片段跳过（例如相邻 ** 或首尾 ** 不产生空段）；
   *  - 若 ** 个数为奇数（存在没闭合的 **），最后一段按普通文本处理，避免后半段被错误地整段加粗。
   */
  public static parseBoldSpans(input: string): TextSpan[] {
    const spans: TextSpan[] = [];
    if (input === null || input === undefined || input.length === 0) {
      return spans;
    }

    const parts: string[] = input.split('**');
    // parts.length 为偶数 => ** 出现奇数次 => 最后一个 ** 没有配对的闭合符
    const hasUnclosedBold: boolean = (parts.length % 2 === 0);

    for (let i = 0; i < parts.length; i++) {
      const segment: string = parts[i];
      if (segment.length === 0) {
        continue;
      }
      let bold: boolean = (i % 2 === 1);
      if (bold && hasUnclosedBold && i === parts.length - 1) {
        // 未闭合的尾部片段不当作加粗
        bold = false;
      }
      spans.push({ text: segment, bold: bold });
    }
    return spans;
  }

  /**
   * 仅去除 ** 标记、不做加粗（兜底/纯文本场景用），保证输出里绝不残留星号。
   */
  public static stripBoldMarkers(input: string): string {
    if (input === null || input === undefined) {
      return '';
    }
    return input.split('**').join('');
  }
}
