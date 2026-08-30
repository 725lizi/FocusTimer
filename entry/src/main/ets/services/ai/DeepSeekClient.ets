// services/ai/DeepSeekClient.ets
// DeepSeek 流式对话客户端（OpenAI 兼容 Chat Completions，stream=true 的 SSE）。
//
// 职责边界：本类只负责「发请求 + 收流 + 解码 + 用已测好的 SseChunkParser 切片 + 错误分类」，
// 不负责决定走 AI 还是规则（那是 ReportStrategy）、不负责组装提示词（ReportPromptBuilder）。
// 网络属于设备相关、无法离线单测，因此把可测的部分都已下沉到纯逻辑类。

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConfig } from './AiConfig';
import { SseChunkParser } from './SseChunkParser';
import { HttpErrorMapper } from './HttpErrorMapper';
import { LlmErrorKind } from './ReportStrategy';
import { ChatCompletionRequest } from './AiChatTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'DeepSeekClient';

/** 流式回调：增量文本 / 出错 / 完成（给出累计全文） */
export interface StreamCallbacks {
  onDelta: (delta: string) => void;
  onError: (kind: LlmErrorKind, message: string) => void;
  onComplete: (fullText: string) => void;
}

/** 请求头结构（显式 interface，避免 ArkTS 无类型对象字面量） */
interface StreamHttpHeader {
  'Content-Type': string;
  'Authorization': string;
  'Accept': string;
}

export class DeepSeekClient {
  private activeRequest: http.HttpRequest | null = null;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  // 标记本次请求是否已收尾，保证 onError/onComplete 只触发一次
  private settled: boolean = false;
  private accumulated: string = '';

  /**
   * 发起一次流式生成。
   * @param apiKey 用户本地保存的 Key
   * @param body 已组装好的请求体（含 messages、stream=true）
   * @param callbacks 流式回调
   */
  public startStream(apiKey: string, body: ChatCompletionRequest, callbacks: StreamCallbacks): void {
    this.cancelInternal(); // 清掉上一次未结束的请求
    this.settled = false;
    this.accumulated = '';

    const httpRequest: http.HttpRequest = http.createHttp();
    this.activeRequest = httpRequest;
    const parser: SseChunkParser = new SseChunkParser();

    // 收到一段数据：先用 TextDecoder 解码（decodeWithStream 能跨包拼好“半个汉字”），
    // 再交给纯逻辑 SseChunkParser 切出增量文本
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      try {
        const chunkText: string = this.decoder.decodeWithStream(new Uint8Array(data));
        const deltas: string[] = parser.feed(chunkText);
        for (let i = 0; i < deltas.length; i++) {
          this.accumulated += deltas[i];
          callbacks.onDelta(deltas[i]);
        }
        if (parser.isDone()) {
          this.finish(callbacks);
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, '解析流式分片失败: ' + JSON.stringify(err));
      }
    });

    // 服务端正常结束
    httpRequest.on('dataEnd', () => {
      this.finish(callbacks);
    });

    const header: StreamHttpHeader = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'Accept': 'text/event-stream'
    };

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(body),
      connectTimeout: AiConfig.CONNECT_TIMEOUT_MS,
      readTimeout: AiConfig.READ_TIMEOUT_MS
    };

    const url: string = AiConfig.BASE_URL + AiConfig.CHAT_PATH;
    // 流式必须用 requestInStream：正文通过 on('dataReceive') 逐段回调，
    // 这里的结束回调第二个参数只是 HTTP 状态码（number），不是完整响应体。
    httpRequest.requestInStream(url, options, (err: BusinessError, statusCode: number) => {
      if (err) {
        // 框架层错误（断网/超时/主动取消），按错误码分类
        const kind: LlmErrorKind = HttpErrorMapper.classifyFrameworkError(err.code);
        this.fail(callbacks, kind, err.message ? err.message : 'network error');
        return;
      }
      if (statusCode !== 200) {
        // 建立连接但返回非 200（Key 错、限流、服务端错等），按状态码分类
        const kind: LlmErrorKind = HttpErrorMapper.classifyStatus(statusCode);
        this.fail(callbacks, kind, `HTTP ${statusCode}`);
        return;
      }
      // 200 时正文已通过 dataReceive 流式处理，dataEnd 会负责 finish，这里兜底
      this.finish(callbacks);
    });
  }

  /** 用户主动取消（例如离开页面） */
  public cancel(): void {
    this.cancelInternal();
  }

  private finish(callbacks: StreamCallbacks): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    this.teardown();
    callbacks.onComplete(this.accumulated);
  }

  private fail(callbacks: StreamCallbacks, kind: LlmErrorKind, message: string): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    this.teardown();
    callbacks.onError(kind, message);
  }

  private cancelInternal(): void {
    if (this.activeRequest !== null) {
      try {
        this.activeRequest.off('dataReceive');
        this.activeRequest.off('dataEnd');
        this.activeRequest.destroy();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '取消请求异常: ' + JSON.stringify(err));
      }
      this.activeRequest = null;
    }
  }

  private teardown(): void {
    if (this.activeRequest !== null) {
      try {
        this.activeRequest.off('dataReceive');
        this.activeRequest.off('dataEnd');
        this.activeRequest.destroy();
      } catch (err) {
        // 销毁幂等，重复销毁时仅记录不抛出
        hilog.warn(DOMAIN, TAG, '销毁请求异常: ' + JSON.stringify(err));
      }
      this.activeRequest = null;
    }
  }
}
