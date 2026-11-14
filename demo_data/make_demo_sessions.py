#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# make_demo_sessions.py —— 「专注画像」合成演示数据集生成器（可复现）
#
# 【声明】本脚本生成的全部记录都是**脚本合成的演示数据**：
#   * 不是真实用户数据，不含任何真实个人隐私，不代表任何真实学习行为；
#   * 仅用于 FocusProfileStats / FocusInsightRules 的功能演示、联调与验收；
#   * 不做健康/心理判断，不产生「效率提升百分比」之类的结论，也不编造因果。
#
# 【可复现】不使用随机数、不读取系统当前时间；所有时间戳都由固定日期 +
#   固定东八区（UTC+8）换算成毫秒。因此在任何机器、任何时区运行，
#   生成的 startTime 与文件内容都逐字节一致。
#
# 【运行】python make_demo_sessions.py
#
# 【输出】与本脚本同目录：
#   demo_sessions.json        7 天窗口主演示数据集（纯 StudySession 数组，可 JSON.parse）
#   demo_sessions.jsonc       同一份数据的带注释版本（头部注释 + 相同数据，便于人读）
#   demo_sessions_30d.json    30 天窗口数据集（= 7 天数据集 + 更早 23 天的记录）
#   study_data_demo           preferences 格式 XML（无扩展名，7 天集）—— 备用，不要求部署
#   study_data_demo_30d       preferences 格式 XML（无扩展名，30 天集）—— 备用，不要求部署
#
# 【口径】字段与 StudySession 完全一致（6 个字段，见 LearningAnalysisService.ets）：
#   id / startTime / duration / tags / isInterrupted / interruptCount
#   统计口径与 FocusProfileStats.ets 一致：按 startTime 归属窗口与日期、
#   一条记录不跨日拆分、时段按开始小时归属整条时长、多标签时长均摊、
#   保留一位小数（与 ArkTS 的 Math.round(x*10)/10 相同）。
# =============================================================================

import json
import math
import os
from datetime import datetime, timedelta, timezone

# ---------------------------------------------------------------------------
# 0. 固定锚点与常量（改这里会改变整份数据，改动后请同步更新 demo_data_readme.md）
# ---------------------------------------------------------------------------
YEAR = 2026
# 固定东八区：不依赖运行机器的时区，保证时间戳稳定
TZ = timezone(timedelta(hours=8))
# 「现在」= 2026-11-13（周五）18:00，周四/周五的记录都排在 18:00 之前
ANCHOR = datetime(YEAR, 11, 13, 18, 0, 0, tzinfo=TZ)
NOW_MS = int(round(ANCHOR.timestamp())) * 1000
DAY_MS = 24 * 60 * 60 * 1000

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
EXTREME_DURATION_MINUTES = 480      # 与引擎一致：>480 分钟视为可疑极端值（保留并标注）
UNCATEGORIZED = '未分类'

# 固定 6 个时段（顺序与 FocusProfileStats.segmentDefs() 一致）
SEGMENT_ORDER = ['dawn', 'morning', 'noon', 'afternoon', 'evening', 'night']
SEGMENT_LABEL = {
    'dawn': '清晨（6-9点）',
    'morning': '上午（9-12点）',
    'noon': '午间（12-14点）',
    'afternoon': '下午（14-18点）',
    'evening': '晚间（18-21点）',
    'night': '深夜（21-6点）',
}

# =============================================================================
# 1. 记录设计
#
#    每条记录写成元组：(月, 日, 时, 分, 时长分钟, 标签数组, 是否中断, 中断次数)
#    id 由脚本按「日期 + 当天序号」自动生成（demo-YYYYMMDD-NN）。
#
#    设计目标（对应验收要求）：
#      * 4 个科目类别 + 少量空标签（未分类）+ 1 条双标签（高数/英语，演示均摊）
#      * 稀疏天（1 条）与密集天（4~5 条）交错，能直接看出每天记录条数的差异
#      * 6 个时段全覆盖，且「上午」明显占比最高（即使剔除极端值仍然最高）
#      * 单次时长含短(5~15)/中(25~40)/长(60+) 与 1 条 485 分钟极端值
#      * 2 条 isInterrupted=True（中断 1 次、2 次），1 条跨午夜记录（23:10 起）
# =============================================================================

# ---------------------------------------------------------------------------
# 1.1 「更早两周」10-16 ~ 10-29：合计 405 分钟、7 条，密度低（平均两三天 1 条）
#     作用：让 30 天窗口有足够长的历史，且不影响「最近 7 天 vs 前 7 天」的口径。
# ---------------------------------------------------------------------------
EARLIER_RECORDS = [
    # 10-16 周五 · 1 条（稀疏）
    (10, 16, 20, 0, 50, ['英语']),
    # 10-18 周日 · 2 条（稀疏）
    (10, 18, 10, 30, 75, ['高数']),
    (10, 18, 16, 0, 40, ['物理']),
    # 10-21 周三 · 1 条（稀疏，空标签 → 未分类）
    (10, 21, 13, 30, 30, []),
    # 10-24 周六 · 1 条（稀疏，长时段）
    (10, 24, 9, 0, 120, ['专业课']),
    # 10-27 周二 · 1 条（稀疏，深夜）
    (10, 27, 22, 10, 35, ['英语']),
    # 10-29 周四 · 1 条（稀疏）
    (10, 29, 19, 30, 55, ['高数']),
]

# ---------------------------------------------------------------------------
# 1.2 「前一周」10-31 ~ 11-06：合计 580 分钟、10 条，整体比最近 7 天稀疏
#     作用：30 天窗口的周际变化 = (1276 − 580) / 580 × 100 = +120.0（可人工复算）。
#     注意：所有记录都在 11-06 18:00 之前，才不会被算进「最近 7 天」。
#     11-03 周二刻意留空（0 条），演示「某天完全没有记录」。
# ---------------------------------------------------------------------------
PREV_WEEK_RECORDS = [
    # 10-31 周六 · 1 条（稀疏）
    (10, 31, 20, 10, 45, ['英语']),
    # 11-01 周日 · 2 条（稀疏）
    (11, 1, 9, 40, 30, ['高数']),
    (11, 1, 14, 50, 25, ['物理']),
    # 11-02 周一 · 1 条（稀疏，深夜）
    (11, 2, 21, 40, 40, ['专业课']),
    # 11-03 周二 · 0 条（完全空白的一天）
    # 11-04 周三 · 2 条（稀疏）
    (11, 4, 13, 20, 35, []),
    (11, 4, 19, 50, 60, ['高数']),
    # 11-05 周四 · 1 条（稀疏）
    (11, 5, 7, 20, 25, ['英语']),
    # 11-06 周五 · 3 条（这一周里最密的一天，且全部在 18:00 之前）
    (11, 6, 9, 10, 110, ['高数']),
    (11, 6, 13, 5, 120, ['物理']),
    (11, 6, 15, 20, 90, ['专业课']),
]

# ---------------------------------------------------------------------------
# 1.3 主演示数据集 11-07 ~ 11-13（跨满 7 天，合计 1276 分钟、21 条）
#
#     稀疏天 / 密集天（按每天记录条数）：
#       11-07 周六  1 条  ← 稀疏
#       11-08 周日  5 条  ← 密集（含极端值、多标签、中断）
#       11-09 周一  1 条  ← 稀疏（深夜跨午夜）
#       11-10 周二  4 条  ← 密集（含第 2 条中断记录）
#       11-11 周三  1 条  ← 稀疏
#       11-12 周四  5 条  ← 密集（6 个时段里再补清晨/午间/下午/晚间）
#       11-13 周五  4 条  ← 密集（今天，记录都发生在 18:00 之前）
#     稀疏天只有 1 条、密集天 4~5 条，画像的「平均每活跃天记录条数」= 21/7 = 3。
# ---------------------------------------------------------------------------
DEMO_7D_RECORDS = [
    # ---- 11-07 周六 · 稀疏天（1 条）：只有一个上午的长时段 ----
    (11, 7, 10, 20, 90, ['高数']),                  # 上午 / 长

    # ---- 11-08 周日 · 密集天（5 条）：时段从清晨铺到晚间 ----
    (11, 8, 7, 40, 12, ['英语']),                   # 清晨 / 短
    (11, 8, 9, 15, 485, ['高数']),                  # 上午 / 极端值（模拟计时未停止）
    (11, 8, 13, 5, 28, ['物理']),                   # 午间 / 中
    (11, 8, 15, 30, 32, ['专业课']),                # 下午 / 中
    (11, 8, 19, 40, 65, ['高数', '英语']),          # 晚间 / 长 + 双标签（时长均摊）

    # ---- 11-09 周一 · 稀疏天（1 条）：23:10 开始，50 分钟后跨过午夜 ----
    (11, 9, 23, 10, 50, ['英语']),                  # 深夜 / 跨午夜（按开始日归属）

    # ---- 11-10 周二 · 密集天（4 条）----
    (11, 10, 8, 10, 25, ['物理']),                  # 清晨 / 中
    (11, 10, 10, 40, 42, ['高数']),                 # 上午 / 中
    (11, 10, 14, 20, 38, ['专业课']),               # 下午 / 中
    (11, 10, 20, 5, 55, ['英语']),                  # 晚间 / 中（中断 2 次）

    # ---- 11-11 周三 · 稀疏天（1 条）----
    (11, 11, 18, 45, 40, ['物理']),                 # 晚间 / 中

    # ---- 11-12 周四 · 密集天（5 条）----
    (11, 12, 6, 50, 15, ['英语']),                  # 清晨 / 短
    (11, 12, 9, 30, 70, ['高数']),                  # 上午 / 长
    (11, 12, 12, 40, 22, []),                       # 午间 / 短（空标签 → 未分类）
    (11, 12, 16, 10, 35, ['专业课']),               # 下午 / 中
    (11, 12, 19, 15, 60, ['高数']),                 # 晚间 / 长

    # ---- 11-13 周五 · 密集天（4 条，都发生在锚点 18:00 之前）----
    (11, 13, 7, 55, 8, ['英语']),                   # 清晨 / 短
    (11, 13, 10, 5, 30, ['高数']),                  # 上午 / 中
    (11, 13, 12, 20, 26, []),                       # 午间 / 中（空标签 → 未分类）
    (11, 13, 14, 35, 48, ['物理']),                 # 下午 / 中
]

# 单独标注「异常记录」，生成完后按 id 回填（避免在数据元组里塞太多参数）
# 说明：中断次数只用于演示「暂停/中断」字段，不参与时长计算。
INTERRUPT_INFO = {
    # (月, 日, 时, 分): 中断次数
    (11, 8, 15, 30): 1,     # 专业课 32 分钟，被打断 1 次
    (11, 10, 20, 5): 2,     # 英语 55 分钟，被打断 2 次
}


# =============================================================================
# 2. 记录构造与自检
# =============================================================================
def to_ms(month, day, hour, minute):
    """把「2026 年某月某日某时某分（东八区）」换算成毫秒时间戳。"""
    dt = datetime(YEAR, month, day, hour, minute, 0, tzinfo=TZ)
    return int(round(dt.timestamp())) * 1000


def build_sessions(record_groups):
    """把 (月,日,时,分,时长,标签) 元组按时间顺序展开成 StudySession 列表。"""
    tuples = []
    for group in record_groups:
        tuples.extend(group)
    # 按时间排序，保证 id 序号与时间顺序一致
    tuples.sort(key=lambda r: (r[0], r[1], r[2], r[3]))

    per_day_seq = {}
    sessions = []
    for month, day, hour, minute, duration, tags in tuples:
        day_key = '%04d%02d%02d' % (YEAR, month, day)
        per_day_seq[day_key] = per_day_seq.get(day_key, 0) + 1
        interrupts = INTERRUPT_INFO.get((month, day, hour, minute), 0)
        session = {
            'id': 'demo-%s-%02d' % (day_key, per_day_seq[day_key]),
            'startTime': to_ms(month, day, hour, minute),
            'duration': duration,
            'tags': list(tags),
            'isInterrupted': interrupts > 0,
            'interruptCount': interrupts,
        }
        sessions.append(session)
    return sessions


# =============================================================================
# 3. 统计复算（严格照抄 FocusProfileStats 的口径，用于自检 + 生成数据说明）
# =============================================================================
def js_round1(x):
    """与 ArkTS 的 Math.round(x * 10) / 10 等价（正数四舍五入）。"""
    return math.floor(x * 10 + 0.5) / 10.0


def fmt_num(x):
    """数值格式化：整数不带小数点，否则保留 1 位小数（与引擎的 round1 输出一致）。"""
    if isinstance(x, float):
        if x.is_integer():
            return str(int(x))
        return '%.1f' % x
    return str(x)


def day_key_of(ms):
    return datetime.fromtimestamp(ms / 1000.0, TZ).strftime('%Y-%m-%d')


def segment_of(hour):
    if 6 <= hour < 9:
        return 'dawn'
    if 9 <= hour < 12:
        return 'morning'
    if 12 <= hour < 14:
        return 'noon'
    if 14 <= hour < 18:
        return 'afternoon'
    if 18 <= hour < 21:
        return 'evening'
    return 'night'


def categories_of(session):
    raw = session['tags']
    if not raw:
        return [UNCATEGORIZED]
    cleaned = []
    for tag in raw:
        name = tag.strip() if (tag is not None and tag.strip()) else UNCATEGORIZED
        if name not in cleaned:
            cleaned.append(name)
    return cleaned if cleaned else [UNCATEGORIZED]


def compute_stats(all_sessions, window_days, now_ms):
    """复算一个窗口的统计结果（字段与 FocusProfileStatsResult 对齐）。"""
    window_start = now_ms - window_days * DAY_MS
    in_window = [s for s in all_sessions if window_start <= s['startTime'] <= now_ms]

    seen = set()
    deduped = []
    duplicate_count = 0
    for s in in_window:
        if s['id'] in seen:
            duplicate_count += 1
            continue
        seen.add(s['id'])
        deduped.append(s)

    invalid_count = 0
    extreme_count = 0
    valid = []
    for s in deduped:
        if not s['duration'] > 0:
            invalid_count += 1
            continue
        if s['duration'] > EXTREME_DURATION_MINUTES:
            extreme_count += 1
        valid.append(s)

    sample_size = len(valid)
    active_days = len(set(day_key_of(s['startTime']) for s in valid))
    total_minutes = sum(s['duration'] for s in valid)
    avg_daily = js_round1(total_minutes / float(window_days)) if window_days else 0

    # 类别分布：多标签均摊，保持首次出现顺序（等价于 JS Map 的插入顺序）
    cat_minutes = {}
    for s in valid:
        cats = categories_of(s)
        per = s['duration'] / float(len(cats))
        for cat in cats:
            cat_minutes[cat] = cat_minutes.get(cat, 0.0) + per
    category_shares = []
    for cat in cat_minutes:
        minutes = cat_minutes[cat]
        category_shares.append({
            'category': cat,
            'minutes': js_round1(minutes),
            'share': js_round1(minutes / total_minutes * 100) if total_minutes > 0 else 0,
        })
    category_shares.sort(key=lambda c: -c['minutes'])   # 稳定排序，等价于 JS 的 sort

    # 时段分布：整条时长按「开始小时」归属，不拆分
    seg_minutes = dict((k, 0) for k in SEGMENT_ORDER)
    for s in valid:
        hour = datetime.fromtimestamp(s['startTime'] / 1000.0, TZ).hour
        seg_minutes[segment_of(hour)] += s['duration']
    segment_shares = []
    for key in SEGMENT_ORDER:
        minutes = seg_minutes[key]
        segment_shares.append({
            'segmentKey': key,
            'label': SEGMENT_LABEL[key],
            'minutes': js_round1(minutes),
            'share': js_round1(minutes / total_minutes * 100) if total_minutes > 0 else 0,
        })

    durations = [s['duration'] for s in valid]
    avg_session = js_round1(sum(durations) / float(sample_size)) if sample_size > 0 else 0
    median_session = median_of(durations)
    per_active_day = js_round1(sample_size / float(active_days)) if active_days > 0 else 0

    wow = week_over_week(all_sessions, now_ms) if window_days == 30 else float('nan')

    insufficient = sample_size < 3 or active_days < 2

    cleaning_note = (
        '口径：按开始时间归属窗口与日期，一条记录不跨日拆分；空标签归「%s」。' % UNCATEGORIZED
        + '本窗口去重 %d 条、剔除时长非正的无效记录 %d 条、' % (duplicate_count, invalid_count)
        + '可疑极端时长（>%d 分钟）%d 条，极端值保留并在相关事实标注。' % (
            EXTREME_DURATION_MINUTES, extreme_count)
    )

    return {
        'windowDays': window_days,
        'windowStart': window_start,
        'windowEnd': now_ms,
        'sampleSize': sample_size,
        'activeDays': active_days,
        'totalMinutes': total_minutes,
        'avgDailyMinutes': avg_daily,
        'categoryShares': category_shares,
        'segmentShares': segment_shares,
        'avgSessionDuration': avg_session,
        'medianSessionDuration': median_session,
        'sessionsPerActiveDay': per_active_day,
        'weekOverWeekChange': wow,
        'insufficientData': insufficient,
        'cleaningNote': cleaning_note,
        'duplicateCount': duplicate_count,
        'invalidCount': invalid_count,
        'extremeCount': extreme_count,
    }


def median_of(values):
    if not values:
        return 0
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return js_round1(ordered[mid])
    return js_round1((ordered[mid - 1] + ordered[mid]) / 2.0)


def week_over_week(all_sessions, now_ms):
    """最近 7 天 vs 再往前 7 天的总时长变化百分比（上一周为 0 时返回 NaN）。"""
    recent_start = now_ms - 7 * DAY_MS
    previous_start = now_ms - 14 * DAY_MS
    recent_total = 0
    previous_total = 0
    for s in all_sessions:
        if not s['duration'] > 0:
            continue
        if recent_start < s['startTime'] <= now_ms:
            recent_total += s['duration']
        elif previous_start < s['startTime'] <= recent_start:
            previous_total += s['duration']
    if previous_total <= 0:
        return float('nan')
    return js_round1((recent_total - previous_total) / float(previous_total) * 100)


def per_day_counts(sessions, window_days, now_ms):
    """按天统计记录条数（用于数据说明里的「稀疏天 / 密集天」表）。"""
    window_start = now_ms - window_days * DAY_MS
    counts = {}
    for s in sessions:
        if window_start <= s['startTime'] <= now_ms:
            counts[day_key_of(s['startTime'])] = counts.get(day_key_of(s['startTime']), 0) + 1
    return dict(sorted(counts.items()))


# =============================================================================
# 4. 设计自检（数据被改动时立刻失败，避免文档与数据脱节）
# =============================================================================
def validate(sessions_7d, sessions_30d, stats_7d, stats_30d):
    problems = []

    ids = set()
    for s in sessions_30d:
        if s['id'] in ids:
            problems.append('id 重复：%s' % s['id'])
        ids.add(s['id'])
        if not isinstance(s['id'], str):
            problems.append('id 不是字符串：%r' % s['id'])
        if not isinstance(s['startTime'], int):
            problems.append('startTime 不是整数：%r' % s['id'])
        if not isinstance(s['duration'], int) or s['duration'] <= 0:
            problems.append('duration 必须为正整数：%r' % s['id'])
        if not isinstance(s['tags'], list) or any(not isinstance(t, str) for t in s['tags']):
            problems.append('tags 必须是字符串数组：%r' % s['id'])
        if not isinstance(s['isInterrupted'], bool):
            problems.append('isInterrupted 必须是布尔：%r' % s['id'])
        if not isinstance(s['interruptCount'], int):
            problems.append('interruptCount 必须是整数：%r' % s['id'])
        if s['startTime'] > NOW_MS:
            problems.append('记录开始时间晚于锚点：%r' % s['id'])

    # 7 天窗口：必须真的跨满 7 天、有稀疏天和密集天
    counts_7d = per_day_counts(sessions_7d, 7, NOW_MS)
    if len(counts_7d) != 7:
        problems.append('7 天数据集应覆盖 7 个不同日期，实际 %d 个' % len(counts_7d))
    sparse = [d for d, c in counts_7d.items() if c == 1]
    dense = [d for d, c in counts_7d.items() if c >= 4]
    if len(sparse) < 2:
        problems.append('稀疏天（1 条）至少要有 2 天')
    if len(dense) < 2:
        problems.append('密集天（4~5 条）至少要有 2 天')

    # 6 个时段必须全部出现，且「上午」最高
    seg_positive = [s for s in stats_7d['segmentShares'] if s['minutes'] > 0]
    if len(seg_positive) != 6:
        problems.append('7 天数据集应覆盖全部 6 个时段，实际 %d 个' % len(seg_positive))
    top_seg = max(stats_7d['segmentShares'], key=lambda s: s['minutes'])
    if top_seg['segmentKey'] != 'morning':
        problems.append('7 天数据集占比最高的时段应为 morning，实际 %s' % top_seg['segmentKey'])

    # 主导类别应为「高数」，且去掉极端记录后仍然是第一
    if stats_7d['categoryShares'][0]['category'] != '高数':
        problems.append('7 天数据集主导类别应为「高数」')

    # 时长结构：短/中/长/极端都要有
    durations = [s['duration'] for s in sessions_7d]
    if not any(d <= 15 for d in durations):
        problems.append('缺少短时长记录（≤15 分钟）')
    if not any(25 <= d <= 40 for d in durations):
        problems.append('缺少中时长记录（25~40 分钟）')
    if not any(d >= 60 for d in durations):
        problems.append('缺少长时长记录（≥60 分钟）')
    if sum(1 for d in durations if d > EXTREME_DURATION_MINUTES) != 1:
        problems.append('极端时长记录应恰好 1 条')

    # 中断记录、空标签、多标签
    if sum(1 for s in sessions_7d if s['isInterrupted']) != 2:
        problems.append('7 天数据集应有 2 条中断记录')
    if sum(1 for s in sessions_7d if len(s['tags']) == 0) != 2:
        problems.append('7 天数据集应有 2 条空标签记录')
    if sum(1 for s in sessions_7d if len(s['tags']) >= 2) != 1:
        problems.append('7 天数据集应有 1 条多标签记录')

    # 30 天：周际变化必须是可复算的 +120%
    if stats_30d['weekOverWeekChange'] != 120.0:
        problems.append('30 天周际变化应为 120.0，实际 %r' % stats_30d['weekOverWeekChange'])

    # 类别占比之和应约等于 100%
    for name, stats in (('7 天', stats_7d), ('30 天', stats_30d)):
        cat_sum = sum(c['share'] for c in stats['categoryShares'])
        seg_sum = sum(s['share'] for s in stats['segmentShares'])
        if not (99.5 <= cat_sum <= 100.5):
            problems.append('%s类别占比之和偏离 100%%：%.1f' % (name, cat_sum))
        if not (99.5 <= seg_sum <= 100.5):
            problems.append('%s时段占比之和偏离 100%%：%.1f' % (name, seg_sum))

    # 30 天数据集里的 7 天记录必须与 7 天数据集完全一致（同一份记录，不做二次加工）
    ids_7d = set(s['id'] for s in sessions_7d)
    ids_30d = set(s['id'] for s in sessions_30d)
    if not ids_7d.issubset(ids_30d):
        problems.append('7 天数据集的记录没有全部包含在 30 天数据集里')

    if problems:
        raise SystemExit('数据自检未通过：\n  - ' + '\n  - '.join(problems))


# =============================================================================
# 5. 输出
# =============================================================================
def dump_json(sessions):
    return json.dumps(sessions, ensure_ascii=False, indent=2, sort_keys=False) + '\n'


def jsonc_with_header(sessions, title):
    """给纯 JSON 加一个 // 注释头（JSONC 便于人读；纯 .json 仍是标准 JSON）。"""
    header = (
        '// %s\n'
        '// 本文件为**合成演示数据**：不是真实用户数据，不含任何真实个人隐私，仅用于专注画像功能演示。\n'
        '// 数据由 make_demo_sessions.py 生成（固定锚点 2026-11-13 18:00 UTC+8，重复运行结果完全一致）。\n'
        '// 字段与 StudySession 一致：id / startTime / duration / tags / isInterrupted / interruptCount。\n'
        '// 说明见 demo_data_readme.md。\n'
    ) % title
    return header + json.dumps(sessions, ensure_ascii=False, indent=2, sort_keys=False) + '\n'


def dump_prefs_xml(sessions, title):
    """输出 preferences 格式 XML（无扩展名，仅作人工查看/备用，不要求部署）。

    结构参考 OpenHarmony preferences 的文件形态：
        <preferences><key name="sessions">值</key></preferences>
    值就是 App 里 JSON.stringify(sessions) 的字符串，这里放进 CDATA 以便直接阅读。
    """
    value = json.dumps(sessions, ensure_ascii=False, separators=(',', ':'))
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!--\n'
        '  %s\n'
        '  【声明】本文件为合成演示数据，不是真实用户数据，不含任何真实个人隐私，仅用于专注画像功能演示。\n'
        '  由 make_demo_sessions.py 生成（固定锚点 2026-11-13 18:00 UTC+8，可重复生成）。\n'
        '  【用途】preferences 文件名 "study_data"、键 "sessions" 的备份形态，仅作人工查看与备用，\n'
        '          不要求也不建议直接部署到设备（部署会覆盖设备上的真实记录）。\n'
        '  【结构】与 App 的 FocusSessionStore 一致：study_data / sessions = JSON.stringify(StudySession[])。\n'
        '-->\n'
        '<preferences version="1.0">\n'
        '  <key name="sessions"><![CDATA[%s]]></key>\n'
        '</preferences>\n'
    ) % (title, value)


def write_text(filename, text):
    path = os.path.join(OUT_DIR, filename)
    # 固定 LF 换行 + UTF-8（不带 BOM），保证跨平台逐字节一致
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    return path


def print_report(name, stats, per_day):
    print('===== %s =====' % name)
    print('windowDays=%d' % stats['windowDays'])
    print('records=%d' % stats['sampleSize'])
    print('activeDays=%d' % stats['activeDays'])
    print('totalMinutes=%d' % stats['totalMinutes'])
    print('avgDailyMinutes=%s' % fmt_num(stats['avgDailyMinutes']))
    print('sessionsPerActiveDay=%s' % fmt_num(stats['sessionsPerActiveDay']))
    print('avgSessionDuration=%s' % fmt_num(stats['avgSessionDuration']))
    print('medianSessionDuration=%s' % fmt_num(stats['medianSessionDuration']))
    wow = stats['weekOverWeekChange']
    print('weekOverWeekChange=%s' % ('NaN' if (isinstance(wow, float) and math.isnan(wow)) else fmt_num(wow)))
    print('insufficientData=%s' % ('true' if stats['insufficientData'] else 'false'))
    print('perDay=' + ','.join('%s:%d' % (k, v) for k, v in per_day.items()))
    print('category=' + ','.join(
        '%s:%s:%s' % (c['category'], fmt_num(c['minutes']), fmt_num(c['share']))
        for c in stats['categoryShares']))
    print('segment=' + ','.join(
        '%s:%s:%s' % (s['segmentKey'], fmt_num(s['minutes']), fmt_num(s['share']))
        for s in stats['segmentShares']))
    print('cleaningNote=' + stats['cleaningNote'])
    print('')


# =============================================================================
# 6. 主流程
# =============================================================================
def main():
    sessions_30d = build_sessions([EARLIER_RECORDS, PREV_WEEK_RECORDS, DEMO_7D_RECORDS])
    window_start_7d = NOW_MS - 7 * DAY_MS
    sessions_7d = [s for s in sessions_30d if s['startTime'] >= window_start_7d]

    stats_7d = compute_stats(sessions_30d, 7, NOW_MS)
    stats_30d = compute_stats(sessions_30d, 30, NOW_MS)
    validate(sessions_7d, sessions_30d, stats_7d, stats_30d)

    title_7d = '7 天主演示数据集（%d 条 / %d 分钟 / 跨 7 天，锚点 2026-11-13 18:00+08:00）' % (
        stats_7d['sampleSize'], stats_7d['totalMinutes'])
    title_30d = '30 天演示数据集（%d 条 / %d 分钟 / 跨 30 天，锚点 2026-11-13 18:00+08:00）' % (
        stats_30d['sampleSize'], stats_30d['totalMinutes'])

    written = [
        write_text('demo_sessions.json', dump_json(sessions_7d)),
        write_text('demo_sessions.jsonc', jsonc_with_header(sessions_7d, title_7d)),
        write_text('demo_sessions_30d.json', dump_json(sessions_30d)),
        write_text('study_data_demo', dump_prefs_xml(sessions_7d, title_7d)),
        write_text('study_data_demo_30d', dump_prefs_xml(sessions_30d, title_30d)),
    ]

    print('锚点 NOW_MS = %d（2026-11-13 18:00 UTC+8）' % NOW_MS)
    print('已生成：')
    for path in written:
        print('  - %s' % os.path.basename(path))
    print('')
    print_report('DATASET 7d', stats_7d, per_day_counts(sessions_30d, 7, NOW_MS))
    print_report('DATASET 30d', stats_30d, per_day_counts(sessions_30d, 30, NOW_MS))


if __name__ == '__main__':
    main()
