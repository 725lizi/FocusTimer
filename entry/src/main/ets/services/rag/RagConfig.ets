// services/rag/RagConfig.ets
// RAG 模块集中配置。关键事实：DeepSeek 官方【不提供】embedding 接口，
// 因此「聊天用 DeepSeek、向量化另选 OpenAI 兼容服务」。
//
// 这里把端点/模型做成可配置：只要对方遵循 OpenAI 的 POST /embeddings 约定
// （请求 {model, input}，响应 data[].embedding），换厂商只改这里，客户端不用动。
//
// 默认选硅基流动（SiliconFlow）的 BAAI/bge-large-zh-v1.5：中文检索效果好、
// 对个人开发者有免费额度、国内可直连、OpenAI 兼容。也可换成：
//  - 智谱：https://open.bigmodel.cn/api/paas/v4 ，模型 embedding-3
//  - 阿里百炼：https://dashscope.aliyuncs.com/compatible-mode/v1 ，模型 text-embedding-v3

export class RagConfig {
  /** 向量化服务基础地址（OpenAI 兼容），不含 /embeddings 路径 */
  static readonly EMBED_BASE_URL: string = 'https://api.siliconflow.cn/v1';
  /** 向量化路径 */
  static readonly EMBED_PATH: string = '/embeddings';
  /** 默认向量模型（中文 BGE） */
  static readonly DEFAULT_EMBED_MODEL: string = 'BAAI/bge-large-zh-v1.5';
  /** 该模型输出向量维度（bge-large-zh 为 1024），用于校验返回是否合法 */
  static readonly EXPECTED_DIM: number = 1024;
  /** 建连/读取超时（毫秒），向量化一般较快 */
  static readonly CONNECT_TIMEOUT_MS: number = 15000;
  static readonly READ_TIMEOUT_MS: number = 30000;
  /** 单次批量向量化最多文本条数，避免一次请求过大 */
  static readonly MAX_BATCH: number = 16;
  /** 保存向量化 Key 的 preferences 文件名与键名（与聊天 Key 分开存） */
  static readonly PREFS_NAME: string = 'rag_settings';
  static readonly KEY_EMBED_API_KEY: string = 'embed_api_key';
  static readonly KEY_EMBED_MODEL: string = 'embed_model';

  /**
   * BGE 中文模型的「查询指令前缀」：检索时给「问题/查询」加这段前缀、
   * 而被入库的文档块不加，可提升中文相似度匹配效果（模型官方推荐用法）。
   */
  static readonly BGE_QUERY_INSTRUCTION: string = '为这个句子生成表示以用于检索相关文章：';

  /** 被检索的查询文本按需加指令前缀；文档块入库时不加 */
  static buildQueryText(rawQuery: string, isQuery: boolean): string {
    const q: string = rawQuery.trim();
    if (isQuery) {
      return RagConfig.BGE_QUERY_INSTRUCTION + q;
    }
    return q;
  }
}
