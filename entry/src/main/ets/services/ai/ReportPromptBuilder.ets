// services/ai/ReportPromptBuilder.ets
// 纯逻辑：把一周专注记录聚合为结构化摘要，并组装成大模型需要的 messages（提示词）。
// 不联网、不依赖 UI，给定同样的记录必得同样结果，可离线单测。

import { ChatMessage, ChatCompletionRequest } from './AiChatTypes';
import { StudySession } from '../LearningAnalysisService';

/** 一周学习数据的结构化摘要（同时也是喂给大模型的“事实底稿”，避免模型瞎编数字） */
export interface WeeklyDataSummary {
  /** 本周一 0 点时间戳（毫秒） */
  weekStart: number;
  /** 本周总专注分钟数 */
  thisWeekMinutes: number;
  /** 上周总专注分钟数 */
  lastWeekMinutes: number;
  /** 环比上周百分比（上周为 0 时记为 0），正为上升、负为下降 */
  changePercent: number;
  /** 本周专注次数 */
  sessionCount: number;
  /** 本周有专注记录的天数 */
  activeDays: number;
  /** 本周被中断的次数 */
  interruptedCount: number;
  /** 平均每次专注分钟数（无记录为 0） */
  avgSessionMinutes: number;
  /** 各科目分钟数：科目 -> 分钟 */
  tagMinutes: Map<string, number>;
}

/**
 * 周报提示词构造器（纯逻辑）。
 * 口径与 LearningAnalysisService.generateWeeklyReport 保持一致：以周一为一周起点。
 */
export class ReportPromptBuilder {
  /** 默认模型名（DeepSeek 的 OpenAI 兼容对话模型；可在设置里覆盖） */
  static readonly DEFAULT_MODEL: string = 'deepseek-chat';

  /** 计算本周一 0 点的时间戳（与规则版周报完全相同的口径，便于结果对照） */
  static getWeekStartTime(now: Date): number {
    const dayOfWeek = now.getDay() || 7; // 周日 getDay()=0，折算成 7
    const mondayOffset = (dayOfWeek - 1) * 24 * 60 * 60 * 1000;
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    weekStart.setTime(weekStart.getTime() - mondayOffset);
    weekStart.setHours(0, 0, 0, 0);
    return weekStart.getTime();
  }

  /** 把原始记录聚合为结构化周摘要 */
  static buildSummary(sessions: StudySession[], now: Date): WeeklyDataSummary {
    const weekStart = ReportPromptBuilder.getWeekStartTime(now);
    const lastWeekStart = weekStart - 7 * 24 * 60 * 60 * 1000;

    const thisWeek: StudySession[] = sessions.filter(s => s.startTime >= weekStart);
    const lastWeek: StudySession[] = sessions.filter(s =>
      s.startTime >= lastWeekStart && s.startTime < weekStart);

    const thisWeekMinutes = thisWeek.reduce((sum, s) => sum + s.duration, 0);
    const lastWeekMinutes = lastWeek.reduce((sum, s) => sum + s.duration, 0);

    const changePercent = lastWeekMinutes > 0
      ? ((thisWeekMinutes - lastWeekMinutes) / lastWeekMinutes) * 100
      : 0;

    const daySet = new Set<string>();
    const tagMinutes = new Map<string, number>();
    let interruptedCount = 0;

    thisWeek.forEach(s => {
      daySet.add(new Date(s.startTime).toDateString());
      if (s.isInterrupted) {
        interruptedCount += 1;
      }
      s.tags.forEach(tag => {
        tagMinutes.set(tag, (tagMinutes.get(tag) || 0) + s.duration);
      });
    });

    const sessionCount = thisWeek.length;
    const avgSessionMinutes = sessionCount > 0
      ? Math.round((thisWeekMinutes / sessionCount) * 10) / 10
      : 0;

    const summary: WeeklyDataSummary = {
      weekStart: weekStart,
      thisWeekMinutes: thisWeekMinutes,
      lastWeekMinutes: lastWeekMinutes,
      changePercent: Math.round(changePercent * 10) / 10,
      sessionCount: sessionCount,
      activeDays: daySet.size,
      interruptedCount: interruptedCount,
      avgSessionMinutes: avgSessionMinutes,
      tagMinutes: tagMinutes
    };
    return summary;
  }

  /** system 角色：限定模型的身份、语气和“只能依据给定数据、不许编造”的铁律 */
  static buildSystemPrompt(): string {
    return '你是一名温和、专业的学习教练。请严格依据用户提供的真实专注统计数据撰写本周学习周报，'
      + '所有数字必须来自给定数据，禁止编造不存在的记录或数字。'
      + '要求：分「总体情况 / 科目分布 / 专注质量 / 下周建议」四部分，使用中文，'
      + '多鼓励、建议具体可执行，整体 250 字以内，可适度使用 emoji。';
  }

  /** user 角色：把结构化摘要转成模型好理解的文字底稿 */
  static buildUserPrompt(summary: WeeklyDataSummary): string {
    const lines: string[] = [];
    lines.push('以下是我本周的真实专注统计（时长单位：分钟）：');
    lines.push(`- 本周总专注：${summary.thisWeekMinutes} 分钟；上周：${summary.lastWeekMinutes} 分钟；`
      + `环比 ${summary.changePercent > 0 ? '上升' : summary.changePercent < 0 ? '下降' : '持平'}`
      + ` ${Math.abs(summary.changePercent)}%`);
    lines.push(`- 专注次数：${summary.sessionCount} 次；覆盖 ${summary.activeDays} 天；`
      + `平均每次 ${summary.avgSessionMinutes} 分钟；被中断 ${summary.interruptedCount} 次`);

    if (summary.tagMinutes.size > 0) {
      const tagParts: string[] = [];
      summary.tagMinutes.forEach((minutes, tag) => {
        tagParts.push(`${tag} ${minutes} 分钟`);
      });
      lines.push(`- 各科目时长：${tagParts.join('，')}`);
    } else {
      lines.push('- 各科目时长：本周暂无科目标签记录');
    }

    if (summary.thisWeekMinutes === 0) {
      lines.push('注意：本周没有任何专注记录，请以鼓励我“尽快开始第一次专注”为主，不要虚构数据。');
    }
    lines.push('请据此生成本周学习周报。');
    return lines.join('\n');
  }

  /** 组装成 OpenAI 兼容的 messages 数组 */
  static buildMessages(summary: WeeklyDataSummary): ChatMessage[] {
    const messages: ChatMessage[] = [
      { role: 'system', content: ReportPromptBuilder.buildSystemPrompt() },
      { role: 'user', content: ReportPromptBuilder.buildUserPrompt(summary) }
    ];
    return messages;
  }

  /** 组装完整请求体（流式固定为 true） */
  static buildStreamRequest(summary: WeeklyDataSummary, model: string): ChatCompletionRequest {
    const request: ChatCompletionRequest = {
      model: model,
      messages: ReportPromptBuilder.buildMessages(summary),
      stream: true,
      temperature: 0.7,
      max_tokens: 600
    };
    return request;
  }
}
