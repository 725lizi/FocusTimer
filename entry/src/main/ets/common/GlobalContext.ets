/**
 * 全局上下文管理器
 * 用于在组件间共享状态
 */
export class GlobalContext {
  private static instance: GlobalContext | null = null;
  private contextMap: Map<string, Object> = new Map<string, Object>();

  private constructor() {
  }

  public static getContext(): GlobalContext {
    if (GlobalContext.instance === null) {
      GlobalContext.instance = new GlobalContext();
    }
    return GlobalContext.instance;
  }

  public setObject(key: string, value: Object): void {
    this.contextMap.set(key, value);
  }

  public getObject(key: string): Object | undefined {
    return this.contextMap.get(key);
  }

  public removeObject(key: string): void {
    this.contextMap.delete(key);
  }

  public clearAll(): void {
    this.contextMap.clear();
  }
}