import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ExportTextService } from '../export/ExportTextService';

/**
 * CacheCleanupResult 是本地缓存清理统计。
 * 维护说明：只返回计数，不返回文件名或完整路径，避免把本地沙箱结构暴露给 UI 日志。
 */
export interface CacheCleanupResult {
  deletedCount: number;
  failedCount: number;
}

/**
 * CacheCleanupService 清理 V1.1 非关键本地缓存，属于 settings 功能模块。
 * 维护说明：只删除应用 cacheDir 下的裁剪缓存和导出 TXT 缓存；不清理 Token、账号状态、用户设置、云端历史或系统相册。
 */
export class CacheCleanupService {
  private static readonly CROP_PREFIX: string = 'ocr-crop-output-';

  /**
   * 清理安全范围内的本地缓存。
   * 参数 context 只用于定位本应用 cacheDir；返回删除统计，不输出真实文件路径。
   */
  static async clearNonCriticalCache(context: common.UIAbilityContext): Promise<CacheCleanupResult> {
    let deletedCount = 0;
    let failedCount = 0;
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(context.cacheDir);
    } catch (_) {
      return { deletedCount: 0, failedCount: 1 };
    }
    for (let index = 0; index < names.length; index++) {
      const name = names[index];
      if (!CacheCleanupService.isSafeCacheName(name)) {
        continue;
      }
      try {
        fileIo.unlinkSync(`${context.cacheDir}/${name}`);
        deletedCount++;
      } catch (_) {
        failedCount++;
      }
    }
    return { deletedCount: deletedCount, failedCount: failedCount };
  }

  private static isSafeCacheName(fileName: string): boolean {
    return fileName.startsWith(CacheCleanupService.CROP_PREFIX) || ExportTextService.isExportCacheFile(fileName);
  }
}
