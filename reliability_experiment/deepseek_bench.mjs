// ============================================================================
// deepseek_bench.mjs —— DeepSeek 多底稿实测驱动（与豆包版完全同口径）
//
// 负责模型：DeepSeek
//
// 用途：用和豆包版一模一样的方式重测 DeepSeek，得到 50 vs 50 的同口径对比。
// 注意：PPT 第 13 页 DeepSeek 列目前写的是「100 次真实调用」历史数据；
// 如果要用本脚本的结果替换，请用同一口径（同一批底稿 × 同一次数）。
//
// 用法（PowerShell）：
//   $env:DEEPSEEK_API_KEY = "你的 DeepSeek Key"     # 必填
//   $env:DEEPSEEK_MODEL   = "deepseek-chat"         # 默认 deepseek-chat
//   $env:BENCH_RUNS       = "10"                    # 每份底稿调用次数，默认 10
//   node deepseek_bench.mjs
//
// 产出（本目录）：deepseek_bench_results.json / deepseek_bench_report.md
// 安全：Key 只从环境变量读，绝不写进任何产物、日志或控制台输出。
// ============================================================================

import { runBench } from './bench_core.mjs';

const key = process.env.DEEPSEEK_API_KEY || '';
if (!key) {
  console.error('未检测到 API Key。请先设置环境变量 DEEPSEEK_API_KEY。');
  process.exit(1);
}

await runBench({
  modelLabel: 'DeepSeek',
  model: process.env.DEEPSEEK_MODEL || 'deepseek-chat',
  baseUrl: process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com',
  apiKey: key,
  runsPerFixture: Number(process.env.BENCH_RUNS || 10),
  outPrefix: 'deepseek_bench',
});
