/**
 * HistoryState 保存历史记录页面的临时导航状态，属于 features/history 模块。
 * 维护说明：状态只保存当前 recordId 和搜索关键词，不保存 Token、图片对象 key 或 OCR 全文。
 */
export class HistoryState {
  private static currentRecordId: string = '';
  private static lastKeyword: string = '';
  private static verifierStage: string = '';
  private static verifierTagId: number = 0;

  /**
   * 记录当前选中的后端历史记录 id。
   * 参数 id 来自列表项；详情页只用该 id 重新请求后端详情，避免通过路由或内存传递 OCR 长文本。
   */
  static selectRecord(id: string): void {
    HistoryState.currentRecordId = id;
  }

  /**
   * 读取当前选中的记录 id。
   * 返回值只用于详情页重新请求后端，不携带记录正文或对象存储 key。
   */
  static getCurrentRecordId(): string {
    return HistoryState.currentRecordId;
  }

  /**
   * 保存历史列表页最近一次搜索关键词。
   * 参数 keyword 只用于页面返回时恢复输入框，不会持久化到设备或后端。
   */
  static setLastKeyword(keyword: string): void {
    HistoryState.lastKeyword = keyword;
  }

  /**
   * 读取最近一次搜索关键词。
   * 维护说明：关键词只存在内存中，用于页面返回恢复，不写入设备持久化存储。
   */
  static getLastKeyword(): string {
    return HistoryState.lastKeyword;
  }

  /**
   * C3 运行时验收使用的短期 stage 标记。
   * 参数只允许保存 page-stage 名称，不包含 Token、OCR 全文、对象 key 或路径。
   */
  static setVerifierStage(stage: string): void {
    HistoryState.verifierStage = stage;
  }

  /**
   * 读取运行时验收 stage 标记。
   * 返回值只影响页面筛选预设，不参与后端鉴权或数据归属判断。
   */
  static getVerifierStage(): string {
    return HistoryState.verifierStage;
  }

  /**
   * C3 运行期专用标签筛选 ID。
   * 参数只用于触发后端真实归属校验，不保存标签名称、OCR 文本或任何凭证。
   */
  static setVerifierTagId(tagId: number): void {
    HistoryState.verifierTagId = tagId > 0 ? tagId : 0;
  }

  /**
   * 读取运行时验收标签 ID。
   * 说明：该 ID 只触发真实后端查询，不能作为绕过 ownership 的凭据。
   */
  static getVerifierTagId(): number {
    return HistoryState.verifierTagId;
  }

  /**
   * 清空当前选中记录 id。
   * 维护说明：只清理内存中的导航选择，不删除历史记录或本地缓存。
   */
  static clearSelection(): void {
    HistoryState.currentRecordId = '';
  }
}
