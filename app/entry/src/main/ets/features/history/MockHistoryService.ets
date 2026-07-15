import { HistoryRecordDetail, HistoryRecordItem, HistorySearchResult, HistorySourceType } from './HistoryModels';

/**
 * MockHistoryService 提供历史记录页面的前端内存模拟数据，属于 features/history 模块。
 * 维护说明：本服务不访问网络、不导入 RecordService、不读取真实 OCR 历史、不持久化用户隐私数据。
 */
export class MockHistoryService {
  private static records: HistoryRecordDetail[] = MockHistoryService.createInitialRecords();

  /**
   * 查询 Mock 历史记录列表。
   * 参数 keyword 为本地搜索关键字；返回值只包含通用示例数据，不会请求后端 records API。
   */
  static async listRecords(keyword: string = ''): Promise<HistorySearchResult> {
    await MockHistoryService.delay(160);
    const normalizedKeyword = keyword.trim().toLowerCase();
    const records: HistoryRecordItem[] = [];

    for (let index = 0; index < MockHistoryService.records.length; index++) {
      const record = MockHistoryService.records[index];
      if (normalizedKeyword.length === 0 || MockHistoryService.matchesKeyword(record, normalizedKeyword)) {
        records.push(MockHistoryService.toItem(record));
      }
    }

    return {
      keyword: keyword.trim(),
      records,
      isSearchMode: keyword.trim().length > 0
    };
  }

  /**
   * 读取单条 Mock 历史详情。
   * 参数 id 为内存记录标识；返回 undefined 表示记录不存在或已被内存态删除。
   */
  static async getRecordDetail(id: string): Promise<HistoryRecordDetail | undefined> {
    await MockHistoryService.delay(120);
    const record = MockHistoryService.findRecord(id);
    if (!record) {
      return undefined;
    }
    return MockHistoryService.cloneDetail(record);
  }

  /**
   * 切换 Mock 收藏状态。
   * 参数 id 为内存记录标识；返回更新后的详情，方法不会调用后端 favorite 接口。
   */
  static async toggleFavorite(id: string): Promise<HistoryRecordDetail | undefined> {
    await MockHistoryService.delay(80);
    const record = MockHistoryService.findRecord(id);
    if (!record) {
      return undefined;
    }
    record.isFavorite = !record.isFavorite;
    return MockHistoryService.cloneDetail(record);
  }

  /**
   * 删除 Mock 历史记录。
   * 参数 id 为内存记录标识；返回 true 表示本地内存数组已移除记录，不会请求 DELETE /records。
   */
  static async deleteRecord(id: string): Promise<boolean> {
    await MockHistoryService.delay(80);
    for (let index = 0; index < MockHistoryService.records.length; index++) {
      if (MockHistoryService.records[index].id === id) {
        MockHistoryService.records.splice(index, 1);
        return true;
      }
    }
    return false;
  }

  /**
   * 重置 Mock 历史记录。
   * 该方法仅用于页面演示和后续测试准备，不会恢复任何真实用户数据。
   */
  static resetMockRecords(): void {
    MockHistoryService.records = MockHistoryService.createInitialRecords();
  }

  private static findRecord(id: string): HistoryRecordDetail | undefined {
    for (let index = 0; index < MockHistoryService.records.length; index++) {
      const record = MockHistoryService.records[index];
      if (record.id === id) {
        return record;
      }
    }
    return undefined;
  }

  private static matchesKeyword(record: HistoryRecordDetail, keyword: string): boolean {
    return record.title.toLowerCase().indexOf(keyword) >= 0 ||
      record.sourceLabel.toLowerCase().indexOf(keyword) >= 0 ||
      record.previewText.toLowerCase().indexOf(keyword) >= 0 ||
      record.recognizedText.toLowerCase().indexOf(keyword) >= 0 ||
      record.createdAtText.toLowerCase().indexOf(keyword) >= 0 ||
      record.language.toLowerCase().indexOf(keyword) >= 0 ||
      record.engineName.toLowerCase().indexOf(keyword) >= 0;
  }

  private static toItem(record: HistoryRecordDetail): HistoryRecordItem {
    return {
      id: record.id,
      title: record.title,
      sourceType: record.sourceType,
      sourceLabel: record.sourceLabel,
      previewText: record.previewText,
      createdAtText: record.createdAtText,
      language: record.language,
      engineName: record.engineName,
      elapsedMs: record.elapsedMs,
      isFavorite: record.isFavorite
    };
  }

  private static cloneDetail(record: HistoryRecordDetail): HistoryRecordDetail {
    return {
      id: record.id,
      title: record.title,
      sourceType: record.sourceType,
      sourceLabel: record.sourceLabel,
      previewText: record.previewText,
      createdAtText: record.createdAtText,
      language: record.language,
      engineName: record.engineName,
      elapsedMs: record.elapsedMs,
      isFavorite: record.isFavorite,
      recognizedText: record.recognizedText
    };
  }

  private static createRecord(
    id: string,
    title: string,
    sourceType: HistorySourceType,
    previewText: string,
    recognizedText: string,
    createdAtText: string,
    elapsedMs: number,
    isFavorite: boolean
  ): HistoryRecordDetail {
    return {
      id,
      title,
      sourceType,
      sourceLabel: sourceType === 'album' ? '相册识别' : '拍照识别',
      previewText,
      recognizedText,
      createdAtText,
      language: 'zh-CN',
      engineName: 'MockHistoryService',
      elapsedMs,
      isFavorite
    };
  }

  private static createInitialRecords(): HistoryRecordDetail[] {
    return [
      MockHistoryService.createRecord(
        'mock-history-001',
        '会议纪要文字识别',
        'camera',
        '项目周会记录，包含待办事项、责任人和下次检查时间。',
        '项目周会记录\n1. 完成 OCR Mock 主流程验收\n2. 准备历史记录页面 Mock 版\n3. 后续再接入 records 保存 API',
        '2026-05-25 09:40',
        1320,
        true
      ),
      MockHistoryService.createRecord(
        'mock-history-002',
        '票据截图识别',
        'album',
        '通用票据示例，展示相册来源、识别耗时和文本清理能力。',
        'Harmony OCR 示例票据\n金额：128.00\n用途：前端 Mock 流程验证\n说明：本记录不包含真实支付信息',
        '2026-05-24 18:12',
        1180,
        false
      ),
      MockHistoryService.createRecord(
        'mock-history-003',
        '课堂资料摘录',
        'camera',
        '纸质资料转文本示例，用于验证历史详情编辑和格式清理。',
        '课堂资料摘录\n图像文字识别可以把纸质内容转换为可编辑文本。\n本示例仅用于 Mock 页面展示。',
        '2026-05-23 14:25',
        1460,
        false
      )
    ];
  }

  private static delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }
}
