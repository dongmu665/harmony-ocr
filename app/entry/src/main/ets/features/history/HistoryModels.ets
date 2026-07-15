/**
 * HistoryModels 定义 OCR 历史记录在前端列表和详情页的展示模型，属于 features/history 模块。
 *
 * 维护说明：该模型面向已完成归属校验的当前用户数据；不要在列表模型中加入 Token、完整媒体 URI 或对象存储 key。
 */
export type HistorySourceType = 'camera' | 'album';

/**
 * 历史记录列表项。
 *
 * 说明：previewText 只用于列表摘要展示，详情页需要展示全文时必须通过记录详情接口或已校验状态获取。
 */
export interface HistoryRecordItem {
  id: string;
  title: string;
  sourceType: HistorySourceType;
  sourceLabel: string;
  previewText: string;
  createdAtText: string;
  language: string;
  engineName: string;
  elapsedMs: number;
  isFavorite: boolean;
}

/**
 * 历史记录详情模型。
 *
 * 安全边界：recognizedText 属于 OCR 隐私文本，只能在当前用户有权访问的详情页内展示和编辑。
 */
export interface HistoryRecordDetail extends HistoryRecordItem {
  recognizedText: string;
}

/**
 * 历史搜索结果模型。
 *
 * 维护说明：keyword 仅保存在页面状态中，不写日志、不作为跨用户查询条件。
 */
export interface HistorySearchResult {
  keyword: string;
  records: HistoryRecordItem[];
  isSearchMode: boolean;
}
