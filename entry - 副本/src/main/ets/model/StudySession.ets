// services/AIAnalysisService.ets
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

// 学习记录数据结构
export interface StudySession {
  id: string;
  startTime: number;
  duration: number; // 单位：分钟
  tags: string[];
  isInterrupted: boolean; // 是否被中断
  interruptCount: number; // 打断次数
}

// AI生成的报告结构
export interface AIReport {
  focusScore: number; // 专注力评分 0-100
  totalMinutes: number; // 总学习时长
  totalDays: number; // 学习天数
  avgDailyMinutes: number; // 日均学习时长
  tagDistribution: Map<string, number>; // 各标签时长分布
  bestTimeSegment: string; // 最佳学习时段
  suggestion: string; // 智能建议
  trend: 'up' | 'down' | 'stable'; // 专注趋势
}

export class AIAnalysisService {
  private static instance: AIAnalysisService;
  private context: Context | null = null;

  public static getInstance(): AIAnalysisService {
    if (!this.instance) {
      this.instance = new AIAnalysisService();
    }
    return this.instance;
  }

  // 初始化上下文（在EntryAbility中调用）
  init(context: Context) {
    this.context = context;
  }

  /**
   * 核心分析方法：基于历史学习数据生成智能报告
   * 不依赖外部模型，纯算法实现“类AI”分析效果
   */
  async generateReport(sessions: StudySession[]): Promise<AIReport> {
    if (sessions.length === 0) {
      return this.getEmptyReport();
    }

    // 1. 基础统计
    const totalMinutes = sessions.reduce((sum, s) => sum + s.duration, 0);
    const uniqueDays = new Set(sessions.map(s => new Date(s.startTime).toDateString())).size;
    const avgDaily = uniqueDays > 0 ? Math.round(totalMinutes / uniqueDays) : 0;

    // 2. 计算专注力评分（核心算法）
    // 维度1：平均单次专注时长（越长越好，基准45分钟）
    const avgDuration = totalMinutes / sessions.length;
    const durationScore = Math.min(100, (avgDuration / 45) * 100);

    // 维度2：中断率（中断越少越好）
    const interruptedSessions = sessions.filter(s => s.isInterrupted).length;
    const interruptRate = interruptedSessions / sessions.length;
    const interruptScore = Math.max(0, 100 - interruptRate * 100);

    // 维度3：规律性（学习时间间隔越规律越好）
    const sortedSessions = [...sessions].sort((a, b) => a.startTime - b.startTime);
    let regularityScore = 80; // 默认中等
    if (sortedSessions.length > 2) {
      const intervals: number[] = [];
      for (let i = 1; i < sortedSessions.length; i++) {
        intervals.push((sortedSessions[i].startTime - sortedSessions[i-1].startTime) / (1000 * 60 * 60));
      }
      const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      const variance = intervals.reduce((sum, val) => sum + Math.pow(val - avgInterval, 2), 0) / intervals.length;
      // 方差越小越规律
      regularityScore = Math.max(0, 100 - variance * 2);
    }

    // 综合专注力评分（加权平均）
    const focusScore = Math.round(
      durationScore * 0.4 +
        interruptScore * 0.35 +
        regularityScore * 0.25
    );

    // 3. 标签分布统计
    const tagMap = new Map<string, number>();
    sessions.forEach(session => {
      session.tags.forEach(tag => {
        const current = tagMap.get(tag) || 0;
        tagMap.set(tag, current + session.duration);
      });
    });

    // 4. 最佳学习时段分析
    const hourMap = new Map<number, number>(); // 小时 -> 学习时长
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

    // 5. 趋势分析（对比前7天和后7天）
    const trend = this.analyzeTrend(sessions);

    // 6. 生成智能建议（基于评分和标签分布）
    const suggestion = this.generateSuggestion(focusScore, tagMap, trend);

    return {
      focusScore,
      totalMinutes,
      totalDays: uniqueDays,
      avgDailyMinutes: avgDaily,
      tagDistribution: tagMap,
      bestTimeSegment,
      suggestion,
      trend
    };
  }

  /**
   * 趋势分析算法：对比近期数据判断专注力变化
   */
  private analyzeTrend(sessions: StudySession[]): 'up' | 'down' | 'stable' {
    const sorted = [...sessions].sort((a, b) => a.startTime - b.startTime);
    const midPoint = Math.floor(sorted.length / 2);
    if (midPoint < 2) return 'stable';

    const firstHalf = sorted.slice(0, midPoint);
    const secondHalf = sorted.slice(midPoint);

    const firstAvg = firstHalf.reduce((s, item) => s + item.duration, 0) / firstHalf.length;
    const secondAvg = secondHalf.reduce((s, item) => s + item.duration, 0) / secondHalf.length;

    const diff = ((secondAvg - firstAvg) / firstAvg) * 100;
    if (diff > 10) return 'up';
    if (diff < -10) return 'down';
    return 'stable';
  }

  /**
   * 智能建议生成器（基于数据分析结果）
   */
  private generateSuggestion(score: number, tagMap: Map<string, number>, trend: 'up' | 'down' | 'stable'): string {
    let suggestion = '';

    // 基于专注力评分
    if (score >= 80) {
      suggestion = '?? 专注状态极佳！建议保持当前节奏，尝试挑战更高难度科目。';
    } else if (score >= 60) {
      suggestion = '?? 专注状态良好，建议减少环境干扰，尝试45分钟番茄工作法。';
    } else if (score >= 40) {
      suggestion = '?? 专注力需要提升，建议开启「手表扬噪模式」减少手机干扰。';
    } else {
      suggestion = '?? 检测到较多中断，建议使用「分布式流转」将手机通知转移到手表，专注当前设备。';
    }

    // 基于趋势补充建议
    if (trend === 'down') {
      suggestion += '\\\\\\\\\\\\\\\\n?? 近期专注力呈下降趋势，建议适当增加休息频次，每25分钟休息5分钟。';
    } else if (trend === 'up') {
      suggestion += '\\\\\\\\\\\\\\\\n?? 专注力持续提升！继续坚持，可尝试延长单次专注时长。';
    }

    // 基于标签分布
    if (tagMap.size > 0) {
      let maxTag = '';
      let maxTime = 0;
      tagMap.forEach((time, tag) => {
        if (time > maxTime) {
          maxTime = time;
          maxTag = tag;
        }
      });
      suggestion += `\\\\\\\\\\\\\\\\n?? 你在「${maxTag}」上投入时间最多，共${Math.round(maxTime)}分钟。`;
    }

    return suggestion;
  }

  private getTimeSegment(hour: number): string {
    if (hour >= 6 && hour < 9) return '?? 清晨（6-9点）';
    if (hour >= 9 && hour < 12) return '?? 上午（9-12点）';
    if (hour >= 12 && hour < 14) return '??? 午间（12-14点）';
    if (hour >= 14 && hour < 18) return '?? 下午（14-18点）';
    if (hour >= 18 && hour < 21) return '?? 晚间（18-21点）';
    return '?? 深夜（21-6点）';
  }

  private getEmptyReport(): AIReport {
    return {
      focusScore: 0,
      totalMinutes: 0,
      totalDays: 0,
      avgDailyMinutes: 0,
      tagDistribution: new Map(),
      bestTimeSegment: '暂无数据',
      suggestion: '开始你的第一次专注学习吧！鸿蒙多端计时本将为你生成专属分析报告。',
      trend: 'stable'
    };
  }
}