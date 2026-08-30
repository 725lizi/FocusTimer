// services/ai/HttpErrorMapper.ets
// 纯逻辑：把 HTTP 状态码 / 底层错误码映射成统一的 LlmErrorKind，供降级决策使用。
// 不依赖网络库本身，给定状态码必得确定结果，可离线单测。

import { LlmErrorKind } from './ReportStrategy';

export class HttpErrorMapper {
  /**
   * 按 HTTP 状态码分类：
   * 401/403 鉴权问题（Key 错/欠费/无权限），429 限流，400 请求体错，5xx 服务端问题，其余视为网络错。
   */
  static classifyStatus(status: number): LlmErrorKind {
    if (status === 401 || status === 403) {
      return 'unauthorized';
    }
    if (status === 429) {
      return 'rate_limited';
    }
    if (status === 400 || status === 404 || status === 422) {
      return 'bad_request';
    }
    if (status >= 500) {
      return 'server';
    }
    if (status === 408) {
      return 'timeout';
    }
    return 'network';
  }

  /**
   * 底层 http 框架抛出的错误码分类（鸿蒙网络栈常见错误码）。
   * 2300089 为请求取消，2300004/2300047 等为连接/读超时；无法识别时保守归为 network。
   */
  static classifyFrameworkError(code: number): LlmErrorKind {
    if (code === 2300089) {
      return 'cancelled';
    }
    if (code === 2300004 || code === 2300047 || code === 2300999) {
      return 'timeout';
    }
    return 'network';
  }

  /** 给用户看的中文提示（与错误类别一一对应） */
  static userMessage(kind: LlmErrorKind): string {
    switch (kind) {
      case 'unauthorized':
        return 'API Key 无效或已欠费，请检查设置';
      case 'rate_limited':
        return '请求过于频繁，已为你切换到本地规则版';
      case 'timeout':
        return 'AI 响应超时，已为你切换到本地规则版';
      case 'server':
        return 'AI 服务暂时不可用，已为你切换到本地规则版';
      case 'bad_request':
        return '请求格式有误，已为你切换到本地规则版';
      case 'cancelled':
        return '已取消生成';
      case 'empty':
        return 'AI 返回为空，已为你切换到本地规则版';
      default:
        return '网络不可用，已为你切换到本地规则版';
    }
  }
}
