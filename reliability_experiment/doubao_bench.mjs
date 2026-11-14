// ============================================================================
// doubao_bench.mjs —— 豆包（火山方舟）多底稿实测驱动
//
// 负责模型：豆包 Doubao（火山方舟 Ark，OpenAI 兼容接口）
//
// 用法（PowerShell）：
//   $env:ARK_API_KEY  = "你的方舟 API Key"          # 必填
//   $env:DOUBAO_MODEL = "doubao-seed-1.6-250615"    # 以方舟控制台模型广场为准
//   $env:BENCH_RUNS   = "10"                        # 每份底稿调用次数，默认 10
//   node doubao_bench.mjs
//
// 产出（本目录）：doubao_bench_results.json / doubao_bench_report.md
// 安全：Key 只从环境变量读，绝不写进任何产物、日志或控制台输出。
// ============================================================================

import { runBench } from './bench_core.mjs';

const key = process.env.ARK_API_KEY || process.env.DOUBAO_API_KEY || '';
if (!key) {
  console.error('未检测到 API Key。请先设置环境变量 ARK_API_KEY（火山方舟控制台 → API Key 管理）。');
  process.exit(1);
}

await runBench({
  modelLabel: '豆包 Doubao',
  model: process.env.DOUBAO_MODEL || 'doubao-seed-1.6-250615',
  baseUrl: process.env.ARK_BASE_URL || 'https://ark.cn-beijing.volces.com/api/v3',
  apiKey: key,
  runsPerFixture: Number(process.env.BENCH_RUNS || 10),
  outPrefix: 'doubao_bench',
});
