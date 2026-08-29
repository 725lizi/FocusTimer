// services/LearningAnalysisService.ets
export interface DocumentParseResult {
  keywords: string[];
  summary: string;
}
// 学习记录数据结构
export interface StudySession {
  id: string;
  startTime: number;
  duration: number;
  tags: string[];
  isInterrupted: boolean;
  interruptCount: number;
}

// 学习分析生成的报告结构（当前为规则模板，阶段2再接入大模型）
export interface LearningReport {
  focusScore: number;
  totalMinutes: number;
  totalDays: number;
  avgDailyMinutes: number;
  tagDistribution: Map<string, number>;
  bestTimeSegment: string;
  suggestion: string;
  trend: 'up' | 'down' | 'stable';
}

/**
 * 学习分析服务。当前实现是本地规则模板（按统计阈值算分、拼建议，不联网、不调大模型）；
 * 阶段 2 将在保持对外方法不变的前提下新增大模型实现，并做到「无网自动回退规则版」。
 * 刻意不命名为 AI，正是为了和未来真正接入的大模型能力区分开。
 */
export class LearningAnalysisService {
  private static instance: LearningAnalysisService | null = null;
  private context: Context | null = null;

  private constructor() {
    // 私有构造函数，防止外部实例化
  }

  public static getInstance(): LearningAnalysisService {
    if (LearningAnalysisService.instance === null) {
      LearningAnalysisService.instance = new LearningAnalysisService();
    }
    return LearningAnalysisService.instance;
  }

  init(context: Context): void {
    this.context = context;
  }

  async generateReport(sessions: StudySession[]): Promise<LearningReport> {
    if (sessions.length === 0) {
      return this.getEmptyReport();
    }

    const totalMinutes = sessions.reduce((sum, s) => sum + s.duration, 0);
    const uniqueDays = new Set(sessions.map(s => new Date(s.startTime).toDateString())).size;
    const avgDaily = uniqueDays > 0 ? Math.round(totalMinutes / uniqueDays) : 0;

    const avgDuration = totalMinutes / sessions.length;
    const durationScore = Math.min(100, (avgDuration / 45) * 100);

    const interruptedSessions = sessions.filter(s => s.isInterrupted).length;
    const interruptRate = interruptedSessions / sessions.length;
    const interruptScore = Math.max(0, 100 - interruptRate * 100);

    const sortedSessions = [...sessions].sort((a, b) => a.startTime - b.startTime);
    let regularityScore = 80;
    if (sortedSessions.length > 2) {
      const intervals: number[] = [];
      for (let i = 1; i < sortedSessions.length; i++) {
        intervals.push((sortedSessions[i].startTime - sortedSessions[i-1].startTime) / (1000 * 60 * 60));
      }
      const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      const variance = intervals.reduce((sum, val) => sum + Math.pow(val - avgInterval, 2), 0) / intervals.length;
      regularityScore = Math.max(0, 100 - variance * 2);
    }

    const focusScore = Math.round(
      durationScore * 0.4 +
        interruptScore * 0.35 +
        regularityScore * 0.25
    );

    const tagMap = new Map<string, number>();
    sessions.forEach(session => {
      session.tags.forEach(tag => {
        const current = tagMap.get(tag) || 0;
        tagMap.set(tag, current + session.duration);
      });
    });

    const hourMap = new Map<number, number>();
    sessions.forEach(session => {
      const hour = new Date(session.startTime).getHours();
      const current = hourMap.get(hour) || 0;
      hourMap.set(hour, current + session.duration);
    });
    let bestHour = 0;
    let bestDuration = 0;
    hourMap.forEach((duration, hour) => {
      if (duration > bestDuration) {
        bestDuration = duration;
        bestHour = hour;
      }
    });
    const bestTimeSegment = this.getTimeSegment(bestHour);
    const trend = this.analyzeTrend(sessions);
    const suggestion = this.generateSuggestion(focusScore, tagMap, trend);

    return {
      focusScore: focusScore,
      totalMinutes: totalMinutes,
      totalDays: uniqueDays,
      avgDailyMinutes: avgDaily,
      tagDistribution: tagMap,
      bestTimeSegment: bestTimeSegment,
      suggestion: suggestion,
      trend: trend
    };
  }

  private analyzeTrend(sessions: StudySession[]): 'up' | 'down' | 'stable' {
    const sorted = [...sessions].sort((a, b) => a.startTime - b.startTime);
    const midPoint = Math.floor(sorted.length / 2);
    if (midPoint < 2) {
      return 'stable';
    }

    const firstHalf = sorted.slice(0, midPoint);
    const secondHalf = sorted.slice(midPoint);

    const firstAvg = firstHalf.reduce((s, item) => s + item.duration, 0) / firstHalf.length;
    const secondAvg = secondHalf.reduce((s, item) => s + item.duration, 0) / secondHalf.length;

    if (firstAvg === 0) {
      return 'stable';
    }

    const diff = ((secondAvg - firstAvg) / firstAvg) * 100;
    if (diff > 10) {
      return 'up';
    }
    if (diff < -10) {
      return 'down';
    }
    return 'stable';
  }

  private generateSuggestion(score: number, tagMap: Map<string, number>, trend: 'up' | 'down' | 'stable'): string {
    let suggestion = '';

    if (score >= 80) {
      suggestion = '🌟 专注状态极佳！建议保持当前节奏，尝试挑战更高难度科目。';
    } else if (score >= 60) {
      suggestion = '✨ 专注状态良好，建议减少环境干扰，尝试45分钟番茄工作法。';
    } else if (score >= 40) {
      suggestion = '💡 专注力需要提升，建议开启「手表扬噪模式」减少手机干扰。';
    } else {
      suggestion = '🔔 检测到较多中断，建议使用「分布式流转」将手机通知转移到手表，专注当前设备。';
    }

    if (trend === 'down') {
      suggestion += '\n💡 近期专注力呈下降趋势，建议适当增加休息频次，每25分钟休息5分钟。';
    } else if (trend === 'up') {
      suggestion += '\n🚀 专注力持续提升！继续坚持，可尝试延长单次专注时长。';
    }

    if (tagMap.size > 0) {
      let maxTag = '';
      let maxTime = 0;
      tagMap.forEach((time, tag) => {
        if (time > maxTime) {
          maxTime = time;
          maxTag = tag;
        }
      });
      suggestion += `\n📚 你在「${maxTag}」上投入时间最多，共${Math.round(maxTime)}分钟。`;
    }

    return suggestion;
  }

  private getTimeSegment(hour: number): string {
    if (hour >= 6 && hour < 9) {
      return '🌅 清晨（6-9点）';
    }
    if (hour >= 9 && hour < 12) {
      return '☀️ 上午（9-12点）';
    }
    if (hour >= 12 && hour < 14) {
      return '🌤️ 午间（12-14点）';
    }
    if (hour >= 14 && hour < 18) {
      return '🌇 下午（14-18点）';
    }
    if (hour >= 18 && hour < 21) {
      return '🌆 晚间（18-21点）';
    }
    return '🌙 深夜（21-6点）';
  }

  private getEmptyReport(): LearningReport {
    return {
      focusScore: 0,
      totalMinutes: 0,
      totalDays: 0,
      avgDailyMinutes: 0,
      tagDistribution: new Map<string, number>(),
      bestTimeSegment: '暂无数据',
      suggestion: '开始你的第一次专注学习吧！鸿蒙多端计时本将为你生成专属分析报告。',
      trend: 'stable'
    };
  }

  /**
   * 提取笔记关键词
   * @param noteContent 笔记内容
   * @returns 关键词列表
   */
  public async extractNoteKeywords(noteContent: string): Promise<string[]> {
    if (!noteContent || noteContent.trim().length === 0) {
      return [];
    }

    const keywords: string[] = [];

    // 检测数学公式（含 $...$ 或 LaTeX 语法）
    const formulaPattern = /(\$[^$]+\$)|(\\[a-zA-Z]+(\{[^}]*\})*)|(\d+[-+*/=]\d+)/g;

    const formulas = noteContent.match(formulaPattern);
    if (keywords.length < 15 && formulas) {
      formulas.slice(0, 5).forEach(f => {
        keywords.push(`📐 公式: ${f.length > 30 ? f.substring(0, 30) + '...' : f}`);
      });
    }

    // 检测英文专业名词
    const englishTermPattern = /\b[A-Z][a-z]*(?:\s+[A-Z][a-z]*)*\b/g;
    const englishTerms = noteContent.match(englishTermPattern);
    if (englishTerms) {
      englishTerms.slice(0, 5).forEach(t => {
        keywords.push(`🔤 术语: ${t}`);
      });
    }

    // 检测中文关键词（2-6字，统计频率）
    const chinesePattern = /[\u4e00-\u9fa5]{2,6}/g;
    const chineseWords = noteContent.match(chinesePattern);
    if (chineseWords) {
      const wordFrequency: Map<string, number> = new Map();
      const stopWords = new Set(['这个', '那个', '我们', '你们', '他们', '因为', '所以', '但是', '然而',
        '然后', '于是', '如果', '那么', '不过', '只是', '还是', '或者', '以及',
        '一个', '什么', '怎么', '为什么', '可以', '没有', '进行', '通过']);

      chineseWords.forEach(word => {
        if (stopWords.has(word)) return;
        wordFrequency.set(word, (wordFrequency.get(word) || 0) + 1);
      });

      const sortedWords = Array.from(wordFrequency.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 8)
        .map(entry => `🔑 ${entry[0]} (×${entry[1]})`);
      keywords.push(...sortedWords);
    }

    return keywords;
  }

  /**
   * 离线课件解析：从文本中提取知识点和提纲
   * @param documentText 课件文本内容
   * @returns 解析结果 { keywords: string[], summary: string }
   */
  public async parseDocument(documentText: string): Promise<DocumentParseResult> {
    if (!documentText || documentText.trim().length === 0) {
      const emptyResult: DocumentParseResult = { keywords: [], summary: '' };
      return emptyResult;
    }

    const keywords = await this.extractNoteKeywords(documentText);

    let summary = '';
    if (keywords.length > 0) {
      const topKeywords = keywords.slice(0, 3).map(k => k.replace(/^[^\u4e00-\u9fa5A-Za-z]+/, ''));
      summary = `本课件重点涵盖：${topKeywords.join('、')}。建议优先掌握以上知识点。`;
    } else {
      summary = '未能自动提取有效知识点，请手动标记重点。';
    }

    const result: DocumentParseResult = { keywords: keywords, summary: summary };
    return result;
  }

  /**
   * 根据历史学习习惯推荐番茄时长
   * @param sessions 历史学习记录
   * @returns 推荐的番茄时长（分钟）
   */
  public recommendPomodoroDuration(sessions: StudySession[]): number {
    if (sessions.length < 3) {
      return 25; // 默认25分钟
    }

    const durations = sessions.map(s => s.duration);
    durations.sort((a, b) => a - b);

    const median = durations[Math.floor(durations.length / 2)];
    const avg = durations.reduce((a, b) => a + b, 0) / durations.length;

    const recommended = Math.min(median, avg);
    const rounded = Math.ceil(recommended / 5) * 5;

    return Math.max(15, Math.min(90, rounded));
  }

  /**
   * 生成更详细的学习周报
   */
  public async generateWeeklyReport(sessions: StudySession[]): Promise<string> {
    if (sessions.length === 0) {
      return '📊 本周暂无学习记录，开始你的第一次专注吧！';
    }

    const weekStart = this.getWeekStartTime();
    const thisWeekSessions = sessions.filter(s => s.startTime >= weekStart);
    const lastWeekStart = weekStart - 7 * 24 * 60 * 60 * 1000;
    const lastWeekSessions = sessions.filter(s => s.startTime >= lastWeekStart && s.startTime < weekStart);

    const thisWeekTotal = thisWeekSessions.reduce((sum, s) => sum + s.duration, 0);
    const lastWeekTotal = lastWeekSessions.reduce((sum, s) => sum + s.duration, 0);

    let report = '📊 本周学习报告\n\n';
    report += `总学习时长：${this.formatDuration(thisWeekTotal)}\n`;

    if (lastWeekTotal > 0) {
      const changePercent = ((thisWeekTotal - lastWeekTotal) / lastWeekTotal * 100);
      if (changePercent > 10) {
        report += `🚀 较上周提升 ${changePercent.toFixed(1)}%，保持良好！\n`;
      } else if (changePercent < -10) {
        report += `⚠️ 较上周下降 ${Math.abs(changePercent).toFixed(1)}%，注意调整节奏。\n`;
      } else {
        report += `✅ 与上周基本持平，保持稳定。\n`;
      }
    }

    const tagMap = new Map<string, number>();
    thisWeekSessions.forEach(session => {
      session.tags.forEach(tag => {
        tagMap.set(tag, (tagMap.get(tag) || 0) + session.duration);
      });
    });

    if (tagMap.size > 0) {
      report += '\n各科情况：\n';
      tagMap.forEach((minutes, tag) => {
        report += `• ${tag}：${this.formatDuration(minutes)}\n`;
      });
    }

    report += '\n💡 智能建议：\n';
    const avgDailyMinutes = thisWeekSessions.length > 0 ? thisWeekTotal / 7 : 0;
    if (avgDailyMinutes < 30) {
      report += '⚠️ 日均学习时间偏少，建议保持每日至少30分钟专注。\n';
    } else if (avgDailyMinutes > 240) {
      report += '⚠️ 日均学习时间较长，注意劳逸结合。\n';
    } else {
      report += '✅ 学习节奏良好，继续保持！\n';
    }

    return report;
  }

  private getWeekStartTime(): number {
    const now = new Date();
    const dayOfWeek = now.getDay() || 7;
    const mondayOffset = (dayOfWeek - 1) * 24 * 60 * 60 * 1000;
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    weekStart.setTime(weekStart.getTime() - mondayOffset);
    weekStart.setHours(0, 0, 0, 0);
    return weekStart.getTime();
  }

  private formatDuration(minutes: number): string {
    const hours = Math.floor(minutes / 60);
    const remainMinutes = Math.round(minutes % 60);
    if (hours > 0) {
      return `${hours}小时${remainMinutes}分钟`;
    }
    return `${remainMinutes}分钟`;
  }
}