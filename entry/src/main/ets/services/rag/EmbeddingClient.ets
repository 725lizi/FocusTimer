// services/rag/EmbeddingClient.ets
// 设备层：调用 OpenAI 兼容的 /embeddings 接口，把一批文本一次性转向量。
//
// 与阶段2聊天「流式 requestInStream」不同：向量化是一次性请求-响应（非流式），
// 用普通 http.request 即可，返回的 JSON 交给纯逻辑 EmbeddingParser 解析。
// 网络属于设备相关、无法离线单测，因此：请求/解码放这里，解析与数学全部下沉到纯逻辑类。
// 错误分类复用阶段2的 HttpErrorMapper，不重复造轮子。

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { RagConfig } from './RagConfig';
import { EmbeddingParser } from './EmbeddingParser';
import { EmbeddingVector } from './RagTypes';
import { HttpErrorMapper } from '../ai/HttpErrorMapper';
import { LlmErrorKind } from '../ai/ReportStrategy';

/** 向量化失败错误：携带统一错误类别，方便上层决定是否降级/提示 */
export class EmbeddingError extends Error {
  kind: LlmErrorKind;

  constructor(kind: LlmErrorKind, message: string) {
    super(message);
    this.kind = kind;
    this.name = 'EmbeddingError';
  }
}

/** 请求体（OpenAI 兼容） */
interface EmbeddingRequestBody {
  model: string;
  input: string[];
  encoding_format: string;
}

export class EmbeddingClient {
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  /**
   * 批量向量化。
   * @param texts 待向量化的文本块（顺序即返回顺序）
   * @param apiKey 向量化服务的 Key（与聊天 Key 分开保存）
   * @param model 模型名，缺省用配置默认值
   * @returns 与 texts 顺序对齐的向量数组
   */
  public async embed(texts: string[], apiKey: string,
    model: string = RagConfig.DEFAULT_EMBED_MODEL): Promise<EmbeddingVector[]> {
    if (texts.length === 0) {
      return [];
    }
    if (apiKey.length === 0) {
      throw new EmbeddingError('unauthorized', '未配置向量化 API Key');
    }

    const body: EmbeddingRequestBody = {
      model: model,
      input: texts,
      encoding_format: 'float'
    };

    const url: string = RagConfig.EMBED_BASE_URL + RagConfig.EMBED_PATH;
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        },
        extraData: JSON.stringify(body),
        connectTimeout: RagConfig.CONNECT_TIMEOUT_MS,
        readTimeout: RagConfig.READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      } as http.HttpRequestOptions);

      const code: number = response.responseCode;
      if (code !== 200) {
        const kind: LlmErrorKind = HttpErrorMapper.classifyStatus(code);
        throw new EmbeddingError(kind, `embedding HTTP ${code}`);
      }

      const raw: string = this.resultToString(response.result);
      const parsed = EmbeddingParser.parseBatchResponse(raw);
      if (!parsed.ok) {
        throw new EmbeddingError('server', '向量化响应解析失败：' + parsed.error);
      }
      if (parsed.vectors.length !== texts.length) {
        // 返回条数和请求条数对不上，属于异常响应，不静默截断
        throw new EmbeddingError('server',
          `向量化条数不一致：请求 ${texts.length} 条，返回 ${parsed.vectors.length} 条`);
      }
      return parsed.vectors;
    } catch (err) {
      // 已经是我们包装过的错误直接抛；框架层错误按错误码分类后包装
      if (err instanceof EmbeddingError) {
        throw err;
      }
      const be = err as BusinessError;
      const code: number = (be.code !== undefined && be.code !== null) ? be.code : -1;
      const kind: LlmErrorKind = HttpErrorMapper.classifyFrameworkError(code);
      throw new EmbeddingError(kind, be.message ? be.message : 'embedding network error');
    } finally {
      httpRequest.destroy();
    }
  }

  /** http 响应体可能是 string / ArrayBuffer / Object，统一转成字符串再交给解析器 */
  private resultToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return this.decoder.decodeWithStream(new Uint8Array(result));
    }
    return JSON.stringify(result);
  }
}
