import { TokenStorage } from '../../common/storage/TokenStorage';
import { RecordService } from '../record/RecordService';
import { RecordResponse, formatDurationLabel, formatRecordTime, normalizeTitle, sourceLabel } from '../record/RecordModels';
import { BatchOcrTaskSummaryResponse, ExportJobResponse } from '../v2/V2Models';
import { V2Service } from '../v2/V2Service';
import { HomeDashboardItem, HomeDashboardState } from './HomeDashboardModels';

/**
 * HomeDashboardService 聚合首页真实读模型。
 * 维护边界：服务只读取当前用户的 records、batch 和 export 摘要；不返回 OCR 全文、Token、objectKey 或完整媒体 URI。
 */
export class HomeDashboardService {
  private static readonly DASHBOARD_LOAD_TIMEOUT_MS: number = 6000;

  /**
   * 加载首页聚合数据。
   * 返回值会按登录状态和超时情况降级，不暴露 OCR 全文、Token、objectKey 或完整媒体 URI。
   */
  static async load(): Promise<HomeDashboardState> {
    const hasToken = await TokenStorage.hasToken();
    if (!hasToken) {
      return HomeDashboardService.emptyLoggedOut();
    }

    try {
      return await HomeDashboardService.withDashboardTimeout(HomeDashboardService.loadAuthenticated());
    } catch (_) {
      return HomeDashboardService.unavailableLoggedIn();
    }
  }

  /**
   * 读取首页所需的多个后端摘要；调用方通过超时保护避免页面长期停留在同步中。
   */
  private static async loadAuthenticated(): Promise<HomeDashboardState> {
    const records = await RecordService.listRecords({ page: 0, size: 4, sort: 'updatedAt_desc' });
    const batches = await V2Service.listBatchTasks();
    const exportJobs = await V2Service.listExportJobs();
    const pendingItems = HomeDashboardService.toPendingItems(batches, exportJobs);
    const recentItems = HomeDashboardService.toRecentItems(records.items);
    return {
      loggedIn: true,
      unavailable: false,
      pendingItems: pendingItems,
      recentItems: recentItems,
      pendingMeta: pendingItems.length > 0 ? '来自真实任务' : '暂无待处理',
      recentMeta: records.total > 0 ? records.total.toString() + ' 条记录' : '暂无记录',
      statusText: '已登录，正在同步真实记录',
      statusTone: 'success'
    };
  }

  private static async withDashboardTimeout(task: Promise<HomeDashboardState>): Promise<HomeDashboardState> {
    return new Promise<HomeDashboardState>((resolve: (value: HomeDashboardState) => void) => {
      let completed = false;
      setTimeout(() => {
        if (!completed) {
          completed = true;
          resolve(HomeDashboardService.unavailableLoggedIn());
        }
      }, HomeDashboardService.DASHBOARD_LOAD_TIMEOUT_MS);
      task.then((value: HomeDashboardState) => {
        if (!completed) {
          completed = true;
          resolve(value);
        }
      }).catch(() => {
        if (!completed) {
          completed = true;
          resolve(HomeDashboardService.unavailableLoggedIn());
        }
      });
    });
  }

  private static emptyLoggedOut(): HomeDashboardState {
    return {
      loggedIn: false,
      unavailable: false,
      pendingItems: [],
      recentItems: [],
      pendingMeta: '登录后同步真实记录',
      recentMeta: '登录后同步真实记录',
      statusText: '未登录，登录后同步真实记录',
      statusTone: 'warning'
    };
  }

  private static unavailableLoggedIn(): HomeDashboardState {
    return {
      loggedIn: true,
      unavailable: true,
      pendingItems: [],
      recentItems: [],
      pendingMeta: '同步不可用',
      recentMeta: '同步不可用',
      statusText: '暂时无法同步记录',
      statusTone: 'danger'
    };
  }

  private static toPendingItems(
    batches: BatchOcrTaskSummaryResponse[],
    exportJobs: ExportJobResponse[]
  ): HomeDashboardItem[] {
    const items: HomeDashboardItem[] = [];
    batches.filter((job: BatchOcrTaskSummaryResponse) => job.status !== 'SUCCESS')
      .slice(0, 2)
      .forEach((job: BatchOcrTaskSummaryResponse, index: number) => {
        items.push({
          id: 'batch-' + job.jobId,
          mark: 'DOC',
          title: HomeDashboardService.batchTitle(job),
          meta: job.total.toString() + ' 个文件 · ' + job.completed.toString() + ' 已完成 · ' + job.failed.toString() + ' 失败',
          badge: job.failed > 0 ? '需重试' : '处理中',
          tone: job.failed > 0 ? 'warn' : 'neutral',
          route: 'batch',
          jobId: job.jobId
        });
      });
    exportJobs.filter((job: ExportJobResponse) => job.status !== 'SUCCESS')
      .slice(0, 1)
      .forEach((job: ExportJobResponse) => {
        items.push({
          id: 'export-' + job.jobId,
          mark: '导出',
          title: HomeDashboardService.safeTitle(job.fileName, '导出任务'),
          meta: job.format + ' · ' + job.status,
          badge: '导出',
          tone: 'neutral',
          route: 'export',
          jobId: job.jobId
        });
      });
    return items.slice(0, 3);
  }

  private static toRecentItems(records: RecordResponse[]): HomeDashboardItem[] {
    const items: HomeDashboardItem[] = [];
    // 最近记录只映射 OCR 历史记录，导出任务不得补位成历史记录。
    records.slice(0, 3).forEach((record: RecordResponse) => {
      items.push({
        id: 'record-' + record.id.toString(),
        mark: record.sourceType === 'import' ? 'DOC' : 'IMG',
        title: normalizeTitle(record),
        meta: sourceLabel(record.sourceType) + ' · ' + formatDurationLabel(record.durationMs ?? 0) + ' · ' + formatRecordTime(record.updatedAt),
        badge: record.favorite ? '收藏' : '可编辑',
        tone: record.favorite ? 'dark' : 'ok',
        route: 'recordDetail',
        recordId: record.id.toString()
      });
    });
    return items;
  }

  private static batchTitle(job: BatchOcrTaskSummaryResponse): string {
    if (job.items.length > 0 && job.items[0].fileName.length > 0) {
      return job.items[0].fileName;
    }
    return '批量 OCR 任务';
  }

  private static safeTitle(value: string | undefined, fallback: string): string {
    if (value !== undefined && value.trim().length > 0) {
      return value.trim();
    }
    return fallback;
  }

}
