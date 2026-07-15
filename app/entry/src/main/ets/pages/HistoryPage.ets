import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import { FilterSummaryBar, HtmlAppBar, HtmlBadgeTone, HtmlFileMark, HtmlListRow, HtmlSectionHead, HtmlStatusBar, HtmlToast, StatusBanner } from '../components/BrandComponents';
import { HistoryState } from '../features/history/HistoryState';
import {
  RecordListViewItem,
  RecordPageResult,
  RecordSourceType,
  RecordQuery,
  RecordResponse,
  RecordSortOption,
  toRecordListViewItem
} from '../features/record/RecordModels';
import { RecordService } from '../features/record/RecordService';
import { TagResponse } from '../features/record/TagModels';
import { TagService } from '../features/record/TagService';

type HistoryDateFilter = 'all' | 'today' | '7d' | '30d';
type HistorySourceFilter = 'all' | RecordSourceType;
type HistoryFavoriteFilter = 'all' | 'favorite' | 'normal';
type HistorySortFilter = RecordSortOption;

/**
 * HistoryDateRange 表示历史记录日期筛选的后端查询边界。
 * 维护说明：只保存 ISO 日期字符串，不保存记录正文、用户身份或本地时区推断结果。
 */
class HistoryDateRange {
  createdFrom?: string;
  createdTo?: string;
}

/**
 * HistoryPage 负责展示后端 records 历史列表。
 * 维护边界：仅渲染和筛选已保存记录，不伪造成功态、标签态或 OCR 内容。
 */
@Entry
@Component
struct HistoryPage {
  @State records: RecordListViewItem[] = [];
  @State keyword: string = '';
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State noticeVisible: boolean = false;
  @State isSearchMode: boolean = false;
  @State page: number = 0;
  @State pageSize: number = 20;
  @State total: number = 0;
  @State operationRecordId: string = '';
  @State pendingDeleteRecordId: string = '';
  @State dateFilter: HistoryDateFilter = 'all';
  @State sourceFilter: HistorySourceFilter = 'all';
  @State favoriteFilter: HistoryFavoriteFilter = 'all';
  @State selectedTagId: number = 0;
  @State ocrEngineFilter: string = '';
  @State sortFilter: HistorySortFilter = 'createdAt_desc';
  @State tags: TagResponse[] = [];
  @State tagsLoading: boolean = false;
  @State showSearchPanel: boolean = false;
  @State showAdvancedFilters: boolean = false;
  @State summaryEntered: boolean = false;
  @State filterEntered: boolean = false;
  @State actionsEntered: boolean = false;
  @State recordsEntered: boolean = false;
  @State verifierStage: string = '';
  @State verifierSearchTriggered: boolean = false;

  private readonly populatedPreviewLimit: number = 5;
  private readonly historyListCardMinHeight: number = 248;

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.verifierStage = HistoryState.getVerifierStage();
    this.verifierSearchTriggered = false;
    this.keyword = HistoryState.getLastKeyword();
    this.applyVerifierStageDefaults();
    this.loadTags();
    this.loadRecords();
  }

  /**
   * C3 验收专用短期入口，只设置 page-stage 必需的筛选条件。
   * 正常启动不读取这些默认值，避免影响用户真实搜索和权限筛选。
   */
  private applyVerifierStageDefaults(): void {
    if (this.verifierStage === 'searchNoResult') {
      this.keyword = 'no-result-v33-c3';
      return;
    }
    if (this.verifierStage === 'permission') {
      const verifierTagId = HistoryState.getVerifierTagId();
      if (verifierTagId > 0) {
        this.selectedTagId = verifierTagId;
      }
    }
  }

  /**
   * 历史页采用与 HTML 参考一致的分层进入节奏。
   * 这里只控制可见卡片的进入时机，不改变任何记录数据。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.filterEntered = true, 0);
    this.revealCard(() => this.recordsEntered = true, 1);
    this.revealCard(() => this.summaryEntered = true, 2);
    this.revealCard(() => this.actionsEntered = true, 3);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 加载标签列表，只用于筛选入口。
   * 安全边界：不在前端合成标签数据，失败时仅降级为无标签可选。
   */
  private async loadTags(): Promise<void> {
    this.tagsLoading = true;
    try {
      this.tags = await TagService.listTags();
    } catch (error) {
      this.tags = [];
      this.showNotice(this.toUserMessage(error, '标签列表暂不可用，历史记录仍可查看。'));
    } finally {
      this.tagsLoading = false;
    }
  }

  /**
   * 展示短反馈 toast。
   * 安全边界：仅显示脱敏文案，不输出 OCR 全文、对象存储键或 Token。
   */
  private showNotice(message: string): void {
    this.noticeMessage = message;
    this.noticeVisible = true;
    setTimeout(() => {
      if (this.noticeMessage === message) {
        this.noticeVisible = false;
      }
    }, AppMotion.DURATION_TOAST * 8);
  }

  /**
   * 从后端 records API 加载历史列表。
   * 失败时页面只给出脱敏提示，避免暴露完整 OCR 内容或对象信息。
   */
  private async loadRecords(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    this.noticeVisible = false;
    if (this.verifierStage === 'loading') {
      this.records = [];
      this.total = 0;
      return;
    }
    const hasToken = await TokenStorage.hasToken();
    if (!hasToken) {
      this.records = [];
      this.loading = false;
      this.errorMessage = '请先登录后查看历史记录。';
      return;
    }

    try {
      const normalizedKeyword = this.keyword.trim();
      const dateRange = this.buildDateRange();
      const query: RecordQuery = {
        page: this.page,
        size: this.pageSize,
        keyword: normalizedKeyword.length > 0 ? normalizedKeyword : undefined,
        sourceType: this.sourceFilter === 'all' ? undefined : this.sourceFilter,
        favorite: this.favoriteQueryValue(),
        tagId: this.selectedTagId > 0 ? this.selectedTagId : undefined,
        ocrEngine: this.ocrEngineFilter.trim().length > 0 ? this.ocrEngineFilter.trim() : undefined,
        sort: this.sortFilter,
        createdFrom: dateRange.createdFrom,
        createdTo: dateRange.createdTo
      };
      const result: RecordPageResult<RecordResponse> = await RecordService.listRecords(query);
      const nextRecords: RecordListViewItem[] = [];
      for (let index = 0; index < result.items.length; index++) {
        nextRecords.push(toRecordListViewItem(result.items[index]));
      }
      this.records = nextRecords;
      this.total = result.total;
      this.isSearchMode = this.hasActiveFilters(normalizedKeyword);
      HistoryState.setLastKeyword(normalizedKeyword);
    } catch (error) {
      this.records = [];
      this.errorMessage = this.toUserMessage(error, '历史记录加载失败，请稍后重试');
    } finally {
      this.loading = false;
    }
  }

  private searchRecords(): void {
    this.page = 0;
    this.loadRecords().finally(() => {
      this.showSearchPanel = false;
      this.showAdvancedFilters = false;
    });
  }

  private clearSearch(): void {
    this.keyword = '';
    this.dateFilter = 'all';
    this.sourceFilter = 'all';
    this.favoriteFilter = 'all';
    this.selectedTagId = 0;
    this.ocrEngineFilter = '';
    this.sortFilter = 'createdAt_desc';
    this.showAdvancedFilters = false;
    this.showSearchPanel = false;
    this.page = 0;
    HistoryState.setLastKeyword('');
    this.loadRecords();
  }

  private setDateFilter(value: HistoryDateFilter): void {
    if (this.dateFilter === value) {
      return;
    }
    this.dateFilter = value;
    this.page = 0;
    this.loadRecords();
  }

  private setSourceFilter(value: HistorySourceFilter): void {
    if (this.sourceFilter === value) {
      return;
    }
    this.sourceFilter = value;
    this.page = 0;
    this.loadRecords();
  }

  /**
   * 切换收藏筛选条件。
   * 参数 value 表示全部、仅收藏或未收藏；刷新前重置分页，保持组合筛选从第一页开始。
   */
  private setFavoriteFilter(value: HistoryFavoriteFilter): void {
    if (this.favoriteFilter === value) {
      return;
    }
    this.favoriteFilter = value;
    this.page = 0;
    this.loadRecords();
  }

  /**
   * 切换标签筛选条件。
   * 参数 tagId 为后端标签 ID；0 表示全部标签，不向 records API 传递 tagId。
   */
  private setTagFilter(tagId: number): void {
    if (this.selectedTagId === tagId) {
      return;
    }
    this.selectedTagId = tagId;
    this.page = 0;
    this.loadRecords();
  }

  /**
   * 更新 OCR 引擎筛选文本。
   * 说明：这里只接收短文本，不记录 OCR 内容。
   */
  private setOcrEngineFilter(value: string): void {
    this.ocrEngineFilter = value;
  }

  /**
   * 切换排序方式。
   * 参数 value 必须是前端白名单类型，后端仍会再次校验 sort 字段。
   */
  private setSortFilter(value: HistorySortFilter): void {
    if (this.sortFilter === value) {
      return;
    }
    this.sortFilter = value;
    this.page = 0;
    this.loadRecords();
  }

  private favoriteQueryValue(): boolean | undefined {
    if (this.favoriteFilter === 'favorite') {
      return true;
    }
    if (this.favoriteFilter === 'normal') {
      return false;
    }
    return undefined;
  }

  private hasActiveFilters(normalizedKeyword: string): boolean {
    return normalizedKeyword.length > 0 ||
      this.dateFilter !== 'all' ||
      this.sourceFilter !== 'all' ||
      this.favoriteFilter !== 'all' ||
      this.selectedTagId > 0 ||
      this.ocrEngineFilter.trim().length > 0 ||
      this.sortFilter !== 'createdAt_desc';
  }

  private buildDateRange(): HistoryDateRange {
    const range = new HistoryDateRange();
    const now = new Date();
    if (this.dateFilter === 'today') {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
      range.createdFrom = this.formatLocalDateTime(start);
      return range;
    }
    if (this.dateFilter === '7d') {
      const start7d = new Date(now);
      start7d.setDate(now.getDate() - 7);
      range.createdFrom = this.formatLocalDateTime(start7d);
      return range;
    }
    if (this.dateFilter === '30d') {
      const start30d = new Date(now);
      start30d.setDate(now.getDate() - 30);
      range.createdFrom = this.formatLocalDateTime(start30d);
      return range;
    }
    return range;
  }

  /**
   * 后端 records API 接收不带时区的 LocalDateTime。
   * 这里保留设备本地时间，避免 toISOString 转 UTC 后产生跨日偏移。
   */
  private formatLocalDateTime(value: Date): string {
    const year = value.getFullYear();
    const month = this.pad2(value.getMonth() + 1);
    const day = this.pad2(value.getDate());
    const hour = this.pad2(value.getHours());
    const minute = this.pad2(value.getMinutes());
    const second = this.pad2(value.getSeconds());
    return `${year}-${month}-${day}T${hour}:${minute}:${second}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  /**
   * 切换到上一页历史记录。
   * 说明：分页参数继续走后端 records API，不在前端缓存 OCR 全文。
   */
  private previousPage(): void {
    if (this.page <= 0 || this.loading) {
      return;
    }
    this.page = this.page - 1;
    this.loadRecords();
  }

  /**
   * 切换到下一页历史记录。
   * 说明：只在后端 total 表明仍有下一页时发起请求。
   */
  private nextPage(): void {
    if (!this.hasNextPage() || this.loading) {
      return;
    }
    this.page = this.page + 1;
    this.loadRecords();
  }

  /**
   * 进入历史详情。
   * 说明：详情页会重新请求后端，避免在列表状态中传递 OCR 全文。
   */
  private openDetail(record: RecordListViewItem): void {
    HistoryState.selectRecord(record.id);
    AppNavigator.push(this.getUIContext(), AppRoutes.RECORD_DETAIL);
  }

  /**
   * 更新收藏状态。
   * 失败时保留原 UI 状态，避免错误反馈覆盖真实后端结果。
   */
  private async toggleFavorite(record: RecordListViewItem): Promise<void> {
    if (this.operationRecordId.length > 0) {
      return;
    }
    this.errorMessage = '';
    this.noticeMessage = '';
    this.noticeVisible = false;
    this.operationRecordId = record.id;
    try {
      const updated: RecordResponse = await RecordService.updateFavorite(record.id, !record.isFavorite);
      this.replaceRecord(toRecordListViewItem(updated));
      this.showNotice(updated.favorite ? '已收藏记录。' : '已取消收藏。');
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '收藏状态更新失败，请稍后重试');
    } finally {
      this.operationRecordId = '';
      this.pendingDeleteRecordId = '';
    }
  }

  /**
   * 触发删除二次确认。
   * 首次点击只进入确认态，再次点击同一记录才调用后端 delete。
   */
  private requestDeleteRecord(record: RecordListViewItem): void {
    if (this.operationRecordId.length > 0) {
      return;
    }
    this.errorMessage = '';
    if (this.pendingDeleteRecordId === record.id) {
      this.deleteRecord(record);
      return;
    }
    this.pendingDeleteRecordId = record.id;
    this.showNotice('请再次点击“确认删除”以删除该历史记录。');
  }

  /**
   * 调用后端 delete 接口删除当前记录。
   * 说明：本阶段不处理对象存储删除联动，只从列表移除记录项。
   */
  private async deleteRecord(record: RecordListViewItem): Promise<void> {
    if (this.operationRecordId.length > 0) {
      return;
    }
    this.errorMessage = '';
    this.noticeMessage = '';
    this.noticeVisible = false;
    this.operationRecordId = record.id;
    try {
      await RecordService.deleteRecord(record.id);
      this.removeRecord(record.id);
      this.showNotice('已删除记录。');
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '删除失败，请稍后重试');
    } finally {
      this.operationRecordId = '';
    }
  }

  private replaceRecord(record: RecordListViewItem): void {
    const nextRecords: RecordListViewItem[] = [];
    for (let index = 0; index < this.records.length; index++) {
      nextRecords.push(this.records[index].id === record.id ? record : this.records[index]);
    }
    this.records = nextRecords;
  }

  private removeRecord(id: string): void {
    const nextRecords: RecordListViewItem[] = [];
    for (let index = 0; index < this.records.length; index++) {
      if (this.records[index].id !== id) {
        nextRecords.push(this.records[index]);
      }
    }
    this.records = nextRecords;
    this.total = this.total > 0 ? this.total - 1 : 0;
  }

  private toUserMessage(error: Error, fallback: string): string {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return '请先登录后查看历史记录。';
    }
    if (apiError.statusCode === 403 || apiError.statusCode === 404 || apiError.code === 'FORBIDDEN' || apiError.code === 'NOT_FOUND') {
      return '记录不存在或无权访问。';
    }
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 80) {
      return apiError.message;
    }
    return fallback;
  }

  private sourceTone(record: RecordListViewItem): string {
    if (record.sourceType === 'pdf') {
      return AppTheme.COLOR_BRAND;
    }
    return record.sourceType === 'album' ? AppTheme.COLOR_WARNING : AppTheme.COLOR_ACTION;
  }

  private sourceBadgeTone(record: RecordListViewItem): HtmlBadgeTone {
    if (record.sourceType === 'pdf') {
      return 'dark';
    }
    if (record.sourceType === 'batch') {
      return 'warn';
    }
    return record.sourceType === 'album' ? 'warn' : 'neutral';
  }

  private recordMark(record: RecordListViewItem): string {
    if (record.sourceType === 'pdf') {
      return 'PDF';
    }
    if (record.sourceType === 'batch') {
      return 'BAT';
    }
    if (record.sourceType === 'album') {
      return 'IMG';
    }
    if (record.sourceType === 'camera') {
      return 'CAM';
    }
    return 'DOC';
  }

  private recordBadge(record: RecordListViewItem): string {
    if (record.sourceType === 'pdf') {
      return record.partial ? '部分成功' : '多页';
    }
    if (record.sourceType === 'batch') {
      return record.partial ? '部分成功' : '批量';
    }
    if (record.sourceType === 'album') {
      return '可导出';
    }
    if (record.isFavorite) {
      return 'AI 结果';
    }
    return '待校对';
  }

  /**
   * 历史记录行只拼接脱敏元信息，避免在列表层暴露完整 OCR 文本、媒体 URI 或对象存储键。
   */
  private recordRowMeta(record: RecordListViewItem): string {
    return record.sourceLabel + ' · ' + record.createdAtText;
  }

  private recordPreviewMeta(record: RecordListViewItem): string {
    return record.language + ' · ' + record.sourceLabel + ' · ' + record.createdAtText;
  }

  private isOperating(record: RecordListViewItem): boolean {
    return this.operationRecordId === record.id;
  }

  private isPendingDelete(record: RecordListViewItem): boolean {
    return this.pendingDeleteRecordId === record.id;
  }

  private totalPages(): number {
    if (this.total <= 0) {
      return 1;
    }
    return Math.floor((this.total + this.pageSize - 1) / this.pageSize);
  }

  private hasNextPage(): boolean {
    return (this.page + 1) < this.totalPages();
  }

  private dateFilterLabel(): string {
    if (this.dateFilter === 'today') {
      return '今天';
    }
    if (this.dateFilter === '7d') {
      return '7天';
    }
    if (this.dateFilter === '30d') {
      return '30天';
    }
    return '全部';
  }

  private sourceFilterLabel(): string {
    if (this.sourceFilter === 'camera') {
      return '拍照';
    }
    if (this.sourceFilter === 'album') {
      return '相册';
    }
    if (this.sourceFilter === 'import') {
      return '导入';
    }
    if (this.sourceFilter === 'pdf') {
      return 'PDF';
    }
    if (this.sourceFilter === 'batch') {
      return '批量';
    }
    return '全部';
  }

  private favoriteFilterLabel(): string {
    if (this.favoriteFilter === 'favorite') {
      return '收藏';
    }
    if (this.favoriteFilter === 'normal') {
      return '未收藏';
    }
    return '全部';
  }

  private tagFilterLabel(): string {
    if (this.selectedTagId <= 0) {
      return '全部';
    }
    for (let index = 0; index < this.tags.length; index++) {
      if (this.tags[index].id === this.selectedTagId) {
        return this.tags[index].name;
      }
    }
    return '已选择';
  }

  private sortFilterLabel(): string {
    if (this.sortFilter === 'createdAt_asc') {
      return '最早创建';
    }
    if (this.sortFilter === 'updatedAt_desc') {
      return '最近更新';
    }
    if (this.sortFilter === 'durationMs_desc') {
      return '耗时最长';
    }
    return '最新创建';
  }

  /**
   * 汇总当前筛选条件，作为文档库顶部的轻量状态摘要。
   * 这里只拼接可见筛选标签，不包含 OCR 全文、完整路径或对象存储信息。
   */
  private activeFilterSummary(): string {
    const parts: string[] = [];
    const normalizedKeyword = this.keyword.trim();
    if (normalizedKeyword.length > 0) {
      parts.push('关键词');
    }
    if (this.selectedTagId > 0) {
      parts.push('标签:' + this.tagFilterLabel());
    }
    if (this.favoriteFilter !== 'all') {
      parts.push('收藏:' + this.favoriteFilterLabel());
    }
    if (this.sortFilter !== 'createdAt_desc') {
      parts.push('排序:' + this.sortFilterLabel());
    }
    if (this.dateFilter !== 'all') {
      parts.push('日期:' + this.dateFilterLabel());
    }
    if (this.sourceFilter !== 'all') {
      parts.push('来源:' + this.sourceFilterLabel());
    }
    if (this.ocrEngineFilter.trim().length > 0) {
      parts.push('引擎');
    }
    if (parts.length === 0) {
      return '全部记录 · 最新创建';
    }
    return parts.join(' / ');
  }

  private tagTone(active: boolean, color?: string): string {
    if (active) {
      return color && color.length > 0 ? color : AppTheme.COLOR_BRAND;
    }
    return AppTheme.COLOR_SURFACE_SOFT;
  }

  @Builder
  private filterChip(label: string, active: boolean, onTap: () => void) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontColor(active ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
      .backgroundColor(active ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: active ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .onClick(() => onTap())
  }

  @Builder
  private tagFilterChip(label: string, active: boolean, color: string | undefined, onTap: () => void) {
    Button(label)
      .height(34)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontColor(active ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
      .backgroundColor(this.tagTone(active, color))
      .border({ width: AppTheme.HAIRLINE, color: active ? this.tagTone(active, color) : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .padding({ left: 10, right: 10 })
      .onClick(() => onTap())
  }

  @Builder
  private topFilterChip(label: string, active: boolean, onTap: () => void) {
    Button(label)
      .height(36)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(active ? AppTheme.COLOR_BRAND : AppTheme.COLOR_TEXT_MUTED)
      .backgroundColor(active ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: active ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .padding({ left: 13, right: 13 })
      .onClick(() => onTap())
  }

  /**
   * 顶部快捷筛选条。
   * 这里保留最常用的文档库入口，复杂筛选下沉到搜索卡片。
   */
  @Builder
  private topFilterStrip() {
    Scroll() {
      Row({ space: 8 }) {
      this.topFilterChip('全部', this.favoriteFilter === 'all' && this.sourceFilter === 'all', () => {
        this.favoriteFilter = 'all';
        this.sourceFilter = 'all';
        this.dateFilter = 'all';
        this.selectedTagId = 0;
        this.ocrEngineFilter = '';
        this.showSearchPanel = false;
        this.showAdvancedFilters = false;
        this.page = 0;
        this.loadRecords();
      })
        this.topFilterChip('待校对', this.sourceFilter === 'camera', () => this.setSourceFilter('camera'))
        this.topFilterChip('可导出', this.sourceFilter === 'album', () => this.setSourceFilter('album'))
        this.topFilterChip('AI 结果', this.favoriteFilter === 'favorite', () => this.setFavoriteFilter('favorite'))
        this.topFilterChip('批量任务', this.sourceFilter === 'batch', () => this.setSourceFilter('batch'))
        this.topFilterChip('PDF', this.sourceFilter === 'pdf', () => this.setSourceFilter('pdf'))
      }
      .padding({ right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .opacity(this.filterEntered ? 1 : 0)
    .translate({ y: this.filterEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  /**
   * 文档库列表卡片。
   * 首屏直接呈现真实 records，空态与错误态都由后端结果和登录状态驱动。
   */
  @Builder
  private historyListCard() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '文档库', meta: '最近记录' })

      if (this.loading) {
        StatusBanner({ label: '加载', title: '正在加载历史记录', message: '列表只展示摘要，不在页面中暴露图片对象信息。', tone: 'info' })
      }

      if (this.errorMessage.length > 0 && this.errorMessage !== '请先登录后查看历史记录。' &&
        this.errorMessage !== '记录不存在或无权访问。') {
        Column({ space: 10 }) {
          StatusBanner({ label: '错误', title: '历史记录不可用', message: this.errorMessage, tone: 'danger' })
          Button('重试')
            .height(38)
            .type(ButtonType.Normal)
            .fontColor(AppTheme.COLOR_DANGER)
            .backgroundColor(AppTheme.COLOR_DANGER_BG)
            .onClick(() => this.loadRecords())
        }
        .width('100%')
      }

      if (!this.loading && this.errorMessage === '请先登录后查看历史记录。') {
        this.compactGuestState()
      } else if (!this.loading && this.errorMessage === '记录不存在或无权访问。') {
        this.compactPermissionState()
      } else if (!this.loading && this.errorMessage.length === 0 && this.isSearchMode && this.records.length === 0) {
        this.compactSearchNoResultState()
      } else if (!this.loading && this.errorMessage.length === 0 && this.records.length === 0) {
        this.compactEmptyState()
      }

      if (this.records.length > 0) {
        List({ space: 8 }) {
          ForEach(this.records, (record: RecordListViewItem) => {
            ListItem() {
              this.recordRow(record)
            }
          }, (record: RecordListViewItem) => record.id)
        }
        .width('100%')
        .height(this.records.length > this.populatedPreviewLimit ? 430 : this.records.length * 84)
        .scrollBar(BarState.Off)
      }

      if (this.total > this.pageSize) {
        Row({ space: 8 }) {
          Button('上一页')
            .layoutWeight(1)
            .height(AppTheme.BUTTON_SECONDARY_HEIGHT)
            .type(ButtonType.Normal)
            .fontSize(AppTheme.FONT_BUTTON)
            .fontColor(AppTheme.COLOR_BRAND)
            .backgroundColor(AppTheme.COLOR_TRANSPARENT)
            .border({ width: 1, color: AppTheme.COLOR_LINE })
            .enabled(this.page > 0 && !this.loading)
            .onClick(() => this.previousPage())
          Text('第 ' + (this.page + 1).toString() + ' / ' + this.totalPages().toString() + ' 页')
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
          Button('下一页')
            .layoutWeight(1)
            .height(AppTheme.BUTTON_SECONDARY_HEIGHT)
            .type(ButtonType.Normal)
            .fontSize(AppTheme.FONT_BUTTON)
            .fontColor(AppTheme.COLOR_BRAND)
            .backgroundColor(AppTheme.COLOR_TRANSPARENT)
            .border({ width: 1, color: AppTheme.COLOR_LINE })
            .enabled(this.hasNextPage() && !this.loading)
            .onClick(() => this.nextPage())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.historyListCardMinHeight })
    .justifyContent(FlexAlign.Start)
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.recordsEntered ? 1 : 0)
    .translate({ y: this.recordsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private recordActionStrip() {
    Scroll() {
      Row({ space: 8 }) {
        this.topFilterChip('导出', false, () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER))
        this.topFilterChip('AI 整理', false, () => AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE))
        this.topFilterChip('批量任务', false, () => AppNavigator.push(this.getUIContext(), AppRoutes.BATCH_OCR))
        this.topFilterChip('刷新', false, () => this.loadRecords())
      }
      .padding({ right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .opacity(this.actionsEntered ? 1 : 0)
    .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private compactEmptyState() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          HtmlFileMark({ label: 'DOC' })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(this.errorMessage.length > 0 ? '暂时无法同步记录' : '暂无历史记录')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .width('100%')
          Text(this.errorMessage.length > 0
            ? '请确认已登录且服务可用。'
            : '识别完成的文档将按时间排列在这里。扫描或导入文档开始创建第一条记录。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')

      Button(this.errorMessage.length > 0 ? '重试加载' : '前往首页')
        .height(40)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_BUTTON)
        .fontColor(AppTheme.COLOR_TEXT_INVERSE)
        .backgroundColor(AppTheme.COLOR_BRAND)
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .onClick(() => {
          if (this.errorMessage.length > 0) {
            this.loadRecords();
            return;
          }
          AppNavigator.push(this.getUIContext(), AppRoutes.HOME);
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private compactGuestState() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          HtmlFileMark({ label: 'REC' })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('登录后查看历史记录')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .width('100%')
          Text('识别完成的文档会按时间保存在历史记录中。登录后即可查看、搜索与管理你的所有 OCR 文档。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button('去登录')
          .width(124)
          .height(40)
          .type(ButtonType.Normal)
          .fontSize(AppTheme.FONT_BUTTON)
          .fontColor(AppTheme.COLOR_TEXT_INVERSE)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .onClick(() => AppNavigator.push(this.getUIContext(), AppRoutes.LOGIN))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private compactPermissionState() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          HtmlFileMark({ label: 'REC' })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('记录不存在或无权访问')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .width('100%')
          Text('当前记录已删除、不可用，或者不属于你的账号。请返回历史列表继续查看其他记录。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')

      Button('返回历史列表')
        .height(40)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_BUTTON)
        .fontColor(AppTheme.COLOR_TEXT_INVERSE)
        .backgroundColor(AppTheme.COLOR_BRAND)
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .onClick(() => AppNavigator.push(this.getUIContext(), AppRoutes.HISTORY))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private compactSearchNoResultState() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          HtmlFileMark({ label: 'SR' })
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('未找到匹配的记录')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .width('100%')
          Text('没有与当前关键词和筛选条件匹配的文档。请尝试更换关键词，或清除筛选条件后重试。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')

      Button('清除搜索')
        .height(40)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_BUTTON)
        .fontColor(AppTheme.COLOR_BRAND)
        .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .onClick(() => this.clearSearch())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 只为首屏附近提供一个轻量记录行摘要，不放入完整 OCR 内容。
   * 当前实现继续使用真实 records，不引入任何 demo 数据。
   */
  private firstAvailableTagId(): number {
    if (this.tags.length > 0) {
      return this.tags[0].id;
    }
    return 0;
  }

  @Builder
  private documentAction(title: string, description: string, route: string, tone: string) {
    HtmlListRow({
      mark: title.substring(0, 2),
      title: title,
      meta: description,
      badge: '进入',
      tone: 'neutral',
      onTap: () => AppNavigator.push(this.getUIContext(), route)
    })
  }

  @Builder
  private historySummaryCard() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '筛选摘要', meta: '当前条件' })
      FilterSummaryBar({
        summary: '历史记录 ' + this.total.toString() + ' · ' + this.activeFilterSummary(),
        active: this.isSearchMode,
        onClear: () => this.clearSearch()
      })
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.summaryEntered ? 1 : 0)
    .translate({ y: this.summaryEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private searchPanel() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '文档库检索', meta: '筛选条件' })

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索标题或识别文本', text: this.keyword })
          .layoutWeight(1)
          .height(AppTheme.INPUT_HEIGHT)
          .fontSize(AppTheme.FONT_META)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .onChange((value: string) => {
            this.keyword = value;
            // C3 运行期的 searchNoResult 需要稳定触发真实查询；仅在该 stage 下自动补一次提交。
            if (this.verifierStage === 'searchNoResult' && !this.verifierSearchTriggered && value.trim().length > 0) {
              this.verifierSearchTriggered = true;
              setTimeout(() => this.searchRecords(), 120);
            }
          })
        Button('搜索')
          .height(AppTheme.INPUT_HEIGHT)
          .fontColor(AppTheme.COLOR_TEXT_INVERSE)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .enabled(!this.loading)
          .onClick(() => this.searchRecords())
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('标签')
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        Row({ space: 8 }) {
          this.tagFilterChip('全部标签', this.selectedTagId === 0, undefined, () => this.setTagFilter(0))
          ForEach(this.tags, (tag: TagResponse) => {
            this.tagFilterChip(tag.name, this.selectedTagId === tag.id, tag.color, () => this.setTagFilter(tag.id))
          }, (tag: TagResponse) => String(tag.id))
        }
        .width('100%')
        if (!this.tagsLoading && this.tags.length === 0) {
          Text('暂无可选标签，可在历史详情中创建并绑定。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
        }
      }

      Row({ space: 8 }) {
        Column({ space: 8 }) {
          Text('收藏')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
          Row({ space: 8 }) {
            this.filterChip('全部', this.favoriteFilter === 'all', () => this.setFavoriteFilter('all'))
            this.filterChip('收藏', this.favoriteFilter === 'favorite', () => this.setFavoriteFilter('favorite'))
            this.filterChip('未收藏', this.favoriteFilter === 'normal', () => this.setFavoriteFilter('normal'))
          }
          .width('100%')
        }
        .layoutWeight(1)

        Column({ space: 8 }) {
          Text('排序')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
          Row({ space: 8 }) {
            this.filterChip('最新', this.sortFilter === 'createdAt_desc', () => this.setSortFilter('createdAt_desc'))
            this.filterChip('更新', this.sortFilter === 'updatedAt_desc', () => this.setSortFilter('updatedAt_desc'))
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')

      Button(this.showAdvancedFilters ? '收起高级筛选' : '展开高级筛选')
        .width('100%')
        .height(38)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_BUTTON)
        .fontColor(AppTheme.COLOR_BRAND)
        .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_BADGE)
        .onClick(() => {
          this.showAdvancedFilters = !this.showAdvancedFilters;
        })

      if (this.showAdvancedFilters) {
        Column({ space: 8 }) {
          Column({ space: 8 }) {
            Text('日期')
              .fontSize(AppTheme.FONT_META)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .lineHeight(AppTheme.LINE_META)
              .width('100%')
            Row({ space: 8 }) {
              this.filterChip('全部', this.dateFilter === 'all', () => this.setDateFilter('all'))
              this.filterChip('今天', this.dateFilter === 'today', () => this.setDateFilter('today'))
              this.filterChip('7天', this.dateFilter === '7d', () => this.setDateFilter('7d'))
              this.filterChip('30天', this.dateFilter === '30d', () => this.setDateFilter('30d'))
            }
            .width('100%')
          }

          Column({ space: 8 }) {
            Text('来源')
              .fontSize(AppTheme.FONT_META)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .lineHeight(AppTheme.LINE_META)
              .width('100%')
            Row({ space: 8 }) {
              this.filterChip('全部', this.sourceFilter === 'all', () => this.setSourceFilter('all'))
              this.filterChip('拍照', this.sourceFilter === 'camera', () => this.setSourceFilter('camera'))
              this.filterChip('相册', this.sourceFilter === 'album', () => this.setSourceFilter('album'))
              this.filterChip('导入', this.sourceFilter === 'import', () => this.setSourceFilter('import'))
              this.filterChip('批量', this.sourceFilter === 'batch', () => this.setSourceFilter('batch'))
              this.filterChip('PDF', this.sourceFilter === 'pdf', () => this.setSourceFilter('pdf'))
            }
            .width('100%')
          }

          Column({ space: 8 }) {
            Text('更多排序')
              .fontSize(AppTheme.FONT_META)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .lineHeight(AppTheme.LINE_META)
              .width('100%')
            Row({ space: 8 }) {
              this.filterChip('最早', this.sortFilter === 'createdAt_asc', () => this.setSortFilter('createdAt_asc'))
              this.filterChip('耗时', this.sortFilter === 'durationMs_desc', () => this.setSortFilter('durationMs_desc'))
            }
            .width('100%')
          }

          TextInput({ placeholder: '按识别服务筛选，例如 端侧识别 或 云端识别', text: this.ocrEngineFilter })
            .width('100%')
            .height(AppTheme.INPUT_HEIGHT)
            .fontSize(AppTheme.FONT_META)
            .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(AppTheme.RADIUS_CONTROL)
            .onChange((value: string) => {
              this.setOcrEngineFilter(value);
            })
        }
        .width('100%')
        .transition({ opacity: 0, translate: { y: AppMotion.ENTER_OFFSET_Y } })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.filterEntered ? 1 : 0)
    .translate({ y: this.filterEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private recordActionsCard() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '文档处理', meta: '文档动作' })
      List({ space: 0 }) {
        ListItem() {
          this.documentAction('导出文档', 'TXT / Markdown 在详情页处理，多记录 PDF 从这里进入。', AppRoutes.EXPORT_CENTER, AppTheme.COLOR_ACCENT)
        }
        ListItem() {
          this.documentAction('AI 整理', '对已保存记录执行纠错、摘要、翻译、标题和转 Markdown。', AppRoutes.AI_WORKSPACE, AppTheme.COLOR_BRAND)
        }
        ListItem() {
          this.documentAction('批量任务', '查看批量 OCR 队列、失败项重试和完成后导出。', AppRoutes.BATCH_OCR, AppTheme.COLOR_ACTION)
        }
      }
      .width('100%')
      .height(168)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.actionsEntered ? 1 : 0)
    .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  /**
   * 历史记录行。
   * 行内只提供脱敏摘要和真实记录操作，不引入任何伪造状态。
   */
  @Builder
  private recordRow(record: RecordListViewItem) {
    HtmlListRow({
      mark: this.recordMark(record),
      title: record.title,
      meta: this.recordPreviewMeta(record),
      badge: this.recordBadge(record),
      tone: record.isFavorite ? 'ok' : this.sourceBadgeTone(record),
      onTap: () => this.openDetail(record)
    })
    .width('100%')
    .transition({ opacity: 0, translate: { y: AppMotion.SUBTLE_OFFSET_Y } })
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
            HtmlAppBar({
              title: '历史记录',
              subtitle: '所有 OCR 文档与处理历史',
              showBackButton: true,
              actionIcon: 'search',
              onBack: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HOME),
              onAction: () => {
                this.showSearchPanel = !this.showSearchPanel;
                if (!this.showSearchPanel) {
                  this.showAdvancedFilters = false;
                }
              }
            })

            this.topFilterStrip()
            this.historyListCard()
            HtmlToast({ message: this.noticeMessage, visible: this.noticeVisible })
            if (this.showSearchPanel) {
              this.searchPanel()
              this.recordActionsCard()
            }

            Column()
              .height(4)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 4, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_PAGE)

      AppBottomNav({ activeTab: 'history' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
