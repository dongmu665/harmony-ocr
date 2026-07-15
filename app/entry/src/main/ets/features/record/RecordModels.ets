/**
 * RecordModels 定义前端 records API 的数据契约，属于 features/record 模块。
 * 维护说明：字段名严格对齐后端 record DTO；页面展示所需摘要和标签应通过转换函数派生，不反向污染 API 模型。
 */
export type RecordSourceType = 'camera' | 'album' | 'import' | 'pdf' | 'batch';

/**
 * RecordBlockRequest 表示创建记录时上传的单个 OCR 文本块。
 * 安全边界：boundingBox 仅保存识别区域字符串，不应包含本地图片路径或媒体 URI。
 */
export interface RecordBlockRequest {
  blockIndex?: number;
  text?: string;
  confidence?: number;
  boundingBox?: string;
}

/**
 * RecordBlockResponse 表示后端返回的单个 OCR 文本块。
 * 维护说明：页面可以展示 text 和 confidence，但不应把全文写入调试日志。
 */
export interface RecordBlockResponse {
  id: number;
  blockIndex?: number;
  text?: string;
  confidence?: number;
  boundingBox?: string;
}

/**
 * RecordPageRequest 表示 PDF 多页识别的页级保存请求。
 * 安全边界：每页只传识别结果和状态，不传 PDF URI、本地路径或对象存储 key。
 */
export interface RecordPageRequest {
  pageIndex?: number;
  pageNumber?: number;
  status?: string;
  rawText?: string;
  editedText?: string;
  durationMs?: number;
  confidence?: number;
  errorCode?: string;
  failureReason?: string;
  blocks?: RecordBlockRequest[];
}

/**
 * RecordPageResponse 表示后端返回的 PDF 页级识别结果。
 * 维护说明：失败页只展示 errorCode/failureReason 等脱敏信息，不暴露底层 Provider 异常栈。
 */
export interface RecordPageResponse {
  id: number;
  pageIndex?: number;
  pageNumber?: number;
  status?: string;
  rawText?: string;
  editedText?: string;
  durationMs?: number;
  confidence?: number;
  errorCode?: string;
  failureReason?: string;
  blocks?: RecordBlockResponse[];
}

/**
 * RecordTagResponse 表示历史记录标签元数据。
 * 安全边界：标签只用于用户自己的记录分类，不承载 OCR 全文或资源地址。
 */
export interface RecordTagResponse {
  id: number;
  name: string;
  color?: string;
  createdAt: string;
  updatedAt: string;
}

/**
 * CreateRecordRequest 是保存 OCR 历史记录的请求模型。
 * 维护说明：imageObjectKey 必须来自 files/upload 响应，前端不得自行拼接或复用其他用户资源。
 */
export interface CreateRecordRequest {
  title?: string;
  sourceType: RecordSourceType;
  imageObjectKey?: string;
  rawText?: string;
  editedText?: string;
  language?: string;
  ocrEngine?: string;
  durationMs?: number;
  favorite?: boolean;
  blocks?: RecordBlockRequest[];
  pages?: RecordPageRequest[];
}

/**
 * UpdateRecordRequest 是编辑历史记录的请求模型。
 * 安全边界：只允许修改标题、编辑文本和收藏状态，不允许前端改写 userId、objectKey 或删除标记。
 */
export interface UpdateRecordRequest {
  title?: string;
  editedText?: string;
  favorite?: boolean;
}

/**
 * FavoriteRecordRequest 表示收藏状态更新。
 * 维护说明：ownership 与幂等处理由后端负责，前端只传目标布尔值。
 */
export interface FavoriteRecordRequest {
  favorite: boolean;
}

/**
 * RecordResponse 表示历史记录详情响应。
 * 安全边界：该响应只属于当前登录用户；页面和服务层不得缓存或展示其他用户记录。
 */
export interface RecordResponse {
  id: number;
  title?: string;
  sourceType: RecordSourceType;
  imageObjectKey?: string;
  rawText?: string;
  editedText?: string;
  language?: string;
  ocrEngine?: string;
  durationMs?: number;
  favorite: boolean;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
  blocks?: RecordBlockResponse[];
  tags?: RecordTagResponse[];
  pages?: RecordPageResponse[];
  pageCount?: number;
  successPageCount?: number;
  failedPageCount?: number;
  partial?: boolean;
}

export type RecordSortOption =
  'createdAt_desc' | 'createdAt_asc' | 'updatedAt_desc' | 'updatedAt_asc' | 'durationMs_desc' | 'durationMs_asc';

/**
 * RecordQueryParams 描述历史记录分页筛选条件。
 * 维护说明：keyword/date/tag 等过滤条件都只作用于当前登录用户的记录集合。
 */
export interface RecordQueryParams {
  page?: number;
  size?: number;
  favorite?: boolean;
  sourceType?: RecordSourceType;
  keyword?: string;
  createdFrom?: string;
  createdTo?: string;
  dateFrom?: string;
  dateTo?: string;
  tagId?: number;
  ocrEngine?: string;
  sort?: RecordSortOption;
}

export type RecordQuery = RecordQueryParams;

/**
 * RecordPageResult 是 records API 的分页响应容器。
 * 维护说明：items 中的记录必须已经由后端按当前用户过滤。
 */
export interface RecordPageResult<T> {
  items: T[];
  total: number;
  page: number;
  size: number;
}

/**
 * RecordListViewItem 是历史列表的脱敏展示模型。
 * 安全边界：previewText 只保留短摘要，列表页不得展示或记录完整 OCR 文本。
 */
export interface RecordListViewItem {
  id: string;
  title: string;
  sourceType: RecordSourceType;
  sourceLabel: string;
  previewText: string;
  createdAtText: string;
  language: string;
  engineName: string;
  elapsedMs: number;
  isFavorite: boolean;
  tags: RecordTagResponse[];
  pageCount?: number;
  partial?: boolean;
}

/**
 * 将后端记录转换为列表展示模型。
 * 参数 record 来自已解包的 records API 响应；返回值只包含 UI 展示需要的脱敏摘要，不记录 OCR 全文。
 */
export function toRecordListViewItem(record: RecordResponse): RecordListViewItem {
  return {
    id: String(record.id),
    title: normalizeTitle(record),
    sourceType: record.sourceType,
    sourceLabel: sourceLabel(record.sourceType),
    previewText: previewText(record),
    createdAtText: formatRecordTime(record.createdAt),
    language: record.language ?? 'unknown',
    engineName: record.ocrEngine ?? 'unknown',
    elapsedMs: record.durationMs ?? 0,
    isFavorite: record.favorite,
    tags: record.tags ?? [],
    pageCount: record.pageCount,
    partial: record.partial
  };
}

/**
 * 将记录来源类型转换为页面文案。
 * 参数 sourceType 来自后端枚举；未知值按拍照识别兜底，避免页面空白。
 */
export function sourceLabel(sourceType: RecordSourceType): string {
  if (sourceType === 'album') {
    return '相册识别';
  }
  if (sourceType === 'import') {
    return '导入识别';
  }
  if (sourceType === 'pdf') {
    return 'PDF 识别';
  }
  if (sourceType === 'batch') {
    return '批量识别';
  }
  return '拍照识别';
}

/**
 * 生成列表预览文本。
 * 参数 record 为当前用户记录；返回值会压缩换行并截断，避免列表页泄露过多 OCR 全文。
 */
export function previewText(record: RecordResponse): string {
  const text = (record.editedText && record.editedText.length > 0) ? record.editedText : (record.rawText ?? '');
  const normalized = text.replace(/\r/g, '\n').replace(/\n+/g, ' ').trim();
  if (normalized.length === 0) {
    return '暂无可展示的识别文本';
  }
  return normalized.length > 72 ? normalized.substring(0, 72) + '...' : normalized;
}

/**
 * 返回详情页应展示的主文本。
 * 说明：优先使用用户编辑文本，空值时回退到原始识别文本。
 */
export function detailText(record: RecordResponse): string {
  return (record.editedText && record.editedText.length > 0) ? record.editedText : (record.rawText ?? '');
}

/**
 * 生成记录标题。
 * 参数 record 缺少标题时使用来源和创建时间兜底，避免列表出现空标题。
 */
export function normalizeTitle(record: RecordResponse): string {
  if (record.title && record.title.trim().length > 0) {
    return record.title;
  }
  return `${sourceLabel(record.sourceType)} ${formatRecordTime(record.createdAt)}`;
}

/**
 * 格式化记录时间。
 * 参数 value 来自后端 ISO 时间字符串；返回值只用于 UI 展示，不参与时区计算。
 */
export function formatRecordTime(value?: string): string {
  if (!value || value.length === 0) {
    return '未知时间';
  }
  return value.replace('T', ' ').substring(0, 19);
}

/**
 * 将耗时格式化为页面标签。
 * 参数 durationMs 直接来自 OCR 或历史记录，仅用于 UI 展示。
 */
export function formatDurationLabel(durationMs: number): string {
  if (durationMs <= 0) {
    return '0 ms';
  }
  if (durationMs < 1000) {
    return `${durationMs} ms`;
  }
  const seconds = durationMs / 1000;
  return `${seconds.toFixed(seconds >= 10 ? 1 : 2)} s`;
}
