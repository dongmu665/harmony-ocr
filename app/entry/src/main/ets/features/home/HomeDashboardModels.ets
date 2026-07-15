/**
 * HomeDashboardModels 定义首页工作台聚合数据模型，属于 features/home 模块。
 *
 * 维护说明：首页只展示任务状态、最近记录摘要和安全导航信息，不承载 OCR 全文、Token、API Key 或对象存储 key。
 */
export type HomeDashboardItemTone = 'neutral' | 'ok' | 'warn' | 'danger' | 'dark';
export type HomeDashboardItemRoute = 'history' | 'recordDetail' | 'batch' | 'export' | 'ai';

/**
 * 首页待处理或最近记录条目。
 *
 * 说明：recordId/jobId 只用于应用内跳转和查询当前用户资源，不能被当作权限凭证。
 */
export interface HomeDashboardItem {
  id: string;
  mark: string;
  title: string;
  meta: string;
  badge: string;
  tone: HomeDashboardItemTone;
  route: HomeDashboardItemRoute;
  recordId?: string;
  jobId?: string;
}

/**
 * 首页工作台整体状态。
 *
 * 维护说明：服务不可用时通过 unavailable/statusText 告知页面降级，不应把底层异常、URL 或认证信息暴露给 UI。
 */
export interface HomeDashboardState {
  loggedIn: boolean;
  unavailable: boolean;
  pendingItems: HomeDashboardItem[];
  recentItems: HomeDashboardItem[];
  pendingMeta: string;
  recentMeta: string;
  statusText: string;
  statusTone: 'success' | 'warning' | 'danger' | 'neutral';
}
